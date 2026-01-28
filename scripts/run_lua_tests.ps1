param(
  [string]$LuaExe = "lua",
  [string]$Tests = "lua/tests/run_tests.lua"
)

& $LuaExe $Tests
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
