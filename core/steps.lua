local util = require("core.util")

local M = {}

local SupplyStep = {}
SupplyStep.__index = SupplyStep

function SupplyStep:execute(ctx)
  ctx:execute_supply(self)
end

local CraftStep = {}
CraftStep.__index = CraftStep

function CraftStep:execute(ctx)
  ctx:execute_craft(self)
end

function M.supply(item, count)
  assert(type(count) == "number" and count > 0, "SupplyStep.count must be > 0")
  local step = {
    kind = "supply",
    item = util.normalize(item),
    count = count,
  }
  return setmetatable(step, SupplyStep)
end

function M.craft(recipe, times)
  assert(type(times) == "number" and times > 0, "CraftStep.times must be > 0")
  assert(recipe and recipe.outputs, "invalid recipe")
  local step = {
    kind = "craft",
    recipe = recipe,
    times = times,
  }
  return setmetatable(step, CraftStep)
end

function M.from_graph(graph)
  local ordered = graph:topological_sort()
  local out = {}
  for _, id in ipairs(ordered) do
    local node = graph.nodes[id]
    if node.kind == "supply" then
      table.insert(out, M.supply(node.item, node.count))
    elseif node.kind == "craft" then
      table.insert(out, M.craft(node.recipe, node.times))
    else
      error("unknown_step")
    end
  end
  return out
end

return M

