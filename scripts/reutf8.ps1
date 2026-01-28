$root = "C:\Users\David\Desktop\proj"

Get-ChildItem -Path $root -Recurse -File -Filter *.lua | ForEach-Object {
    $text = Get-Content -Path $_.FullName -Raw
    [System.IO.File]::WriteAllText(
        $_.FullName,
        $text,
        [System.Text.UTF8Encoding]::new($false)
    )
    Write-Host "OK:" $_.FullName
}
