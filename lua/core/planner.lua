local util = require("core.util")
local steps = require("core.steps")

local M = {}

local function compute_reachable(target, recipes_by_output)
  local reachable = {}
  local function dfs(item_key)
    local key = util.normalize(item_key)
    if reachable[key] then return end
    reachable[key] = true
    local recipes = recipes_by_output[key] or {}
    for _, recipe in ipairs(recipes) do
      for _, input in ipairs(recipe.inputs) do
        dfs(input.item)
      end
    end
  end
  dfs(target)
  return reachable
end

local function select_recipe(recipes)
  table.sort(recipes, function(a, b)
    return (a.priority or 0) > (b.priority or 0)
  end)
  return recipes[1]
end

local function get_output_for_item(recipe, item)
  for _, output in ipairs(recipe.outputs) do
    if util.normalize(output.item) == item then
      return output
    end
  end
  return nil
end

local function compress_supplies(plan)
  local totals = {}
  local order = {}
  local crafts = {}
  for _, step in ipairs(plan) do
    if step.kind == "supply" then
      if not totals[step.item] then
        totals[step.item] = 0
        table.insert(order, step.item)
      end
      totals[step.item] = totals[step.item] + step.count
    else
      table.insert(crafts, step)
    end
  end
  local merged = {}
  for _, item in ipairs(order) do
    if totals[item] > 0 then
      table.insert(merged, steps.supply(item, totals[item]))
    end
  end
  for _, step in ipairs(crafts) do
    table.insert(merged, step)
  end
  return merged
end

local function compress_crafts(plan)
  local merged = {}
  local last = nil
  for _, step in ipairs(plan) do
    if step.kind == "craft" then
      if last and last.kind == "craft" and last.recipe.id == step.recipe.id and last.recipe.machine == step.recipe.machine then
        last.times = last.times + step.times
      else
        table.insert(merged, step)
        last = step
      end
    else
      table.insert(merged, step)
      last = step
    end
  end
  return merged
end

local function plan_need(ctx, item, count)
  local key = util.normalize(item)
  if ctx.stack[key] then
    return false, "cycle"
  end
  if not ctx.reachable[key] then
    return false, "item_not_reachable"
  end

  local available = ctx.virtual_stock[key]
  if available == nil then
    return false, "item_not_initialized"
  end

  local use = math.min(count, math.max(0, available))
  if use > 0 then
    local from_stock = math.min(use, ctx.stock_remaining[key] or 0)
    if from_stock > 0 then
      ctx.stock_remaining[key] = ctx.stock_remaining[key] - from_stock
      if ctx.stock_remaining[key] < 0 then
        return false, "supply_exceeds_stock"
      end
      table.insert(ctx.plan, steps.supply(key, from_stock))
    end
    ctx.virtual_stock[key] = available - use
    if ctx.virtual_stock[key] < 0 then
      return false, "virtual_stock_negative"
    end
  end

  local remain = count - use
  if remain == 0 then
    return true
  end

  local recipes = ctx.recipes[key]
  if not recipes or #recipes == 0 then
    return false, "no_recipe_or_stock"
  end

  ctx.stack[key] = true

  local recipe = select_recipe(recipes)
  local out = get_output_for_item(recipe, key)
  if not out or out.count <= 0 then
    ctx.stack[key] = nil
    return false, "no_matching_output"
  end
  local times = math.floor((remain + out.count - 1) / out.count)

  for _, input in ipairs(recipe.inputs) do
    local ok, err = plan_need(ctx, input.item, input.count * times)
    if not ok then
      ctx.stack[key] = nil
      return false, err
    end
  end

  table.insert(ctx.plan, steps.craft(recipe, times))

  for _, output in ipairs(recipe.outputs) do
    local out_item = util.normalize(output.item)
    local produced = output.count * times
    ctx.virtual_stock[out_item] = (ctx.virtual_stock[out_item] or 0) + produced
  end

  local current = ctx.virtual_stock[key] or 0
  if current - remain < 0 then
    ctx.stack[key] = nil
    return false, "virtual_stock_negative"
  end
  ctx.virtual_stock[key] = current - remain
  ctx.stack[key] = nil
  return true
end

function M.plan(target_item_key, target_count, recipes_by_output, resource_provider)
  local reachable = compute_reachable(target_item_key, recipes_by_output)
  local ctx = {
    resource = resource_provider,
    recipes = recipes_by_output,
    reachable = reachable,
    virtual_stock = {},
    stock_remaining = {},
    stack = {},
    plan = {},
  }

  if resource_provider.prepare then
    resource_provider:prepare(reachable)
  end

  for item, _ in pairs(reachable) do
    local value = resource_provider:get(item)
    ctx.virtual_stock[item] = value
    ctx.stock_remaining[item] = value
  end

  if resource_provider.snapshot then
    resource_provider:snapshot()
  end

  local ok, err = plan_need(ctx, target_item_key, target_count)
  if not ok then
    return false, err
  end

  local result = compress_supplies(ctx.plan)
  result = compress_crafts(result)
  return true, result
end

return M
