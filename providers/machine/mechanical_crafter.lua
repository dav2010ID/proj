local task_state = require("runtime.task_state")

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
      return { id = "mechanical_crafter:" .. recipe.id, state = task_state.TaskState.FAILED, error = "mechanical_crafter_not_implemented" }
    end,
    poll = function(self, handle)
      return handle.state
    end,
    collect_outputs = function(self, handle)
      return {}
    end,
  }
end

return M

