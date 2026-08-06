param(
    [string]$ProjectRoot = "C:\Users\LAZER GAMES\Documents\beta-12"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Require-File {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Arquivo obrigatorio ausente: $Path"
    }
}

$PackageRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " HIT MUSIC - VOLTAR DA R8 PARA A R11" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Projeto: $ProjectRoot"
Write-Host "Pacote:  $PackageRoot"
Write-Host ""

Require-File (Join-Path $ProjectRoot "project.godot")
Require-File (Join-Path $ProjectRoot "scripts\hit_music_r7\stage.gd")
Require-File (Join-Path $ProjectRoot "scripts\hit_music_r7\selector.gd")
Require-File (Join-Path $ProjectRoot "scripts\hit_music_r7\chart_factory.gd")

$R9 = Join-Path $PackageRoot "aplicar_hit_music_r9_gameplay_ranking.ps1"
$R10 = Join-Path $PackageRoot "aplicar_hit_music_r10_touch_mandala_leds.ps1"
$R11 = Join-Path $PackageRoot "aplicar_hit_music_r11_refino_visual_leds_SEGURO.ps1"

Require-File $R9
Require-File $R10
Require-File $R11

Push-Location $ProjectRoot

try {
    Write-Host "ETAPA 1/3 - Aplicando R9..." -ForegroundColor Yellow
    & $R9 -ProjectRoot $ProjectRoot

    Require-File (Join-Path $ProjectRoot "scripts\hit_music_r7\stage_v9.gd")
    Require-File (Join-Path $ProjectRoot "scripts\hit_music_r7\selector_v9.gd")

    Write-Host ""
    Write-Host "ETAPA 2/3 - Aplicando R10..." -ForegroundColor Yellow
    & $R10 -ProjectRoot $ProjectRoot

    Require-File (Join-Path $ProjectRoot "scripts\hit_music_r7\stage_v10.gd")
    Require-File (Join-Path $ProjectRoot "scripts\hit_music_r7\selector_v10.gd")

    Write-Host ""
    Write-Host "ETAPA 3/3 - Aplicando R11 segura..." -ForegroundColor Yellow
    & $R11 -ProjectRoot $ProjectRoot

    $RequiredFinalFiles = @(
        "scripts\hit_music_r7\stage_v11.gd",
        "scripts\hit_music_r7\selector_v11.gd",
        "scripts\hit_music_r7\theme_overlay_v11.gd",
        "scripts\hit_music_r7\led_client.gd",
        "scripts\change_scenes.gd"
    )

    Write-Host ""
    Write-Host "VALIDACAO FINAL:" -ForegroundColor Cyan

    foreach ($RelativePath in $RequiredFinalFiles) {
        $FullPath = Join-Path $ProjectRoot $RelativePath
        Require-File $FullPath
        Write-Host "[OK] $RelativePath" -ForegroundColor Green
    }

    $StageContent = Get-Content -LiteralPath (
        Join-Path $ProjectRoot "scripts\hit_music_r7\stage_v11.gd"
    ) -Raw

    if ($StageContent -match "super\._finish_song") {
        throw "A R11 ainda contem super._finish_song invalido."
    }

    if ($StageContent -match "super\._exit_tree") {
        throw "A R11 ainda contem super._exit_tree invalido."
    }

    Write-Host "[OK] Chamadas super invalidas removidas." -ForegroundColor Green

    Write-Host ""
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host " HIT MUSIC RESTAURADO PARA R11" -ForegroundColor Green
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host "R9, R10 e R11 foram aplicadas em sequencia."
    Write-Host "Os commits foram criados somente localmente; nenhum push foi feito."
    Write-Host ""
    Write-Host "Agora abra o Godot, aguarde importar e pressione F5." -ForegroundColor Yellow
}
finally {
    Pop-Location
}
