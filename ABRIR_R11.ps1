$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Bridge = Join-Path $ProjectRoot "bridge_hit_music_serial.ps1"
$Project = Join-Path $ProjectRoot "project.godot"

Start-Process powershell.exe -ArgumentList @(
    "-NoExit",
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    ('"' + $Bridge + '"'),
    "-ComPort",
    "COM5",
    "-BaudRate",
    "9600",
    "-VerboseLog"
)

Start-Sleep -Milliseconds 900
Start-Process $Project