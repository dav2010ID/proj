local assert_equal = require("tests.assert").assert_equal
local capability = require("core.capability")

local M = {}

local function test_capability_validate_ok()
  local caps = {
    batch = { max_items = 64, max_total = 128 },
    async = true,
    parallel = false,
    transactional = true,
  }
  local ok = capability.validate(caps)
  assert_equal(ok, true, "valid caps")
end

local function test_capability_validate_bad()
  local caps = {
    batch = { max_items = 0 },
    async = "yes",
  }
  local ok = capability.validate(caps)
  assert_equal(ok, false, "invalid caps")
end

function M.run()
  test_capability_validate_ok()
  test_capability_validate_bad()
end

return M
