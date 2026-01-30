local assert_equal = require("tests.assert").assert_equal
local plan_graph = require("core.plan_graph")

local M = {}

local function test_plan_graph_basic()
  local graph = plan_graph.new()
  local supply_id = graph:add_node({ kind = "supply", item = "item:a", count = 1 })
  local craft_id = graph:add_node({ kind = "craft", recipe = { id = "make_b" }, times = 1 })
  graph:add_edge(supply_id, craft_id)

  local deps = graph:get_dependencies(craft_id)
  assert_equal(#deps, 1, "deps count")
  assert_equal(deps[1], supply_id, "dependency order")

  local order = graph:topological_sort()
  assert_equal(order[1], supply_id, "topological order supply")
  assert_equal(order[2], craft_id, "topological order craft")
end

function M.run()
  test_plan_graph_basic()
end

return M
