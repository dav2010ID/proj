local assert_equal = require("tests.assert").assert_equal
local utils = require("tests.test_utils")
local recipe = require("core.recipe")
local planner = require("core.planner")
local executor = require("runtime.executor")
local virtual_world = require("virtual.world")
local virtual_machine = require("virtual.machine")

local M = {}

local function test_async_storage_delays_craft()
  local world = virtual_world.new(
    { ["item:a"] = 1 },
    { async_storage = true, storage_delay = 3 }
  )
  local scheduler = world.scheduler
  local provider = virtual_machine.new(scheduler, { duration = 1 })
  world:attach_machine("m", provider, "m1")

  local registry = recipe.new_registry()
  recipe.add(registry, {
    id = "make_b",
    inputs = { { item = "item:a", count = 1 } },
    outputs = { { item = "item:b", count = 1 } },
    machine = "m",
    priority = 1,
  })

  local recipes_by_output = recipe.rebuild_index(registry)
  local ok, plan_or_err = planner.plan("item:b", 1, recipes_by_output, world.storage)
  assert(ok, plan_or_err)

  local co = coroutine.create(function()
    local exec_ok, err = executor.execute(plan_or_err, world.storage, world:get_allocator())
    if not exec_ok then
      error(err)
    end
  end)

  utils.run_coroutine(world, co, 50)

  local first_start = nil
  for _, ev in ipairs(world:trace_dump()) do
    if ev.type == "TaskStarted" then
      first_start = ev.now
      break
    end
  end
  assert_equal(first_start ~= nil, true, "task started")
  assert_equal(first_start >= 3, true, "craft starts after async supply")
end

function M.run()
  test_async_storage_delays_craft()
end

return M

