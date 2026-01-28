local task_state = require("runtime.task_state")
local errors = require("core.error_codes")

local M = {}

function M.new()
  return {
    can_craft = function(self, recipe, machine)
      return recipe.machine == "mechanical_crafter"
    end,
    configure = function(self, machine, params)
      return false, "mechanical_crafter_not_implemented"
    end,
    start = function(self, recipe, times)
      return {
        id = "mechanical_crafter:" .. recipe.id,
        state = task_state.TaskState.RUNNING,
        fail_on_poll = true,
        error = { code = errors.CRAFT_FAILED },
      }
    end,
    poll = function(self, handle)
      if handle.state == task_state.TaskState.RUNNING and handle.fail_on_poll then
        handle.fail_on_poll = false
        return task_state.TaskState.RUNNING
      end
      if handle.state == task_state.TaskState.RUNNING then
        handle.state = task_state.TaskState.FAILED
      end
      return handle.state
    end,
    collect_outputs = function(self, handle)
      if handle.state ~= task_state.TaskState.DONE then
        error({ code = errors.OUTPUTS_NOT_READY })
      end
      if handle.collected then
        error({ code = errors.OUTPUTS_COLLECTED })
      end
      handle.collected = true
      return {}
    end,
  }
end

return M

