local M = {}

function M.normalize(item)
  if type(item) ~= "string" then
    error("item must be string")
  end
  return (item:gsub("^%s+", ""):gsub("%s+$", ""))
end

return M
