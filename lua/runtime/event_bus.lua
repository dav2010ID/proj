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
    if self.on_emit then
      self.on_emit(event)
    end
    local handlers = self.subscribers[event.type] or {}
    for _, h in ipairs(handlers) do
      h(event)
    end
  end

  return self
end

return M

