local log = require("core.log")
local recipe = require("core.recipe")
local planner = require("core.planner")
local executor = require("runtime.executor")
local virtual_world = require("virtual.world")
local virtual_machine = require("virtual.machine")

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

  local recipe_path = "recipes.json"
  local ok_reg, registry_or_err = recipe.load_registry(recipe_path)
  if not ok_reg then
    log.error(registry_or_err)
    return nil
  end
  local registry = registry_or_err

  local recipes_by_output = recipe.rebuild_index(registry)
  local resource = world.storage
  local allocator = world:get_allocator()

  local ok, graph_or_err = planner.plan("minecraft:crafting_table", 1, recipes_by_output, resource)
  if not ok then
    log.error(graph_or_err)
    return nil
  end

  local co = coroutine.create(function()
    local exec_ok, err = executor.execute(graph_or_err, resource, allocator)
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

  resource:begin()
  local snapshot = resource:snapshot()
  resource:commit()
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

