local assert_equal = require("tests.assert").assert_equal


local log = require("core.log")
local recipe = require("core.recipe")
local planner = require("core.planner")
local executor = require("runtime.executor")
local multi_storage = require("runtime.multi_storage")
local chest_adapter = require("providers.resource.chest_adapter")
local virtual_world = require("virtual.world")
local virtual_machine = require("virtual.machine")
local errors = require("core.error_codes")

local M = {}

local function build_craftos_storage(bus, seed_chest_1, seed_chest_2)
  if not periphemu or not peripheral then
    return nil
  end

  local function cleanup_side(side)
    if periphemu.remove then
      pcall(function()
        periphemu.remove(side)
      end)
    end
  end

  local function seed_provider(provider, seed)
    provider:begin()
    for item, count in pairs(seed or {}) do
      provider:add(item, count)
    end
    provider:commit()
  end

  cleanup_side("front")
  cleanup_side("back")

  local chest_1 = chest_adapter.new({
    side = "front",
    create = true,
    double = false,
    allowlist = {
      ["minecraft:oak_log"] = true,
      ["minecraft:oak_planks"] = true,
      ["minecraft:stick"] = true,
      ["minecraft:cobblestone"] = true,
      ["minecraft:furnace"] = true,
    },
  })

  local chest_2 = chest_adapter.new({
    side = "back",
    create = true,
    double = false,
    allowlist = {
      ["minecraft:iron_ore"] = true,
      ["minecraft:coal"] = true,
      ["minecraft:iron_ingot"] = true,
      ["minecraft:iron_plate"] = true,
      ["minecraft:machine_casing"] = true,
      ["minecraft:iron_gear"] = true,
      ["minecraft:basic_circuit"] = true,
      ["minecraft:mechanism"] = true,
      ["minecraft:advanced_machine"] = true,
    },
  })

  seed_provider(chest_1, {
    ["minecraft:oak_log"] = (seed_chest_1 and seed_chest_1["minecraft:oak_log"]) or 8,
    ["minecraft:cobblestone"] = (seed_chest_1 and seed_chest_1["minecraft:cobblestone"]) or 16,
  })

  seed_provider(chest_2, {
    ["minecraft:iron_ore"] = (seed_chest_2 and seed_chest_2["minecraft:iron_ore"]) or 13,
    ["minecraft:coal"] = (seed_chest_2 and seed_chest_2["minecraft:coal"]) or 13,
  })

  return {
    kind = "craftos",
    chest_1 = chest_1,
    chest_2 = chest_2,
    storage = multi_storage.new({
      { id = "chest_1", provider = chest_1 },
      { id = "chest_2", provider = chest_2 },
    }, bus),
  }
end

local function run_startup(opts)
  opts = opts or {}
  local world = virtual_world.new({})
  local craftos = build_craftos_storage(world.bus, opts.seed_chest_1, opts.seed_chest_2)
  if craftos then
    world:attach_storage(craftos.storage)
  else
    world.storage:begin()
    world.storage:add("minecraft:oak_log", 8)
    world.storage:add("minecraft:cobblestone", 16)
    world.storage:add("minecraft:iron_ore", 13)
    world.storage:add("minecraft:coal", 13)
    world.storage:commit()
  end

  local scheduler = world.scheduler

  -- machines
  local crafting = virtual_machine.new(scheduler, { duration = 1 })
  local furnace  = virtual_machine.new(scheduler, { duration = 3 })
  local assembler = virtual_machine.new(scheduler, { duration = 2 })

  world:attach_machine("crafting_table", crafting, "ct_1")
  world:attach_machine("furnace", furnace, "f_1")
  world:attach_machine("assembler", assembler, "a_1")

  local registry = recipe.new_registry()

  -- 1. logs -> planks
  recipe.add(registry, {
    id = "planks",
    inputs = { { item = "minecraft:oak_log", count = 1 } },
    outputs = { { item = "minecraft:oak_planks", count = 4 } },
    machine = "crafting_table",
    priority = 50,
  })

  -- 2. planks -> sticks
  recipe.add(registry, {
    id = "sticks",
    inputs = { { item = "minecraft:oak_planks", count = 2 } },
    outputs = { { item = "minecraft:stick", count = 4 } },
    machine = "crafting_table",
    priority = 40,
  })

  -- 3. cobble -> furnace
  recipe.add(registry, {
    id = "furnace",
    inputs = {
      { item = "minecraft:cobblestone", count = 8 },
    },
    outputs = { { item = "minecraft:furnace", count = 1 } },
    machine = "crafting_table",
    priority = 30,
  })

  -- 4. iron ore -> iron ingot
  recipe.add(registry, {
    id = "smelt_iron",
    inputs = {
      { item = "minecraft:iron_ore", count = 1 },
      { item = "minecraft:coal", count = 1 },
    },
    outputs = { { item = "minecraft:iron_ingot", count = 1 } },
    machine = "furnace",
    priority = 60,
  })

  -- 5. iron ingot -> plates
  recipe.add(registry, {
    id = "iron_plate",
    inputs = { { item = "minecraft:iron_ingot", count = 2 } },
    outputs = { { item = "minecraft:iron_plate", count = 1 } },
    machine = "assembler",
    priority = 20,
  })

  -- 6. iron plates -> casing
  recipe.add(registry, {
    id = "machine_casing",
    inputs = {
      { item = "minecraft:iron_plate", count = 4 },
    },
    outputs = { { item = "minecraft:machine_casing", count = 1 } },
    machine = "assembler",
    priority = 15,
  })

  -- 7. sticks + iron -> gears
  recipe.add(registry, {
    id = "iron_gear",
    inputs = {
      { item = "minecraft:iron_ingot", count = 2 },
      { item = "minecraft:stick", count = 2 },
    },
    outputs = { { item = "minecraft:iron_gear", count = 1 } },
    machine = "crafting_table",
    priority = 25,
  })

  -- 8. planks + iron -> circuit board
  recipe.add(registry, {
    id = "basic_circuit",
    inputs = {
      { item = "minecraft:oak_planks", count = 4 },
      { item = "minecraft:iron_ingot", count = 1 },
    },
    outputs = { { item = "minecraft:basic_circuit", count = 1 } },
    machine = "assembler",
    priority = 10,
  })

  -- 9. gears + circuit -> mechanism
  recipe.add(registry, {
    id = "mechanism",
    inputs = {
      { item = "minecraft:iron_gear", count = 2 },
      { item = "minecraft:basic_circuit", count = 1 },
    },
    outputs = { { item = "minecraft:mechanism", count = 1 } },
    machine = "assembler",
    priority = 5,
  })

  -- 10. final assembly
  recipe.add(registry, {
    id = "advanced_machine",
    inputs = {
      { item = "minecraft:machine_casing", count = 1 },
      { item = "minecraft:mechanism", count = 1 },
      { item = "minecraft:furnace", count = 1 },
    },
    outputs = { { item = "minecraft:advanced_machine", count = 1 } },
    machine = "assembler",
    priority = 1,
  })

  local recipes_by_output = recipe.rebuild_index(registry)
  local resource = world.storage
  local allocator = world:get_allocator()

  local ok, graph_or_err =
    planner.plan("minecraft:advanced_machine", 1, recipes_by_output, resource)

  if not ok then
    if not opts.suppress_errors then
      log.error(plan_or_err)
    end
    return {
      ok = false,
      err = graph_or_err,
      craftos = craftos,
      trace = world:trace_dump(),
    }
  end

  local co = coroutine.create(function()
    local exec_ok, err = executor.execute(graph_or_err, resource, allocator, { max_steps_per_tick = 1000 })
    if not exec_ok then
      log.error(err)
    else
      log.info("Execution complete")
    end
  end)

  while coroutine.status(co) ~= "dead" do
    local ok_run, err_run = coroutine.resume(co)
    if not ok_run then
      log.error(err_run)
      break
    end
    world:tick(1)
  end

  resource:begin()
  local snapshot = resource:snapshot()
  resource:commit()
  log.info("Final stock:")
  for k, v in pairs(snapshot) do
    log.info("  " .. k .. " = " .. tostring(v))
  end

  return {
    ok = true,
    snapshot = snapshot,
    craftos = craftos,
    trace = world:trace_dump(),
  }
end

local function get_first_time(trace, event_type, matcher)
  for _, ev in ipairs(trace) do
    local payload = ev.payload or {}
    if ev.type == event_type and (not matcher or matcher(payload, ev)) then
      return ev.now or 0
    end
  end
  return nil
end

local function get_last_time(trace, event_type, matcher)
  local found = nil
  for _, ev in ipairs(trace) do
    local payload = ev.payload or {}
    if ev.type == event_type and (not matcher or matcher(payload, ev)) then
      found = ev.now or 0
    end
  end
  return found
end

local function assert_only_in(primary, secondary, items, label)
  for _, item in ipairs(items) do
    assert_equal(secondary[item] or 0, 0, label .. " secondary has " .. item)
  end
end

local function assert_all_zero(snapshot, items, label)
  for _, item in ipairs(items) do
    assert_equal(snapshot[item] or 0, 0, label .. " has residue " .. item)
  end
end


local function test_startup_test_run()
  local result = run_startup()
  if not result or not result.ok then
    error("startup_test run returned nil")
  end
  local snapshot = result.snapshot
  local trace = result.trace or {}
  assert_equal(snapshot["minecraft:advanced_machine"], 1, "advanced_machine")

  assert_all_zero(snapshot, {
    "minecraft:stick",
    "minecraft:furnace",
    "minecraft:iron_ingot",
    "minecraft:iron_plate",
    "minecraft:machine_casing",
    "minecraft:iron_gear",
    "minecraft:basic_circuit",
    "minecraft:mechanism",
  }, "final stock")

  if result.craftos then
    result.craftos.chest_1:begin()
    result.craftos.chest_2:begin()
    local chest_1 = result.craftos.chest_1:snapshot()
    local chest_2 = result.craftos.chest_2:snapshot()
    result.craftos.chest_1:commit()
    result.craftos.chest_2:commit()

    assert_only_in(chest_1, chest_2, {
      "minecraft:oak_log",
      "minecraft:oak_planks",
      "minecraft:stick",
      "minecraft:cobblestone",
      "minecraft:furnace",
    }, "chest_1")

    assert_only_in(chest_2, chest_1, {
      "minecraft:iron_ore",
      "minecraft:coal",
      "minecraft:iron_ingot",
      "minecraft:iron_plate",
      "minecraft:machine_casing",
      "minecraft:iron_gear",
      "minecraft:basic_circuit",
      "minecraft:mechanism",
      "minecraft:advanced_machine",
    }, "chest_2")

    local smelt_start = get_first_time(trace, "TaskStarted", function(payload)
      return payload.task_id and string.find(payload.task_id, "smelt_iron", 1, true)
    end)
    local smelt_finish = get_last_time(trace, "TaskFinished", function(payload)
      return payload.task_id and string.find(payload.task_id, "smelt_iron", 1, true)
    end)
    assert_equal(smelt_start ~= nil, true, "smelt_iron started")
    assert_equal(smelt_finish ~= nil, true, "smelt_iron finished")

    local iron_plate_start = get_first_time(trace, "TaskStarted", function(payload)
      return payload.task_id and string.find(payload.task_id, "iron_plate", 1, true)
    end)
    local iron_plate_finish = get_last_time(trace, "TaskFinished", function(payload)
      return payload.task_id and string.find(payload.task_id, "iron_plate", 1, true)
    end)
    assert_equal(iron_plate_start ~= nil, true, "iron_plate started")
    assert_equal(iron_plate_finish ~= nil, true, "iron_plate finished")

    local mechanism_finish = get_last_time(trace, "TaskFinished", function(payload)
      return payload.task_id and string.find(payload.task_id, "mechanism", 1, true)
    end)
    assert_equal(mechanism_finish ~= nil, true, "mechanism finished")

    local casing_finish = get_last_time(trace, "TaskFinished", function(payload)
      return payload.task_id and string.find(payload.task_id, "machine_casing", 1, true)
    end)
    assert_equal(casing_finish ~= nil, true, "machine_casing finished")

    local furnace_finish = get_last_time(trace, "TaskFinished", function(payload)
      return payload.task_id and string.find(payload.task_id, "furnace", 1, true)
    end)
    assert_equal(furnace_finish ~= nil, true, "furnace finished")

    local advanced_start = get_first_time(trace, "TaskStarted", function(payload)
      return payload.task_id and string.find(payload.task_id, "advanced_machine", 1, true)
    end)
    assert_equal(advanced_start ~= nil, true, "advanced_machine started")
    if advanced_start then
      assert_equal(advanced_start > casing_finish, true, "advanced_machine after casing")
      assert_equal(advanced_start > mechanism_finish, true, "advanced_machine after mechanism")
      assert_equal(advanced_start > furnace_finish, true, "advanced_machine after furnace")
    end

    local batch_done_chest_2 = get_first_time(trace, "BatchDone", function(payload)
      return payload.storage_id == "chest_2"
    end)
    if smelt_start and batch_done_chest_2 then
      assert_equal(batch_done_chest_2 <= smelt_start, true, "smelt after supply batch")
    end

    local parallel_ok = false
    for _, ev in ipairs(trace) do
      local payload = ev.payload or {}
      if ev.type == "TaskStarted" and payload.task_id and (string.find(payload.task_id, "planks", 1, true) or string.find(payload.task_id, "sticks", 1, true)) then
        if smelt_start and smelt_finish and ev.now >= smelt_start and ev.now <= smelt_finish then
          parallel_ok = true
          break
        end
      end
    end
    assert_equal(parallel_ok, true, "parallel smelt and crafting")

    local batch_queued = 0
    for _, ev in ipairs(trace) do
      if ev.type == "BatchQueued" then
        batch_queued = batch_queued + 1
      end
    end
    assert_equal(batch_queued, 2, "batch aggregation per storage")
  end
end

function M.run()
  log.info("test_startup:start")
  test_startup_test_run()
  local negative = run_startup({
    seed_chest_2 = {
      ["minecraft:iron_ore"] = 13,
      ["minecraft:coal"] = 12,
    },
    suppress_errors = true,
  })
  if negative and negative.ok then
    error("negative variant unexpectedly succeeded")
  end
  if negative and negative.err and negative.err.code then
    assert_equal(negative.err.code, errors.NO_RECIPE_OR_STOCK, "missing coal should fail")
  end
  log.info("test_startup:done")
end

return M

