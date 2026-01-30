-- StorageView: transactional/view layer over a physical storage backend.
-- Applies deltas locally and only mutates the backend on commit.
local errors = require("core.error_codes")
local util = require("core.util")

local M = {}

local function bind(target, value)
  if type(value) ~= "function" then
    return value
  end
  return function(_, ...)
    return value(target, ...)
  end
end

local function copy_map(map)
  local out = {}
  for k, v in pairs(map or {}) do
    out[k] = v
  end
  return out
end

function M.new(backend)
  local self = {
    backend = backend,
    capabilities = backend and backend.capabilities or nil,
    in_txn = false,
    snapshot_taken = false,
    snapshot_keys = nil,
    reachable = nil,
    base_snapshot = nil,
    delta_minus = {},
    delta_plus = {},
  }

  local function require_backend()
    local target = self.backend
    if not target then
      error("no storage backend")
    end
    return target
  end

  local function ensure_snapshot()
    if self.base_snapshot then
      return
    end
    local target = require_backend()
    if target.snapshot then
      self.base_snapshot = target:snapshot()
    else
      self.base_snapshot = {}
    end
  end

  local function assert_txn()
    if not self.in_txn then
      error({ code = errors.TXN_NOT_ACTIVE })
    end
  end

  local function assert_reachable(item)
    if not self.reachable then
      return
    end
    local key = util.normalize(item)
    if not self.reachable[key] then
      error({ code = errors.ITEM_NOT_REACHABLE, item = key })
    end
  end

  local function get_base(key)
    if self.base_snapshot then
      return self.base_snapshot[key] or 0
    end
    local target = require_backend()
    if target.get then
      return target:get(key)
    end
    return 0
  end

  function self:prepare(reachable)
    local target = require_backend()
    if target.prepare then
      target:prepare(reachable)
    end
    self.reachable = {}
    for item, _ in pairs(reachable or {}) do
      self.reachable[util.normalize(item)] = true
    end
    self.base_snapshot = nil
    self.snapshot_taken = false
    self.snapshot_keys = nil
    self.delta_minus = {}
    self.delta_plus = {}
  end

  function self:begin()
    local target = require_backend()
    if target.begin then
      target:begin()
    end
    if self.in_txn then
      error({ code = errors.TXN_ALREADY_ACTIVE })
    end
    self.in_txn = true
    self.base_snapshot = nil
    self.snapshot_taken = false
    self.snapshot_keys = nil
    self.delta_minus = {}
    self.delta_plus = {}
  end

  function self:get(item)
    local key = util.normalize(item)
    assert_reachable(key)
    if self.snapshot_taken and (not self.snapshot_keys or not self.snapshot_keys[key]) then
      error({ code = errors.GET_AFTER_SNAPSHOT, item = key })
    end
    local base = get_base(key)
    local minus = self.delta_minus[key] or 0
    local plus = self.delta_plus[key] or 0
    return base - minus + plus
  end

  function self:consume(item, count)
    assert_txn()
    if self.snapshot_taken then
      error({ code = errors.MUTATE_AFTER_SNAPSHOT })
    end
    local key = util.normalize(item)
    assert_reachable(key)
    if count < 0 then
      error({ code = errors.NEGATIVE_COUNT, item = key, count = count })
    end
    local available = self:get(key)
    if available < count then
      error({ code = errors.INSUFFICIENT_STOCK, item = key, need = count, current = available })
    end
    self.delta_minus[key] = (self.delta_minus[key] or 0) + count
  end

  function self:add(item, count)
    assert_txn()
    if self.snapshot_taken then
      error({ code = errors.MUTATE_AFTER_SNAPSHOT })
    end
    local key = util.normalize(item)
    assert_reachable(key)
    if count < 0 then
      error({ code = errors.NEGATIVE_COUNT, item = key, count = count })
    end
    self.delta_plus[key] = (self.delta_plus[key] or 0) + count
  end

  function self:snapshot()
    assert_txn()
    if self.snapshot_taken then
      error({ code = errors.SNAPSHOT_TAKEN })
    end
    ensure_snapshot()
    local copy = copy_map(self.base_snapshot)
    for item, count in pairs(self.delta_minus) do
      copy[item] = (copy[item] or 0) - count
    end
    for item, count in pairs(self.delta_plus) do
      copy[item] = (copy[item] or 0) + count
    end
    local keys = {}
    for item, _ in pairs(copy) do
      keys[item] = true
    end
    self.snapshot_keys = keys
    self.snapshot_taken = true
    return copy
  end

  function self:commit()
    if not self.in_txn then
      local target = require_backend()
      if target.commit then
        target:commit()
        return
      end
      error({ code = errors.TXN_NOT_ACTIVE })
    end
    local target = require_backend()
    for item, count in pairs(self.delta_minus) do
      if count > 0 and target.consume then
        target:consume(item, count)
      end
    end
    for item, count in pairs(self.delta_plus) do
      if count > 0 and target.add then
        target:add(item, count)
      end
    end
    if target.commit then
      target:commit()
    end
    self.delta_minus = {}
    self.delta_plus = {}
    self.base_snapshot = nil
    self.snapshot_taken = false
    self.snapshot_keys = nil
    self.in_txn = false
  end

  function self:rollback()
    if not self.in_txn then
      local target = require_backend()
      if target.rollback then
        target:rollback()
        return
      end
      error({ code = errors.TXN_NOT_ACTIVE })
    end
    local target = require_backend()
    if target.rollback then
      target:rollback()
    end
    self.delta_minus = {}
    self.delta_plus = {}
    self.base_snapshot = nil
    self.snapshot_taken = false
    self.snapshot_keys = nil
    self.in_txn = false
  end

  setmetatable(self, {
    __index = function(t, k)
      if k == "backend" then
        return rawget(t, "backend")
      end
      local target = rawget(t, "backend")
      if not target then
        error("no storage backend")
      end
      return bind(target, target[k])
    end,
  })

  return self
end

return M
