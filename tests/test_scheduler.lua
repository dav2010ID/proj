local assert_equal = require("tests.assert").assert_equal
local plan_graph = require("core.plan_graph")
local scheduler = require("runtime.scheduler")

local M = {}

local function test_scheduler_ready_tasks()
  local graph = plan_graph.new()
  local supply_id = graph:add_node({ kind = "supply", item = "item:a", count = 1 })
  local craft_id = graph:add_node({ kind = "craft", recipe = { id = "make_b" }, times = 1 })
  graph:add_edge(supply_id, craft_id)

  local state = scheduler.schedule(graph, {})
  local ready = scheduler.get_ready_tasks(state)
  assert_equal(#ready, 1, "ready count")
  assert_equal(ready[1].id, supply_id, "supply ready first")

  scheduler.mark_started(state, ready[1])
  scheduler.update_after_completion(ready[1], state)

  ready = scheduler.get_ready_tasks(state)
  assert_equal(#ready, 1, "ready count after supply")
  assert_equal(ready[1].id, craft_id, "craft ready after supply")
end

function M.run()
  test_scheduler_ready_tasks()
end

return M
