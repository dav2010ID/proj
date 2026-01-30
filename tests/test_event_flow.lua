local assert_equal = require("tests.assert").assert_equal
local virtual_world = require("virtual.world")

local M = {}

local function find_event(trace, event_type)
  for _, ev in ipairs(trace or {}) do
    if ev.type == event_type then
      return ev
    end
  end
  return nil
end

local function test_event_flow_has_ids()
  local world = virtual_world.new({})
  world:attach_machine("m", {}, "m1")
  world:tick(1)

  local trace = world:trace_dump()
  local detected = find_event(trace, "MachineDetected")
  assert_equal(detected ~= nil, true, "machine detected")
  assert_equal(type((detected.payload or {}).event_id) == "string", true, "event_id present")

  local tick = find_event(trace, "Tick")
  assert_equal(tick ~= nil, true, "tick emitted")
  assert_equal(type((tick.payload or {}).event_id) == "string", true, "tick event_id")
end

function M.run()
  test_event_flow_has_ids()
end

return M
