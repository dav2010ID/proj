local assert_equal = require("tests.assert").assert_equal
local utils = require("tests.test_utils")
local assert_error = utils.assert_error_code
local run_coroutine = utils.run_coroutine
local recipe = require("core.recipe")
local planner = require("core.planner")
local executor = require("runtime.executor")
local virtual_world = require("virtual.world")
local virtual_machine = require("virtual.machine")
local errors = require("core.error_codes")

local M = {}

local function test_executor_success()
  local world = virtual_world.new({ ["item:a"] = 1, ["item:b"] = 0 })
  local scheduler = world.scheduler
  local provider = virtual_machine.new(scheduler, { duration = 1 })
  world:attach_machine("m", provider, "m1")
  local registry = recipe.new_registry()
  recipe.add(registry, {
    id = "make_b",
    inputs = { { item = "item:a", count = 1 } },
    outputs = { { item = "item:b", count = 1 } },
    machine = "m",
    priority = 1,
  })
  local recipes_by_output = recipe.rebuild_index(registry)
  local ok, plan_or_err = planner.plan("item:b", 1, recipes_by_output, world.storage)
  assert_equal(ok, true, "plan ok")
  local co = coroutine.create(function()
    local exec_ok, err = executor.execute(plan_or_err, world.storage, world:get_allocator())
    if not exec_ok then
      error(err)
    end
  end)
  run_coroutine(world, co, 20)
  world.storage:begin()
  local snap = world.storage:snapshot()
  world.storage:commit()
  assert_equal(snap["item:a"], 0, "item:a consumed")
  assert_equal(snap["item:b"], 1, "item:b produced")
end

local function test_no_compatible_machine()
  local world = virtual_world.new({ ["item:a"] = 1, ["item:b"] = 0 })
  local registry = recipe.new_registry()
  recipe.add(registry, {
    id = "make_b",
    inputs = { { item = "item:a", count = 1 } },
    outputs = { { item = "item:b", count = 1 } },
    machine = "m",
    priority = 1,
  })
  local recipes_by_output = recipe.rebuild_index(registry)
  local ok, plan_or_err = planner.plan("item:b", 1, recipes_by_output, world.storage)
  assert_equal(ok, true, "plan ok")
  local co = coroutine.create(function()
    local exec_ok, err = executor.execute(plan_or_err, world.storage, world:get_allocator())
    if exec_ok then
      error("expected failure")
    end
    assert_error(err, errors.NO_COMPATIBLE_MACHINE, "no_compatible_machine")
  end)
  run_coroutine(world, co, 20)
end

local function test_executor_deadlock()
  local world = virtual_world.new({ ["item:a"] = 0 })
  local scheduler = world.scheduler
  local provider = virtual_machine.new(scheduler, { duration = 1 })
  world:attach_machine("m", provider, "m1")
  local registry = recipe.new_registry()
  recipe.add(registry, {
    id = "make_b",
    inputs = { { item = "item:a", count = 1 } },
    outputs = { { item = "item:b", count = 1 } },
    machine = "m",
    priority = 1,
  })
  local plan = { require("core.steps").craft(recipe.rebuild_index(registry)["item:b"][1], 1) }
  local co = coroutine.create(function()
    local exec_ok, err = executor.execute(plan, world.storage, world:get_allocator())
    if exec_ok then
      error("expected deadlock")
    end
    assert_error(err, errors.DEADLOCK, "deadlock")
  end)
  run_coroutine(world, co, 20)
end

local function test_executor_timeout()
  local world = virtual_world.new({ ["item:a"] = 1 })
  local scheduler = world.scheduler
  local provider = virtual_machine.new(scheduler, { duration = 5 })
  world:attach_machine("m", provider, "m1")
  local registry = recipe.new_registry()
  recipe.add(registry, {
    id = "make_b",
    inputs = { { item = "item:a", count = 1 } },
    outputs = { { item = "item:b", count = 1 } },
    machine = "m",
    priority = 1,
  })
  local recipes_by_output = recipe.rebuild_index(registry)
  local ok, plan_or_err = planner.plan("item:b", 1, recipes_by_output, world.storage)
  assert_equal(ok, true, "plan ok")
  local co = coroutine.create(function()
    local exec_ok, err = executor.execute(plan_or_err, world.storage, world:get_allocator(), { task_timeout = 1 })
    if exec_ok then
      error("expected timeout")
    end
    assert_error(err, errors.TASK_TIMEOUT, "task timeout")
  end)
  run_coroutine(world, co, 20)
end

local function test_executor_one_machine_serial()
  local world = virtual_world.new({ ["item:a"] = 2 })
  local scheduler = world.scheduler
  local provider = virtual_machine.new(scheduler, { duration = 2 })
  world:attach_machine("m", provider, "m1")
  local registry = recipe.new_registry()
  recipe.add(registry, {
    id = "make_b",
    inputs = { { item = "item:a", count = 1 } },
    outputs = { { item = "item:b", count = 1 } },
    machine = "m",
    priority = 1,
  })
  local recipes_by_output = recipe.rebuild_index(registry)
  local plan = {
    require("core.steps").supply("item:a", 2),
    require("core.steps").craft(recipes_by_output["item:b"][1], 1),
    require("core.steps").craft(recipes_by_output["item:b"][1], 1),
  }
  local co = coroutine.create(function()
    local exec_ok, err = executor.execute(plan, world.storage, world:get_allocator())
    if not exec_ok then
      error(err)
    end
  end)
  run_coroutine(world, co, 50)
  local started = 0
  for _, ev in ipairs(world:trace_dump()) do
    if ev.type == "TaskStarted" then
      started = started + 1
    end
  end
  assert_equal(started, 2, "two tasks started")
end

local function test_executor_two_machines_parallel()
  local world = virtual_world.new({ ["item:a"] = 2 })
  local scheduler = world.scheduler
  local provider1 = virtual_machine.new(scheduler, { duration = 2 })
  local provider2 = virtual_machine.new(scheduler, { duration = 2 })
  world:attach_machine("m", provider1, "m1")
  world:attach_machine("m", provider2, "m2")
  local registry = recipe.new_registry()
  recipe.add(registry, {
    id = "make_b",
    inputs = { { item = "item:a", count = 1 } },
    outputs = { { item = "item:b", count = 1 } },
    machine = "m",
    priority = 1,
  })
  local recipes_by_output = recipe.rebuild_index(registry)
  local plan = {
    require("core.steps").supply("item:a", 2),
    require("core.steps").craft(recipes_by_output["item:b"][1], 1),
    require("core.steps").craft(recipes_by_output["item:b"][1], 1),
  }
  local co = coroutine.create(function()
    local exec_ok, err = executor.execute(plan, world.storage, world:get_allocator())
    if not exec_ok then
      error(err)
    end
  end)
  run_coroutine(world, co, 50)
  local started = 0
  for _, ev in ipairs(world:trace_dump()) do
    if ev.type == "TaskStarted" then
      started = started + 1
    end
  end
  assert_equal(started, 2, "two tasks started")
end

local function test_executor_dependency_order()
  local world = virtual_world.new({ ["item:a"] = 1 })
  local scheduler = world.scheduler
  local provider1 = virtual_machine.new(scheduler, { duration = 2 })
  local provider2 = virtual_machine.new(scheduler, { duration = 2 })
  world:attach_machine("m", provider1, "m1")
  world:attach_machine("m", provider2, "m2")
  local registry = recipe.new_registry()
  recipe.add(registry, {
    id = "make_b",
    inputs = { { item = "item:a", count = 1 } },
    outputs = { { item = "item:b", count = 1 } },
    machine = "m",
    priority = 1,
  })
  recipe.add(registry, {
    id = "make_c",
    inputs = { { item = "item:b", count = 1 } },
    outputs = { { item = "item:c", count = 1 } },
    machine = "m",
    priority = 1,
  })
  local recipes_by_output = recipe.rebuild_index(registry)
  local plan = {
    require("core.steps").supply("item:a", 1),
    require("core.steps").craft(recipes_by_output["item:b"][1], 1),
    require("core.steps").craft(recipes_by_output["item:c"][1], 1),
  }
  local co = coroutine.create(function()
    local exec_ok, err = executor.execute(plan, world.storage, world:get_allocator())
    if not exec_ok then
      error(err)
    end
  end)
  run_coroutine(world, co, 50)
  local start_b, finish_b, start_c
  for _, ev in ipairs(world:trace_dump()) do
    local payload = ev.payload or {}
    if ev.type == "TaskStarted" and payload.task_id and string.find(payload.task_id, "make_b", 1, true) then
      start_b = ev.now
    elseif ev.type == "TaskFinished" and payload.task_id and string.find(payload.task_id, "make_b", 1, true) then
      finish_b = ev.now
    elseif ev.type == "TaskStarted" and payload.task_id and string.find(payload.task_id, "make_c", 1, true) then
      start_c = ev.now
    end
  end
  if start_b == nil or finish_b == nil or start_c == nil then
    error("missing task events")
  end
  if start_c <= finish_b then
    error("dependent craft started before output ready")
  end
end

local function test_executor_rollback_on_fail()
  local world = virtual_world.new({ ["item:a"] = 1, ["item:b"] = 0 })
  local scheduler = world.scheduler
  local provider = virtual_machine.new(scheduler, { fail_immediate = true })
  world:attach_machine("m", provider, "m1")
  local registry = recipe.new_registry()
  recipe.add(registry, {
    id = "make_b",
    inputs = { { item = "item:a", count = 1 } },
    outputs = { { item = "item:b", count = 1 } },
    machine = "m",
    priority = 1,
  })
  local recipes_by_output = recipe.rebuild_index(registry)
  local ok, plan_or_err = planner.plan("item:b", 1, recipes_by_output, world.storage)
  assert_equal(ok, true, "plan ok")
  local co = coroutine.create(function()
    local exec_ok, err = executor.execute(plan_or_err, world.storage, world:get_allocator())
    if exec_ok then
      error("expected failure")
    end
    assert_error(err, errors.CRAFT_FAILED, "craft failed")
  end)
  run_coroutine(world, co, 20)
  world.storage:begin()
  local snap = world.storage:snapshot()
  world.storage:commit()
  assert_equal(snap["item:a"], 1, "rollback restores item:a")
  assert_equal(snap["item:b"] or 0, 0, "rollback restores item:b")
  local allocator = world:get_allocator()
  local locked = allocator:lock("m")
  assert_equal(locked ~= nil, true, "machine unlocked after failure")
  if not locked or not locked.id then
    error("missing locked machine id")
  end
  allocator:unlock(locked.id)
end

local function test_executor_yield()
  local world = virtual_world.new({ ["item:a"] = 1000 })
  local plan = {}
  for i = 1, 1000 do
    plan[i] = require("core.steps").supply("item:a", 1)
  end
  local co = coroutine.create(function()
    executor.execute(plan, world.storage, world:get_allocator(), { max_steps_per_tick = 10 })
  end)
  local ok_run, err_run = coroutine.resume(co)
  if not ok_run then
    error(err_run)
  end
  assert_equal(coroutine.status(co), "suspended", "executor yields")
end

function M.run()
  test_executor_success()
  test_no_compatible_machine()
  test_executor_deadlock()
  test_executor_timeout()
  test_executor_one_machine_serial()
  test_executor_two_machines_parallel()
  test_executor_dependency_order()
  test_executor_rollback_on_fail()
  test_executor_yield()
end

return M

