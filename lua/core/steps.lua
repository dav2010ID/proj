local util = require("core.util")

local M = {}

function M.supply(item, count)
  return {
    kind = "supply",
    item = util.normalize(item),
    count = count,
    execute = function(self, ctx)
      return ctx:execute_supply(self)
    end,
  }
end

function M.craft(recipe, times)
  return {
    kind = "craft",
    recipe = recipe,
    times = times,
    execute = function(self, ctx)
      return ctx:execute_craft(self)
    end,
  }
end

return M
