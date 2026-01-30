local util = require("core.util")
local errors = require("core.error_codes")

local M = {}

local function normalize_item_name(item)
  if type(item) == "table" then
    return util.normalize(item.name or item.item or item.id or "")
  end
  return util.normalize(item)
end

local function copy_slots(slots)
  local out = {}
  for slot, entry in pairs(slots) do
    out[slot] = { key = entry.key, count = entry.count }
  end
  return out
end

function M.new(opts)
  opts = opts or {}
  local side = opts.side or "front"
  local create = opts.create
  if create == nil then
    create = true
  end

  if create then
    if not periphemu then
      error("periphemu not available (CraftOS-PC only)")
    end
    periphemu.create(side, "chest", opts.double or false)
  end

  local chest = peripheral and peripheral.wrap(side) or nil
  if not chest then
    error("chest peripheral not found on " .. side)
  end
  if not chest.list or not chest.setItem then
    error("chest peripheral missing list/setItem methods")
  end

  local size = chest.size and chest.size() or (opts.double and 54 or 27)

  local self = {
    chest = chest,
    size = size,
    side = side,
    double = opts.double or false,
    stock = {},
    slots = {},
    delta_minus = {},
    delta_plus = {},
    snapshot_taken = false,
    reachable = nil,
    slot_snapshot = nil,
    skip_refresh_once = false,
    allowlist = opts.allowlist,
  }

  local function refresh()
    local list = chest.list() or {}
    local stock = {}
    local slots = {}
    for slot, item in pairs(list) do
      local key = normalize_item_name(item)
      local count = item.count or item.amount or 0
      if key ~= "" and key ~= "minecraft:air" and count > 0 then
        stock[key] = (stock[key] or 0) + count
        slots[slot] = { key = key, count = count }
      end
    end
    self.stock = stock
    self.slots = slots
  end

  local function set_slot(slot, key, count)
    if count <= 0 then
      chest.setItem(slot, { name = "minecraft:air", item = "minecraft:air", count = 1 })
      self.slots[slot] = nil
      return
    end
    chest.setItem(slot, { name = key, item = key, count = count })
    self.slots[slot] = { key = key, count = count }
  end

  local function remove_from_slots(item, count)
    local remaining = count
    for slot = 1, size do
      local entry = self.slots[slot]
      if entry and entry.key == item then
        local take = math.min(entry.count, remaining)
        local new_count = entry.count - take
        set_slot(slot, item, new_count)
        remaining = remaining - take
        if remaining <= 0 then
          break
        end
      end
    end
    if remaining > 0 then
      error({ code = errors.INSUFFICIENT_STOCK, item = item, need = count, current = self.stock[item] or 0 })
    end
  end

  local function add_to_slots(item, count)
    local remaining = count
    for slot = 1, size do
      local entry = self.slots[slot]
      if entry and entry.key == item then
        set_slot(slot, item, entry.count + remaining)
        remaining = 0
        break
      end
    end
    if remaining > 0 then
      for slot = 1, size do
        if not self.slots[slot] then
          set_slot(slot, item, remaining)
          remaining = 0
          break
        end
      end
    end
    if remaining > 0 then
      error({ code = errors.RESOURCE_FAILED, item = item, count = count, reason = "no_empty_slot" })
    end
  end

  function self:supports(item)
    if self.allowlist then
      return self.allowlist[util.normalize(item)] == true
    end
    return true
  end

  function self:prepare(reachable)
    self.reachable = {}
    for item, _ in pairs(reachable) do
      self.reachable[util.normalize(item)] = true
    end
    self.snapshot_taken = false
    self.delta_minus = {}
    self.delta_plus = {}
    self.skip_refresh_once = false
    refresh()
  end

  function self:begin()
    self.snapshot_taken = false
    self.delta_minus = {}
    self.delta_plus = {}
    self.skip_refresh_once = false
    self.slot_snapshot = copy_slots(self.slots)
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
    if count < 0 then
      error({ code = errors.NEGATIVE_COUNT, item = key, count = count })
    end
    if (self.stock[key] or 0) < count then
      error({ code = errors.INSUFFICIENT_STOCK, item = key, need = count, current = self.stock[key] or 0 })
    end
    if count > 0 then
      remove_from_slots(key, count)
      self.stock[key] = (self.stock[key] or 0) - count
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
    if count > 0 then
      add_to_slots(key, count)
      self.stock[key] = (self.stock[key] or 0) + count
      table.insert(self.delta_plus, { key = key, count = count })
    end
  end

  function self:commit()
    self.delta_minus = {}
    self.delta_plus = {}
    self.snapshot_taken = false
    self.slot_snapshot = nil
  end

  function self:rollback()
    if not self.slot_snapshot then
      refresh()
      self.delta_minus = {}
      self.delta_plus = {}
      self.snapshot_taken = false
      return
    end
    local stock = {}
    for _, entry in pairs(self.slot_snapshot) do
      stock[entry.key] = (stock[entry.key] or 0) + entry.count
    end
    self.stock = stock
    self.slots = copy_slots(self.slot_snapshot)
    self.skip_refresh_once = true
    for slot = 1, size do
      set_slot(slot, "", 0)
    end
    for slot, entry in pairs(self.slot_snapshot) do
      set_slot(slot, entry.key, entry.count)
    end
    self.delta_minus = {}
    self.delta_plus = {}
    self.snapshot_taken = false
    self.slot_snapshot = nil
  end

  function self:snapshot()
    if self.snapshot_taken then
      error({ code = errors.SNAPSHOT_TAKEN })
    end
    if self.skip_refresh_once then
      self.skip_refresh_once = false
    else
      refresh()
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
