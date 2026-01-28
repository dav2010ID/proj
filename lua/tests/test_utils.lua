local M = {}

function M.assert_error_code(err, code, message)
  if type(err) == "table" and err.code then
    if err.code ~= code then
      error((message or "assert_error_code failed") .. ": expected=" .. tostring(code) .. " actual=" .. tostring(err.code))
    end
    return
  end
  local text = tostring(err)
  if not string.find(text, code, 1, true) then
    error((message or "assert_error_code failed") .. ": expected=" .. tostring(code) .. " actual=" .. text)
  end
end

function M.run_coroutine(world, co, max_ticks, timeout_code)
  local ticks = 0
  while coroutine.status(co) ~= "dead" do
    local ok_run, err_run = coroutine.resume(co)
    if not ok_run then
      error(err_run)
    end
    if world then
      world:tick(1)
    end
    ticks = ticks + 1
    if max_ticks and ticks > max_ticks then
      error({ code = timeout_code or "TASK_TIMEOUT", message = "test_timeout" })
    end
  end
end

return M

