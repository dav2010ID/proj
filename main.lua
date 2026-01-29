local recipe = require("core.recipe")
local planner = require("core.planner")
local executor = require("runtime.executor")
local machines = require("machines")
local crafting_table = require("providers.machine.crafting_table")
local memory_resource = require("providers.resource.memory")
local log = require("core.log")

local registry = recipe.new_registry()
recipe.add(registry, {
  id = "oak_planks",
  inputs = { { item = "minecraft:oak_log", count = 1 } },
  outputs = { { item = "minecraft:oak_planks", count = 4 } },
  machine = "crafting_table",
  priority = 10,
})
recipe.add(registry, {
  id = "sticks",
  inputs = { { item = "minecraft:oak_planks", count = 2 } },
  outputs = { { item = "minecraft:stick", count = 4 } },
  machine = "crafting_table",
  priority = 5,
})
recipe.add(registry, {
  id = "crafting_table",
  inputs = {
    { item = "minecraft:oak_planks", count = 4 },
    { item = "minecraft:stick", count = 2 },
  },
  outputs = { { item = "minecraft:crafting_table", count = 1 } },
  machine = "crafting_table",
  priority = 1,
})

local recipes_by_output = recipe.rebuild_index(registry)
local resource = memory_resource.new({
  ["minecraft:oak_log"] = 2,
  ["minecraft:oak_planks"] = 0,
  ["minecraft:stick"] = 0,
  ["minecraft:crafting_table"] = 0,
})

local allocator = machines.new_allocator({
  machines.new("crafting_table_1", "crafting_table", crafting_table.new()),
})

local ok, plan_or_err = planner.plan("minecraft:crafting_table", 1, recipes_by_output, resource)
if not ok then
  log.error(plan_or_err)
  return
end

local exec_ok, err = executor.execute(plan_or_err, resource, allocator)
if not exec_ok then
  log.error(err)
  return
end

log.info("Execution complete")

