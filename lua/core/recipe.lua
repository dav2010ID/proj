local util = require("core.util")

local M = {}

function M.new_registry()
  return { recipes = {}, index = {} }
end

function M.add(registry, recipe)
  if not recipe.outputs or #recipe.outputs == 0 then
    error("recipe.outputs must not be empty: " .. tostring(recipe.id))
  end
  table.insert(registry.recipes, recipe)
end

function M.rebuild_index(registry)
  -- rebuilds and replaces registry.index, invalidates previous snapshots
  local index = {}
  for _, recipe in ipairs(registry.recipes) do
    local seen_outputs = {}
    for _, output in ipairs(recipe.outputs) do
      local key = util.normalize(output.item)
      if seen_outputs[key] then
        error("duplicate recipe output: " .. tostring(recipe.id) .. " -> " .. key)
      end
      seen_outputs[key] = true
      if not index[key] then index[key] = {} end
      table.insert(index[key], recipe)
    end
  end
  registry.index = index
  return index
end

function M.get_producers(registry, item_key)
  local key = util.normalize(item_key)
  local list = registry.index[key]
  if not list then return {} end
  local copy = {}
  for i, recipe in ipairs(list) do
    copy[i] = recipe
  end
  return copy
end

return M
