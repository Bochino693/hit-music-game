param(
    [string]$ComPort = "COM5",
    [int]$BaudRate = 9600,
    [string]$SpoolPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($SpoolPath)) {
    $godotBase = Join-Path ([Environment]::GetFolderPath("ApplicationData")) "Godot\app_userdata"
    $serialDir = Get-ChildItem -LiteralPath $godotBase -Directory -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq "hit_music_serial" } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($null -eq $serialDir) {
        throw "Não achei hit_music_serial. Abra o jogo uma vez ou informe -SpoolPath."
    }

    $basePath = $serialDir.FullName
    $SpoolPath = Join-Path $basePath "spool"
}
else {
    $basePath = Split-Path -Parent $SpoolPath
}

New-Item -ItemType Directory -Path $SpoolPath -Force | Out-Null

$alivePath    = Join-Path $basePath "bridge_alive.txt"
$readyPath    = Join-Path $basePath "bridge_ready.txt"
$startingPath = Join-Path $basePath "bridge_starting.txt"
$stopPath     = Join-Path $basePath "bridge_stop.txt"

function Touch-File([string]$Path) {
    [System.IO.File]::WriteAllText($Path, [DateTime]::UtcNow.Ticks.ToString())
}

function Close-Serial($Port) {
    try {
        if ($null -ne $Port -and $Port.IsOpen) { $Port.Close() }
    } catch {}
    try {
        if ($null -ne $Port) { $Port.Dispose() }
    } catch {}
}

function Open-HitMusicSerial {
    $p = [System.IO.Ports.SerialPort]::new(
        $ComPort,
        $BaudRate,
        [System.IO.Ports.Parity]::None,
        8,
        [System.IO.Ports.StopBits]::One
    )
    $p.Handshake = [System.IO.Ports.Handshake]::None
    $p.NewLine = "`n"
    $p.Encoding = [System.Text.Encoding]::ASCII
    $p.DtrEnable = $false
    $p.RtsEnable = $false
    $p.ReadTimeout = 100
    $p.WriteTimeout = 400
    $p.Open()

    # Nano/Uno podem reiniciar ao abrir a porta.
    Start-Sleep -Milliseconds 1900
    $p.DiscardInBuffer()
    $p.DiscardOutBuffer()

    # Handshake real: não marca READY sem confirmar o firmware.
    $p.Write("HELLO`n")
    $confirmed = $false
    $deadline = [DateTime]::UtcNow.AddMilliseconds(1800)

    while (-not $confirmed -and [DateTime]::UtcNow -lt $deadline) {
        try {
            if ($p.ReadLine().Trim() -eq "HITMUSIC_OK") {
                $confirmed = $true
            }
        } catch [System.TimeoutException] {}
    }

    if (-not $confirmed) {
        Close-Serial $p
        throw "$ComPort abriu, mas o firmware não respondeu HITMUSIC_OK."
    }

    return $p
}

Write-Host ""
Write-Host "HIT MUSIC - BRIDGE SERIAL R17"
Write-Host "COM:   $ComPort"
Write-Host "BAUD:  $BaudRate"
Write-Host "SPOOL: $SpoolPath"
Write-Host "Sem timeout de heartbeat. Sem CLEAR automático."
Write-Host ""

$serial = $null
$lastAlive = [DateTime]::MinValue

try {
    while ($true) {
        if (Test-Path -LiteralPath $stopPath) {
            # Encerramento solicitado pelo jogo:
            # apaga o hardware PRIMEIRO e só depois libera a COM.
            try {
                if ($null -ne $serial -and $serial.IsOpen) {
                    $serial.Write("CLEAR`n")
                    Start-Sleep -Milliseconds 80
                }
            } catch {}

            Remove-Item -LiteralPath $stopPath -Force -ErrorAction SilentlyContinue
            break
        }

        $now = [DateTime]::UtcNow
        if (($now - $lastAlive).TotalMilliseconds -ge 250) {
            Touch-File $alivePath
            $lastAlive = $now
        }

        if ($null -eq $serial -or -not $serial.IsOpen) {
            try {
                Remove-Item -LiteralPath $readyPath -Force -ErrorAction SilentlyContinue
                $serial = Open-HitMusicSerial
                Touch-File $readyPath
                Remove-Item -LiteralPath $startingPath -Force -ErrorAction SilentlyContinue
                Write-Host "Arduino conectado e confirmado."
            }
            catch {
                Close-Serial $serial
                $serial = $null
                Start-Sleep -Milliseconds 600
                continue
            }
        }

        $files = Get-ChildItem -LiteralPath $SpoolPath -Filter "*.cmd" -File -ErrorAction SilentlyContinue |
            Sort-Object Name

        foreach ($f in $files) {
            try {
                $cmd = [System.IO.File]::ReadAllText($f.FullName).Trim()
                if ($cmd.Length -gt 0) {
                    $serial.Write($cmd + "`n")
                }
                Remove-Item -LiteralPath $f.FullName -Force
            }
            catch {
                Close-Serial $serial
                $serial = $null
                Remove-Item -LiteralPath $readyPath -Force -ErrorAction SilentlyContinue
                break
            }
        }

        Start-Sleep -Milliseconds 8
    }
}
finally {
    # Se o processo estiver sendo encerrado normalmente, tenta apagar os LEDs
    # antes de liberar a COM. (No stop solicitado pelo jogo, CLEAR já foi enviado acima.)
    try {
        if ($null -ne $serial -and $serial.IsOpen) {
            $serial.Write("CLEAR`n")
            Start-Sleep -Milliseconds 50
        }
    } catch {}

    Close-Serial $serial
    Remove-Item -LiteralPath $readyPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $alivePath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $startingPath -Force -ErrorAction SilentlyContinue
}
