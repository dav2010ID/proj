$craftos = "CraftOS-PC_console.exe"
$baseDir = "$env:APPDATA\CraftOS-PC\computer\0"
$logFile = Join-Path $baseDir "CraftOSTest.log"
$retFile = Join-Path $env:USERPROFILE ".retval"

# cleanup
if (Test-Path $retFile) { Remove-Item $retFile -Force }
if (Test-Path $logFile) { Remove-Item $logFile -Force }

& $craftos --headless --script tests/CraftOSTest.lua *> $null
$code = $LASTEXITCODE

if ($code -ne 0) {
    $code | Out-File $retFile -Encoding ascii
}

if (Test-Path $logFile) {
    Get-Content $logFile
}

if (Test-Path $retFile) {
    exit [int](Get-Content $retFile)
}
