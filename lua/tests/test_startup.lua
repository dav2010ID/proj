local assert_equal = require("tests.assert").assert_equal
local startup_test = require("startup_test")
local startup = require("startup")
if type(startup) ~= "table" then
  package.loaded["startup"] = nil
  local chunk = assert(loadfile(debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") .. "/../startup.lua"))
  startup = chunk("startup")
end

local M = {}

local function test_startup_run()
  local snapshot = startup.run()
  if not snapshot then
    error("startup run returned nil")
  end
  assert_equal(snapshot["minecraft:oak_log"], 0, "startup oak_log")
  assert_equal(snapshot["minecraft:oak_planks"], 2, "startup oak_planks")
  assert_equal(snapshot["minecraft:stick"], 2, "startup stick")
  assert_equal(snapshot["minecraft:crafting_table"], 1, "startup crafting_table")
end

local function test_startup_test_run()
  local snapshot = startup_test.run()
  if not snapshot then
    error("startup_test run returned nil")
  end
  assert_equal(snapshot["minecraft:advanced_machine"], 1, "advanced_machine")
end

function M.run()
  test_startup_run()
  test_startup_test_run()
end

return M
