local assert_equal = require("tests.assert").assert_equal
local assert_error = require("tests.test_utils").assert_error_code
local recipe = require("core.recipe")
local planner = require("core.planner")
local virtual_world = require("virtual.world")
local errors = require("core.error_codes")

local M = {}

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
  local ok, plan_or_err = planner.plan("item:b", 1, recipes_by_output, world.storage, { return_steps = true })
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
  assert_error(err, errors.CYCLE_DETECTED, "cycle detected")
end

local function test_planner_unreachable_item()
  local world = virtual_world.new({ ["item:x"] = 0 })
  local registry = recipe.new_registry()
  local recipes_by_output = recipe.rebuild_index(registry)
  local ok, err = planner.plan("item:x", 1, recipes_by_output, world.storage)
  assert_equal(ok, false, "unreachable item")
  assert_error(err, errors.NO_RECIPE_OR_STOCK, "no recipe or stock")
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
  local ok1, plan1 = planner.plan("item:b", 1, recipes_by_output, world.storage, { return_steps = true })
  local ok2, plan2 = planner.plan("item:b", 1, recipes_by_output, world.storage, { return_steps = true })
  assert_equal(ok1, true, "plan ok 1")
  assert_equal(ok2, true, "plan ok 2")
  assert_equal(serialize_plan(plan1), serialize_plan(plan2), "deterministic plan")
end

function M.run()
  test_planner_basic()
  test_planner_cycle_detection()
  test_planner_unreachable_item()
  test_planner_deterministic()
end

return M

