local assert_equal = require("tests.assert").assert_equal
local recipe = require("core.recipe")
local planner = require("core.planner")
local executor = require("runtime.executor")
local virtual_world = require("runtime.virtual_world")
local virtual_machine = require("runtime.virtual_machine")
local utils = require("tests.test_utils")

local M = {}

local function test_parallel_goals()
  local world = virtual_world.new({
    ["minecraft:oak_log"] = 2,
    ["minecraft:cobblestone"] = 8,
  })

  local scheduler = world.scheduler
  local crafting1 = virtual_machine.new(scheduler, { duration = 2 })
  local crafting2 = virtual_machine.new(scheduler, { duration = 2 })

  world:attach_machine("crafting_table", crafting1, "ct_1")
  world:attach_machine("crafting_table", crafting2, "ct_2")

  local registry = recipe.new_registry()
  recipe.add(registry, {
    id = "planks",
    inputs = { { item = "minecraft:oak_log", count = 1 } },
    outputs = { { item = "minecraft:oak_planks", count = 4 } },
    machine = "crafting_table",
  })
  recipe.add(registry, {
    id = "sticks",
    inputs = { { item = "minecraft:oak_planks", count = 2 } },
    outputs = { { item = "minecraft:stick", count = 4 } },
    machine = "crafting_table",
  })
  recipe.add(registry, {
    id = "crafting_table",
    inputs = {
      { item = "minecraft:oak_planks", count = 4 },
      { item = "minecraft:stick", count = 2 },
    },
    outputs = { { item = "minecraft:crafting_table", count = 1 } },
    machine = "crafting_table",
  })
  recipe.add(registry, {
    id = "furnace",
    inputs = { { item = "minecraft:cobblestone", count = 8 } },
    outputs = { { item = "minecraft:furnace", count = 1 } },
    machine = "crafting_table",
  })

  local recipes_by_output = recipe.rebuild_index(registry)
  local resource = world.storage
  local allocator = world:get_allocator()

  local goals = {
    { item = "minecraft:crafting_table", count = 1 },
    { item = "minecraft:furnace", count = 1 },
  }

  local ok, plan_or_err = planner.plan_many(goals, recipes_by_output, resource)
  assert(ok, plan_or_err)

  local co = coroutine.create(function()
    local exec_ok, err = executor.execute(plan_or_err, resource, allocator)
    assert(exec_ok, err)
  end)

  utils.run_coroutine(world, co, 50)

  local snapshot = resource:snapshot()
  assert_equal(snapshot["minecraft:crafting_table"], 1, "crafting_table missing")
  assert_equal(snapshot["minecraft:furnace"], 1, "furnace missing")
  assert_equal(snapshot["minecraft:oak_log"], 0, "oak_log not fully consumed")
  assert_equal(snapshot["minecraft:cobblestone"], 0, "cobblestone not fully consumed")
end

function M.run()
  test_parallel_goals()
end

return M
