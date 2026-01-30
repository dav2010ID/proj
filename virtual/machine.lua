-- TEST SUPPORT CODE
-- Not used in production.
local task_state = require("runtime.task_state")
local errors = require("core.error_codes")

local global_counter = 0

local M = {}

function M.new(scheduler, opts)
  opts = opts or {}
  local duration = opts.duration or 1
  local auto_advance = opts.auto_advance or false
  local fail_immediate = opts.fail_immediate or false

  return {
    capabilities = {
      async = true,
      parallel = false,
      transactional = false,
    },
    can_craft = function(self, recipe, machine)
      if recipe.machine ~= machine.type then
        return false
      end
      if not recipe.conditions or not recipe.conditions.requires then
        return true
      end
      for key, value in pairs(recipe.conditions.requires) do
        if machine.state[key] ~= value then
          return false
        end
      end
      return true
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
      global_counter = global_counter + 1
      local outputs = {}
      for _, out in ipairs(recipe.outputs) do
        outputs[out.item] = (outputs[out.item] or 0) + out.count * times
      end
      local handle = {
        id = "virtual:" .. recipe.id .. ":" .. tostring(global_counter),
        state = task_state.TaskState.RUNNING,
        outputs = outputs,
        remaining = duration,
        collected = false,
      }
      if fail_immediate then
        scheduler:fail(handle, { code = errors.CRAFT_FAILED })
      else
        scheduler:register(handle, duration)
      end
      return handle
    end,
    request = function(self, payload)
      if type(payload) ~= "table" then
        error({ code = errors.INVALID_REQUEST, reason = "payload_required" })
      end
      if not payload.recipe or payload.times == nil then
        error({ code = errors.INVALID_REQUEST, reason = "recipe_times_required" })
      end
      return self:start(payload.recipe, payload.times)
    end,
    poll = function(self, handle)
      if auto_advance then
        scheduler:tick()
      end
      return handle.state
    end,
    collect = function(self, handle)
      return self:collect_outputs(handle)
    end,
    collect_outputs = function(self, handle)
      if handle.state ~= task_state.TaskState.DONE then
        error({ code = errors.OUTPUTS_NOT_READY, task_id = handle.id })
      end
      if handle.collected then
        error({ code = errors.OUTPUTS_COLLECTED, task_id = handle.id })
      end
      handle.collected = true
      return handle.outputs or {}
    end,
  }
end

return M



