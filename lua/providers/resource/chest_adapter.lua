local errors = require("core.error_codes")
local task_state = require("runtime.task_state")
local util = require("core.util")

local M = {}

local function normalize_item(item)
  return util.normalize(item)
end

local function sorted_slots(slot_list)
  table.sort(slot_list, function(a, b) return a.slot < b.slot end)
  return slot_list
end

local function build_inventory_index(listing)
  local counts = {}
  local slots = {}
  for slot, entry in pairs(listing or {}) do
    if entry and entry.name then
      local key = normalize_item(entry.name)
      local count = entry.count or 0
      counts[key] = (counts[key] or 0) + count
      slots[key] = slots[key] or {}
      table.insert(slots[key], { slot = slot, count = count })
    end
  end
  return counts, slots
end

local function normalize_request_map(request_map)
  local normalized = {}
  for item, count in pairs(request_map or {}) do
    local key = normalize_item(item)
    normalized[key] = (normalized[key] or 0) + count
  end
  return normalized
end

function M.new(peripheral, scheduler, opts)
  opts = opts or {}
  local input_name = opts.input_name or opts.buffer_name
  local output_name = opts.output_name or opts.buffer_name
  local input_peripheral = opts.input_peripheral

  local self = {
    peripheral = peripheral,
    scheduler = scheduler,
    inflight = {},
    counter = 0,
    max_items_per_batch = opts.max_items_per_batch,
    max_total_count = opts.max_total_count,
  }

  local function require_output()
    if not output_name then
      error({ code = errors.RESOURCE_FAILED, message = "chest adapter missing output_name" })
    end
  end

  local function require_input()
    if not input_name or not input_peripheral then
      error({ code = errors.RESOURCE_FAILED, message = "chest adapter missing input_name or input_peripheral" })
    end
  end

  function self:supports(item)
    local key = normalize_item(item)
    local counts = build_inventory_index(self.peripheral:list())
    return (counts[key] or 0) > 0
  end

  function self:get(item)
    local key = normalize_item(item)
    local counts = build_inventory_index(self.peripheral:list())
    return counts[key] or 0
  end

  function self:capabilities()
    return {
      max_items_per_batch = self.max_items_per_batch,
      max_total_count = self.max_total_count,
    }
  end

  local function ensure_counts_available(requests, counts)
    for item, count in pairs(requests) do
      if count < 0 then
        error({ code = errors.NEGATIVE_COUNT, item = item, count = count })
      end
      if (counts[item] or 0) < count then
        return false, { code = errors.INSUFFICIENT_STOCK, item = item }
      end
    end
    return true, nil
  end

  local function push_from_chest(requests, slots)
    require_output()
    local moved = {}
    for item, count in pairs(requests) do
      local remaining = count
      local slot_list = sorted_slots(slots[item] or {})
      for _, entry in ipairs(slot_list) do
        if remaining <= 0 then
          break
        end
        local take = math.min(entry.count, remaining)
        local pushed = self.peripheral:pushItems(output_name, entry.slot, take)
        pushed = pushed or 0
        remaining = remaining - pushed
        moved[item] = (moved[item] or 0) + pushed
      end
      if remaining > 0 then
        return false, { code = errors.RESOURCE_FAILED, item = item }
      end
    end
    return true, moved
  end

  local function pull_into_chest(item, count)
    require_input()
    if count < 0 then
      error({ code = errors.NEGATIVE_COUNT, item = item, count = count })
    end
    local listing = input_peripheral:list()
    local counts, slots = build_inventory_index(listing)
    if (counts[item] or 0) < count then
      error({ code = errors.INSUFFICIENT_STOCK, item = item, need = count })
    end
    local remaining = count
    local slot_list = sorted_slots(slots[item] or {})
    local moved = 0
    for _, entry in ipairs(slot_list) do
      if remaining <= 0 then
        break
      end
      local take = math.min(entry.count, remaining)
      local pulled = self.peripheral:pullItems(input_name, entry.slot, take)
      pulled = pulled or 0
      remaining = remaining - pulled
      moved = moved + pulled
    end
    if moved < count then
      error({ code = errors.RESOURCE_FAILED, item = item })
    end
  end

  local function schedule_request(id, request_map)
    self.scheduler:schedule(0, function()
      local counts, slots = build_inventory_index(self.peripheral:list())
      local ok, err = ensure_counts_available(request_map, counts)
      if not ok then
        self.inflight[id].state = task_state.TaskState.FAILED
        self.inflight[id].error = err
        return
      end
      local moved_ok, moved_or_err = push_from_chest(request_map, slots)
      if not moved_ok then
        self.inflight[id].state = task_state.TaskState.FAILED
        self.inflight[id].error = moved_or_err
        return
      end
      self.inflight[id].state = task_state.TaskState.DONE
      self.inflight[id].result = moved_or_err
    end)
  end

  function self:get_async(item, count)
    local key = normalize_item(item)
    self.counter = self.counter + 1
    local id = "chest_req_" .. tostring(self.counter)
    self.inflight[id] = {
      state = task_state.TaskState.RUNNING,
      item = key,
      count = count,
    }
    schedule_request(id, { [key] = count })
    return id
  end

  function self:get_batch_async(request_map)
    local normalized = normalize_request_map(request_map)
    self.counter = self.counter + 1
    local id = "chest_batch_" .. tostring(self.counter)
    self.inflight[id] = {
      state = task_state.TaskState.RUNNING,
      items = normalized,
    }
    schedule_request(id, normalized)
    return id
  end

  function self:poll_request(id)
    local req = self.inflight[id]
    if not req then
      error({ code = errors.INVALID_HANDLE, id = id })
    end
    return req.state
  end

  function self:collect_request(id)
    local req = self.inflight[id]
    if not req then
      error({ code = errors.INVALID_HANDLE, id = id })
    end
    if req.state ~= task_state.TaskState.DONE then
      error({ code = errors.REQUEST_NOT_DONE, id = id })
    end
    local result = req.result or {}
    self.inflight[id] = nil
    if req.items then
      return result
    end
    return result[req.item] or 0
  end

  function self:add(item, count)
    local key = normalize_item(item)
    pull_into_chest(key, count)
  end

  function self:commit()
    self.inflight = {}
  end

  function self:rollback()
    self.inflight = {}
  end

  return self
end

function M.from_periphemu(periphemu, peripheral_api, scheduler, opts)
  opts = opts or {}
  if not periphemu then
    error({ code = errors.RESOURCE_FAILED, message = "periphemu is required" })
  end
  if not peripheral_api then
    error({ code = errors.RESOURCE_FAILED, message = "peripheral api is required" })
  end
  if not opts.side then
    error({ code = errors.RESOURCE_FAILED, message = "periphemu side is required" })
  end

  local peripheral_type = opts.peripheral_type or "minecraft:chest"
  periphemu.create(opts.side, peripheral_type)

  local chest_name = opts.peripheral_name or opts.side
  local chest = peripheral_api.wrap(chest_name)
  if not chest then
    error({ code = errors.RESOURCE_FAILED, message = "failed to wrap chest peripheral" })
  end

  local input_peripheral = opts.input_peripheral
  if not input_peripheral and opts.input_name then
    input_peripheral = peripheral_api.wrap(opts.input_name)
  end

  local adapter_opts = {
    input_name = opts.input_name,
    output_name = opts.output_name,
    buffer_name = opts.buffer_name,
    input_peripheral = input_peripheral,
    max_items_per_batch = opts.max_items_per_batch,
    max_total_count = opts.max_total_count,
  }

  return M.new(chest, scheduler, adapter_opts)
end

return M
