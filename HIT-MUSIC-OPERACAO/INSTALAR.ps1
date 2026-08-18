$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Origem = Join-Path $ScriptDir "arquivos"
function E($t, $c = "Gray") { Write-Host $t -ForegroundColor $c }

E ""; E "  LAZER BEASTS - Hit Music - ajustes de operacao" "Cyan"
E "  ==================================================" "Cyan"; E ""

if (-not (Test-Path $Origem)) {
    E "  ERRO: pasta 'arquivos' nao encontrada. Extraia o ZIP INTEIRO." "Red"
    Read-Host "`n  Enter para fechar"; exit 1
}

$Projeto = $null; $C = $ScriptDir
for ($i = 0; $i -lt 5 -and $C; $i++) {
    if (Test-Path (Join-Path $C "project.godot")) { $Projeto = $C; break }
    $C = Split-Path -Parent $C
}
if (-not $Projeto) {
    E "  Nao achei o project.godot perto deste instalador." "Yellow"
    $D = (Read-Host "  Cole o caminho da pasta do projeto").Trim('"', ' ')
    if ($D -and (Test-Path (Join-Path $D "project.godot"))) { $Projeto = $D }
    else { E "  ERRO: pasta invalida." "Red"; Read-Host "`n  Enter para fechar"; exit 1 }
}
E "  Projeto: $Projeto"

$Arquivos = Get-ChildItem -Path $Origem -Recurse -File | Where-Object { $_.Name -ne "_REMOVER.txt" }
$Remover = @()
$ListaRem = Join-Path $Origem "_REMOVER.txt"
if (Test-Path $ListaRem) {
    $Remover = Get-Content $ListaRem | Where-Object { $_.Trim() -ne "" }
}
$Novos = 0; $Trocados = 0
foreach ($a in $Arquivos) {
    $rel = $a.FullName.Substring($Origem.Length).TrimStart('\', '/')
    if (Test-Path (Join-Path $Projeto $rel)) { $Trocados++ } else { $Novos++ }
}
E ""
E "  $Novos novo(s), $Trocados substituido(s), $($Remover.Count) removido(s)." "Gray"
E "  Tudo que sair do lugar vai para uma pasta de backup antes." "Green"; E ""
$R = Read-Host "  Aplicar agora? (S/N)"
if ($R -notmatch '^[SsYy]') { E "`n  Cancelado. Nada foi alterado." "Yellow"; Read-Host "`n  Enter para fechar"; exit 0 }

$Carimbo = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$Backup = Join-Path $Projeto "backup_operacao_$Carimbo"
$N = 2
while (Test-Path $Backup) { $Backup = Join-Path $Projeto "backup_operacao_${Carimbo}_$N"; $N++ }

E ""
foreach ($a in $Arquivos) {
    $rel = $a.FullName.Substring($Origem.Length).TrimStart('\', '/')
    $dst = Join-Path $Projeto $rel
    if (Test-Path $dst) {
        $bk = Join-Path $Backup $rel
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $bk) | Out-Null
        Copy-Item $dst $bk -Force
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
    Copy-Item $a.FullName $dst -Force
    E "    + $rel" "DarkGray"
}
foreach ($rel in $Remover) {
    $dst = Join-Path $Projeto $rel.Trim()
    if (Test-Path $dst) {
        $bk = Join-Path $Backup $rel.Trim()
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $bk) | Out-Null
        Copy-Item $dst $bk -Force
        Remove-Item $dst -Force
        E "    - $rel (prototipo morto, guardado no backup)" "DarkGray"
    }
}
if (Test-Path $Backup) { E "`n  Backup: $(Split-Path -Leaf $Backup)" "Green" }


# --- project.godot: REMENDADO, nunca sobrescrito -------------------------
# O project.godot do operador pode ter ajuste local (porta COM, resolucao).
# Trocar o arquivo inteiro apagaria isso, entao entram so as linhas novas.
$ProjArquivo = Join-Path $Projeto "project.godot"
$Conteudo = Get-Content $ProjArquivo -Raw -Encoding UTF8
$Novas = @(
    'ArcadeCounters="*res://scripts/arcade_counters.gd"',
    'ArcadeShell="*res://scripts/arcade_shell.gd"'
)
$Mudou = $false
foreach ($linha in $Novas) {
    if ($Conteudo -match [regex]::Escape($linha)) { continue }
    # Depois do ArcadeSettings: os dois autoloads novos leem o estado dele,
    # e a ordem no arquivo e a ordem de carregamento.
    if ($Conteudo -match '(?m)^(ArcadeSettings=.*)$') {
        $Conteudo = $Conteudo -replace '(?m)^(ArcadeSettings=.*)$', "`$1`r`n$linha"
        $Mudou = $true
    } elseif ($Conteudo -match '(?m)^\[autoload\]\s*$') {
        $Conteudo = $Conteudo -replace '(?m)^(\[autoload\])\s*$', "`$1`r`n$linha"
        $Mudou = $true
    } else {
        E "  ATENCAO: nao achei [autoload] no project.godot." "Yellow"
        E "  Adicione a mao em Projeto > Configuracoes > Autoload:" "Yellow"
        E "     $linha" "White"
    }
}
if ($Mudou) {
    [System.IO.File]::WriteAllText($ProjArquivo, $Conteudo, (New-Object System.Text.UTF8Encoding $false))
    E "  project.godot: autoloads ArcadeCounters e ArcadeShell registrados." "Green"
} else {
    E "  project.godot: autoloads ja estavam registrados." "Gray"
}

E ""; E "  PRONTO." "Green"; E ""
E "  Abra no Godot 4.6 e deixe reimportar. Para conferir:" "Gray"
E "    godot --headless --path . res://tools/smoke_arcade.tscn" "White"
E ""
E "  Antes de exportar pro cliente, vire em scripts/arcade_counters.gd:" "Yellow"
E "    const NO_CLIENTE: bool = true" "White"
E ""
E "  Para animar outra Beast depois de marcar o esqueleto dela:" "Gray"
E "    python tools/animar_beast.py --id <nome>" "White"
Read-Host "`n  Enter para fechar"
