param(
    [string]$ComPort = "COM5",
    [int]$BaudRate = 9600,
    [string]$SpoolPath = "",
    [switch]$VerboseLog
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-DefaultSpoolPath {
    $appData = [Environment]::GetFolderPath("ApplicationData")
    $godotBase = Join-Path $appData "Godot\app_userdata"

    if (-not (Test-Path -LiteralPath $godotBase)) {
        throw "Pasta do Godot nao encontrada: $godotBase"
    }

    $candidate = Get-ChildItem `
        -LiteralPath $godotBase `
        -Directory `
        -Recurse `
        -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -eq "spool" -and
            $_.Parent.Name -eq "hit_music_serial"
        } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($null -ne $candidate) {
        return $candidate.FullName
    }

    $appFolder = Get-ChildItem `
        -LiteralPath $godotBase `
        -Directory `
        -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($null -eq $appFolder) {
        throw "Abra o Hit Music uma vez para criar o app_userdata."
    }

    $fallback = Join-Path `
        $appFolder.FullName `
        "hit_music_serial\spool"

    New-Item `
        -ItemType Directory `
        -Path $fallback `
        -Force |
        Out-Null

    return $fallback
}

if ([string]::IsNullOrWhiteSpace($SpoolPath)) {
    $SpoolPath = Get-DefaultSpoolPath
}
elseif (-not (Test-Path -LiteralPath $SpoolPath)) {
    New-Item `
        -ItemType Directory `
        -Path $SpoolPath `
        -Force |
        Out-Null
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host " HIT MUSIC R11 - PONTE SERIAL" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "COM:   $ComPort"
Write-Host "BAUD:  $BaudRate"
Write-Host "SPOOL: $SpoolPath"
Write-Host ""

$serial = [System.IO.Ports.SerialPort]::new(
    $ComPort,
    $BaudRate,
    [System.IO.Ports.Parity]::None,
    8,
    [System.IO.Ports.StopBits]::One
)

$serial.Handshake = [System.IO.Ports.Handshake]::None
$serial.NewLine = "`n"
$serial.Encoding = [System.Text.Encoding]::ASCII
$serial.DtrEnable = $false
$serial.RtsEnable = $false
$serial.ReadTimeout = 100
$serial.WriteTimeout = 300
$serial.Open()

try {
    Start-Sleep -Milliseconds 1900
    $serial.DiscardInBuffer()
    $serial.DiscardOutBuffer()

    $serial.Write("HELLO`n")

    $confirmed = $false
    $deadline = [DateTime]::UtcNow.AddMilliseconds(1800)

    while (
        -not $confirmed -and
        [DateTime]::UtcNow -lt $deadline
    ) {
        try {
            $answer = $serial.ReadLine().Trim()

            if ($answer -eq "HITMUSIC_OK") {
                $confirmed = $true
            }
        }
        catch [System.TimeoutException] {
        }
    }

    if (-not $confirmed) {
        throw (
            "COM5 abriu, mas o Arduino nao respondeu HITMUSIC_OK. "
            + "Grave o firmware R11 e feche o Monitor Serial."
        )
    }

    $serial.Write("CLEAR`n")
    Write-Host "ARDUINO R11 CONFIRMADO: HITMUSIC_OK" -ForegroundColor Green
    Write-Host "Aguardando comandos do Godot. CTRL+C encerra." -ForegroundColor Green
    Write-Host ""

    while ($true) {
        $files = Get-ChildItem `
            -LiteralPath $SpoolPath `
            -Filter "*.cmd" `
            -File `
            -ErrorAction SilentlyContinue |
            Sort-Object Name

        foreach ($file in $files) {
            $command = [IO.File]::ReadAllText(
                $file.FullName
            ).Trim()

            if (-not [string]::IsNullOrWhiteSpace($command)) {
                $serial.Write($command + "`n")
                $serial.BaseStream.Flush()

                if ($VerboseLog) {
                    Write-Host (
                        "[{0}] {1}"
                        -f (
                            Get-Date -Format "HH:mm:ss.fff"
                        ),
                        $command
                    )
                }
            }

            Remove-Item `
                -LiteralPath $file.FullName `
                -Force `
                -ErrorAction SilentlyContinue
        }

        Start-Sleep -Milliseconds 8
    }
}
finally {
    try {
        if ($serial.IsOpen) {
            $serial.Write("CLEAR`n")
            $serial.Close()
        }
    }
    catch {
    }

    $serial.Dispose()
}
