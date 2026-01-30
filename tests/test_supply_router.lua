local assert_equal = require("tests.assert").assert_equal
local assert_error = require("tests.test_utils").assert_error_code
local supply_router = require("runtime.supply_router")
local errors = require("core.error_codes")

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

local function test_split_limits_capabilities_format()
  local batches = supply_router.split_batches(
    { ["a"] = 3, ["b"] = 2 },
    { batch = { max_items = 1, max_total = 2 } }
  )
  assert_equal(#batches, 3, "batch count (caps)")
  assert_equal(batches[1]["a"], 2, "batch1 a (caps)")
  assert_equal(batches[2]["a"], 1, "batch2 a (caps)")
  assert_equal(batches[3]["b"], 2, "batch3 b (caps)")
end

local function test_split_single_item()
  local batches = supply_router.split_batches(
    { ["iron"] = 100 },
    { max_items_per_batch = 1, max_total_count = 64 }
  )
  assert_equal(#batches, 2, "single item split")
  assert_equal(batches[1]["iron"], 64, "batch1 iron")
  assert_equal(batches[2]["iron"], 36, "batch2 iron")
end

local function test_max_items_distinct()
  local batches = supply_router.split_batches(
    { ["a"] = 1, ["b"] = 1, ["c"] = 1 },
    { max_items_per_batch = 2, max_total_count = 10 }
  )
  assert_equal(#batches, 2, "distinct item split")
  assert_equal(batches[1]["a"], 1, "batch1 a")
  assert_equal(batches[1]["b"], 1, "batch1 b")
  assert_equal(batches[2]["c"], 1, "batch2 c")
end

local function test_empty_request()
  local batches = supply_router.split_batches({}, { max_items_per_batch = 2, max_total_count = 10 })
  assert_equal(#batches, 0, "empty request")
end

local function test_zero_count_rejected()
  local ok, err = pcall(function()
    supply_router.split_batches({ ["a"] = 0 }, { max_items_per_batch = 2, max_total_count = 10 })
  end)
  assert_equal(ok, false, "zero count rejected")
  assert_error(err, errors.NEGATIVE_COUNT, "zero count error")
end

function M.run()
  test_split_limits()
  test_split_limits_capabilities_format()
  test_split_single_item()
  test_max_items_distinct()
  test_empty_request()
  test_zero_count_rejected()
end

return M

