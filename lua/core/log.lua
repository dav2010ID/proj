local util = require("core.util")

local M = {}

local function format_error(err)
  local t = type(err)
  if t == "string" then
    return err
  elseif t == "table" then
    if err.code then
      return tostring(err.code)
    end
    if util.dump then
      return util.dump(err)
    end
    return tostring(err)
  else
    return tostring(err)
  end
end

function M.info(message)
  print("[INFO] " .. tostring(message))
end

function M.error(err)
  print("[ERROR] " .. format_error(err))
end

return M
