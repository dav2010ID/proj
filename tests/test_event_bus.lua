local assert_equal = require("tests.assert").assert_equal
local events = require("core.events")
local event_bus = require("runtime.event_bus")

local M = {}

local function test_event_bus_publish()
  local bus = event_bus.new()
  local seen = {}
  bus:subscribe("TaskStarted", function(ev)
    seen = ev
  end)
  local ev = events.TaskStarted({ task_id = "task:bus" })
  bus:publish(ev)
  assert_equal(seen.type, "TaskStarted", "subscriber called")
  assert_equal(seen.task_id, "task:bus", "payload")
end

local function test_event_bus_rejects_invalid()
  local bus = event_bus.new()
  local ok = pcall(function()
    bus:emit({ type = "TaskStarted" })
  end)
  assert_equal(ok, false, "invalid rejected")
end

function M.run()
  test_event_bus_publish()
  test_event_bus_rejects_invalid()
end

return M
