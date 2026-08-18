#!/usr/bin/env bash
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ORIGEM="$DIR/arquivos"
[ -d "$ORIGEM" ] || { echo "  ERRO: extraia o ZIP inteiro."; exit 1; }
PROJETO=""; C="$DIR"
for _ in 1 2 3 4 5; do
  [ -f "$C/project.godot" ] && { PROJETO="$C"; break; }
  N="$(dirname "$C")"; [ "$N" = "$C" ] && break; C="$N"
done
if [ -z "$PROJETO" ]; then
  read -r -p "  Cole o caminho da pasta do projeto: " PROJETO
  [ -f "$PROJETO/project.godot" ] || { echo "  ERRO: pasta invalida."; exit 1; }
fi
echo "  Projeto: $PROJETO"
LISTA=$(cd "$ORIGEM" && find . -type f ! -name _REMOVER.txt | sed 's|^\./||' | sort)
NOVOS=0; TROCA=0
while IFS= read -r r; do [ -f "$PROJETO/$r" ] && TROCA=$((TROCA+1)) || NOVOS=$((NOVOS+1)); done <<< "$LISTA"
echo; echo "  $NOVOS novo(s), $TROCA substituido(s)."
read -r -p "  Aplicar agora? (S/N) " R
case "$R" in [SsYy]*) ;; *) echo "  Cancelado."; exit 0 ;; esac
BASE="$PROJETO/backup_operacao_$(date +%Y-%m-%d_%H-%M-%S)"; BACKUP="$BASE"; K=2
while [ -e "$BACKUP" ]; do BACKUP="${BASE}_$K"; K=$((K+1)); done
echo
while IFS= read -r r; do
  if [ -f "$PROJETO/$r" ]; then mkdir -p "$BACKUP/$(dirname "$r")"; cp "$PROJETO/$r" "$BACKUP/$r"; fi
  mkdir -p "$PROJETO/$(dirname "$r")"; cp "$ORIGEM/$r" "$PROJETO/$r"; echo "    + $r"
done <<< "$LISTA"
if [ -f "$ORIGEM/_REMOVER.txt" ]; then
  while IFS= read -r r; do
    [ -z "$r" ] && continue
    if [ -f "$PROJETO/$r" ]; then
      mkdir -p "$BACKUP/$(dirname "$r")"; cp "$PROJETO/$r" "$BACKUP/$r"; rm -f "$PROJETO/$r"
      echo "    - $r (prototipo morto, guardado no backup)"
    fi
  done < "$ORIGEM/_REMOVER.txt"
fi
[ -d "$BACKUP" ] && { echo; echo "  Backup: $(basename "$BACKUP")"; }

# --- project.godot: REMENDADO, nunca sobrescrito -------------------------
PROJ="$PROJETO/project.godot"
for LINHA in 'ArcadeCounters="*res://scripts/arcade_counters.gd"' 'ArcadeShell="*res://scripts/arcade_shell.gd"'; do
  if grep -qF "$LINHA" "$PROJ"; then continue; fi
  if grep -q '^ArcadeSettings=' "$PROJ"; then
    awk -v l="$LINHA" '{print} /^ArcadeSettings=/ && !f {print l; f=1}' "$PROJ" > "$PROJ.tmp" && mv "$PROJ.tmp" "$PROJ"
    echo "  project.godot: + $LINHA"
  elif grep -q '^\[autoload\]' "$PROJ"; then
    awk -v l="$LINHA" '{print} /^\[autoload\]/ && !f {print l; f=1}' "$PROJ" > "$PROJ.tmp" && mv "$PROJ.tmp" "$PROJ"
    echo "  project.godot: + $LINHA"
  else
    echo "  ATENCAO: sem [autoload] no project.godot; adicione a mao: $LINHA"
  fi
done

echo; echo "  PRONTO. Abra no Godot 4.6 e deixe reimportar."
echo "  Para conferir:"
echo "    godot --headless --path . res://tools/smoke_arcade.tscn"
echo "  Antes de exportar pro cliente, vire em scripts/arcade_counters.gd:"
echo "    const NO_CLIENTE: bool = true"
