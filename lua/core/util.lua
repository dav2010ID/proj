

local M = {}

function M.normalize(item)
  if type(item) ~= "string" then
    error("item must be string")
  end
  return (item:gsub("^%s+", ""):gsub("%s+$", ""))
end

function M.dump(value)
  local t = type(value)
  if t == "nil" then return "nil" end
  if t == "string" then return string.format("%q", value) end
  if t == "number" or t == "boolean" then return tostring(value) end
  if t ~= "table" then return tostring(value) end

  local seen = {}
  local function dump_table(tbl)
    if seen[tbl] then return "<cycle>" end
    seen[tbl] = true
    local parts = {}
    for k, v in pairs(tbl) do
      table.insert(parts, "[" .. dump_table(k) .. "]=" .. dump_table(v))
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end

  return dump_table(value)
end

return M
