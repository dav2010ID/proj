local errors = require("core.error_codes")
local supply_router = require("runtime.supply_router")
local util = require("core.util")
local task_state = require("runtime.task_state")

local M = {}

local function sort_keys(map)
  local keys = {}
  for k, _ in pairs(map) do
    table.insert(keys, k)
  end
  table.sort(keys)
  return keys
end

function M.new(providers, bus)
  local self = {
    providers = providers or {},
    bus = bus,
    inflight = {},
    counter = 0,
    stats = {
      total_batches = 0,
      failed_batches = 0,
      split_batches = 0,
    },
  }

  local function emit(event)
    if self.bus then
      self.bus:emit(event)
    end
  end

  local function find_provider(item)
    for _, entry in ipairs(self.providers) do
      local provider = entry.provider
      if provider.supports and provider:supports(item) then
        return entry
      end
    end
    return nil
  end

  function self:prepare(reachable)
    for _, entry in ipairs(self.providers) do
      if entry.provider.prepare then
        entry.provider:prepare(reachable)
      end
    end
  end

  function self:begin()
    for _, entry in ipairs(self.providers) do
      if entry.provider.begin then
        entry.provider:begin()
      end
    end
  end

  function self:snapshot()
    local snapshot = {}
    for _, entry in ipairs(self.providers) do
      if entry.provider.snapshot then
        local sub = entry.provider:snapshot()
        for k, v in pairs(sub) do
          snapshot[k] = v
        end
      end
    end
    return snapshot
  end

  function self:get(item)
    local key = util.normalize(item)
    local entry = find_provider(key)
    if not entry then
      error({ code = errors.ITEM_NOT_REACHABLE, item = key })
    end
    return entry.provider:get(key)
  end

  function self:consume(item, count)
    local key = util.normalize(item)
    local entry = find_provider(key)
    if not entry then
      error({ code = errors.ITEM_NOT_REACHABLE, item = key })
    end
    return entry.provider:consume(key, count)
  end

  function self:add(item, count)
    local key = util.normalize(item)
    local entry = find_provider(key)
    if not entry then
      error({ code = errors.ITEM_NOT_REACHABLE, item = key })
    end
    return entry.provider:add(key, count)
  end

  function self:capabilities()
    return {
      max_items_per_batch = nil,
      max_total_count = nil,
    }
  end

  function self:get_batch_async(request_map)
    self.counter = self.counter + 1
    local master_id = "multi_batch_" .. tostring(self.counter)
    local master = {
      id = master_id,
      requests = {},
      state = "RUNNING",
    }
    self.inflight[master_id] = master

    local keys = sort_keys(request_map)
    local per_provider = {}
    for _, item in ipairs(keys) do
      local entry = find_provider(item)
      if not entry then
        error({ code = errors.ITEM_NOT_REACHABLE, item = item })
      end
      per_provider[entry.id] = per_provider[entry.id] or { entry = entry, items = {} }
      per_provider[entry.id].items[item] = (per_provider[entry.id].items[item] or 0) + request_map[item]
    end

    for _, group in pairs(per_provider) do
      local entry = group.entry
      local provider = entry.provider
      local caps = provider.capabilities and provider:capabilities() or {}
      local batches = supply_router.split_batches(group.items, caps)
      if #batches > 1 then
        self.stats.split_batches = self.stats.split_batches + 1
        emit({
          type = "BatchSplit",
          storage_id = entry.id,
          original_size = group.items,
          batches_count = #batches,
        })
      end
      for _, batch in ipairs(batches) do
      local req_id
        if provider.get_batch_async then
          req_id = provider:get_batch_async(batch)
        else
          local only_item, only_count
          for item, count in pairs(batch) do
            only_item = item
            only_count = count
            break
          end
          req_id = provider:get_async(only_item, only_count)
        end
        table.insert(master.requests, { id = req_id, provider = provider, storage_id = entry.id, batch = batch })
        self.stats.total_batches = self.stats.total_batches + 1
        emit({ type = "BatchQueued", storage_id = entry.id, batch_id = req_id })
      end
    end

    emit({ type = "SupplyRequested", batch_id = master_id })
    return master_id
  end

  function self:poll_request(id)
    local master = self.inflight[id]
    if not master then
      error({ code = errors.INVALID_HANDLE, id = id })
    end
    local all_done = true
    for _, sub in ipairs(master.requests) do
      local state = sub.provider:poll_request(sub.id)
      if state == task_state.TaskState.FAILED then
        master.state = "FAILED"
        self.stats.failed_batches = self.stats.failed_batches + 1
        emit({ type = "BatchFailed", storage_id = sub.storage_id, batch_id = sub.id })
        return task_state.TaskState.FAILED
      elseif state == task_state.TaskState.RUNNING then
        all_done = false
      end
    end
    if all_done then
      master.state = "DONE"
      return task_state.TaskState.DONE
    end
    return task_state.TaskState.RUNNING
  end

  function self:collect_request(id)
    local master = self.inflight[id]
    if not master then
      error({ code = errors.INVALID_HANDLE, id = id })
    end
    local result = {}
    for _, sub in ipairs(master.requests) do
      local out = sub.provider:collect_request(sub.id)
      if type(out) == "table" then
        for item, count in pairs(out) do
          result[item] = (result[item] or 0) + count
        end
      else
        local only_item
        for item, _ in pairs(sub.batch or {}) do
          only_item = item
          break
        end
        if only_item then
          result[only_item] = (result[only_item] or 0) + out
        end
      end
      emit({ type = "BatchDone", storage_id = sub.storage_id, batch_id = sub.id })
    end
    self.inflight[id] = nil
    emit({ type = "SupplySatisfied", batch_id = id })
    return result
  end

  function self:commit()
    for _, entry in ipairs(self.providers) do
      if entry.provider.commit then
        entry.provider:commit()
      end
    end
  end

  function self:rollback()
    for _, entry in ipairs(self.providers) do
      if entry.provider.rollback then
        entry.provider:rollback()
      end
    end
    self.inflight = {}
  end

  function self:stats_snapshot()
    return {
      total_batches = self.stats.total_batches,
      failed_batches = self.stats.failed_batches,
      split_batches = self.stats.split_batches,
    }
  end

  return self
end

return M
