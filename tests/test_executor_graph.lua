local assert_equal = require("tests.assert").assert_equal
local utils = require("tests.test_utils")
local recipe = require("core.recipe")
local planner = require("core.planner")
local executor = require("runtime.executor")
local virtual_world = require("virtual.world")
local virtual_machine = require("virtual.machine")

local M = {}

local function test_executor_graph_success()
  local world = virtual_world.new({ ["item:a"] = 1, ["item:b"] = 0 })
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
  local ok, _plan, graph = planner.plan("item:b", 1, recipes_by_output, world.storage, { return_graph = true })
  assert_equal(ok, true, "plan ok")

  local co = coroutine.create(function()
    local exec_ok, err = executor.execute(graph, world.storage, world:get_allocator())
    if not exec_ok then
      error(err)
    end
  end)
  utils.run_coroutine(world, co, 20)

  world.storage:begin()
  local snap = world.storage:snapshot()
  world.storage:commit()
  assert_equal(snap["item:b"], 1, "item:b produced")
end

function M.run()
  test_executor_graph_success()
end

return M
