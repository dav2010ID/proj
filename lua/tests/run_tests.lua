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
  for _, name in ipairs(modules) do
    local mod = require(name)
    log.info("run " .. name)
    mod.run(ctx)
  end
end

local ok, err = pcall(run_all)
if not ok then
  log.error(err)
  return
end
log.info("All virtual tests passed")
