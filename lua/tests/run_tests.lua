local here = debug.getinfo(1, "S").source:sub(2)
local here_dir = here:match("^(.*)[/\\]") or "."
local lua_root = here_dir .. "/.."
package.path = lua_root .. "/?.lua;" .. lua_root .. "/?/init.lua;" .. package.path
local log = require("core.log")
local recipe = require("core.recipe")
local planner = require("core.planner")
local executor = require("runtime.executor")
local virtual_world = require("runtime.virtual_world")
local virtual_machine = require("runtime.virtual_machine")
local virtual_storage = require("runtime.virtual_storage")
local errors = require("core.error_codes")

local function assert_equal(actual, expected, message)
  if actual ~= expected then
    error((message or "assert_equal failed") .. ": expected=" .. tostring(expected) .. " actual=" .. tostring(actual))
  end
end

local function assert_error_code(err, code, message)
  if type(err) == "table" and err.code then
    if err.code ~= code then
      error((message or "assert_error_code failed") .. ": expected=" .. tostring(code) .. " actual=" .. tostring(err.code))
    end
    return
  end
  local text = tostring(err)
  if not string.find(text, code, 1, true) then
    error((message or "assert_error_code failed") .. ": expected=" .. tostring(code) .. " actual=" .. text)
  end
end

local function run_coroutine(world, co, max_ticks)
  local ticks = 0
  while coroutine.status(co) ~= "dead" do
    local ok_run, err_run = coroutine.resume(co)
    if not ok_run then
      error(err_run)
    end
    if world then
      world:tick(1)
    end
    ticks = ticks + 1
    if max_ticks and ticks > max_ticks then
      error({ code = errors.TASK_TIMEOUT, message = "test_timeout" })
    end
  end
end

local function test_planner_basic()
  local world = virtual_world.new({
    ["item:a"] = 1,
    ["item:b"] = 0,
  })

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
  assert_equal(#plan_or_err, 2, "plan length")
end

local function test_planner_cycle_detection()
  local world = virtual_world.new({
    ["item:a"] = 0,
    ["item:b"] = 0,
  })
  local registry = recipe.new_registry()
  recipe.add(registry, {
    id = "make_a",
    inputs = { { item = "item:b", count = 1 } },
    outputs = { { item = "item:a", count = 1 } },
    machine = "m",
    priority = 1,
  })
  recipe.add(registry, {
    id = "make_b",
    inputs = { { item = "item:a", count = 1 } },
    outputs = { { item = "item:b", count = 1 } },
    machine = "m",
    priority = 1,
  })
  local recipes_by_output = recipe.rebuild_index(registry)
  local ok, err = planner.plan("item:a", 1, recipes_by_output, world.storage)
  assert_equal(ok, false, "cycle detection")
  assert_error_code(err, errors.CYCLE_DETECTED, "cycle detected")
end

local function test_planner_unreachable_item()
  local world = virtual_world.new({ ["item:x"] = 0 })
  local registry = recipe.new_registry()
  local recipes_by_output = recipe.rebuild_index(registry)
  local ok, err = planner.plan("item:x", 1, recipes_by_output, world.storage)
  assert_equal(ok, false, "unreachable item")
  assert_error_code(err, errors.NO_RECIPE_OR_STOCK, "no recipe or stock")
end

local function serialize_plan(plan)
  local items = {}
  for _, step in ipairs(plan) do
    if step.kind == "supply" then
      table.insert(items, "supply:" .. step.item .. ":" .. tostring(step.count))
    else
      table.insert(items, "craft:" .. step.recipe.id .. ":" .. tostring(step.times))
    end
  end
  return table.concat(items, "|")
end

local function test_planner_deterministic()
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
  local ok1, plan1 = planner.plan("item:b", 1, recipes_by_output, world.storage)
  local ok2, plan2 = planner.plan("item:b", 1, recipes_by_output, world.storage)
  assert_equal(ok1, true, "plan ok 1")
  assert_equal(ok2, true, "plan ok 2")
  assert_equal(serialize_plan(plan1), serialize_plan(plan2), "deterministic plan")
end

local function test_executor_success()
  local world = virtual_world.new({
    ["item:a"] = 1,
    ["item:b"] = 0,
  })
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

  local snap = world.storage:snapshot()
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
    assert_error_code(err, errors.NO_COMPATIBLE_MACHINE, "no_compatible_machine")
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
    assert_error_code(err, errors.DEADLOCK, "deadlock")
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
    assert_error_code(err, errors.TASK_TIMEOUT, "task timeout")
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
  local ticks = 0
  while coroutine.status(co) ~= "dead" and ticks < 50 do
    local ok_run, err_run = coroutine.resume(co)
    if not ok_run then
      error(err_run)
    end
    world:tick(1)
    ticks = ticks + 1
  end
  if coroutine.status(co) ~= "dead" then
    local started = 0
    local finished = 0
    for _, ev in ipairs(world:trace_dump()) do
      if ev.type == "TaskStarted" then
        started = started + 1
      elseif ev.type == "TaskFinished" then
        finished = finished + 1
      end
    end
    error({ code = errors.TASK_TIMEOUT, message = "parallel_timeout", data = { started = started, finished = finished } })
  end
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
  local ticks = 0
  while coroutine.status(co) ~= "dead" and ticks < 50 do
    local ok_run, err_run = coroutine.resume(co)
    if not ok_run then
      error(err_run)
    end
    world:tick(1)
    ticks = ticks + 1
  end
  if coroutine.status(co) ~= "dead" then
    local started = 0
    local finished = 0
    for _, ev in ipairs(world:trace_dump()) do
      if ev.type == "TaskStarted" then
        started = started + 1
      elseif ev.type == "TaskFinished" then
        finished = finished + 1
      end
    end
    print("[DEBUG] parallel timeout started=" .. tostring(started) .. " finished=" .. tostring(finished))
    error({ code = errors.TASK_TIMEOUT, message = "parallel_timeout", data = { started = started, finished = finished } })
  end
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
    if ev.type == "TaskStarted" and ev.task_id and string.find(ev.task_id, "make_b", 1, true) then
      start_b = ev.now
    elseif ev.type == "TaskFinished" and ev.task_id and string.find(ev.task_id, "make_b", 1, true) then
      finish_b = ev.now
    elseif ev.type == "TaskStarted" and ev.task_id and string.find(ev.task_id, "make_c", 1, true) then
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
  assert_error_code(err, errors.MUTATE_AFTER_SNAPSHOT, "mutate after snapshot")
  storage:rollback()
end

local function test_virtual_machine_outputs_once()
  local scheduler = require("runtime.virtual_scheduler").new()
  local provider = virtual_machine.new(scheduler, { duration = 1 })
  local recipe = {
    id = "r1",
    inputs = {},
    outputs = { { item = "item:o", count = 1 } },
    machine = "m",
  }
  local handle = provider:start(recipe, 1)
  scheduler:tick()
  local outputs = provider:collect_outputs(handle)
  assert_equal(outputs["item:o"], 1, "outputs collected")
  local ok, err = pcall(function()
    provider:collect_outputs(handle)
  end)
  assert_equal(ok, false, "collect outputs twice should fail")
  assert_error_code(err, errors.OUTPUTS_COLLECTED, "outputs collected")
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
    assert_error_code(err, errors.CRAFT_FAILED, "craft failed")
  end)

  run_coroutine(world, co, 20)

  local snap = world.storage:snapshot()
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
  local registry = recipe.new_registry()
  recipe.add(registry, {
    id = "make_a",
    inputs = {},
    outputs = { { item = "item:a", count = 1 } },
    machine = "m",
    priority = 1,
  })
  local recipes_by_output = recipe.rebuild_index(registry)
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

local function run_all()
  log.info("test_planner_basic")
  test_planner_basic()
  log.info("test_planner_cycle_detection")
  test_planner_cycle_detection()
  log.info("test_planner_unreachable_item")
  test_planner_unreachable_item()
  log.info("test_planner_deterministic")
  test_planner_deterministic()
  log.info("test_executor_success")
  test_executor_success()
  log.info("test_no_compatible_machine")
  test_no_compatible_machine()
  log.info("test_executor_deadlock")
  test_executor_deadlock()
  log.info("test_executor_timeout")
  test_executor_timeout()
  log.info("test_executor_one_machine_serial")
  test_executor_one_machine_serial()
  log.info("test_executor_two_machines_parallel")
  test_executor_two_machines_parallel()
  log.info("test_executor_dependency_order")
  test_executor_dependency_order()
  log.info("test_storage_rollback")
  test_storage_rollback()
  log.info("test_storage_snapshot_freeze")
  test_storage_snapshot_freeze()
  log.info("test_virtual_machine_outputs_once")
  test_virtual_machine_outputs_once()
  log.info("test_executor_rollback_on_fail")
  test_executor_rollback_on_fail()
  log.info("test_executor_yield")
  test_executor_yield()
end

local ok, err = pcall(run_all)
if not ok then
  log.error(err)
  return
end
log.info("All virtual tests passed")

