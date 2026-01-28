local errors = require("core.error_codes")
local task_state = require("runtime.task_state")
local util = require("core.util")

local M = {}

function M.new(scheduler, initial, latency)
  local self = {
    data = initial or {},
    latency = latency or 2,
    scheduler = scheduler,
    inflight = {},
    frozen = false,
    counter = 0,
    supports_set = nil,
    max_items_per_batch = nil,
    max_total_count = nil,
  }

  function self:prepare(reachable)
    self.reachable = {}
    for item, _ in pairs(reachable) do
      self.reachable[util.normalize(item)] = true
    end
  end

  function self:snapshot()
    self.frozen = true
    local copy = {}
    for k, v in pairs(self.data) do
      copy[k] = v
    end
    return copy
  end

  function self:begin()
    self.frozen = false
  end

  function self:get(item)
    local key = util.normalize(item)
    if self.reachable and not self.reachable[key] then
      error({ code = errors.ITEM_NOT_REACHABLE, item = key })
    end
    return self.data[key] or 0
  end

  function self:consume(item, count)
    local key = util.normalize(item)
    if self.frozen then
      error({ code = errors.MUTATE_AFTER_SNAPSHOT })
    end
    local current = self.data[key] or 0
    if count < 0 then
      error({ code = errors.NEGATIVE_COUNT, item = key, count = count })
    end
    if current < count then
      error({ code = errors.INSUFFICIENT_STOCK, item = key, need = count, current = current })
    end
    self.data[key] = current - count
  end

  function self:add(item, count)
    local key = util.normalize(item)
    if self.frozen then
      error({ code = errors.MUTATE_AFTER_SNAPSHOT })
    end
    if count < 0 then
      error({ code = errors.NEGATIVE_COUNT, item = key, count = count })
    end
    self.data[key] = (self.data[key] or 0) + count
  end

  function self:supports(item)
    if not self.supports_set then
      return true
    end
    local key = util.normalize(item)
    return self.supports_set[key] == true
  end

  function self:supports_batch()
    return true
  end

  function self:capabilities()
    return {
      max_items_per_batch = self.max_items_per_batch,
      max_total_count = self.max_total_count,
    }
  end

  function self:get_async(item, count)
    if self.frozen then
      error({ code = errors.MUTATE_AFTER_SNAPSHOT })
    end
    local key = util.normalize(item)
    if not self:supports(key) then
      error({ code = errors.ITEM_NOT_REACHABLE, item = key })
    end
    self.counter = self.counter + 1
    local id = "req_" .. tostring(self.counter)
    self.inflight[id] = {
      item = key,
      count = count,
      state = task_state.TaskState.RUNNING,
    }
    self.scheduler:schedule(self.latency, function()
      local cur = self.data[key] or 0
      if cur < count then
        self.inflight[id].state = task_state.TaskState.FAILED
        self.inflight[id].error = { code = errors.INSUFFICIENT_STOCK, item = key }
      else
        self.inflight[id].state = task_state.TaskState.DONE
      end
    end)
    return id
  end

  function self:get_batch_async(request_map)
    if self.frozen then
      error({ code = errors.MUTATE_AFTER_SNAPSHOT })
    end
    self.counter = self.counter + 1
    local id = "batch_" .. tostring(self.counter)
    local req = {
      items = request_map,
      state = task_state.TaskState.RUNNING,
      error = nil,
    }
    self.inflight[id] = req
    self.scheduler:schedule(self.latency, function()
      for item, count in pairs(request_map) do
        local key = util.normalize(item)
        if not self:supports(key) then
          req.state = task_state.TaskState.FAILED
          req.error = { code = errors.ITEM_NOT_REACHABLE, item = key }
          return
        end
        local cur = self.data[key] or 0
        if cur < count then
          req.state = task_state.TaskState.FAILED
          req.error = { code = errors.INSUFFICIENT_STOCK, item = key }
          return
        end
      end
      req.state = task_state.TaskState.DONE
    end)
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
    if req.items then
      local result = {}
      for item, count in pairs(req.items) do
        local key = util.normalize(item)
        self.data[key] = (self.data[key] or 0) - count
        result[key] = count
      end
      self.inflight[id] = nil
      return result
    else
      self.data[req.item] = (self.data[req.item] or 0) - req.count
      self.inflight[id] = nil
      return req.count
    end
  end

  function self:commit()
    self.frozen = false
    self.inflight = {}
  end

  function self:rollback()
    self.frozen = false
    self.inflight = {}
  end

  function self:set_supported_items(items)
    local set = {}
    for _, item in ipairs(items) do
      set[util.normalize(item)] = true
    end
    self.supports_set = set
  end

  function self:set_limits(max_items_per_batch, max_total_count)
    self.max_items_per_batch = max_items_per_batch
    self.max_total_count = max_total_count
  end

  function self:inflight_count()
    local count = 0
    for _ in pairs(self.inflight) do
      count = count + 1
    end
    return count
  end

  return self
end

return M
