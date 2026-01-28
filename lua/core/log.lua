local M = {}

function M.info(message)
  print("[INFO] " .. message)
end

function M.error(message)
  print("[ERROR] " .. message)
end

return M
