local here = debug.getinfo(1, "S").source:sub(2)
local here_dir = here:match("^(.*)[/\\]") or "."
local lua_root = here_dir .. "/.."
package.path = here_dir .. "/?.lua;" .. lua_root .. "/?.lua;" .. lua_root .. "/?/init.lua;" .. package.path

local log = require("core.log")

local modules = {
  "tests.test_planner",
  "tests.test_executor",
  "tests.test_storage",
  "tests.test_async_storage",
  "tests.test_multi_storage",
  "tests.test_supply_router",
  "tests.test_startup",
  "tests.test_provider_contract",
  "tests.test_parallel_goals",
}

local function run_all()
  local ctx = {
    seed = os.time(),
    max_ticks = 200,
    log_level = "info",
  }
  local failed = 0
  for _, name in ipairs(modules) do
    log.info("run " .. name)
    local ok_mod, mod_or_err = pcall(require, name)
    if not ok_mod then
      failed = failed + 1
      log.error(mod_or_err)
    else
      local ok_run, err_run = pcall(mod_or_err.run, ctx)
      if not ok_run then
        failed = failed + 1
        log.error(err_run)
      end
    end
  end
  return failed
end

local failed = run_all()
if failed > 0 then
  log.error("tests failed: " .. tostring(failed))
else
  print("==> All tests passed.")
  log.info("All virtual tests passed")
end
if os and os.shutdown then
  os.shutdown(failed)
end

