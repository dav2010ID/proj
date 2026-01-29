local assert_equal = require("tests.assert").assert_equal
local utils = require("tests.test_utils")
local assert_error = utils.assert_error_code
local virtual_world = require("virtual.world")
local virtual_storage = require("virtual.storage")
local task_state = require("runtime.task_state")
local errors = require("core.error_codes")

local M = {}

local function test_storage_rollback()
  local storage = virtual_storage.new({ ["item:x"] = 5 })
  storage:begin()
  storage:consume("item:x", 2)
  storage:add("item:y", 3)
  storage:rollback()
  local snap = storage:snapshot()
  assert_equal(snap["item:x"], 5, "rollback restores item:x")
  assert_equal(snap["item:y"] or 0, 0, "rollback restores item:y")
end

local function test_storage_snapshot_freeze()
  local storage = virtual_storage.new({ ["item:x"] = 1 })
  storage:prepare({ ["item:x"] = true })
  storage:get("item:x")
  storage:snapshot()
  local ok, err = pcall(function()
    storage:consume("item:x", 1)
  end)
  assert_equal(ok, false, "consume after snapshot should fail")
  assert_error(err, errors.MUTATE_AFTER_SNAPSHOT, "mutate after snapshot")
  storage:rollback()
end

local function test_async_storage_get()
  local world = virtual_world.new({ ["item:a"] = 3 }, { async_storage = true, storage_delay = 2 })
  local storage = world.storage
  storage:prepare({ ["item:a"] = true })
  local req_id = storage:get_batch_async({ ["item:a"] = 2 })
  assert_equal(storage:poll_request(req_id), task_state.TaskState.RUNNING, "get_async pending")
  world:tick(1)
  assert_equal(storage:poll_request(req_id), task_state.TaskState.RUNNING, "get_async pending 2")
  world:tick(1)
  assert_equal(storage:poll_request(req_id), task_state.TaskState.DONE, "get_async done")
  local taken = storage:collect_request(req_id)
  assert_equal(taken["item:a"], 2, "collect_request count")
  local value = storage:get("item:a")
  assert_equal(value, 1, "get after async")
end

local function test_async_batch_supply()
  local world = virtual_world.new(
    { ["item:a"] = 2, ["item:b"] = 3 },
    { async_storage = true, storage_delay = 3 }
  )
  local storage = world.storage
  storage:prepare({ ["item:a"] = true, ["item:b"] = true })
  if storage.set_limits then
    storage:set_limits(1, 3)
  end
  local req_id = storage:get_batch_async({ ["item:a"] = 2, ["item:b"] = 3 })
  assert_equal(storage:poll_request(req_id), task_state.TaskState.RUNNING, "batch pending")
  world:tick(3)
  assert_equal(storage:poll_request(req_id), task_state.TaskState.DONE, "batch done")
  local taken = storage:collect_request(req_id)
  assert_equal(taken["item:a"], 2, "batch a")
  assert_equal(taken["item:b"], 3, "batch b")
  assert_equal(storage:get("item:a"), 0, "stock a")
  assert_equal(storage:get("item:b"), 0, "stock b")
end

local function test_async_batch_fail_rolls_back()
  local world = virtual_world.new(
    { ["item:a"] = 1 },
    { async_storage = true, storage_delay = 2 }
  )
  local storage = world.storage
  storage:prepare({ ["item:a"] = true })
  local req_id = storage:get_batch_async({ ["item:a"] = 2 })
  world:tick(2)
  local state = storage:poll_request(req_id)
  assert_equal(state, task_state.TaskState.FAILED, "batch failed")
  storage:rollback()
  assert_equal(storage:get("item:a"), 1, "stock preserved on fail")
end

function M.run()
  test_storage_rollback()
  test_storage_snapshot_freeze()
  test_async_storage_get()
  test_async_batch_supply()
  test_async_batch_fail_rolls_back()
end

return M

