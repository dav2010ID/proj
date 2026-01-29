local log = require("core.log")
local assert_equal = require("tests.assert").assert_equal
local task_state = require("runtime.task_state")
local virtual_world = require("virtual.world")

local M = {}

-- provider_factory(world, scheduler) -> provider
-- recipe -> Recipe
function M.run_contract(provider_factory, recipe)
  local world = virtual_world.new({})
  local scheduler = world.scheduler
  local provider = provider_factory(world, scheduler)

  log.info("provider_contract_start")

  local handle = provider:start(recipe, 1)
  assert(handle, "start must return handle")
  assert(handle.id, "handle.id required")

  local state = provider:poll(handle)
  assert(
    state == task_state.TaskState.RUNNING or state == task_state.TaskState.DONE,
    "invalid state after start"
  )

  if state ~= task_state.TaskState.DONE then
    local ok = pcall(function()
      provider:collect_outputs(handle)
    end)
    assert(not ok, "collect_outputs before DONE must error")
  end

  local final_state
  for _ = 1, 20 do
    world:tick(1)
    final_state = provider:poll(handle)
    if final_state ~= task_state.TaskState.RUNNING then
      break
    end
  end

  assert(final_state ~= task_state.TaskState.RUNNING, "task never finished")

  if final_state == task_state.TaskState.FAILED then
    assert(handle.error, "FAILED task must set handle.error")
    local ok = pcall(function()
      provider:collect_outputs(handle)
    end)
    assert(not ok, "collect_outputs after FAILED must error")
    return true
  end

  local outputs = provider:collect_outputs(handle)
  assert(type(outputs) == "table", "outputs must be table")

  local ok = pcall(function()
    provider:collect_outputs(handle)
  end)
  assert(not ok, "collect_outputs twice must error")

  local state2 = provider:poll(handle)
  assert_equal(state2, task_state.TaskState.DONE, "state must stay DONE")

  log.info("provider_contract_ok")
  return true
end

return M

