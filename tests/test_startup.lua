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


local function map_to_pairs(map)
  local keys = {}
  for k, _ in pairs(map or {}) do
    table.insert(keys, k)
  end
  table.sort(keys)
  local out = {}
  for _, k in ipairs(keys) do
    table.insert(out, k .. "=" .. tostring(map[k]))
  end
  return table.concat(out, ", ")
end

local function node_label(id, node)
  if node.kind == "supply" then
    return string.format("#%d supply %s x%d", id, node.item or "?", node.count or 0)
  end
  local recipe_id = node.recipe and node.recipe.id or "?"
  return string.format("#%d craft %s x%d", id, recipe_id, node.times or 0)
end

local function dump_graph(graph)
  if not graph or type(graph.nodes) ~= "table" then
    return
  end
  log.info("PlanGraph:")
  local order = nil
  local ok, sorted = pcall(function()
    return graph:topological_sort()
  end)
  if ok then
    order = sorted
  end
  if not order then
    order = {}
    for i = 1, #graph.nodes do
      table.insert(order, i)
    end
  end
  for _, id in ipairs(order) do
    local node = graph.nodes[id]
    log.info("  " .. node_label(id, node))
    if node.inputs and next(node.inputs) ~= nil then
      log.info("    inputs: " .. map_to_pairs(node.inputs))
    end
    if node.outputs and next(node.outputs) ~= nil then
      log.info("    outputs: " .. map_to_pairs(node.outputs))
    end
    local deps = graph:get_dependencies(id)
    if #deps > 0 then
      local dep_str = {}
      for _, dep in ipairs(deps) do
        table.insert(dep_str, tostring(dep))
      end
      log.info("    deps: " .. table.concat(dep_str, ", "))
    end
    local flows = graph.flows and graph.flows[id] or nil
    if flows and #flows > 0 then
      local flow_parts = {}
      for _, flow in ipairs(flows) do
        table.insert(flow_parts, string.format("%d:%s=%s", flow.from, flow.item or "?", tostring(flow.amount or 0)))
      end
      log.info("    flows: " .. table.concat(flow_parts, ", "))
    end
  end
end

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

local function setup_world(opts)
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

  return world, craftos
end

local function build_registry()
  local recipe_path = "recipes_startup.json"
  local ok_reg, registry_or_err = recipe.load_registry(recipe_path)
  if not ok_reg then
    error(registry_or_err)
  end
  local registry = registry_or_err
  return registry
end

local function run_plan(world)
  local registry = build_registry()
  local recipes_by_output = recipe.rebuild_index(registry)
  local resource = world.storage
  local ok, graph_or_err =
    planner.plan("minecraft:advanced_machine", 1, recipes_by_output, resource)

  if not ok then
    return {
      ok = false,
      err = graph_or_err,
    }
  end
  dump_graph(graph_or_err)

  return {
    ok = true,
    graph = graph_or_err,
  }
end

local function run_executor(world, graph)
  local resource = world.storage
  local allocator = world:get_allocator()
  local co = coroutine.create(function()
    local exec_ok, err = executor.execute(graph, resource, allocator, { max_steps_per_tick = 1000 })
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
    trace = world:trace_dump(),
  }
end

local function run_startup(opts)
  opts = opts or {}
  local world, craftos = setup_world(opts)
  local plan = run_plan(world)
  if not plan.ok then
    if not opts.suppress_errors then
      log.error(plan.err)
    end
    return {
      ok = false,
      err = plan.err,
      craftos = craftos,
      trace = world:trace_dump(),
    }
  end
  local result = run_executor(world, plan.graph)
  result.craftos = craftos
  return result
end

local function find_time(trace, event_type, matcher, mode)
  for _, ev in ipairs(trace) do
    local payload = ev.payload or {}
    if ev.type == event_type and (not matcher or matcher(payload, ev)) then
      local time = ev.now or 0
      if mode == "first" then
        return time
      end
      local last = time
      for i = 1, #trace do
        if trace[i] == ev then
          for j = i + 1, #trace do
            local next_ev = trace[j]
            local next_payload = next_ev.payload or {}
            if next_ev.type == event_type and (not matcher or matcher(next_payload, next_ev)) then
              last = next_ev.now or 0
            end
          end
          break
        end
      end
      return last
    end
  end
  return nil
end

local function assert_absent(snapshot, items, label)
  for _, item in ipairs(items) do
    assert_equal(snapshot[item] or 0, 0, label .. " has " .. item)
  end
end

local function assert_zero(snapshot, items, label)
  for _, item in ipairs(items) do
    assert_equal(snapshot[item] or 0, 0, label .. " has residue " .. item)
  end
end

local function assert_task_ran(trace, task_id)
  local started = find_time(trace, "TaskStarted", function(payload)
    return payload.task_id and string.find(payload.task_id, task_id, 1, true)
  end, "first")
  local finished = find_time(trace, "TaskFinished", function(payload)
    return payload.task_id and string.find(payload.task_id, task_id, 1, true)
  end, "last")
  assert_equal(started ~= nil, true, task_id .. " started")
  assert_equal(finished ~= nil, true, task_id .. " finished")
  return started, finished
end

local function assert_task_order(trace, task_id, prereqs)
  local task_start = find_time(trace, "TaskStarted", function(payload)
    return payload.task_id and string.find(payload.task_id, task_id, 1, true)
  end, "first")
  assert_equal(task_start ~= nil, true, task_id .. " started")
  if not task_start then
    return
  end
  for _, prereq in ipairs(prereqs or {}) do
    local prereq_finish = find_time(trace, "TaskFinished", function(payload)
      return payload.task_id and string.find(payload.task_id, prereq, 1, true)
    end, "last")
    assert_equal(prereq_finish ~= nil, true, prereq .. " finished")
    if prereq_finish then
      assert_equal(task_start > prereq_finish, true, task_id .. " after " .. prereq)
    end
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

  assert_zero(snapshot, {
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

    assert_absent(chest_2, {
      "minecraft:oak_log",
      "minecraft:oak_planks",
      "minecraft:stick",
      "minecraft:cobblestone",
      "minecraft:furnace",
    }, "chest_1")

    assert_absent(chest_1, {
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

    local smelt_start, smelt_finish = assert_task_ran(trace, "smelt_iron")
    assert_task_ran(trace, "iron_plate")
    assert_task_ran(trace, "mechanism")
    assert_task_ran(trace, "machine_casing")
    assert_task_ran(trace, "furnace")
    assert_task_order(trace, "advanced_machine", { "machine_casing", "mechanism", "furnace" })

    local batch_done_chest_2 = find_time(trace, "BatchDone", function(payload)
      return payload.storage_id == "chest_2"
    end, "first")
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

