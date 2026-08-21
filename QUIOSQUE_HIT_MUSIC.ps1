<#
    HIT MUSIC - QUIOSQUE / MOLDURA TOUCH
    ====================================

    Desliga tudo que o Windows coloca POR CIMA do jogo ou desenha em cima
    da moldura touch. O gabinete e uma mesa: o jogador esbarra na tela o
    tempo todo, e cada um desses recursos vira uma janela, um menu ou uma
    bolinha cinza no meio da partida.

    O que e desligado (tudo no usuario atual, sem administrador):

      marca cinza do dedo ...... Control Panel\Cursors ContactVisualization
      rastro dos gestos ........ Control Panel\Cursors GestureVisualization
      segurar = botao direito .. Wisp\Touch TouchMode_hold
      avisos / notificacoes .... PushNotifications ToastEnabled
      balao de notificacao ..... Notifications\Settings NOC_GLOBAL_...
      janela do pendrive ....... Explorer\AutoplayHandlers DisableAutoplay
      teclado virtual .......... TabletTip\1.7 EnableDesktopModeAutoInvoke
      protetor de tela ......... Control Panel\Desktop ScreenSaveActive
      desligar tela / dormir ... powercfg (monitor, standby, hibernate)

    Com administrador, tambem:

      arrastar da borda ........ Policies\...\EdgeUI AllowEdgeSwipe
                                 (Central de Acoes, alternar tarefas)

    O valor anterior de cada item vai para um backup em JSON, entao
    -Restaurar devolve a maquina exatamente como estava.

    USO

        powershell -ExecutionPolicy Bypass -File .\QUIOSQUE_HIT_MUSIC.ps1
        powershell -ExecutionPolicy Bypass -File .\QUIOSQUE_HIT_MUSIC.ps1 -Restaurar

    O jogo chama este script sozinho ao abrir (ver arcade_shell.gd), entao
    rodar a mao so e necessario para conferir ou para restaurar.
#>

param(
    [switch]$Restaurar,
    [string]$BackupPath = ""
)

$ErrorActionPreference = "Continue"

if ([string]::IsNullOrWhiteSpace($BackupPath)) {
    $pastaBackup = Join-Path $env:APPDATA "Hit Music"
    $BackupPath = Join-Path $pastaBackup "quiosque_backup.json"
}

function Log($texto) {
    Write-Host ("[QUIOSQUE] " + $texto)
}

# ---------------------------------------------------------------
# Aplica as mudancas na hora, sem precisar sair da sessao do Windows.
# SPI_SETCONTACTVISUALIZATION / SPI_SETGESTUREVISUALIZATION so existem
# no Windows 8+; em versao antiga a chamada falha e sobra o registro,
# que vale no proximo logon.
# ---------------------------------------------------------------
$assinatura = @"
using System;
using System.Runtime.InteropServices;

public static class HitMusicQuiosque
{
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern bool SystemParametersInfo(
        uint uiAction, uint uiParam, IntPtr pvParam, uint fWinIni);

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
        uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);

    public const uint SPI_SETCONTACTVISUALIZATION = 0x2019;
    public const uint SPI_SETGESTUREVISUALIZATION = 0x201B;
    public const uint SPI_SETSCREENSAVEACTIVE     = 0x0011;
    public const uint SPIF_UPDATEINIFILE          = 0x01;
    public const uint SPIF_SENDCHANGE             = 0x02;

    public static void Avisar()
    {
        UIntPtr resultado;
        SendMessageTimeout(
            (IntPtr)0xffff, 0x001A, UIntPtr.Zero, "Environment",
            0x0002, 1000, out resultado);
    }
}
"@

try {
    if (-not ("HitMusicQuiosque" -as [type])) {
        Add-Type -TypeDefinition $assinatura -Language CSharp | Out-Null
    }
    $temApi = $true
} catch {
    $temApi = $false
    Log "aviso: nao foi possivel carregar a API do Windows; valendo so pelo registro"
}

# ---------------------------------------------------------------
# ITENS
#
# Tipo "DWord" e "String" sao gravados no registro. `Padrao` e o valor
# que o Windows usa de fabrica: e o que entra quando o backup nao existe
# e o operador pede -Restaurar.
# ---------------------------------------------------------------
$itens = @(
    @{
        Nome    = "marca cinza do dedo"
        Caminho = "HKCU:\Control Panel\Cursors"
        Chave   = "ContactVisualization"
        Tipo    = "DWord"
        Valor   = 0
        Padrao  = 1
        Admin   = $false
    },
    @{
        Nome    = "rastro dos gestos"
        Caminho = "HKCU:\Control Panel\Cursors"
        Chave   = "GestureVisualization"
        Tipo    = "DWord"
        Valor   = 0
        Padrao  = 31
        Admin   = $false
    },
    @{
        Nome    = "segurar o dedo = botao direito"
        Caminho = "HKCU:\Software\Microsoft\Wisp\Touch"
        Chave   = "TouchMode_hold"
        Tipo    = "DWord"
        Valor   = 0
        Padrao  = 1
        Admin   = $false
    },
    @{
        Nome    = "notificacoes (toasts)"
        Caminho = "HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications"
        Chave   = "ToastEnabled"
        Tipo    = "DWord"
        Valor   = 0
        Padrao  = 1
        Admin   = $false
    },
    @{
        Nome    = "balao de notificacao"
        Caminho = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings"
        Chave   = "NOC_GLOBAL_SETTING_TOASTS_ENABLED"
        Tipo    = "DWord"
        Valor   = 0
        Padrao  = 1
        Admin   = $false
    },
    @{
        Nome    = "janela automatica do pendrive"
        Caminho = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers"
        Chave   = "DisableAutoplay"
        Tipo    = "DWord"
        Valor   = 1
        Padrao  = 0
        Admin   = $false
    },
    @{
        Nome    = "teclado virtual automatico"
        Caminho = "HKCU:\Software\Microsoft\TabletTip\1.7"
        Chave   = "EnableDesktopModeAutoInvoke"
        Tipo    = "DWord"
        Valor   = 0
        Padrao  = 1
        Admin   = $false
    },
    @{
        Nome    = "protetor de tela"
        Caminho = "HKCU:\Control Panel\Desktop"
        Chave   = "ScreenSaveActive"
        Tipo    = "String"
        Valor   = "0"
        Padrao  = "1"
        Admin   = $false
    },
    @{
        Nome    = "arrastar da borda (Central de Acoes)"
        Caminho = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\EdgeUI"
        Chave   = "AllowEdgeSwipe"
        Tipo    = "DWord"
        Valor   = 0
        Padrao  = 1
        Admin   = $true
    }
)

function Ler-Valor($item) {
    try {
        $atual = Get-ItemProperty -LiteralPath $item.Caminho -Name $item.Chave -ErrorAction Stop
        return $atual.($item.Chave)
    } catch {
        return $null
    }
}

function Gravar-Valor($item, $valor) {
    if (-not (Test-Path -LiteralPath $item.Caminho)) {
        New-Item -Path $item.Caminho -Force -ErrorAction Stop | Out-Null
    }
    New-ItemProperty -LiteralPath $item.Caminho -Name $item.Chave `
        -PropertyType $item.Tipo -Value $valor -Force -ErrorAction Stop | Out-Null
}

function Sou-Administrador {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($id)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

$admin = Sou-Administrador

# ---------------------------------------------------------------
# RESTAURAR
# ---------------------------------------------------------------
if ($Restaurar) {
    Log "restaurando a maquina"

    $backup = @{}
    if (Test-Path -LiteralPath $BackupPath) {
        try {
            $lido = Get-Content -LiteralPath $BackupPath -Raw | ConvertFrom-Json
            foreach ($propriedade in $lido.PSObject.Properties) {
                $backup[$propriedade.Name] = $propriedade.Value
            }
        } catch {
            Log "aviso: backup ilegivel; voltando para os valores de fabrica"
        }
    } else {
        Log "aviso: sem backup; voltando para os valores de fabrica"
    }

    foreach ($item in $itens) {
        if ($item.Admin -and -not $admin) { continue }

        $id = $item.Caminho + "|" + $item.Chave
        $valor = $item.Padrao
        if ($backup.ContainsKey($id) -and $null -ne $backup[$id]) {
            $valor = $backup[$id]
        }

        try {
            Gravar-Valor $item $valor
            Log ("restaurado: " + $item.Nome)
        } catch {
            Log ("nao deu para restaurar: " + $item.Nome)
        }
    }

    if ($temApi) {
        [HitMusicQuiosque]::SystemParametersInfo(
            [HitMusicQuiosque]::SPI_SETCONTACTVISUALIZATION, 0, [IntPtr]1,
            [HitMusicQuiosque]::SPIF_UPDATEINIFILE -bor [HitMusicQuiosque]::SPIF_SENDCHANGE) | Out-Null
        [HitMusicQuiosque]::SystemParametersInfo(
            [HitMusicQuiosque]::SPI_SETGESTUREVISUALIZATION, 0, [IntPtr]31,
            [HitMusicQuiosque]::SPIF_UPDATEINIFILE -bor [HitMusicQuiosque]::SPIF_SENDCHANGE) | Out-Null
        [HitMusicQuiosque]::SystemParametersInfo(
            [HitMusicQuiosque]::SPI_SETSCREENSAVEACTIVE, 1, [IntPtr]::Zero,
            [HitMusicQuiosque]::SPIF_UPDATEINIFILE -bor [HitMusicQuiosque]::SPIF_SENDCHANGE) | Out-Null
        [HitMusicQuiosque]::Avisar()
    }

    try {
        & powercfg /change monitor-timeout-ac 10  | Out-Null
        & powercfg /change standby-timeout-ac 30  | Out-Null
        Log "energia: tempos padrao devolvidos"
    } catch {
        Log "aviso: powercfg nao respondeu"
    }

    Log "pronto. A maquina voltou ao comportamento normal do Windows."
    exit 0
}

# ---------------------------------------------------------------
# APLICAR
# ---------------------------------------------------------------
Log "preparando a maquina para a moldura touch"

$backupNovo = @{}
$aplicados = 0
$pulados = 0

foreach ($item in $itens) {
    if ($item.Admin -and -not $admin) {
        Log ("PULADO (precisa de administrador): " + $item.Nome)
        $pulados++
        continue
    }

    $anterior = Ler-Valor $item
    $backupNovo[($item.Caminho + "|" + $item.Chave)] = $anterior

    if ($null -ne $anterior -and "$anterior" -eq "$($item.Valor)") {
        Log ("ja estava desligado: " + $item.Nome)
        $aplicados++
        continue
    }

    try {
        Gravar-Valor $item $item.Valor
        Log ("desligado: " + $item.Nome)
        $aplicados++
    } catch {
        Log ("NAO DEU: " + $item.Nome + " (" + $_.Exception.Message + ")")
        $pulados++
    }
}

# O backup so e escrito na PRIMEIRA vez. Rodar o script de novo nao pode
# gravar por cima com os valores ja desligados, senao -Restaurar deixaria
# a maquina exatamente como esta agora.
try {
    $pastaDestino = Split-Path -Parent $BackupPath
    if (-not (Test-Path -LiteralPath $pastaDestino)) {
        New-Item -ItemType Directory -Path $pastaDestino -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $BackupPath)) {
        $backupNovo | ConvertTo-Json -Depth 4 |
            Set-Content -LiteralPath $BackupPath -Encoding UTF8
        Log ("backup do estado anterior em " + $BackupPath)
    }
} catch {
    Log "aviso: nao foi possivel gravar o backup"
}

if ($temApi) {
    # Vale na hora, sem sair da sessao.
    [HitMusicQuiosque]::SystemParametersInfo(
        [HitMusicQuiosque]::SPI_SETCONTACTVISUALIZATION, 0, [IntPtr]::Zero,
        [HitMusicQuiosque]::SPIF_UPDATEINIFILE -bor [HitMusicQuiosque]::SPIF_SENDCHANGE) | Out-Null
    [HitMusicQuiosque]::SystemParametersInfo(
        [HitMusicQuiosque]::SPI_SETGESTUREVISUALIZATION, 0, [IntPtr]::Zero,
        [HitMusicQuiosque]::SPIF_UPDATEINIFILE -bor [HitMusicQuiosque]::SPIF_SENDCHANGE) | Out-Null
    [HitMusicQuiosque]::SystemParametersInfo(
        [HitMusicQuiosque]::SPI_SETSCREENSAVEACTIVE, 0, [IntPtr]::Zero,
        [HitMusicQuiosque]::SPIF_UPDATEINIFILE -bor [HitMusicQuiosque]::SPIF_SENDCHANGE) | Out-Null
    [HitMusicQuiosque]::Avisar()
    Log "visual do toque atualizado na hora"
}

try {
    & powercfg /change monitor-timeout-ac 0   | Out-Null
    & powercfg /change standby-timeout-ac 0   | Out-Null
    & powercfg /change hibernate-timeout-ac 0 | Out-Null
    & powercfg /change disk-timeout-ac 0      | Out-Null
    Log "energia: a tela nao apaga e a maquina nao dorme"
} catch {
    Log "aviso: powercfg nao respondeu"
}

Log ("concluido. itens tratados: " + $aplicados + "   pulados: " + $pulados)

if (-not $admin) {
    Log "obs.: rodando sem administrador, o arrastar da borda continua ligado."
    Log "      Para desligar tambem, rode uma vez como administrador."
}
