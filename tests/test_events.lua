local assert_equal = require("tests.assert").assert_equal
local events = require("core.events")

local M = {}

local function test_events_construct()
  local ev = events.TaskStarted({ task_id = "task:1" })
  assert_equal(ev.type, "TaskStarted", "type")
  assert_equal(ev.task_id, "task:1", "task_id")
  assert_equal(type(ev.event_id) == "string", true, "event_id")
  assert_equal(type(ev.time) == "number", true, "time")
end

local function test_events_task_completed()
  local ev = events.TaskCompleted({ task_id = "task:2", result = { ok = true } })
  assert_equal(ev.type, "TaskCompleted", "type")
  assert_equal(ev.task_id, "task:2", "task_id")
end

function M.run()
  test_events_construct()
  test_events_task_completed()
end

return M
