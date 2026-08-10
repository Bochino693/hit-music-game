param(
    [string]$ProjectRoot = (Get-Location).Path
)

$ErrorActionPreference = "Stop"
$pack = Split-Path -Parent $MyInvocation.MyCommand.Path

function Read-Utf8([string]$Path) {
    return [System.IO.File]::ReadAllText(
        $Path,
        [System.Text.Encoding]::UTF8
    )
}

function Write-Utf8([string]$Path, [string]$Text) {
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $enc)
}

function Copy-Safe {
    param(
        [string]$Source,
        [string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        throw "Arquivo do pacote nao encontrado: $Source"
    }

    $src = [System.IO.Path]::GetFullPath($Source)
    $dst = [System.IO.Path]::GetFullPath($Destination)

    if ($src -ieq $dst) {
        Write-Host "Ja esta no destino: $Destination" -ForegroundColor DarkGray
        return
    }

    $parent = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    Copy-Item -LiteralPath $Source `
              -Destination $Destination `
              -Force

    Write-Host "Instalado: $Destination" -ForegroundColor Green
}

$projectFile = Join-Path $ProjectRoot "project.godot"

if (-not (Test-Path -LiteralPath $projectFile)) {
    throw "Execute na raiz do projeto beta-12."
}

# Não permite aplicar acidentalmente na main.
$branch = (
    git -C $ProjectRoot branch --show-current
).Trim()

if ($branch -eq "main") {
    throw "Voce esta na main. Use a branch limpeza-led-definitiva."
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$parentDir = Split-Path -Parent $ProjectRoot
$archive = Join-Path $parentDir ("beta-12_legacy_" + $stamp)

New-Item -ItemType Directory -Path $archive -Force | Out-Null

Write-Host ""
Write-Host "Backup externo:" -ForegroundColor Yellow
Write-Host "  $archive"
Write-Host ""

# ------------------------------------------------------------
# 1) Backup dos arquivos realmente importantes.
# ------------------------------------------------------------
$critical = @(
    "project.godot",
    "ABRIR.ps1",
    "scripts\opening.gd",
    "scripts\led_client.gd",
    "scripts\hit_music_r7\led_client.gd",
    "scripts\hit_music_r7\selector_final.gd",
    "scripts\hit_music_r7\stage_final.gd",
    "scripts\hit_music_r7\stage_v11.gd",
    "scripts\hit_music_r7\stage_v10.gd",
    "scripts\hit_music_r7\stage.gd"
)

foreach ($relative in $critical) {
    $src = Join-Path $ProjectRoot $relative
    if (Test-Path -LiteralPath $src) {
        $safeName = $relative -replace '[\\/:*?"<>|]', '_'
        Copy-Item -LiteralPath $src `
                  -Destination (Join-Path $archive $safeName) `
                  -Force
    }
}

# ------------------------------------------------------------
# 2) Para qualquer bridge antiga.
# ------------------------------------------------------------
$serialBase = Join-Path `
    $env:APPDATA `
    "Godot\app_userdata\beta12\hit_music_serial"

if (Test-Path -LiteralPath $serialBase) {
    try {
        Set-Content `
            -LiteralPath (Join-Path $serialBase "bridge_stop.txt") `
            -Value "STOP" `
            -Encoding ASCII
    } catch {}
}

Start-Sleep -Milliseconds 350

try {
    Get-CimInstance Win32_Process |
        Where-Object {
            $_.Name -eq "powershell.exe" -and
            $_.CommandLine -match "BRIDGE(_R[0-9]+)?\.ps1"
        } |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }
} catch {}

# ------------------------------------------------------------
# 3) Limpa spool antigo.
# ------------------------------------------------------------
if (Test-Path -LiteralPath $serialBase) {
    $spool = Join-Path $serialBase "spool"

    if (Test-Path -LiteralPath $spool) {
        Get-ChildItem -LiteralPath $spool -Force -ErrorAction SilentlyContinue |
            Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
    }

    foreach ($name in @(
        "game_mode.flag",
        "bridge_alive.txt",
        "bridge_ready.txt",
        "bridge_starting.txt",
        "bridge_stop.txt"
    )) {
        Remove-Item `
            -LiteralPath (Join-Path $serialBase $name) `
            -Force `
            -ErrorAction SilentlyContinue
    }
}

# ------------------------------------------------------------
# 4) project.godot: apenas LedClient.
# ------------------------------------------------------------
$t = Read-Utf8 $projectFile

$t = [regex]::Replace(
    $t,
    '(?m)^HitMusicSerial="\*[^"]+"\r?\n',
    ''
)

if ($t -notmatch '(?m)^LedClient=') {
    $t = $t -replace (
        '(?m)^\[autoload\]\r?\n',
        "[autoload]`r`n`r`nLedClient=`"*res://scripts/led_client.gd`"`r`n"
    )
}

Write-Utf8 $projectFile $t

# ------------------------------------------------------------
# 5) Instala a arquitetura única.
# ------------------------------------------------------------
Copy-Safe `
    (Join-Path $pack "led_client.gd") `
    (Join-Path $ProjectRoot "scripts\led_client.gd")

Copy-Safe `
    (Join-Path $pack "legacy_led_client.gd") `
    (Join-Path $ProjectRoot "scripts\hit_music_r7\led_client.gd")

Copy-Safe `
    (Join-Path $pack "stage_final.gd") `
    (Join-Path $ProjectRoot "scripts\hit_music_r7\stage_final.gd")

Copy-Safe `
    (Join-Path $pack "selector_final.gd") `
    (Join-Path $ProjectRoot "scripts\hit_music_r7\selector_final.gd")

Copy-Safe `
    (Join-Path $pack "opening.gd") `
    (Join-Path $ProjectRoot "scripts\opening.gd")

Copy-Safe `
    (Join-Path $pack "BRIDGE_R21.ps1") `
    (Join-Path $ProjectRoot "BRIDGE_R21.ps1")

Copy-Safe `
    (Join-Path $pack "ABRIR.ps1") `
    (Join-Path $ProjectRoot "ABRIR.ps1")

# ------------------------------------------------------------
# 6) Arquiva duplicatas/experimentos conhecidos.
# Não toca scenes, assets, songs, shaders nem scripts de gameplay.
# ------------------------------------------------------------
$legacyFiles = @(
    "led_client.gd",
    "led_client.gd.uid",
    "play.gd",
    "play.gd.uid",
    "selector_led_client.gd",
    "selector_led_client.gd.uid",

    "scripts\HitMusicSerialBus.gd",
    "scripts\HitMusicSerialBus.gd.uid",

    "BRIDGE.ps1",
    "BRIDGE_R13.ps1",
    "BRIDGE_R14.ps1",
    "BRIDGE_R16.ps1",
    "BRIDGE_R17.ps1",
    "BRIDGE_R19.ps1",
    "BRIDGE_R20.ps1",

    "ABRIR_R11.ps1",
    "ARDUINO11.ino",
    "HitMusic_R11_CENARIO_GUIA_FLASH.ino",

    "FINAL.ps1",
    "FINAL2.ps1",

    "APLICAR_LED_ATOMICO_R18.ps1",
    "CORRIGIR_CARMINE_LED_ATOMICO.ps1",
    "CORRIGIR_HIT_MUSIC_R16_FADE_LIMPO.ps1",

    "INSTALAR_R14.ps1",
    "INSTALAR_R14_CORRIGIDO.ps1",
    "INSTALAR_R15_LEDS.ps1",
    "INSTALAR_R16.ps1",
    "INSTALAR_R17.ps1",
    "INSTALAR_R19_UNIFICADO.ps1",
    "INSTALAR_R19_UNIFICADO_CORRIGIDO.ps1",

    "HIT_MUSIC_VOLTA_R11_COMPLETA.zip",
    "HIT_MUSIC_R14_PRONTO_PARA_USAR.zip",
    "HIT_MUSIC_R15_LEDS_ESTRITOS.zip",
    "HIT_MUSIC_R17_LED_ALVOS_CORRIGIDO.zip",
    "HIT_MUSIC_R19_UNIFICADO_COMPLETO.zip",
    "HIT_MUSIC_R20_ATOMICO_REAL.zip"
)

foreach ($relative in $legacyFiles) {
    $src = Join-Path $ProjectRoot $relative

    if (Test-Path -LiteralPath $src) {
        $safeName = $relative -replace '[\\/:*?"<>|]', '_'
        $dst = Join-Path $archive $safeName

        Move-Item -LiteralPath $src `
                  -Destination $dst `
                  -Force

        Write-Host "Arquivado: $relative" -ForegroundColor DarkGray
    }
}

# Pastas de backup/experimento conhecidas.
Get-ChildItem -LiteralPath $ProjectRoot `
              -Directory `
              -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -like "backup_*" -or
        $_.Name -like "_backup_*"
    } |
    ForEach-Object {
        Move-Item -LiteralPath $_.FullName `
                  -Destination (Join-Path $archive $_.Name) `
                  -Force
        Write-Host "Arquivada pasta: $($_.Name)" -ForegroundColor DarkGray
    }

# Pasta R11 histórica.
$oldR11 = Join-Path $ProjectRoot "HIT_MUSIC_VOLTA_R11_COMPLETA"
if (Test-Path -LiteralPath $oldR11) {
    Move-Item -LiteralPath $oldR11 `
              -Destination (Join-Path $archive "HIT_MUSIC_VOLTA_R11_COMPLETA") `
              -Force
}

# ------------------------------------------------------------
# 7) Preserva UM firmware atual, se existir.
# ------------------------------------------------------------
$currentFirmware = Join-Path $ProjectRoot "HitMusic_R19_ATOMICO.ino"
if (Test-Path -LiteralPath $currentFirmware) {
    $arduinoDir = Join-Path $ProjectRoot "arduino"
    New-Item -ItemType Directory -Path $arduinoDir -Force | Out-Null

    Move-Item -LiteralPath $currentFirmware `
              -Destination (Join-Path $arduinoDir "HitMusic.ino") `
              -Force

    Write-Host "Firmware preservado em arduino\HitMusic.ino" -ForegroundColor Green
}

Write-Host ""
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host " HIT MUSIC R21 - LIMPEZA CONCLUIDA" -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Arquitetura:" -ForegroundColor Green
Write-Host "  Godot -> LedClient -> BRIDGE_R21 -> COM5 -> Arduino"
Write-Host ""
Write-Host "Opening:" -ForegroundColor Green
Write-Host "  estado persistente; nao existe bridge propria"
Write-Host ""
Write-Host "Selector:" -ForegroundColor Green
Write-Host "  D2/D3 fixos; sem heartbeat e sem HIT/PULSE"
Write-Host ""
Write-Host "Game:" -ForegroundColor Green
Write-Host "  somente MULTI; tap = cor do tazo; hold = amarelo; slide = apagado"
Write-Host ""
Write-Host "Backup externo:" -ForegroundColor Yellow
Write-Host "  $archive"
Write-Host ""
Write-Host "NAO abra bridge manualmente." -ForegroundColor Cyan
Write-Host "Abra pelo Godot/F6/F5 ou use ABRIR.ps1." -ForegroundColor Cyan
