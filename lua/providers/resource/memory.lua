local util = require("core.util")
local errors = require("core.error_codes")

local M = {}

function M.new(initial)
  local self = {
    stock = initial or {},
    delta_minus = {},
    delta_plus = {},
    snapshot_taken = false,
    reachable = nil,
  }

  function self:prepare(reachable)
    self.reachable = {}
    for item, _ in pairs(reachable) do
      self.reachable[util.normalize(item)] = true
    end
    self.snapshot_taken = false
    self.delta_minus = {}
    self.delta_plus = {}
  end

  function self:begin()
    self.snapshot_taken = false
    self.delta_minus = {}
    self.delta_plus = {}
  end

  function self:get(item)
    local key = util.normalize(item)
    if self.reachable and not self.reachable[key] then
      error({ code = errors.ITEM_NOT_REACHABLE, item = key })
    end
    if self.snapshot_taken and self.stock[key] == nil then
      error({ code = errors.GET_AFTER_SNAPSHOT, item = key })
    end
    if self.stock[key] == nil then
      self.stock[key] = 0
    end
    return self.stock[key]
  end

  function self:consume(item, count)
    local key = util.normalize(item)
    if self.snapshot_taken then
      error({ code = errors.MUTATE_AFTER_SNAPSHOT })
    end
    local current = self.stock[key] or 0
    if count < 0 then
      error({ code = errors.NEGATIVE_COUNT, item = key, count = count })
    end
    if current < count then
      error({ code = errors.INSUFFICIENT_STOCK, item = key, need = count, current = current })
    end
    self.stock[key] = current - count
    if count > 0 then
      table.insert(self.delta_minus, { key = key, count = count })
    end
  end

  function self:add(item, count)
    local key = util.normalize(item)
    if self.snapshot_taken then
      error({ code = errors.MUTATE_AFTER_SNAPSHOT })
    end
    if count < 0 then
      error({ code = errors.NEGATIVE_COUNT, item = key, count = count })
    end
    self.stock[key] = (self.stock[key] or 0) + count
    if count > 0 then
      table.insert(self.delta_plus, { key = key, count = count })
    end
  end

  function self:commit()
    self.delta_minus = {}
    self.delta_plus = {}
    self.snapshot_taken = false
  end

  function self:rollback()
    for i = #self.delta_plus, 1, -1 do
      local entry = self.delta_plus[i]
      self.stock[entry.key] = (self.stock[entry.key] or 0) - entry.count
    end
    for i = #self.delta_minus, 1, -1 do
      local entry = self.delta_minus[i]
      self.stock[entry.key] = (self.stock[entry.key] or 0) + entry.count
    end
    self.delta_minus = {}
    self.delta_plus = {}
    self.snapshot_taken = false
  end

  function self:snapshot()
    if self.snapshot_taken then
      error({ code = errors.SNAPSHOT_TAKEN })
    end
    self.snapshot_taken = true
    local copy = {}
    for k, v in pairs(self.stock) do
      copy[k] = v
    end
    return copy
  end

  return self
end

return M



