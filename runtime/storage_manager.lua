local M = {}

local function bind_method(target, value)
  if type(value) ~= "function" then
    return value
  end
  return function(_, ...)
    return value(target, ...)
  end
end

function M.new(default_storage, bus)
  local self = {
    storage = default_storage,
    default = default_storage,
    disabled = false,
    bus = bus,
  }

  setmetatable(self, {
    __index = function(t, k)
      local target = t.storage
      if not target then
        return nil
      end
      return bind_method(target, target[k])
    end,
  })

  function self:on_storage_detected(event)
    self.storage = event.provider
    self.disabled = nil
  end

  function self:on_storage_removed(_event)
    self.storage = self.default
    self.disabled = true
  end

  function self:on_storage_disabled(_event)
    self.disabled = true
  end

  function self:on_storage_enabled(_event)
    self.disabled = nil
  end

  function self:current()
    return self.storage
  end

  return self
end

return M
