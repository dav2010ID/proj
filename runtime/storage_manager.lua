-- Runtime manager
-- Coordinates a single active storage via events; not business logic.
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
    active_storage = default_storage,
    has_active = default_storage ~= nil,
  }

  setmetatable(self, {
    __index = function(t, k)
      local target = t.storage
      if not target then
        error("no active storage")
      end
      local value = target[k]
      if type(value) == "function" then
        return function(_, ...)
          if t.disabled then
            local blocked = {
              begin = true,
              commit = true,
              rollback = true,
              consume = true,
              add = true,
              get_async = true,
              get_batch_async = true,
              collect_request = true,
              request = true,
              collect = true,
              set_limits = true,
              set_supported_items = true,
            }
            if blocked[k] then
              error("storage disabled")
            end
          end
          return value(target, ...)
        end
      end
      return value
    end,
  })

  function self:on_storage_detected(event)
    self.storage = event.provider
    self.disabled = nil
    self.active_storage = event.provider
    self.has_active = event.provider ~= nil
  end

  function self:on_storage_removed(_event)
    self.storage = self.default
    self.disabled = true
    self.active_storage = nil
    self.has_active = false
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
