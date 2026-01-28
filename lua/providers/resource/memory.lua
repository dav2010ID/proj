local util = require("core.util")

local M = {}

function M.new(initial)
  local self = {
    available = initial or {},
    consumed = {},
    added = {},
    frozen = false,
    allowed = nil,
  }

  function self:prepare(reachable)
    self.allowed = {}
    for item, _ in pairs(reachable) do
      self.allowed[util.normalize(item)] = true
    end
  end

  function self:get(item)
    local key = util.normalize(item)
    if self.allowed and not self.allowed[key] then
      error("get outside reachable items")
    end
    if self.frozen and self.available[key] == nil then
      error("get after snapshot")
    end
    if self.available[key] == nil then
      self.available[key] = 0
    end
    return self.available[key]
  end

  function self:consume(item, count)
    local key = util.normalize(item)
    local current = self.available[key] or 0
    if count < 0 then
      error("count must be non-negative")
    end
    if current < count then
      error("insufficient stock")
    end
    self.available[key] = current - count
    if count > 0 then
      table.insert(self.consumed, { key = key, count = count })
    end
  end

  function self:add(item, count)
    local key = util.normalize(item)
    if count < 0 then
      error("count must be non-negative")
    end
    self.available[key] = (self.available[key] or 0) + count
    if count > 0 then
      table.insert(self.added, { key = key, count = count })
    end
  end

  function self:commit()
    self.consumed = {}
    self.added = {}
  end

  function self:rollback()
    for i = #self.added, 1, -1 do
      local entry = self.added[i]
      self.available[entry.key] = (self.available[entry.key] or 0) - entry.count
    end
    for i = #self.consumed, 1, -1 do
      local entry = self.consumed[i]
      self.available[entry.key] = (self.available[entry.key] or 0) + entry.count
    end
    self.consumed = {}
    self.added = {}
  end

  function self:snapshot()
    if self.frozen then
      error("snapshot already taken")
    end
    self.frozen = true
    local copy = {}
    for k, v in pairs(self.available) do
      copy[k] = v
    end
    return copy
  end

  return self
end

return M
