local util = require("core.util")

local M = {}

function M.new_registry()
  return { recipes = {}, index = {} }
end

function M.add(registry, recipe)
  table.insert(registry.recipes, recipe)
end

function M.rebuild_index(registry)
  local index = {}
  for _, recipe in ipairs(registry.recipes) do
    for _, output in ipairs(recipe.outputs) do
      local key = util.normalize(output.item)
      if not index[key] then index[key] = {} end
      table.insert(index[key], recipe)
    end
  end
  registry.index = index
  return index
end

function M.get_producers(registry, item_key)
  local key = util.normalize(item_key)
  return registry.index[key] or {}
end

return M
