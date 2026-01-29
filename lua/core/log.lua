local util = require("core.util")

local M = {}

local log_file = nil

local function write_file(line)
  local ok, fh = pcall(io.open, "out.log", "a")
  if not ok or not fh then
    return
  end
  fh:write(line .. "\n")
  fh:close()
end

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
  local line = "[INFO] " .. tostring(message)
  print(line)
  write_file(line)
end

function M.error(err)
  local line = "[ERROR] " .. format_error(err)
  print(line)
  write_file(line)
end

function M.set_log_file(path)
  log_file = path
end

function M.configure(opts)
  if not opts then
    return
  end
  if opts.file then
    log_file = opts.file
  end
end

local ok_env, env_file = pcall(function()
  if os and os.getenv then
    return os.getenv("LOG_FILE")
  end
  return nil
end)
if ok_env and env_file and env_file ~= "" then
  log_file = env_file
end

return M
