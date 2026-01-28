local task_state = require("runtime.task_state")
local errors = require("core.error_codes")

local M = {}

function M.new()
  local counter = 0
  return {
    synchronous = true,
    can_craft = function(self, recipe, machine)
      if recipe.machine ~= "crafting_table" then
        return false
      end
      if not recipe.conditions or not recipe.conditions.requires then
        return true
      end
      return true
    end,
    configure = function(self, machine, params)
      if not params or next(params) == nil then
        return true
      end
      return false, "crafting_table_has_no_configuration"
    end,
    start = function(self, recipe, times)
      counter = counter + 1
      local outputs = {}
      for _, out in ipairs(recipe.outputs) do
        outputs[out.item] = (outputs[out.item] or 0) + out.count * times
      end
      return {
        id = "crafting_table:" .. recipe.id .. ":" .. tostring(counter),
        state = task_state.TaskState.DONE,
        outputs = outputs,
        collected = false,
      }
    end,
    poll = function(self, handle)
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
      return handle.outputs or {}
    end,
  }
end

return M

