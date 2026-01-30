cd C:\Users\David\AppData\Roaming\CraftOS-PC\computer\0\
& craftos-PC_console --headless --script tests/CraftOSTest.lua
if ($LASTEXITCODE -ne 0) {
    $LASTEXITCODE | Out-File "$env:USERPROFILE\.retval" -Encoding ascii
}

Get-Content "$env:APPDATA\CraftOS-PC\computer\0\CraftOSTest.log"

if (Test-Path "$env:USERPROFILE\.retval") {
    exit [int](Get-Content "$env:USERPROFILE\.retval")
}
