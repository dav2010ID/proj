local log = require("core.log")
local recipe = require("core.recipe")
local planner = require("core.planner")
local executor = require("runtime.executor")
local virtual_world = require("runtime.virtual_world")
local virtual_machine = require("runtime.virtual_machine")

local M = {}

function M.run()
  local world = virtual_world.new({
    ["minecraft:oak_log"] = 2,
    ["minecraft:oak_planks"] = 0,
    ["minecraft:stick"] = 0,
    ["minecraft:crafting_table"] = 0,
  })

  local scheduler = world.scheduler
  local provider = virtual_machine.new(scheduler, { duration = 2 })
  world:attach_machine("crafting_table", provider, "vt_1")

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
  local resource = world.storage
  local allocator = world:get_allocator()

  local ok, plan_or_err = planner.plan("minecraft:crafting_table", 1, recipes_by_output, resource)
  if not ok then
    log.error(plan_or_err)
    return nil
  end

  local co = coroutine.create(function()
    local exec_ok, err = executor.execute(plan_or_err, resource, allocator)
    if not exec_ok then
      log.error(err)
    else
      log.info("Execution complete")
    end
  end)

  local running = true
  while running do
    if coroutine.status(co) == "dead" then
      running = false
      break
    end
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

if ... == nil then
  M.run()
end

return M
