local assert_equal = require("tests.assert").assert_equal
local utils = require("tests.test_utils")
local assert_error = utils.assert_error_code
local task_state = require("runtime.task_state")
local errors = require("core.error_codes")
local virtual_scheduler = require("virtual.scheduler")
local virtual_async_storage = require("virtual.async_storage")
local virtual_machine = require("virtual.machine")

local M = {}

local function test_storage_request_single()
  local scheduler = virtual_scheduler.new()
  local storage = virtual_async_storage.new(scheduler, { ["item:a"] = 3 }, 2)
  storage:prepare({ ["item:a"] = true })
  local handle = storage:request({ item = "item:a", count = 2 })
  assert_equal(storage:poll(handle), task_state.TaskState.RUNNING, "storage request running")
  scheduler:tick()
  assert_equal(storage:poll(handle), task_state.TaskState.RUNNING, "storage request running 2")
  scheduler:tick()
  assert_equal(storage:poll(handle), task_state.TaskState.DONE, "storage request done")
  local taken = storage:collect(handle)
  assert_equal(taken, 2, "storage collect count")
  assert_equal(storage:get("item:a"), 1, "storage stock reduced")
end

local function test_storage_request_batch()
  local scheduler = virtual_scheduler.new()
  local storage = virtual_async_storage.new(scheduler, { ["item:a"] = 2, ["item:b"] = 3 }, 1)
  storage:prepare({ ["item:a"] = true, ["item:b"] = true })
  local handle = storage:request({ items = { ["item:a"] = 2, ["item:b"] = 3 } })
  assert_equal(storage:poll(handle), task_state.TaskState.RUNNING, "batch running")
  scheduler:tick()
  assert_equal(storage:poll(handle), task_state.TaskState.DONE, "batch done")
  local taken = storage:collect(handle)
  assert_equal(taken["item:a"], 2, "batch a")
  assert_equal(taken["item:b"], 3, "batch b")
  assert_equal(storage:get("item:a"), 0, "stock a")
  assert_equal(storage:get("item:b"), 0, "stock b")
end

local function test_machine_request()
  local scheduler = virtual_scheduler.new()
  local machine = virtual_machine.new(scheduler, { duration = 2 })
  local recipe = {
    id = "test_recipe",
    inputs = { { item = "item:x", count = 1 } },
    outputs = { { item = "item:y", count = 1 } },
    machine = "crafting_table",
  }
  local handle = machine:request({ recipe = recipe, times = 3 })
  assert_equal(machine:poll(handle), task_state.TaskState.RUNNING, "machine running")
  scheduler:tick()
  assert_equal(machine:poll(handle), task_state.TaskState.RUNNING, "machine running 2")
  scheduler:tick()
  assert_equal(machine:poll(handle), task_state.TaskState.DONE, "machine done")
  local outputs = machine:collect(handle)
  assert_equal(outputs["item:y"], 3, "machine outputs")
end

local function test_request_validation()
  local scheduler = virtual_scheduler.new()
  local storage = virtual_async_storage.new(scheduler, { ["item:a"] = 1 }, 1)
  local ok, err = pcall(function()
    storage:request({})
  end)
  assert_equal(ok, false, "storage invalid request")
  assert_error(err, errors.INVALID_REQUEST, "invalid request error")

  local machine = virtual_machine.new(scheduler, { duration = 1 })
  local ok_m, err_m = pcall(function()
    machine:request({})
  end)
  assert_equal(ok_m, false, "machine invalid request")
  assert_error(err_m, errors.INVALID_REQUEST, "invalid request error machine")
end

function M.run()
  test_storage_request_single()
  test_storage_request_batch()
  test_machine_request()
  test_request_validation()
end

return M
