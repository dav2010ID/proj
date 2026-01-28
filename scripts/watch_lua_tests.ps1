param(
  [string]$LuaExe = "lua",
  [string]$Tests = "lua/tests/run_tests.lua",
  [string[]]$Paths = @("lua")
)

$watchers = @()
$timer = New-Object Timers.Timer
$timer.Interval = 300
$timer.AutoReset = $false

$action = {
  Write-Host "\n[watch] change detected, running tests..."
  & $LuaExe $Tests
  if ($LASTEXITCODE -ne 0) {
    Write-Host "[watch] tests failed"
  } else {
    Write-Host "[watch] tests passed"
  }
}

$timer.add_Elapsed({
  $action.Invoke()
})

foreach ($p in $Paths) {
  $fsw = New-Object IO.FileSystemWatcher
  $fsw.Path = (Resolve-Path $p)
  $fsw.Filter = "*.lua"
  $fsw.IncludeSubdirectories = $true
  $fsw.EnableRaisingEvents = $true
  Register-ObjectEvent $fsw Changed -Action { $timer.Stop(); $timer.Start() } | Out-Null
  Register-ObjectEvent $fsw Created -Action { $timer.Stop(); $timer.Start() } | Out-Null
  Register-ObjectEvent $fsw Renamed -Action { $timer.Stop(); $timer.Start() } | Out-Null
  Register-ObjectEvent $fsw Deleted -Action { $timer.Stop(); $timer.Start() } | Out-Null
  $watchers += $fsw
}

Write-Host "[watch] watching: $($Paths -join ', ')"
Write-Host "[watch] running initial tests..."
& $LuaExe $Tests

while ($true) {
  Start-Sleep -Seconds 1
}
