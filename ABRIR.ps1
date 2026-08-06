$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectFile = Join-Path $ProjectRoot "project.godot"
$BridgeFile = Join-Path $ProjectRoot "BRIDGE.ps1"

if (-not (Test-Path -LiteralPath $ProjectFile)) {
    throw "project.godot nao encontrado: $ProjectFile"
}

if (-not (Test-Path -LiteralPath $BridgeFile)) {
    throw "BRIDGE.ps1 nao encontrado: $BridgeFile"
}

Start-Process $ProjectFile

Start-Sleep -Milliseconds 1200

Start-Process powershell.exe -ArgumentList @(
    "-NoExit",
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    ('"' + $BridgeFile + '"'),
    "-ComPort",
    "COM5",
    "-BaudRate",
    "9600",
    "-VerboseLog"
)

Write-Host ""
Write-Host "Godot e ponte COM5 iniciados." -ForegroundColor Green
Write-Host "Aguarde a importacao e pressione F5 no Godot."
