local task_state = require("runtime.task_state")

local M = {}

function M.new(bus)
  local self = {
    time = 0,
    tasks = {},
    bus = bus,
  }

  function self:register(handle, duration)
    handle.state = task_state.TaskState.RUNNING
    handle.remaining = duration
    self.tasks[handle.id] = handle
    if self.bus then
      self.bus:emit({ type = "TaskStarted", task_id = handle.id })
    end
  end

  function self:tick()
    self.time = self.time + 1
    for _, handle in pairs(self.tasks) do
      if handle.state == task_state.TaskState.RUNNING then
        handle.remaining = handle.remaining - 1
        if handle.remaining <= 0 then
          handle.state = task_state.TaskState.DONE
          if self.bus then
            self.bus:emit({ type = "TaskFinished", task_id = handle.id })
          end
        end
      end
    end
  end

  function self:fail(handle, error_message)
    handle.state = task_state.TaskState.FAILED
    handle.error = error_message
    if self.bus then
      self.bus:emit({ type = "TaskFailed", task_id = handle.id, error = error_message })
    end
  end

  return self
end

return M
