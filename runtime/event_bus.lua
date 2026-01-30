local event_validator = require("core.event_validator")

local M = {}

function M.new()
  local self = { subscribers = {}, on_emit = nil }

  function self:subscribe(event_type, handler)
    if not self.subscribers[event_type] then
      self.subscribers[event_type] = {}
    end
    table.insert(self.subscribers[event_type], handler)
  end

  function self:emit(event)
    local ok, err = event_validator.validate_event(event)
    if not ok then
      error(err)
    end
    if self.on_emit then
      self.on_emit(event)
    end
    local handlers = self.subscribers[event.type] or {}
    for _, h in ipairs(handlers) do
      h(event)
    end
  end

  function self:publish(event)
    self:emit(event)
  end

  return self
end

return M

