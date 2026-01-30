local util = require("core.util")
local steps = require("core.steps")
local errors = require("core.error_codes")
local plan_graph = require("core.plan_graph")

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

local function compute_reachable_many(goals, recipes_by_output)
  local reachable = {}
  for _, goal in ipairs(goals) do
    local sub = compute_reachable(goal.item, recipes_by_output)
    for k, v in pairs(sub) do
      reachable[k] = v
    end
  end
  return reachable
end

local function select_recipe(recipes)
  local best = nil
  for _, recipe in ipairs(recipes) do
    if not best or (recipe.priority or 0) > (best.priority or 0) then
      best = recipe
    end
  end
  return best
end

local function get_output_for_item(recipe, item)
  for _, output in ipairs(recipe.outputs) do
    if util.normalize(output.item) == item then
      return output
    end
  end
  return nil
end

local function add_supply_node(ctx, item, count)
  local key = util.normalize(item)
  local node = {
    kind = "supply",
    item = key,
    count = count,
    inputs = {},
    outputs = { [key] = count },
  }
  return ctx.graph:add_node(node)
end

local function add_craft_node(ctx, recipe, times)
  local inputs = {}
  local outputs = {}
  for _, input in ipairs(recipe.inputs or {}) do
    local key = util.normalize(input.item)
    inputs[key] = (inputs[key] or 0) + (input.count * times)
  end
  for _, output in ipairs(recipe.outputs or {}) do
    local key = util.normalize(output.item)
    outputs[key] = (outputs[key] or 0) + (output.count * times)
  end
  local node = {
    kind = "craft",
    recipe = recipe,
    times = times,
    inputs = inputs,
    outputs = outputs,
  }
  return ctx.graph:add_node(node)
end

local function plan_need(ctx, item, count, consumer_id)
  local key = util.normalize(item)
  if ctx.stack[key] then
    return false, { code = errors.CYCLE_DETECTED }
  end
  if not ctx.reachable[key] then
    return false, { code = errors.ITEM_NOT_REACHABLE }
  end

  local available = ctx.virtual_stock[key]
  assert(available ~= nil, "item_not_initialized")

  local use = math.min(count, math.max(0, available))
  if use > 0 then
    local from_stock = math.min(use, ctx.stock_remaining[key] or 0)
    if from_stock > 0 then
      ctx.stock_remaining[key] = ctx.stock_remaining[key] - from_stock
      if ctx.stock_remaining[key] < 0 then
        return false, { code = errors.INSUFFICIENT_STOCK }
      end
      ctx.supply_totals[key] = (ctx.supply_totals[key] or 0) + from_stock
      if consumer_id then
        ctx.supply_edges[key] = ctx.supply_edges[key] or {}
        table.insert(ctx.supply_edges[key], { to = consumer_id, amount = from_stock })
      end
    end
    ctx.virtual_stock[key] = available - use
    if ctx.virtual_stock[key] < 0 then
      return false, { code = errors.BUFFER_NEGATIVE }
    end
  end

  local remain = count - use
  if remain == 0 then
    return true, nil
  end

  local recipes = ctx.recipes[key]
  if not recipes or #recipes == 0 then
    return false, { code = errors.NO_RECIPE_OR_STOCK }
  end

  ctx.stack[key] = true

  local recipe = select_recipe(recipes)
  local out = get_output_for_item(recipe, key)
  if not out or out.count <= 0 then
    ctx.stack[key] = nil
    return false, { code = errors.NO_RECIPE_OR_STOCK }
  end
  local times = math.floor((remain + out.count - 1) / out.count)
  local craft_id = add_craft_node(ctx, recipe, times)
  if consumer_id then
    ctx.graph:add_flow(craft_id, consumer_id, key, remain)
  end

  for _, input in ipairs(recipe.inputs) do
    local ok, err = plan_need(ctx, input.item, input.count * times, craft_id)
    if not ok then
      ctx.stack[key] = nil
      return false, err
    end
  end

  for _, output in ipairs(recipe.outputs) do
    local out_item = util.normalize(output.item)
    local produced = output.count * times
    ctx.virtual_stock[out_item] = (ctx.virtual_stock[out_item] or 0) + produced
  end

  local current = ctx.virtual_stock[key] or 0
  if current - remain < 0 then
    ctx.stack[key] = nil
    return false, { code = errors.BUFFER_NEGATIVE }
  end
  ctx.virtual_stock[key] = current - remain
  ctx.stack[key] = nil
  return true, nil
end

function M.plan(target_item_key, target_count, recipes_by_output, resource_provider, opts)
  local reachable = compute_reachable(target_item_key, recipes_by_output)
  local ctx = {
    resource = resource_provider,
    recipes = recipes_by_output,
    reachable = reachable,
    virtual_stock = {},
    stock_remaining = {},
    stack = {},
    graph = plan_graph.new(),
    supply_totals = {},
    supply_edges = {},
  }

  if resource_provider.prepare then
    resource_provider:prepare(reachable)
  end
  local began = false
  if resource_provider.begin then
    resource_provider:begin()
    began = true
  end

  for item, _ in pairs(reachable) do
    local value = resource_provider:get(item)
    ctx.virtual_stock[item] = value
    ctx.stock_remaining[item] = value
  end

  if resource_provider.snapshot then
    resource_provider:snapshot()
  end

  local ok, err = plan_need(ctx, target_item_key, target_count, nil)
  if not ok then
    if began and resource_provider.rollback then
      resource_provider:rollback()
    elseif began and resource_provider.commit then
      resource_provider:commit()
    end
    return false, err
  end

  if began and resource_provider.commit then
    resource_provider:commit()
  end

  for item, total in pairs(ctx.supply_totals) do
    local supply_id = add_supply_node(ctx, item, total)
    for _, edge in ipairs(ctx.supply_edges[item] or {}) do
      ctx.graph:add_flow(supply_id, edge.to, item, edge.amount)
    end
  end

  ctx.graph = plan_graph.normalize(ctx.graph)

  if opts and opts.return_steps then
    local result = steps.from_graph(ctx.graph)
    return true, result, ctx.graph
  end
  return true, ctx.graph
end

function M.plan_many(goals, recipes_by_output, resource_provider, opts)
  local reachable = compute_reachable_many(goals, recipes_by_output)
  local ctx = {
    resource = resource_provider,
    recipes = recipes_by_output,
    reachable = reachable,
    virtual_stock = {},
    stock_remaining = {},
    stack = {},
    graph = plan_graph.new(),
    supply_totals = {},
    supply_edges = {},
  }

  if resource_provider.prepare then
    resource_provider:prepare(reachable)
  end
  local began = false
  if resource_provider.begin then
    resource_provider:begin()
    began = true
  end

  for item, _ in pairs(reachable) do
    local value = resource_provider:get(item)
    ctx.virtual_stock[item] = value
    ctx.stock_remaining[item] = value
  end

  if resource_provider.snapshot then
    resource_provider:snapshot()
  end

  for _, goal in ipairs(goals) do
    local ok, err = plan_need(ctx, goal.item, goal.count, nil)
    if not ok then
      if began and resource_provider.rollback then
        resource_provider:rollback()
      elseif began and resource_provider.commit then
        resource_provider:commit()
      end
      return false, err
    end
  end

  if began and resource_provider.commit then
    resource_provider:commit()
  end

  for item, total in pairs(ctx.supply_totals) do
    local supply_id = add_supply_node(ctx, item, total)
    for _, edge in ipairs(ctx.supply_edges[item] or {}) do
      ctx.graph:add_flow(supply_id, edge.to, item, edge.amount)
    end
  end

  ctx.graph = plan_graph.normalize(ctx.graph)

  if opts and opts.return_steps then
    local result = steps.from_graph(ctx.graph)
    return true, result, ctx.graph
  end
  return true, ctx.graph
end

return M




