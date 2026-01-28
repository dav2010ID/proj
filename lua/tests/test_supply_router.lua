local assert_equal = require("tests.assert").assert_equal
local supply_router = require("runtime.supply_router")

local M = {}

local function test_split_limits()
  local batches = supply_router.split_batches(
    { ["a"] = 3, ["b"] = 2 },
    { max_items_per_batch = 1, max_total_count = 2 }
  )
  assert_equal(#batches, 3, "batch count")
  assert_equal(batches[1]["a"], 2, "batch1 a")
  assert_equal(batches[2]["a"], 1, "batch2 a")
  assert_equal(batches[3]["b"], 2, "batch3 b")
end

function M.run()
  test_split_limits()
end

return M
