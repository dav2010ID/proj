local assert_equal = require("tests.assert").assert_equal
local events = require("core.events")
local validator = require("core.event_validator")

local M = {}

local function test_event_validator_ok()
  local ev = events.TaskStarted({ task_id = "task:ok" })
  local ok, err = validator.validate_event(ev)
  assert_equal(ok, true, "valid event")
  assert_equal(err == nil, true, "no error")
end

local function test_event_validator_missing_field()
  local ev = { type = "TaskStarted" }
  local ok = validator.validate_event(ev)
  assert_equal(ok, false, "missing field")
end

local function test_event_validator_bad_type()
  local ev = events.TaskStarted({ task_id = 123 })
  local ok = validator.validate_event(ev)
  assert_equal(ok, false, "bad type")
end

local function test_event_validator_unknown()
  local ev = { type = "UnknownEvent", event_id = "1", time = 0 }
  local ok = validator.validate_event(ev)
  assert_equal(ok, false, "unknown type")
end

function M.run()
  test_event_validator_ok()
  test_event_validator_missing_field()
  test_event_validator_bad_type()
  test_event_validator_unknown()
end

return M
