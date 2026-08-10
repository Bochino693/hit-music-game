$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectFile = Join-Path $ProjectRoot "project.godot"

if (-not (Test-Path -LiteralPath $ProjectFile)) {
    throw "project.godot nao encontrado: $ProjectFile"
}

# R21:
# O launcher abre SOMENTE o projeto.
# LedClient é a única autoridade que inicia/fecha BRIDGE_R21 e COM5.
Start-Process $ProjectFile

Write-Host ""
Write-Host "HIT MUSIC aberto." -ForegroundColor Green
Write-Host "A ponte serial sera iniciada automaticamente pelo LedClient." -ForegroundColor Cyan
