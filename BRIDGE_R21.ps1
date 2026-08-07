param(
    [string]$ComPort = "COM5",
    [int]$BaudRate = 9600,
    [string]$SpoolPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($SpoolPath)) {
    throw "BRIDGE_R21 exige -SpoolPath."
}

$basePath = Split-Path -Parent $SpoolPath
New-Item -ItemType Directory -Path $SpoolPath -Force | Out-Null

$alivePath = Join-Path $basePath "bridge_alive.txt"
$readyPath = Join-Path $basePath "bridge_ready.txt"
$startingPath = Join-Path $basePath "bridge_starting.txt"
$stopPath = Join-Path $basePath "bridge_stop.txt"
$gameModePath = Join-Path $basePath "game_mode.flag"

$gameStatePath = Join-Path $SpoolPath "game_state.cmd"
$gameProcessingPath = Join-Path $SpoolPath "game_state.processing"

$uiStatePath = Join-Path $SpoolPath "ui_state.cmd"
$uiProcessingPath = Join-Path $SpoolPath "ui_state.processing"

function Touch-File([string]$Path) {
    [System.IO.File]::WriteAllText(
        $Path,
        [DateTime]::UtcNow.Ticks.ToString()
    )
}

function Close-Serial($Port) {
    try {
        if ($null -ne $Port -and $Port.IsOpen) {
            $Port.Close()
        }
    } catch {}

    try {
        if ($null -ne $Port) {
            $Port.Dispose()
        }
    } catch {}
}

function Send-Line($Port, [string]$Command) {
    if ($null -eq $Port -or -not $Port.IsOpen) {
        return
    }

    if ([string]::IsNullOrWhiteSpace($Command)) {
        return
    }

    $Port.Write($Command.Trim() + "`n")
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

    Start-Sleep -Milliseconds 1900
    $p.DiscardInBuffer()
    $p.DiscardOutBuffer()

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
        throw "$ComPort abriu, mas o Arduino não respondeu HITMUSIC_OK."
    }

    return $p
}

function Consume-StateFile(
    $Port,
    [string]$SourcePath,
    [string]$ProcessingPath
) {
    if (-not (Test-Path -LiteralPath $SourcePath)) {
        return
    }

    try {
        Remove-Item -LiteralPath $ProcessingPath `
                    -Force `
                    -ErrorAction SilentlyContinue

        Move-Item -LiteralPath $SourcePath `
                  -Destination $ProcessingPath `
                  -Force

        $cmd = [System.IO.File]::ReadAllText(
            $ProcessingPath
        ).Trim()

        if ($cmd.Length -gt 0) {
            Send-Line $Port $cmd
        }

        Remove-Item -LiteralPath $ProcessingPath `
                    -Force `
                    -ErrorAction SilentlyContinue
    }
    catch {
        Remove-Item -LiteralPath $ProcessingPath `
                    -Force `
                    -ErrorAction SilentlyContinue
    }
}

Write-Host ""
Write-Host "HIT MUSIC - BRIDGE SERIAL R21"
Write-Host "COM:   $ComPort"
Write-Host "BAUD:  $BaudRate"
Write-Host "SPOOL: $SpoolPath"
Write-Host ""

$serial = $null
$lastAlive = [DateTime]::MinValue

try {
    while ($true) {
        if (Test-Path -LiteralPath $stopPath) {
            try {
                if ($null -ne $serial -and $serial.IsOpen) {
                    Send-Line $serial "CLEAR"
                    Start-Sleep -Milliseconds 70
                }
            } catch {}

            Remove-Item -LiteralPath $stopPath `
                        -Force `
                        -ErrorAction SilentlyContinue
            break
        }

        $now = [DateTime]::UtcNow

        if (($now - $lastAlive).TotalMilliseconds -ge 250) {
            Touch-File $alivePath
            $lastAlive = $now
        }

        if ($null -eq $serial -or -not $serial.IsOpen) {
            try {
                Remove-Item -LiteralPath $readyPath `
                            -Force `
                            -ErrorAction SilentlyContinue

                $serial = Open-HitMusicSerial

                Touch-File $readyPath
                Remove-Item -LiteralPath $startingPath `
                            -Force `
                            -ErrorAction SilentlyContinue

                Write-Host "Arduino conectado e confirmado."
            }
            catch {
                Close-Serial $serial
                $serial = $null
                Start-Sleep -Milliseconds 600
                continue
            }
        }

        $gameMode = Test-Path -LiteralPath $gameModePath

        if ($gameMode) {
            # Durante a partida absolutamente nada da fila normal é processado.
            # Somente o frame mais recente das oito lanes.
            Consume-StateFile `
                $serial `
                $gameStatePath `
                $gameProcessingPath
        }
        else {
            # Efeitos temporários fora da partida.
            $files = Get-ChildItem `
                -LiteralPath $SpoolPath `
                -Filter "cmd_*.cmd" `
                -File `
                -ErrorAction SilentlyContinue |
                Sort-Object Name

            foreach ($file in $files) {
                try {
                    $cmd = [System.IO.File]::ReadAllText(
                        $file.FullName
                    ).Trim()

                    if ($cmd.Length -gt 0) {
                        Send-Line $serial $cmd
                    }

                    Remove-Item -LiteralPath $file.FullName -Force
                }
                catch {
                    Close-Serial $serial
                    $serial = $null

                    Remove-Item -LiteralPath $readyPath `
                                -Force `
                                -ErrorAction SilentlyContinue
                    break
                }
            }

            # Estado persistente por último.
            # Assim MENU/ATTRACT/SCENE novo vence um CLEAR antigo.
            if ($null -ne $serial -and $serial.IsOpen) {
                Consume-StateFile `
                    $serial `
                    $uiStatePath `
                    $uiProcessingPath
            }
        }

        Start-Sleep -Milliseconds 5
    }
}
finally {
    try {
        if ($null -ne $serial -and $serial.IsOpen) {
            Send-Line $serial "CLEAR"
            Start-Sleep -Milliseconds 50
        }
    } catch {}

    Close-Serial $serial

    Remove-Item -LiteralPath $readyPath `
                -Force `
                -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $alivePath `
                -Force `
                -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $startingPath `
                -Force `
                -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $gameModePath `
                -Force `
                -ErrorAction SilentlyContinue
}
