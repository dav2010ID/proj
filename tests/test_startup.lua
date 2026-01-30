local assert_equal = require("tests.assert").assert_equal


local log = require("core.log")
local recipe = require("core.recipe")
local planner = require("core.planner")
local executor = require("runtime.executor")
local multi_storage = require("runtime.multi_storage")
local chest_adapter = require("providers.resource.chest_adapter")
local virtual_world = require("virtual.world")
local virtual_machine = require("virtual.machine")

local M = {}

local function build_craftos_storage(bus)
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
    ["minecraft:oak_log"] = 8,
    ["minecraft:cobblestone"] = 16,
  })

  seed_provider(chest_2, {
    ["minecraft:iron_ore"] = 13,
    ["minecraft:coal"] = 13,
  })

  return multi_storage.new({
    { id = "chest_1", provider = chest_1 },
    { id = "chest_2", provider = chest_2 },
  }, bus)
end

local function run_startup()
  local world = virtual_world.new({})
  local craftos_storage = build_craftos_storage(world.bus)
  if craftos_storage then
    world:attach_storage(craftos_storage)
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

  local ok, plan_or_err =
    planner.plan("minecraft:advanced_machine", 1, recipes_by_output, resource)

  if not ok then
    log.error(plan_or_err)
    return nil
  end

  local co = coroutine.create(function()
    local exec_ok, err = executor.execute(plan_or_err, resource, allocator, { max_steps_per_tick = 1000 })
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

  local snapshot = resource:snapshot()
  log.info("Final stock:")
  for k, v in pairs(snapshot) do
    log.info("  " .. k .. " = " .. tostring(v))
  end

  return snapshot
end


local function test_startup_test_run()
  local snapshot = run_startup()
  if not snapshot then
    error("startup_test run returned nil")
  end
  assert_equal(snapshot["minecraft:advanced_machine"], 1, "advanced_machine")
end

function M.run()
  log.info("test_startup:start")
  test_startup_test_run()
  log.info("test_startup:done")
end

return M

