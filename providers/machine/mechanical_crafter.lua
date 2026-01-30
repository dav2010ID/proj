local task_state = require("runtime.task_state")

local M = {}

function M.new()
  local counter = 0
  return {
    can_craft = function(self, recipe, machine)
      return recipe.machine == "mechanical_crafter"
    end,
    configure = function(self, machine, params)
      if not params or next(params) == nil then
        return true
      end
      for key, value in pairs(params) do
        machine.state[key] = value
      end
      return true
    end,
    start = function(self, recipe, times)
      counter = counter + 1
      local outputs = {}
      for _, out in ipairs(recipe.outputs) do
        outputs[out.item] = (outputs[out.item] or 0) + out.count * times
      end
      return {
        id = "mechanical_crafter:" .. recipe.id .. ":" .. tostring(counter),
        state = task_state.TaskState.DONE,
        outputs = outputs,
      }
    end,
    poll = function(self, handle)
      return handle.state
    end,
    collect_outputs = function(self, handle)
      return handle.outputs or {}
    end,
  }
end

return M

