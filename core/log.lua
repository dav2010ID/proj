local util = require("core.util")

local M = {}

local LOG_PATH = "CraftOSTest.log"

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

local function append_log(line)
  if not fs or not fs.open then
    return
  end
  local handle = fs.open(LOG_PATH, "a")
  if not handle then
    return
  end
  handle.writeLine(line)
  handle.close()
end

function M.info(message)
  local line = "[INFO] " .. tostring(message)
  print(line)
  append_log(line)
end

function M.error(err)
  local line = "[ERROR] " .. format_error(err)
  print(line)
  append_log(line)
end

return M

