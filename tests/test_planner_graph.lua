local assert_equal = require("tests.assert").assert_equal
local recipe = require("core.recipe")
local planner = require("core.planner")
local virtual_world = require("virtual.world")

local M = {}

local function test_planner_returns_graph()
  local world = virtual_world.new({
    ["item:a"] = 1,
    ["item:b"] = 0,
  })
  local registry = recipe.new_registry()
  recipe.add(registry, {
    id = "make_b",
    inputs = { { item = "item:a", count = 1 } },
    outputs = { { item = "item:b", count = 1 } },
    machine = "m",
    priority = 1,
  })
  local recipes_by_output = recipe.rebuild_index(registry)

  local ok, plan_or_err, graph = planner.plan("item:b", 1, recipes_by_output, world.storage, { return_steps = true })
  assert_equal(ok, true, "plan ok")
  assert_equal(type(graph) == "table", true, "graph returned")
  assert_equal(#graph.nodes, #plan_or_err, "graph size")

  local order = graph:topological_sort()
  assert_equal(#order, #graph.nodes, "topological size")
end

function M.run()
  test_planner_returns_graph()
end

return M
