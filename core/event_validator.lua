local events = require("core.events")

local M = {}

local function matches_type(value, expected)
  if expected == "any" then
    return true
  end
  return type(value) == expected
end

function M.validate_event(event)
  if type(event) ~= "table" then
    return false, "event must be table"
  end
  if type(event.type) ~= "string" then
    return false, "event.type must be string"
  end
  local schema = events.schemas[event.type]
  if not schema then
    return false, "unknown event type: " .. tostring(event.type)
  end
  for _, key in ipairs(schema.required or {}) do
    if event[key] == nil then
      return false, "missing field: " .. tostring(key)
    end
  end
  for key, expected in pairs(schema.types or {}) do
    if event[key] ~= nil and not matches_type(event[key], expected) then
      return false, "invalid type for " .. tostring(key)
    end
  end
  return true, nil
end

return M
