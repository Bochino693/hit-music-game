param(
    [string]$ComPort = "AUTO",
    [int]$BaudRate = 9600,
    [string]$SpoolPath = "",
    [switch]$SelfTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($SpoolPath)) {
    throw "BRIDGE_HIT_MUSIC exige -SpoolPath."
}

$basePath = Split-Path -Parent $SpoolPath
New-Item -ItemType Directory -Path $basePath -Force | Out-Null
New-Item -ItemType Directory -Path $SpoolPath -Force | Out-Null

$alivePath = Join-Path $basePath "bridge_alive.txt"
$readyPath = Join-Path $basePath "bridge_ready.txt"
$stopPath = Join-Path $basePath "bridge_stop.txt"
$gameModePath = Join-Path $basePath "game_mode.flag"
$portCachePath = Join-Path $basePath "arduino_port.txt"
$logPath = Join-Path $basePath "bridge_hit_music.log"
$selfTestPath = Join-Path $basePath "hardware_test.txt"

$uiStatePath = Join-Path $SpoolPath "ui_state.cmd"
$gameStatePath = Join-Path $SpoolPath "game_state.cmd"

function Log([string]$Message) {
    try {
        $line = (
            (Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff") +
            " | " +
            $Message +
            [Environment]::NewLine
        )

        [System.IO.File]::AppendAllText(
            $logPath,
            $line,
            [System.Text.Encoding]::UTF8
        )
    }
    catch {}
}

function Remove-RuntimeReady {
    Remove-Item `
        -LiteralPath $readyPath `
        -Force `
        -ErrorAction SilentlyContinue

    Remove-Item `
        -LiteralPath $alivePath `
        -Force `
        -ErrorAction SilentlyContinue
}

function Touch-Alive {
    [System.IO.File]::WriteAllText(
        $alivePath,
        [DateTime]::UtcNow.Ticks.ToString()
    )
}

function Touch-Ready {
    [System.IO.File]::WriteAllText(
        $readyPath,
        [DateTime]::UtcNow.Ticks.ToString()
    )
}

function Close-Serial($Port) {
    try {
        if ($null -ne $Port -and $Port.IsOpen) {
            $Port.Close()
        }
    }
    catch {}

    try {
        if ($null -ne $Port) {
            $Port.Dispose()
        }
    }
    catch {}
}

function Send-Line(
    $Port,
    [string]$Command
) {
    if (
        $null -eq $Port -or
        -not $Port.IsOpen
    ) {
        throw "Serial não está aberta."
    }

    $cmd = $Command.Trim()

    if ($cmd.Length -eq 0) {
        return
    }

    $Port.Write(
        $cmd + "`n"
    )
}

function Read-State([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        return ""
    }

    try {
        return [System.IO.File]::ReadAllText(
            $Path
        ).Trim()
    }
    catch {
        return ""
    }
}

function Get-CandidatePorts {
    $result = New-Object System.Collections.Generic.List[string]

    function Add-Port([string]$Name) {
        if ([string]::IsNullOrWhiteSpace($Name)) {
            return
        }

        if (-not $result.Contains($Name)) {
            $result.Add($Name)
        }
    }

    if (
        -not [string]::IsNullOrWhiteSpace($ComPort) -and
        $ComPort.ToUpperInvariant() -ne "AUTO"
    ) {
        Add-Port $ComPort
        return @($result)
    }

    if (Test-Path -LiteralPath $portCachePath) {
        try {
            Add-Port (
                [System.IO.File]::ReadAllText(
                    $portCachePath
                ).Trim()
            )
        }
        catch {}
    }

    # Histórico do gabinete: tente COM5 cedo, mas não dependa dela.
    Add-Port "COM5"

    foreach (
        $name in (
            [System.IO.Ports.SerialPort]::GetPortNames() |
            Sort-Object
        )
    ) {
        Add-Port $name
    }

    return @($result)
}

function Try-OpenHitMusic([string]$PortName) {
    $port = $null

    try {
        Log "Testando $PortName @ $BaudRate."

        $port = [System.IO.Ports.SerialPort]::new(
            $PortName,
            $BaudRate,
            [System.IO.Ports.Parity]::None,
            8,
            [System.IO.Ports.StopBits]::One
        )

        $port.Handshake = [System.IO.Ports.Handshake]::None
        $port.NewLine = "`n"
        $port.Encoding = [System.Text.Encoding]::ASCII
        $port.ReadTimeout = 120
        $port.WriteTimeout = 500

        # Mantém a mesma estratégia estável do gabinete.
        $port.DtrEnable = $false
        $port.RtsEnable = $false

        $port.Open()

        # Se a placa resetar ao abrir a USB, esperamos o boot.
        Start-Sleep -Milliseconds 1900

        try { $port.DiscardInBuffer() } catch {}
        try { $port.DiscardOutBuffer() } catch {}

        # Repetir HELLO torna o handshake robusto a boot/reset tardio.
        for ($attempt = 0; $attempt -lt 8; $attempt++) {
            $port.Write("HELLO`n")

            $deadline = [DateTime]::UtcNow.AddMilliseconds(420)

            while ([DateTime]::UtcNow -lt $deadline) {
                try {
                    $reply = $port.ReadLine().Trim()

                    if ($reply.Length -gt 0) {
                        Log "$PortName RX: $reply"
                    }

                    if ($reply -eq "HITMUSIC_OK") {
                        Log "$PortName confirmado como Arduino HIT MUSIC."
                        return $port
                    }
                }
                catch [System.TimeoutException] {}
            }
        }

        Log "$PortName não respondeu HITMUSIC_OK."
        Close-Serial $port
        return $null
    }
    catch {
        Log (
            "Falha em " +
            $PortName +
            ": " +
            $_.Exception.Message
        )

        Close-Serial $port
        return $null
    }
}

function Open-HitMusic {
    $ports = @(Get-CandidatePorts)

    if ($ports.Count -eq 0) {
        throw "Nenhuma porta COM disponível."
    }

    foreach ($portName in $ports) {
        $candidate = Try-OpenHitMusic $portName

        if ($null -ne $candidate) {
            [System.IO.File]::WriteAllText(
                $portCachePath,
                $portName
            )

            return $candidate
        }
    }

    throw (
        "Nenhuma porta respondeu HELLO -> HITMUSIC_OK. Tentadas: " +
        ($ports -join ", ")
    )
}

function Run-SelfTest($Port) {
    Log "SELFTEST iniciado."

    Send-Line $Port "CLEAR"
    Start-Sleep -Milliseconds 200

    Send-Line $Port "ALL 255 0 0"
    Start-Sleep -Milliseconds 700

    Send-Line $Port "ALL 0 255 0"
    Start-Sleep -Milliseconds 700

    Send-Line $Port "ALL 0 0 255"
    Start-Sleep -Milliseconds 700

    # Valida especificamente MULTI: somente lane 0 em magenta.
    Send-Line $Port "MULTI FF00FF000000000000000000000000000000000000000000"
    Start-Sleep -Milliseconds 700

    # Valida MENU com índices explícitos 0/1.
    Send-Line $Port "MENU 0 184 255 255 209 20 0 1"
    Start-Sleep -Milliseconds 700

    Send-Line $Port "CLEAR"
    Start-Sleep -Milliseconds 150

    [System.IO.File]::WriteAllText(
        $selfTestPath,
        "OK|" + $Port.PortName + "|" + $BaudRate
    )

    Log "SELFTEST concluído."
}

# Garante apenas uma bridge por sessão de usuário.
$mutex = New-Object System.Threading.Mutex(
    $false,
    "Local\HitMusicSerialBridgeClean"
)

$ownsMutex = $false

try {
    try {
        $ownsMutex = $mutex.WaitOne(0)
    }
    catch [System.Threading.AbandonedMutexException] {
        $ownsMutex = $true
    }

    if (-not $ownsMutex) {
        Log "Outra bridge HIT MUSIC já está ativa. Encerrando duplicata."
        exit 0
    }

    Remove-RuntimeReady

    Log "=================================================="
    Log "BRIDGE HIT MUSIC CLEAN iniciada."
    Log "PortRequest=$ComPort Baud=$BaudRate Spool=$SpoolPath"

    $serial = $null
    $lastAlive = [DateTime]::MinValue
    $lastUiSent = ""
    $lastGameSent = ""
    $lastMode = ""

    while ($true) {
        if (Test-Path -LiteralPath $stopPath) {
            if ($null -ne $serial -and $serial.IsOpen) {
                try {
                    Send-Line $serial "CLEAR"
                    Start-Sleep -Milliseconds 70
                }
                catch {}
            }

            Remove-Item `
                -LiteralPath $stopPath `
                -Force `
                -ErrorAction SilentlyContinue

            break
        }

        if (
            $null -eq $serial -or
            -not $serial.IsOpen
        ) {
            Remove-RuntimeReady
            Close-Serial $serial
            $serial = $null

            try {
                $serial = Open-HitMusic

                # Ready/alive SOMENTE depois do HITMUSIC_OK.
                Touch-Ready
                Touch-Alive

                $lastAlive = [DateTime]::UtcNow
                $lastUiSent = ""
                $lastGameSent = ""
                $lastMode = ""

                Log (
                    "Arduino conectado em " +
                    $serial.PortName +
                    ". READY."
                )

                if ($SelfTest) {
                    Run-SelfTest $serial
                    break
                }
            }
            catch {
                Log (
                    "Aguardando Arduino: " +
                    $_.Exception.Message
                )

                Start-Sleep -Milliseconds 800
                continue
            }
        }

        $now = [DateTime]::UtcNow

        if (
            ($now - $lastAlive).TotalMilliseconds -ge 250
        ) {
            Touch-Alive
            $lastAlive = $now
        }

        try {
            $gameMode = Test-Path -LiteralPath $gameModePath
            $mode = if ($gameMode) { "GAME" } else { "UI" }

            if ($mode -ne $lastMode) {
                Log "Modo=$mode"

                if ($gameMode) {
                    # Não deixa MENU/SCENE vazar para a partida.
                    Send-Line $serial "CLEAR"
                    $lastGameSent = ""
                }
                else {
                    $lastUiSent = ""
                }

                $lastMode = $mode
            }

            if ($gameMode) {
                $cmd = Read-State $gameStatePath

                if (
                    $cmd.Length -gt 0 -and
                    $cmd -ne $lastGameSent
                ) {
                    Send-Line $serial $cmd
                    $lastGameSent = $cmd
                }
            }
            else {
                # Temporários fora do jogo.
                $files = @(
                    Get-ChildItem `
                        -LiteralPath $SpoolPath `
                        -Filter "cmd_*.cmd" `
                        -File `
                        -ErrorAction SilentlyContinue |
                    Sort-Object Name
                )

                foreach ($file in $files) {
                    $cmd = [System.IO.File]::ReadAllText(
                        $file.FullName
                    ).Trim()

                    if ($cmd.Length -gt 0) {
                        Send-Line $serial $cmd
                    }

                    Remove-Item `
                        -LiteralPath $file.FullName `
                        -Force `
                        -ErrorAction SilentlyContinue
                }

                # ui_state.cmd fica no disco. Após reconexão ele é reenviado.
                $ui = Read-State $uiStatePath

                if (
                    $ui.Length -gt 0 -and
                    $ui -ne $lastUiSent
                ) {
                    Send-Line $serial $ui
                    $lastUiSent = $ui
                }
            }
        }
        catch {
            Log (
                "Conexão serial perdida: " +
                $_.Exception.Message
            )

            Remove-RuntimeReady
            Close-Serial $serial
            $serial = $null

            Start-Sleep -Milliseconds 250
        }

        Start-Sleep -Milliseconds 5
    }
}
catch {
    Log (
        "ERRO FATAL: " +
        $_.Exception.ToString()
    )

    if ($SelfTest) {
        try {
            [System.IO.File]::WriteAllText(
                $selfTestPath,
                "ERRO|" + $_.Exception.Message
            )
        }
        catch {}
    }

    exit 24
}
finally {
    try {
        if (
            $null -ne $serial -and
            $serial.IsOpen
        ) {
            Send-Line $serial "CLEAR"
            Start-Sleep -Milliseconds 50
        }
    }
    catch {}

    Close-Serial $serial
    Remove-RuntimeReady

    if ($ownsMutex) {
        try {
            $mutex.ReleaseMutex()
        }
        catch {}
    }

    try {
        $mutex.Dispose()
    }
    catch {}

    Log "BRIDGE HIT MUSIC CLEAN encerrada."
}