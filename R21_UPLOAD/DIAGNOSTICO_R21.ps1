$ErrorActionPreference = "SilentlyContinue"

$ProjectRoot = (Get-Location).Path
$project = Join-Path $ProjectRoot "project.godot"

Write-Host ""
Write-Host "=== HIT MUSIC R21 DIAGNOSTICO ===" -ForegroundColor Cyan

Write-Host ""
Write-Host "[Autoload]" -ForegroundColor Yellow
Select-String -Path $project -Pattern 'HitMusicSerial|LedClient='

Write-Host ""
Write-Host "[Bridges em execucao]" -ForegroundColor Yellow
Get-CimInstance Win32_Process |
    Where-Object {
        $_.Name -eq "powershell.exe" -and
        $_.CommandLine -match "BRIDGE"
    } |
    Select-Object ProcessId, CommandLine

$base = Join-Path $env:APPDATA "Godot\app_userdata\beta12\hit_music_serial"
$spool = Join-Path $base "spool"

Write-Host ""
Write-Host "[Spool]" -ForegroundColor Yellow
if (Test-Path $spool) {
    Get-ChildItem $spool |
        Select-Object Name, Length, LastWriteTime
} else {
    Write-Host "Spool ainda nao criado."
}

Write-Host ""
Write-Host "[Modo GAME]" -ForegroundColor Yellow
Test-Path (Join-Path $base "game_mode.flag")

Write-Host ""
Write-Host "Durante a partida, o spool deve mostrar no maximo game_state.cmd." -ForegroundColor Green
