local assert_equal = require("tests.assert").assert_equal
local startup_test = require("startup_test")

local M = {}


local function test_startup_test_run()
  local snapshot = startup_test.run()
  if not snapshot then
    error("startup_test run returned nil")
  end
  assert_equal(snapshot["minecraft:advanced_machine"], 1, "advanced_machine")
end

function M.run()
  test_startup_test_run()
end

return M
