-- TEST SUPPORT CODE
-- Not used in production.
local task_state = require("runtime.task_state")
local events = require("core.events")

local M = {}

function M.new(bus)
  local self = {
    time = 0,
    tasks = {},
    bus = bus,
    timers = {},
    in_tick = false,
    pending_events = {},
  }

  function self:register(handle, duration)
    if not handle or not handle.id then
      error("task handle must have id")
    end
    if self.tasks[handle.id] then
      error("task already registered: " .. tostring(handle.id))
    end
    if type(duration) ~= "number" or duration <= 0 then
      error("task duration must be > 0")
    end
    if handle.state ~= nil and handle.state ~= task_state.TaskState.RUNNING then
      error("task already has state: " .. tostring(handle.id))
    end
    handle.state = task_state.TaskState.RUNNING
    handle.remaining = duration
    self.tasks[handle.id] = handle
    if self.bus then
      if self.in_tick then
        table.insert(self.pending_events, events.TaskStarted({ task_id = handle.id }))
      else
        self.bus:emit(events.TaskStarted({ task_id = handle.id }))
      end
    end
  end

  function self:tick()
    -- Tick phases: timers -> tasks -> events.
    self.in_tick = true
    self.time = self.time + 1
    for i = #self.timers, 1, -1 do
      local t = self.timers[i]
      t.remaining = t.remaining - 1
      if t.remaining <= 0 then
        table.remove(self.timers, i)
        t.fn()
      end
    end
    local snapshot = {}
    for _, handle in pairs(self.tasks) do
      table.insert(snapshot, handle)
    end
    for _, handle in ipairs(snapshot) do
      if handle.state == task_state.TaskState.RUNNING then
        handle.remaining = handle.remaining - 1
        if handle.remaining <= 0 then
          handle.state = task_state.TaskState.DONE
          if self.bus then
            table.insert(self.pending_events, events.TaskFinished({ task_id = handle.id }))
          end
        end
      end
    end
    for id, handle in pairs(self.tasks) do
      if handle.state == task_state.TaskState.DONE or handle.state == task_state.TaskState.FAILED then
        self.tasks[id] = nil
      end
    end
    self.in_tick = false
    if self.bus and #self.pending_events > 0 then
      for _, event in ipairs(self.pending_events) do
        self.bus:emit(event)
      end
      self.pending_events = {}
    end
  end

  function self:schedule(delay, fn)
    table.insert(self.timers, { remaining = delay, fn = fn })
  end

  function self:fail(handle, error_message)
    if not handle or not handle.id then
      error("task handle must have id")
    end
    local registered = self.tasks[handle.id] ~= nil
    handle.state = task_state.TaskState.FAILED
    handle.error = error_message
    if self.bus then
      if self.in_tick then
        table.insert(self.pending_events, events.TaskFailed({ task_id = handle.id, error = error_message }))
      else
        self.bus:emit(events.TaskFailed({ task_id = handle.id, error = error_message }))
      end
    end
    if registered and not self.in_tick then
      self.tasks[handle.id] = nil
    end
  end

  return self
end

return M

