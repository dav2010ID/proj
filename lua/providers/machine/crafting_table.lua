local base = require("providers.machine.base")

local M = {}

function M.new()
  return {
    can_craft = function(self, recipe, machine)
      if recipe.machine ~= "crafting_table" then
        return false
      end
      return not recipe.conditions
    end,
    configure = function(self, machine, params)
      return params == nil
    end,
    start = function(self, recipe, times)
      local outputs = {}
      for _, out in ipairs(recipe.outputs) do
        outputs[out.item] = (outputs[out.item] or 0) + out.count * times
      end
      return { id = "crafting_table:" .. recipe.id, state = base.TaskState.DONE, outputs = outputs }
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
