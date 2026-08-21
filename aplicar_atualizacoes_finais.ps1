<#
    HIT MUSIC - ATUALIZACOES FINAIS
    ===============================

    Aplica de uma vez as tres mudancas de fechamento do jogo:

      1. VOLTAR na tela de escolha do modo (dificuldade), no mesmo desenho
         do painel, com o cursor andando por FACIL / DIFICIL / VOLTAR
         pelos tres botoes ja acesos (A sobe, E desce, B confirma).

      2. Configuracoes (F9 / SELECT) acendendo A, E e B na mesa: a serial
         da tela anterior e cancelada (CLEAR) e o quadro do menu sobe em
         seguida, sem herdar o ATTRACT da abertura.

      3. Botao IMPORTAR TODAS na tela de musicas: importa o pendrive
         inteiro, avisa quais pacotes nao estao funcionando e conta os
         que ja tinham entrado, para poder refazer sem repetir trabalho.

    COMO RODAR (PowerShell, dentro da pasta do jogo):

        powershell -ExecutionPolicy Bypass -File .\aplicar_atualizacoes_finais.ps1

    Conferir depois, sem abrir o gabinete:

        godot --headless --path . res://tools/smoke_final.tscn
#>

param(
    [string]$Repo = ".",
    [string]$Branch = "claude/hit-music-game-final-updates-pd0j18"
)

# O git escreve mensagens normais na saida de erro (inclusive o
# "Applied patch ... cleanly"). Com ErrorActionPreference = Stop isso
# viraria excecao, entao cada chamada e conferida pelo codigo de saida.
$ErrorActionPreference = "Continue"
$script:GitExit = 0

function Passo($texto) { Write-Host "`n==> $texto" -ForegroundColor Cyan }
function Ok($texto)    { Write-Host "    OK   $texto" -ForegroundColor Green }
function Aviso($texto) { Write-Host "    !    $texto" -ForegroundColor Yellow }

function Git-Run {
    $saida = & git @args 2>&1
    $script:GitExit = $LASTEXITCODE
    return $saida
}

function Parar($texto) {
    Write-Host ""
    Write-Host "ERRO: $texto" -ForegroundColor Red
    exit 1
}

Passo "Conferindo a pasta do jogo"

if (-not (Test-Path -LiteralPath $Repo)) { Parar "Pasta nao encontrada: $Repo" }
Set-Location -LiteralPath $Repo

$raiz = Git-Run rev-parse --show-toplevel
if ($script:GitExit -ne 0) {
    Parar "Esta pasta nao e um repositorio git do Hit Music. Rode o script dentro da pasta do jogo."
}
$raiz = ($raiz | Select-Object -First 1).ToString().Trim()
Set-Location -LiteralPath $raiz

if (-not (Test-Path -LiteralPath (Join-Path $raiz "project.godot"))) {
    Parar "Nao achei project.godot em $raiz. Rode o script na raiz do projeto Hit Music."
}
Ok "projeto Hit Music em $raiz"

$pendentes = Git-Run status --porcelain
if ($script:GitExit -eq 0 -and $pendentes) {
    Aviso "existem alteracoes nao commitadas nesta pasta; elas entram no mesmo commit"
}

Passo "Guardando o patch"

$patch = @'
diff --git a/README_HIT_MUSIC_R7.md b/README_HIT_MUSIC_R7.md
index fa904bb..0376fa0 100644
--- a/README_HIT_MUSIC_R7.md
+++ b/README_HIT_MUSIC_R7.md
@@ -83,6 +83,20 @@ The down button in the menus is `input_e` (physical lane 4). It is defined once,
 in `led_client.gd` (`NAV_DOWN_ACTION` / `NAV_DOWN_LANE`), and the song selector,
 the difficulty screen and their LEDs all read from there.
 
+Difficulty screen (the mode screen): the cursor walks through **FACIL,
+DIFICIL and VOLTAR** with the same three lit buttons as everywhere else —
+`input_a` up, `input_e` down, `input_b` confirms — and the panel can also be
+touched directly. VOLTAR goes back to the song selector, which is the way out
+when the wrong song was picked. No credit is spent up to that point:
+`_confirm_difficulty` is what consumes it.
+
+Settings screen (F9 / SELECT): the same three buttons stay lit on the table
+(A up, B start/confirm, E down). Entering the panel hands the serial over —
+`LedClient.begin_settings()` drops the previous screen's state (the opening
+writes `ATTRACT`) with a `CLEAR`, and the menu frame goes out right after it,
+far enough apart for the bridge to see both. Leaving clears the table again so
+the next screen writes its own frame in `_ready()`.
+
 Every song generates slides on both difficulties. `slide_every` / `hold_every`
 from the JSON now act as *weights* in the phrase draw rather than a fixed
 cadence, so a 110 s track lands roughly 4–7 slides and 3–7 holds per difficulty,
@@ -125,6 +139,36 @@ sampled from the cover when there is one. All operator songs share
 `scenes/user_song.tscn`, which resolves which song to play from the tree meta,
 because a new `.tscn` cannot be generated at runtime.
 
+### Importing a whole pen drive
+
+The music screen lists every folder found on the removable drives and keeps
+**IMPORTAR TODAS** as the first stop of the cursor. It imports the entire pen
+drive in one go — one package per frame, so the panel keeps drawing and the
+counter moves — and VOLTAR interrupts it at any point without losing what
+already went in.
+
+- Folders that are not valid packages are no longer hidden. They show up in the
+  list as `ERRO` with what is missing (`1 OGV`, `ARQUIVO EXTRA`, `TXT SEM
+  name="..."`) and are named again in the report at the end of the batch.
+- Packages already on the machine are skipped and counted, never imported
+  twice: the match is by audio hash, package id or title.
+- Every attempt is written to `user://hit_music_import_log.json`
+  (`user_catalog.import_log_record`). Running the batch again after swapping the
+  pen drive, or after a cancel, picks up exactly where it stopped, and a package
+  that failed before is flagged as `FALHOU ANTES` in the list.
+- Packages without BPM in the file still go through the 16 s audio analysis; the
+  batch waits for it and carries on by itself.
+
+### Smoke test
+
+```powershell
+godot --headless --path . res://tools/smoke_final.tscn
+```
+
+Checks the VOLTAR on the mode screen, the A/E/B LEDs plus the serial handover in
+Settings, and the batch import (including the second pass, which must import
+nothing and count the songs already installed). It prints `SMOKE_FINAL_OK`.
+
 ## Song catalog
 
 All packs are configured in:
diff --git a/scripts/config.gd b/scripts/config.gd
index 8851fcc..b1650e1 100644
--- a/scripts/config.gd
+++ b/scripts/config.gd
@@ -16,6 +16,13 @@ extends Node2D
 
 const SETTINGS_GATE: Script = preload("res://scripts/hit_music_r7/settings_gate.gd")
 const USER_CATALOG: Script = preload("res://scripts/hit_music_r7/user_catalog.gd")
+const LED_CLIENT: Script = preload("res://scripts/hit_music_r7/led_client.gd")
+
+## Atraso entre o CLEAR que cancela a serial da tela anterior e o primeiro
+## quadro de LED desta tela. A bridge le o ui_state.cmd a cada 5 ms; sem a
+## pausa os dois estados sairiam na mesma escrita e o CLEAR nunca chegaria
+## ao Arduino — a mesa continuaria com o ATTRACT da abertura.
+const LED_HANDOFF_SEG: float = 0.12
 
 const LANE_COUNT: int = 8
 const LANE_ACTIONS: Array[String] = [
@@ -41,6 +48,13 @@ enum MenuItem {
 
 const MENU_ITEM_COUNT: int = 7
 
+## Posição do botão IMPORTAR TODAS na navegação da tela de músicas: ele
+## fica ANTES do primeiro pacote, por isso o índice -1.
+const IMPORT_ALL_INDEX: int = -1
+
+## Quantos nomes de pacote com problema cabem no relatório final.
+const REPORT_NAME_LIMIT: int = 3
+
 var _return_path: String = "res://scenes/opening.tscn"
 var _cursor: int = 0
 
@@ -77,6 +91,20 @@ var _music_labels: Array[Label] = []
 var _music_row_indices: Array[int] = []
 var _usb_packages: Array = []
 
+# Botão IMPORTAR TODAS: primeira parada do cursor na tela de músicas.
+var _import_all_panel: Panel
+var _import_all_label: Label
+
+# Importação em lote (pendrive cheio de músicas).
+var _batch_active: bool = false
+var _batch_queue: Array[int] = []
+var _batch_position: int = 0
+var _batch_total: int = 0
+var _batch_ok: int = 0
+var _batch_skipped: int = 0
+var _batch_failures: Array[String] = []
+var _batch_invalid: Array[String] = []
+
 # Botão VOLTAR dedicado ao touch nas telas internas.
 var _touch_layer: CanvasLayer
 var _touch_back_panel: Panel
@@ -112,9 +140,7 @@ func _ready() -> void:
 	_return_path = SETTINGS_GATE.return_path()
 	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
 
-	var client := get_node_or_null("/root/LedClient")
-	if client != null and client.has_method("begin_menu"):
-		client.call("begin_menu")
+	_iniciar_serial_da_tela()
 
 	var screen: Vector2 = get_viewport_rect().size
 	_calculate_machine_geometry(screen)
@@ -152,6 +178,12 @@ func _process(delta: float) -> void:
 		_process_bpm_analysis(delta)
 		return
 
+	if _batch_active:
+		# Um pacote por quadro: o painel continua respondendo e o
+		# contador anda na tela enquanto o pendrive é copiado.
+		_passo_lote()
+		return
+
 	if _in_music_view:
 		_process_music_inputs()
 		return
@@ -207,10 +239,24 @@ func _handle_touch(position_value: Vector2) -> void:
 		_handle_back()
 		return
 
-	if _bpm_analysis_active:
+	if _bpm_analysis_active or _batch_active:
 		return
 
 	if _in_music_view:
+		if (
+			_import_all_panel != null
+			and is_instance_valid(_import_all_panel)
+			and _import_all_panel.visible
+			and Rect2(
+				_import_all_panel.global_position,
+				_import_all_panel.size
+			).has_point(position_value)
+		):
+			_music_cursor = IMPORT_ALL_INDEX
+			_refresh_music_view()
+			_activate_music_cursor()
+			return
+
 		for slot in range(_music_rows.size()):
 			var row: Panel = _music_rows[slot]
 			if not row.visible:
@@ -331,7 +377,7 @@ func _move_cursor(direction: int) -> void:
 		return
 	_cursor = posmod(_cursor + direction, _menu_labels.size())
 	_refresh_menu_texts()
-	_menu_feedback("menu_next_feedback")
+	_nav_feedback(direction)
 
 
 func _activate_cursor() -> void:
@@ -360,6 +406,11 @@ func _activate_cursor() -> void:
 
 
 func _handle_back() -> void:
+	if _batch_active:
+		# Interrompe o lote sem sair da tela: o operador vê o relatório
+		# do que entrou até aqui e pode retomar depois.
+		_encerrar_lote(true)
+		return
 	if _bpm_analysis_active:
 		_cancel_bpm_analysis("ANÁLISE CANCELADA")
 		return
@@ -379,18 +430,98 @@ func _close_settings() -> void:
 	_cancel_bpm_analysis("")
 	_cleanup_bpm_bus()
 
-	var client := get_node_or_null("/root/LedClient")
-	if client != null and client.has_method("clear_all"):
-		client.call("clear_all")
+	# Apaga a mesa ANTES de trocar de cena: a proxima tela (abertura ou
+	# seletor) grava o proprio quadro no _ready() e nao herda o menu
+	# aceso do painel.
+	LED_CLIENT.clear_all()
 
 	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
 	get_tree().change_scene_to_file(_return_path)
 
 
-func _menu_feedback(method_name: String) -> void:
+## ---------------------------------------------------------------
+## LEDS DA MESA NA TELA DE CONFIGURACOES
+##
+## Os tres botoes que comandam este painel ficam ACESOS o tempo todo,
+## com a mesma logica do seletor de musicas:
+##   A (lane 0) = sobe            B (lane 1) = confirma / START
+##   E (lane 4) = desce
+##
+## Antes nada acendia aqui. Dois motivos, os dois corrigidos:
+##   1. o painel chamava metodos (`menu_next_feedback`, `clear_all`) que
+##      so existem no ADAPTADOR res://scripts/hit_music_r7/led_client.gd,
+##      nunca no Autoload /root/LedClient — protegidos por has_method(),
+##      falhavam calados;
+##   2. a tela entrava em LedMode.MENU sem nunca mandar um quadro MENU,
+##      entao a mesa seguia rodando o ATTRACT gravado pela abertura.
+## ---------------------------------------------------------------
+
+## Cancela a serial da tela anterior e sobe o quadro desta. O CLEAR sai
+## primeiro (dentro de begin_settings) e o MENU logo depois, com a pausa
+## que a bridge precisa para enxergar os dois estados.
+func _iniciar_serial_da_tela() -> void:
 	var client := get_node_or_null("/root/LedClient")
-	if client != null and client.has_method(method_name):
-		client.call(method_name)
+	if client != null and client.has_method("begin_settings"):
+		client.call("begin_settings")
+	elif client != null and client.has_method("begin_stage"):
+		# Compatibilidade com versoes do Autoload sem begin_settings().
+		client.call("begin_stage")
+		LED_CLIENT.clear_all()
+
+	_agendar_leds_menu()
+
+
+func _agendar_leds_menu() -> void:
+	var tree: SceneTree = get_tree()
+	if tree == null:
+		_aplicar_leds_menu()
+		return
+
+	var timer: SceneTreeTimer = tree.create_timer(LED_HANDOFF_SEG, false)
+	timer.timeout.connect(_aplicar_leds_menu)
+
+
+## Quadro persistente do painel: A sobe, B confirma, E desce.
+func _aplicar_leds_menu() -> void:
+	if not is_inside_tree():
+		return
+	if _in_test_view:
+		# O teste governa lane a lane; nao pisa nele.
+		return
+
+	LED_CLIENT.menu_state_three(
+		LED_CLIENT.MENU_NEXT_COLOR,
+		LED_CLIENT.MENU_SELECT_COLOR,
+		LED_CLIENT.MENU_NEXT_COLOR,
+		LED_CLIENT.NAV_NEXT_LANE,
+		LED_CLIENT.NAV_SELECT_LANE,
+		LED_CLIENT.NAV_DOWN_LANE
+	)
+
+
+## Flash curto no botao que o operador acabou de apertar. Depois do flash
+## o firmware devolve o quadro MENU, entao os tres continuam acesos.
+func _menu_feedback(method_name: String) -> void:
+	if method_name == "menu_select_feedback":
+		LED_CLIENT.menu_select_feedback()
+	else:
+		LED_CLIENT.menu_next_feedback()
+
+
+## Feedback de navegacao no botao certo: A quando sobe, E quando desce.
+func _nav_feedback(direction: int) -> void:
+	if direction < 0:
+		LED_CLIENT.hit_lane(
+			LED_CLIENT.NAV_NEXT_LANE,
+			LED_CLIENT.MENU_NEXT_COLOR,
+			170
+		)
+	else:
+		LED_CLIENT.hit_lane(
+			LED_CLIENT.NAV_DOWN_LANE,
+			LED_CLIENT.MENU_NEXT_COLOR,
+			170
+		)
 
 
 ## ---------------------------------------------------------------
@@ -718,8 +849,8 @@ func _build_music_view() -> void:
 		HORIZONTAL_ALIGNMENT_CENTER,
 		font
 	)
-	_music_title.position = Vector2(panel_size.x * 0.12, panel_size.y * 0.055)
-	_music_title.size = Vector2(panel_size.x * 0.76, panel_size.y * 0.080)
+	_music_title.position = Vector2(panel_size.x * 0.12, panel_size.y * 0.045)
+	_music_title.size = Vector2(panel_size.x * 0.76, panel_size.y * 0.078)
 	_music_title.add_theme_color_override("font_color", Color(0.10, 0.85, 1.0, 1.0))
 	_music_title.clip_text = true
 	_music_panel.add_child(_music_title)
@@ -730,16 +861,38 @@ func _build_music_view() -> void:
 		HORIZONTAL_ALIGNMENT_CENTER,
 		font
 	)
-	_music_status.position = Vector2(panel_size.x * 0.14, panel_size.y * 0.145)
-	_music_status.size = Vector2(panel_size.x * 0.72, panel_size.y * 0.075)
+	_music_status.position = Vector2(panel_size.x * 0.14, panel_size.y * 0.128)
+	_music_status.size = Vector2(panel_size.x * 0.72, panel_size.y * 0.070)
 	_music_status.clip_text = true
 	_music_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
 	_music_status.add_theme_color_override("font_color", Color(0.70, 0.78, 0.90, 1.0))
 	_music_panel.add_child(_music_status)
 
-	var row_y: float = panel_size.y * 0.245
-	var row_pitch: float = panel_size.y * 0.093
-	var row_height: float = panel_size.y * 0.072
+	# Botão de lote: um pendrive de cliente chega com dezenas de pastas e
+	# importar uma a uma (com 16 s de análise de BPM em cada) era o gargalo
+	# da instalação. Ele fica no topo da lista, como primeira parada do
+	# cursor, para o operador achar sem procurar.
+	_import_all_panel = Panel.new()
+	_import_all_panel.position = Vector2(panel_size.x * 0.145, panel_size.y * 0.210)
+	_import_all_panel.size = Vector2(panel_size.x * 0.71, panel_size.y * 0.074)
+	_import_all_panel.clip_contents = true
+	_import_all_panel.add_theme_stylebox_override("panel", _row_style(false))
+	_music_panel.add_child(_import_all_panel)
+
+	_import_all_label = _make_label(
+		"IMPORTAR TODAS",
+		int(_radius * 0.031),
+		HORIZONTAL_ALIGNMENT_CENTER,
+		font
+	)
+	_import_all_label.size = _import_all_panel.size
+	_import_all_label.clip_text = true
+	_import_all_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
+	_import_all_panel.add_child(_import_all_label)
+
+	var row_y: float = panel_size.y * 0.310
+	var row_pitch: float = panel_size.y * 0.081
+	var row_height: float = panel_size.y * 0.066
 
 	# Cinco linhas visíveis; listas maiores são paginadas pelo cursor.
 	for i in range(5):
@@ -769,15 +922,15 @@ func _build_music_view() -> void:
 		HORIZONTAL_ALIGNMENT_CENTER,
 		font
 	)
-	_music_detail.position = Vector2(panel_size.x * 0.13, panel_size.y * 0.725)
-	_music_detail.size = Vector2(panel_size.x * 0.74, panel_size.y * 0.105)
+	_music_detail.position = Vector2(panel_size.x * 0.13, panel_size.y * 0.716)
+	_music_detail.size = Vector2(panel_size.x * 0.74, panel_size.y * 0.115)
 	_music_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 	_music_detail.clip_text = true
 	_music_detail.add_theme_color_override("font_color", Color(0.72, 0.80, 0.92, 1.0))
 	_music_panel.add_child(_music_detail)
 
 	_music_hint = _make_label(
-		"A ↑   E ↓   B IMPORTA   •   TOQUE 2X INSTALA   •   VOLTAR",
+		"A ↑   E ↓   B IMPORTA   •   IMPORTAR TODAS NO TOPO   •   VOLTAR",
 		int(_radius * 0.021),
 		HORIZONTAL_ALIGNMENT_CENTER,
 		font
@@ -797,6 +950,10 @@ func _open_music_view() -> void:
 	_set_touch_back_visible(true)
 	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
 
+	# Abre com o cursor no botão de lote: é a ação que o operador usa em
+	# 9 de 10 instalações.
+	_music_cursor = IMPORT_ALL_INDEX
+
 	_set_top_context(
 		"INSTALAÇÃO DE MÚSICAS",
 		"A: SUBIR   •   E: DESCER   •   B: IMPORTAR   •   SELECT/F9: VOLTAR",
@@ -806,6 +963,7 @@ func _open_music_view() -> void:
 
 
 func _close_music_view() -> void:
+	_cancelar_lote(true)
 	_cancel_bpm_analysis("")
 	_in_music_view = false
 	_music_layer.visible = false
@@ -824,12 +982,19 @@ func _scan_usb() -> void:
 	_music_status.text = "ESCANEANDO PENDRIVES..."
 	_music_status.add_theme_color_override("font_color", Color(0.20, 0.88, 1.0, 1.0))
 	_usb_packages = USER_CATALOG.scan_usb_packages()
-	_music_cursor = clampi(_music_cursor, 0, maxi(0, _usb_packages.size() - 1))
+	# O -1 (IMPORTAR TODAS) é uma posição válida do cursor e precisa
+	# sobreviver ao reescaneamento que roda depois de cada importação.
+	if _music_cursor >= 0:
+		_music_cursor = clampi(_music_cursor, 0, maxi(0, _usb_packages.size() - 1))
 	_music_scan_busy = false
 	_refresh_music_view()
 
 
 func _process_music_inputs() -> void:
+	if _batch_active:
+		# Durante o lote os botões de navegação ficam parados de
+		# propósito: só VOLTAR/SELECT/F9 interrompe.
+		return
 	if Input.is_action_just_pressed("input_a"):
 		_move_music_cursor(-1)
 		return
@@ -843,15 +1008,34 @@ func _process_music_inputs() -> void:
 		_activate_music_cursor()
 
 
+## Navegação da tela de músicas: [IMPORTAR TODAS] + um item por pacote.
+func _proximo_cursor_musica(direction: int) -> int:
+	var total: int = _usb_packages.size() + 1
+	var posicao: int = posmod((_music_cursor + 1) + direction, total)
+	return posicao - 1
+
+
 func _move_music_cursor(direction: int) -> void:
+	if _batch_active:
+		return
 	if _usb_packages.is_empty():
 		return
-	_music_cursor = posmod(_music_cursor + direction, _usb_packages.size())
+	_music_cursor = _proximo_cursor_musica(direction)
 	_refresh_music_view()
-	_menu_feedback("menu_next_feedback")
+	_nav_feedback(direction)
 
 
 func _activate_music_cursor() -> void:
+	if _batch_active:
+		return
+
+	if _music_cursor == IMPORT_ALL_INDEX:
+		if _usb_packages.is_empty():
+			_scan_usb()
+			return
+		_iniciar_lote()
+		return
+
 	if _usb_packages.is_empty():
 		_scan_usb()
 		return
@@ -893,6 +1077,7 @@ func _refresh_music_view() -> void:
 
 	if count == 0:
 		_music_row_indices.clear()
+		_music_cursor = IMPORT_ALL_INDEX
 		_music_status.text = "NENHUM PACOTE ENCONTRADO — B PARA REESCANEAR"
 		_music_status.add_theme_color_override("font_color", Color(1.0, 0.72, 0.30, 1.0))
 		_music_detail.text = (
@@ -901,6 +1086,7 @@ func _refresh_music_view() -> void:
 		)
 		for i in range(_music_labels.size()):
 			_music_rows[i].visible = false
+		_atualizar_botao_lote(0, 0, 0)
 		_fit_multiline_label(_music_detail, int(_radius * 0.026), 10)
 		return
 
@@ -908,16 +1094,40 @@ func _refresh_music_view() -> void:
 		row.visible = true
 
 	var usb_installed: int = 0
+	var usb_invalid: int = 0
 	for package_value in _usb_packages:
-		if package_value is Dictionary and bool((package_value as Dictionary).get("installed", false)):
+		if not (package_value is Dictionary):
+			continue
+		var item: Dictionary = package_value as Dictionary
+		if not bool(item.get("valid", false)):
+			usb_invalid += 1
+		elif bool(item.get("installed", false)):
 			usb_installed += 1
 
-	var new_count: int = count - usb_installed
-	_music_status.text = "%d NOVA(S)   •   %d JÁ INSTALADA(S)" % [
-		new_count,
-		usb_installed,
-	]
-	_music_status.add_theme_color_override("font_color", Color(0.32, 1.0, 0.62, 1.0))
+	var new_count: int = count - usb_installed - usb_invalid
+
+	if _batch_active:
+		_music_status.text = "IMPORTANDO %d/%d   •   %d OK   •   %d FALHA(S)" % [
+			mini(_batch_position + 1, _batch_total),
+			_batch_total,
+			_batch_ok,
+			_batch_failures.size(),
+		]
+		_music_status.add_theme_color_override("font_color", Color(1.0, 0.84, 0.24, 1.0))
+	else:
+		_music_status.text = "%d NOVA(S)   •   %d JÁ INSTALADA(S)   •   %d COM ERRO" % [
+			new_count,
+			usb_installed,
+			usb_invalid,
+		]
+		_music_status.add_theme_color_override(
+			"font_color",
+			Color(1.0, 0.72, 0.30, 1.0)
+			if usb_invalid > 0
+			else Color(0.32, 1.0, 0.62, 1.0)
+		)
+
+	_atualizar_botao_lote(new_count, usb_installed, usb_invalid)
 
 	var visible_count: int = _music_labels.size()
 	_music_row_indices.clear()
@@ -949,14 +1159,22 @@ func _refresh_music_view() -> void:
 			else "BPM: ANALISAR"
 		)
 
+		# "JÁ IMPORTADA" vem do histórico em disco: mesmo que o operador
+		# tenha apagado a música da máquina, a lista lembra que aquela
+		# pasta já passou por aqui e o que aconteceu com ela.
+		var log_status: String = str(package.get("log_status", ""))
+		var situacao: String = (
+			"JÁ INSTALADA"
+			if installed
+			else ("NOVA" if valid else "ERRO")
+		)
+		if not installed and valid and log_status == "erro":
+			situacao = "FALHOU ANTES"
+
 		_music_labels[slot].text = "%s   •   %s   •   %s" % [
 			str(package.get("name", "?")).to_upper(),
 			bpm_text,
-			(
-				"JÁ INSTALADA"
-				if installed
-				else ("NOVA" if valid else "ERRO")
-			),
+			situacao,
 		]
 
 		var selected: bool = index == _music_cursor
@@ -973,6 +1191,11 @@ func _refresh_music_view() -> void:
 		)
 		_fit_label_to_width(_music_labels[slot], int(_radius * 0.031), 10)
 
+	if _music_cursor == IMPORT_ALL_INDEX:
+		_music_detail.text = _texto_detalhe_lote(new_count, usb_installed, usb_invalid)
+		_fit_multiline_label(_music_detail, int(_radius * 0.026), 10)
+		return
+
 	var selected_package: Dictionary = _usb_packages[_music_cursor]
 	if bool(selected_package.get("installed", false)):
 		var existing: Dictionary = selected_package.get("installed_match", {}) as Dictionary
@@ -1007,7 +1230,7 @@ func _refresh_music_view() -> void:
 
 
 func _import_package(package: Dictionary, bpm: float) -> void:
-	var result: Dictionary = USER_CATALOG.import_usb_package(package, bpm)
+	var result: Dictionary = _importar_pacote_resultado(package, bpm)
 
 	if bool(result.get("ok", false)):
 		_music_status.add_theme_color_override("font_color", Color(0.32, 1.0, 0.62, 1.0))
@@ -1026,6 +1249,285 @@ func _import_package(package: Dictionary, bpm: float) -> void:
 	_refresh_menu_texts()
 
 
+## Importa e ANOTA o resultado no histórico em disco. É essa anotação que
+## permite refazer uma importação em lote sem repetir trabalho e sem
+## perder de vista o pacote que falhou na tentativa anterior.
+func _importar_pacote_resultado(package: Dictionary, bpm: float) -> Dictionary:
+	var result: Dictionary = USER_CATALOG.import_usb_package(package, bpm)
+
+	if bool(result.get("ok", false)):
+		USER_CATALOG.import_log_record(package, "ok", "%d BPM" % roundi(bpm))
+	elif bool(result.get("already_installed", false)):
+		USER_CATALOG.import_log_record(
+			package,
+			"duplicada",
+			str(result.get("erro", ""))
+		)
+	else:
+		USER_CATALOG.import_log_record(
+			package,
+			"erro",
+			str(result.get("erro", "Falha ao importar."))
+		)
+
+	return result
+
+
+## ---------------------------------------------------------------
+## IMPORTACAO EM LOTE (PENDRIVE CHEIO)
+##
+## Um pacote por quadro: o painel continua desenhando, o contador anda na
+## tela e VOLTAR interrompe a qualquer momento. Pacotes sem BPM gravado
+## passam pela análise de áudio (~16 s) e o lote continua sozinho quando
+## ela termina.
+##
+## Nada é importado duas vezes: o que já está na máquina é PULADO (e
+## contado), e cada resultado vai para o histórico em disco — então
+## repetir a importação depois de trocar o pendrive, ou depois de um
+## cancelamento, retoma exatamente de onde parou.
+## ---------------------------------------------------------------
+
+func _iniciar_lote() -> void:
+	if _batch_active or _bpm_analysis_active:
+		return
+
+	_batch_queue.clear()
+	_batch_failures.clear()
+	_batch_invalid.clear()
+	_batch_ok = 0
+	_batch_skipped = 0
+	_batch_position = 0
+
+	for index in range(_usb_packages.size()):
+		var package_value: Variant = _usb_packages[index]
+		if not (package_value is Dictionary):
+			continue
+
+		var package: Dictionary = package_value as Dictionary
+
+		if not bool(package.get("valid", false)):
+			_batch_invalid.append(_descricao_falha(package, str(package.get("error", ""))))
+			continue
+
+		if bool(package.get("installed", false)):
+			_batch_skipped += 1
+			continue
+
+		_batch_queue.append(index)
+
+	_batch_total = _batch_queue.size()
+
+	if _batch_total == 0:
+		_menu_feedback("menu_next_feedback")
+		_mostrar_relatorio_lote(false)
+		return
+
+	_batch_active = true
+	_menu_feedback("menu_select_feedback")
+	_refresh_music_view()
+
+
+func _passo_lote() -> void:
+	if not _batch_active or _bpm_analysis_active:
+		return
+
+	if _batch_position >= _batch_queue.size():
+		_encerrar_lote(false)
+		return
+
+	var index: int = _batch_queue[_batch_position]
+	if index < 0 or index >= _usb_packages.size():
+		_batch_position += 1
+		return
+
+	var package_value: Variant = _usb_packages[index]
+	if not (package_value is Dictionary):
+		_batch_position += 1
+		return
+
+	var package: Dictionary = package_value as Dictionary
+	_refresh_music_view()
+
+	var bpm: float = float(package.get("bpm", 0.0))
+	if bpm >= 40.0 and bpm <= 260.0:
+		_registrar_resultado_lote(package, _importar_pacote_resultado(package, bpm))
+		_batch_position += 1
+		return
+
+	# Sem BPM no arquivo: a análise de áudio assume e o lote continua em
+	# _finish_bpm_analysis().
+	if not _start_bpm_analysis(package):
+		_batch_failures.append(
+			_descricao_falha(package, "MP3 não pôde ser analisado")
+		)
+		USER_CATALOG.import_log_record(package, "erro", "MP3 não pôde ser analisado")
+		_batch_position += 1
+
+
+func _registrar_resultado_lote(package: Dictionary, result: Dictionary) -> void:
+	if bool(result.get("ok", false)):
+		_batch_ok += 1
+	elif bool(result.get("already_installed", false)):
+		_batch_skipped += 1
+	else:
+		_batch_failures.append(
+			_descricao_falha(package, str(result.get("erro", "Falha ao importar.")))
+		)
+
+
+func _cancelar_lote(silencioso: bool) -> void:
+	if not _batch_active:
+		return
+	_encerrar_lote(true, silencioso)
+
+
+func _encerrar_lote(cancelado: bool, silencioso: bool = false) -> void:
+	_batch_active = false
+	_cancel_bpm_analysis("")
+	_refresh_menu_texts()
+
+	if silencioso:
+		return
+
+	# Reescaneia para que as recém-instaladas apareçam como JÁ INSTALADA:
+	# é o que faz uma segunda tentativa pular o que já entrou.
+	_scan_usb()
+	_mostrar_relatorio_lote(cancelado)
+
+
+## Relatório final: quantas entraram, quantas foram puladas e — o ponto
+## que o operador precisa levar para o cliente — QUAIS não funcionaram.
+func _mostrar_relatorio_lote(cancelado: bool) -> void:
+	if _music_status == null or not is_instance_valid(_music_status):
+		return
+
+	var problemas: Array[String] = []
+	problemas.append_array(_batch_failures)
+	problemas.append_array(_batch_invalid)
+
+	if cancelado:
+		_music_status.text = "IMPORTAÇÃO CANCELADA EM %d/%d   •   %d OK   •   %d FALHA(S)" % [
+			mini(_batch_position, _batch_total),
+			_batch_total,
+			_batch_ok,
+			problemas.size(),
+		]
+		_music_status.add_theme_color_override("font_color", Color(1.0, 0.72, 0.30, 1.0))
+	elif _batch_total == 0:
+		_music_status.text = "NADA NOVO PARA IMPORTAR   •   %d JÁ INSTALADA(S)   •   %d COM ERRO" % [
+			_batch_skipped,
+			_batch_invalid.size(),
+		]
+		_music_status.add_theme_color_override("font_color", Color(0.32, 1.0, 0.62, 1.0))
+	else:
+		_music_status.text = "IMPORTAÇÃO CONCLUÍDA   •   %d OK   •   %d PULADA(S)   •   %d FALHA(S)" % [
+			_batch_ok,
+			_batch_skipped,
+			problemas.size(),
+		]
+		_music_status.add_theme_color_override(
+			"font_color",
+			Color(1.0, 0.72, 0.30, 1.0)
+			if not problemas.is_empty()
+			else Color(0.32, 1.0, 0.62, 1.0)
+		)
+
+	if _music_detail == null or not is_instance_valid(_music_detail):
+		return
+
+	if problemas.is_empty():
+		_music_detail.text = (
+			"Nenhum pacote com problema. Importar de novo é seguro: "
+			+ "as músicas que já entraram são puladas automaticamente."
+		)
+	else:
+		var mostrados: Array[String] = []
+		for texto in problemas:
+			if mostrados.size() >= REPORT_NAME_LIMIT:
+				break
+			mostrados.append(texto)
+
+		var restante: int = problemas.size() - mostrados.size()
+		_music_detail.text = (
+			"NÃO FUNCIONARAM: "
+			+ "   |   ".join(mostrados)
+			+ ("   |   + %d PACOTE(S)" % restante if restante > 0 else "")
+		)
+
+	_fit_multiline_label(_music_detail, int(_radius * 0.026), 10)
+
+
+func _descricao_falha(package: Dictionary, motivo: String) -> String:
+	var nome: String = str(package.get("name", "")).strip_edges()
+	if nome.is_empty():
+		nome = str(package.get("folder", "?")).get_file()
+	var texto: String = nome.to_upper()
+	if not motivo.strip_edges().is_empty():
+		texto += " (" + motivo.strip_edges() + ")"
+	return texto
+
+
+func _atualizar_botao_lote(
+	novas: int,
+	instaladas: int,
+	invalidas: int
+) -> void:
+	if _import_all_panel == null or not is_instance_valid(_import_all_panel):
+		return
+
+	var selecionado: bool = _music_cursor == IMPORT_ALL_INDEX
+
+	if _batch_active:
+		_import_all_label.text = "IMPORTANDO %d/%d   •   VOLTAR CANCELA" % [
+			mini(_batch_position + 1, _batch_total),
+			_batch_total,
+		]
+	elif novas > 0:
+		_import_all_label.text = "IMPORTAR TODAS   •   %d NOVA(S)" % novas
+	elif instaladas > 0 or invalidas > 0:
+		_import_all_label.text = "IMPORTAR TODAS   •   NADA NOVO"
+	else:
+		_import_all_label.text = "IMPORTAR TODAS   •   REESCANEAR"
+
+	_import_all_panel.add_theme_stylebox_override("panel", _row_style(selecionado))
+	_import_all_label.add_theme_color_override(
+		"font_color",
+		Color(1.0, 0.86, 0.20, 1.0)
+		if selecionado
+		else (
+			Color(0.42, 1.0, 0.68, 1.0)
+			if novas > 0
+			else Color(0.70, 0.78, 0.90, 1.0)
+		)
+	)
+	_fit_label_to_width(_import_all_label, int(_radius * 0.031), 10)
+
+
+func _texto_detalhe_lote(
+	novas: int,
+	instaladas: int,
+	invalidas: int
+) -> String:
+	if _batch_active:
+		return (
+			"Importando o pendrive inteiro. Não retire o pendrive. "
+			+ "VOLTAR interrompe — o que já entrou continua instalado."
+		)
+
+	if novas <= 0 and invalidas <= 0:
+		return (
+			"Todas as %d músicas do pendrive já estão na máquina." % instaladas
+			+ "   B reescaneia o pendrive."
+		)
+
+	var texto: String = "B importa as %d música(s) nova(s) de uma vez." % novas
+	if instaladas > 0:
+		texto += "   %d já instalada(s) serão puladas." % instaladas
+	if invalidas > 0:
+		texto += "   %d pasta(s) com erro serão listadas no final." % invalidas
+	return texto
+
+
 ## ---------------------------------------------------------------
 ## DETECÇÃO AUTOMÁTICA DE BPM
 ## ---------------------------------------------------------------
@@ -1069,11 +1571,15 @@ func _cleanup_bpm_bus() -> void:
 		AudioServer.remove_bus(existing)
 
 
-func _start_bpm_analysis(package: Dictionary) -> void:
+## Devolve `true` quando a análise realmente começou. O lote depende
+## dessa resposta: um MP3 ilegível precisa virar falha registrada, não
+## uma chamada repetida a cada quadro.
+func _start_bpm_analysis(package: Dictionary) -> bool:
 	var audio_path: String = str(package.get("audio", ""))
 	if audio_path.is_empty() or not FileAccess.file_exists(audio_path):
+		_music_status.add_theme_color_override("font_color", Color(1.0, 0.42, 0.42, 1.0))
 		_music_status.text = "MP3 NÃO ENCONTRADO PARA ANÁLISE"
-		return
+		return false
 
 	if _bpm_player == null or not is_instance_valid(_bpm_player):
 		_ensure_bpm_analyzer()
@@ -1082,7 +1588,7 @@ func _start_bpm_analysis(package: Dictionary) -> void:
 	if stream == null:
 		_music_status.add_theme_color_override("font_color", Color(1.0, 0.42, 0.42, 1.0))
 		_music_status.text = "NÃO FOI POSSÍVEL ABRIR O MP3"
-		return
+		return false
 
 	_bpm_pending_package = package.duplicate(true)
 	_bpm_analysis_active = true
@@ -1104,6 +1610,7 @@ func _start_bpm_analysis(package: Dictionary) -> void:
 	_music_status.add_theme_color_override("font_color", Color(1.0, 0.84, 0.24, 1.0))
 	_music_status.text = "ANALISANDO BPM... 0%"
 	_music_detail.text = "O áudio está sendo analisado em silêncio. Não retire o pendrive."
+	return true
 
 
 func _process_bpm_analysis(delta: float) -> void:
@@ -1149,7 +1656,11 @@ func _process_bpm_analysis(delta: float) -> void:
 		0,
 		100
 	)
-	_music_status.text = "ANALISANDO BPM... %d%%" % progress
+	_music_status.text = (
+		("LOTE %d/%d   •   " % [mini(_batch_position + 1, _batch_total), _batch_total])
+		if _batch_active
+		else ""
+	) + "ANALISANDO BPM... %d%%" % progress
 
 	if (
 		_bpm_analysis_elapsed >= BPM_ANALYSIS_SECONDS
@@ -1166,6 +1677,17 @@ func _finish_bpm_analysis() -> void:
 	_bpm_analysis_active = false
 
 	if bpm < 40.0:
+		if _batch_active:
+			var recusado: Dictionary = _bpm_pending_package.duplicate(true)
+			_batch_failures.append(
+				_descricao_falha(recusado, "BPM não detectado")
+			)
+			USER_CATALOG.import_log_record(recusado, "erro", "BPM não detectado")
+			_bpm_pending_package.clear()
+			_batch_position += 1
+			_refresh_music_view()
+			return
+
 		_music_status.add_theme_color_override("font_color", Color(1.0, 0.55, 0.28, 1.0))
 		_music_status.text = "BPM NÃO CONFIÁVEL — USE TBPM NO MP3 OU bpm= NO TXT"
 		_music_detail.text = (
@@ -1175,6 +1697,15 @@ func _finish_bpm_analysis() -> void:
 		return
 
 	_bpm_pending_package["bpm"] = bpm
+
+	if _batch_active:
+		var pacote: Dictionary = _bpm_pending_package.duplicate(true)
+		_bpm_pending_package.clear()
+		_registrar_resultado_lote(pacote, _importar_pacote_resultado(pacote, bpm))
+		_batch_position += 1
+		_refresh_music_view()
+		return
+
 	_music_status.text = "BPM DETECTADO: %d" % roundi(bpm)
 	_import_package(_bpm_pending_package, bpm)
 
@@ -1458,11 +1989,10 @@ func _close_test_view() -> void:
 	_panel.visible = true
 	_set_touch_back_visible(false)
 
-	var client := get_node_or_null("/root/LedClient")
-	if client != null and client.has_method("clear_all"):
-		client.call("clear_all")
-	if client != null and client.has_method("begin_menu"):
-		client.call("begin_menu")
+	# O teste deixa lanes acesas uma a uma; o trio do menu so volta
+	# depois de apagar tudo.
+	LED_CLIENT.clear_all()
+	_agendar_leds_menu()
 
 	for i in range(_lane_pressed_state.size()):
 		_lane_pressed_state[i] = false
diff --git a/scripts/hit_music_r7/stage_v10.gd b/scripts/hit_music_r7/stage_v10.gd
index 2160595..2ea88d9 100644
--- a/scripts/hit_music_r7/stage_v10.gd
+++ b/scripts/hit_music_r7/stage_v10.gd
@@ -15,13 +15,14 @@ func _ready() -> void:
 	_difficulty_confirmed = false
 	_display_score = 0.0
 	_select_difficulty("easy", true)
+	_centralizar_botao_voltar()
 
 	if _pre_game_title != null:
 		_pre_game_title.text = "ESCOLHA A DIFICULDADE"
 	if _pre_game_subtitle != null:
 		_pre_game_subtitle.text = (
-			"A / E: MOVER     B: SELECIONAR\n"
-			+ "TOQUE EM FACIL OU DIFICIL PARA INICIAR"
+			"A SOBE     E DESCE     B CONFIRMA\n"
+			+ "FACIL   •   DIFICIL   •   VOLTAR PARA TROCAR DE MUSICA"
 		)
 
 	_update_pre_game_styles()
@@ -37,18 +38,17 @@ func _ready() -> void:
 	_apply_menu_leds()
 
 
+## A sobe, E desce, B confirma — exatamente como no seletor de musicas e
+## nas Configuracoes. O cursor passeia por FACIL, DIFICIL e VOLTAR, entao
+## desistir da musica usa os mesmos tres botoes acesos na mesa: nao existe
+## um quarto botao apagado que o jogador teria que adivinhar.
 func _process_pre_game_inputs() -> void:
-	# input_e e o mesmo botao fisico de DESCER usado no seletor de
-	# musicas (ver DOWN_ACTION em selector.gd), entao ele tambem move o
-	# cursor aqui — o jogador nao precisa trocar de botao entre telas.
-	if _action_pressed("input_a") or _action_pressed("input_e"):
-		_move_difficulty_cursor()
-	elif _action_pressed("input_b"):
-		_confirm_difficulty()
-	elif _action_pressed("ui_down"):
-		_move_difficulty_cursor()
-	elif _action_pressed("ui_accept"):
-		_confirm_difficulty()
+	if _action_pressed("input_a") or _action_pressed("ui_up") or _action_pressed("ui_left"):
+		_move_difficulty_cursor(-1)
+	elif _action_pressed("input_e") or _action_pressed("ui_down") or _action_pressed("ui_right"):
+		_move_difficulty_cursor(1)
+	elif _action_pressed("input_b") or _action_pressed("ui_accept"):
+		_confirmar_item_do_cursor()
 
 
 func _handle_pre_game_touch(
@@ -76,6 +76,12 @@ func _handle_pre_game_touch(
 		_difficulty_cursor = 1
 		_select_difficulty("hard")
 		_confirm_difficulty()
+		return
+
+	if _toque_no_voltar(position_value):
+		_difficulty_cursor = BACK_CURSOR
+		_update_pre_game_styles()
+		_voltar_para_selecao()
 
 
 ## Trio de LEDs dos menus (A = mover, B = selecionar, E = descer).
@@ -91,23 +97,65 @@ func _apply_menu_leds() -> void:
 	)
 
 
-func _move_difficulty_cursor() -> void:
+## Itens da tela, na ordem em que o cursor anda: FACIL, DIFICIL, VOLTAR.
+const CURSOR_ITEM_COUNT: int = 3
+const BACK_CURSOR: int = 2
+
+
+func _centralizar_botao_voltar() -> void:
+	# Nesta cadeia o JOGAR nao aparece (confirmar e o proprio B), entao o
+	# VOLTAR assume a linha inteira, centralizado.
+	if _back_button == null or not is_instance_valid(_back_button):
+		return
+	if _pre_game_panel == null or not is_instance_valid(_pre_game_panel):
+		return
+
+	var panel_size: Vector2 = _pre_game_panel.size
+	_back_button.size = Vector2(
+		panel_size.x * 0.42,
+		panel_size.y * 0.185
+	)
+	_back_button.position = Vector2(
+		(panel_size.x - _back_button.size.x) * 0.5,
+		panel_size.y * 0.665
+	)
+
+	if _back_button_label != null and is_instance_valid(_back_button_label):
+		_back_button_label.size = _back_button.size
+
+
+func _move_difficulty_cursor(direction: int = 1) -> void:
 	_difficulty_cursor = (
 		0
 		if _difficulty_cursor < 0
-		else (_difficulty_cursor + 1) % 2
+		else posmod(_difficulty_cursor + direction, CURSOR_ITEM_COUNT)
 	)
 
-	_select_difficulty(
-		"easy"
-		if _difficulty_cursor == 0
-		else "hard"
-	)
+	# VOLTAR nao mexe na dificuldade: sair da linha do VOLTAR devolve
+	# exatamente o nivel que estava marcado.
+	if _difficulty_cursor != BACK_CURSOR:
+		_select_difficulty(
+			"easy"
+			if _difficulty_cursor == 0
+			else "hard"
+		)
+	else:
+		_update_pre_game_styles()
 
 	LED_CLIENT.menu_next_feedback()
 	_apply_menu_leds()
 
 
+## B confirma o item onde o cursor estiver.
+func _confirmar_item_do_cursor() -> void:
+	if _difficulty_cursor == BACK_CURSOR:
+		LED_CLIENT.menu_select_feedback()
+		_voltar_para_selecao()
+		return
+
+	_confirm_difficulty()
+
+
 func _confirm_difficulty() -> void:
 	if _difficulty_cursor < 0:
 		return
@@ -164,6 +212,7 @@ func _update_pre_game_styles() -> void:
 
 	var easy_selected: bool = _difficulty_cursor == 0
 	var hard_selected: bool = _difficulty_cursor == 1
+	_aplicar_estilo_voltar(_difficulty_cursor == BACK_CURSOR)
 
 	_easy_button.add_theme_stylebox_override(
 		"panel",
diff --git a/scripts/hit_music_r7/stage_v9.gd b/scripts/hit_music_r7/stage_v9.gd
index 53e9f86..3955a64 100644
--- a/scripts/hit_music_r7/stage_v9.gd
+++ b/scripts/hit_music_r7/stage_v9.gd
@@ -25,6 +25,12 @@ var _easy_button_label: Label
 var _hard_button_label: Label
 var _play_button: Panel
 var _play_button_label: Label
+var _back_button: Panel
+var _back_button_label: Label
+
+## Trava do VOLTAR: a troca de cena leva alguns quadros e sem isto um
+## toque duplo (ou o botao segurado) disparava duas trocas.
+var _voltando: bool = false
 
 var _center_hud: Control
 var _center_score: Label
@@ -180,6 +186,30 @@ func _handle_pre_game_touch(position_value: Vector2) -> void:
 		).has_point(position_value)
 	):
 		_confirm_difficulty()
+		return
+
+	if _toque_no_voltar(position_value):
+		_voltar_para_selecao()
+
+
+## O VOLTAR e sempre a mesma area de toque, aqui e na cadeia final.
+func _toque_no_voltar(position_value: Vector2) -> bool:
+	if _back_button == null or not is_instance_valid(_back_button):
+		return false
+	if not _back_button.visible:
+		return false
+	return _back_button.get_global_rect().has_point(position_value)
+
+
+## Desiste da musica e volta ao seletor. Nenhuma ficha foi consumida
+## ainda, entao nao ha nada para devolver.
+func _voltar_para_selecao() -> void:
+	if _voltando or _difficulty_confirmed:
+		return
+	_voltando = true
+
+	LED_CLIENT.menu_select_feedback()
+	_go_to_selector()
 
 
 func _select_difficulty(name_value: String, immediate: bool = false) -> void:
@@ -381,6 +411,42 @@ func _build_pre_game_overlay() -> void:
 	_play_button_label.size = _play_button.size
 	_play_button.add_child(_play_button_label)
 
+	# VOLTAR: a musica ja foi escolhida no seletor, mas errar a escolha e
+	# comum — e ate aqui nenhuma ficha foi gasta (quem gasta e
+	# _confirm_difficulty). Sem este botao a unica saida era jogar a
+	# musica errada ate o fim.
+	_back_button = Panel.new()
+	_back_button.position = Vector2(
+		panel_size.x * 0.535,
+		panel_size.y * 0.665
+	)
+	_back_button.size = Vector2(
+		panel_size.x * 0.38,
+		panel_size.y * 0.185
+	)
+	_pre_game_panel.add_child(_back_button)
+
+	_back_button_label = _make_label(
+		"VOLTAR",
+		int(_radius * 0.040),
+		HORIZONTAL_ALIGNMENT_CENTER,
+		font
+	)
+	_back_button_label.size = _back_button.size
+	_back_button.add_child(_back_button_label)
+
+	# Com o VOLTAR ocupando a direita, o JOGAR fica na esquerda da mesma
+	# linha (a cadeia final esconde o JOGAR e recentraliza o VOLTAR).
+	_play_button.position = Vector2(
+		panel_size.x * 0.085,
+		panel_size.y * 0.665
+	)
+	_play_button.size = Vector2(
+		panel_size.x * 0.38,
+		panel_size.y * 0.185
+	)
+	_play_button_label.size = _play_button.size
+
 
 func _build_center_hud() -> void:
 	if _hud_layer == null:
@@ -730,6 +796,7 @@ func _update_pre_game_styles() -> void:
 		"panel",
 		_play_button_style()
 	)
+	_aplicar_estilo_voltar(false)
 
 	_easy_button_label.add_theme_color_override(
 		"font_color",
@@ -745,6 +812,30 @@ func _update_pre_game_styles() -> void:
 	)
 
 
+## Mesmo desenho dos botoes de dificuldade (mesma borda, mesmo raio,
+## mesmo brilho quando selecionado), so que na cor de atencao — para o
+## VOLTAR pertencer ao painel sem ser confundido com "jogar".
+const BACK_BUTTON_COLOR: Color = Color(1.0, 0.36, 0.42, 1.0)
+
+
+func _aplicar_estilo_voltar(selected: bool) -> void:
+	if _back_button == null or not is_instance_valid(_back_button):
+		return
+
+	_back_button.add_theme_stylebox_override(
+		"panel",
+		_difficulty_button_style(selected, BACK_BUTTON_COLOR)
+	)
+
+	if _back_button_label != null and is_instance_valid(_back_button_label):
+		_back_button_label.add_theme_color_override(
+			"font_color",
+			Color.WHITE
+			if selected
+			else Color(0.58, 0.65, 0.76, 1.0)
+		)
+
+
 func _pre_game_panel_style() -> StyleBoxFlat:
 	var style := StyleBoxFlat.new()
 	style.bg_color = Color(0.004, 0.009, 0.024, 0.96)
diff --git a/scripts/hit_music_r7/user_catalog.gd b/scripts/hit_music_r7/user_catalog.gd
index 85f8168..3c1d515 100644
--- a/scripts/hit_music_r7/user_catalog.gd
+++ b/scripts/hit_music_r7/user_catalog.gd
@@ -30,6 +30,12 @@ extends RefCounted
 const FACTORY_CATALOG_PATH: String = "res://data/hit_music_songs.json"
 
 const USER_SONGS_PATH: String = "user://hit_music_user_songs.json"
+
+## Histórico de importação por pacote (pendrive). Guarda o resultado da
+## última tentativa de cada pasta para que uma nova importação em lote
+## saiba o que já entrou, o que falhou e por quê.
+const IMPORT_LOG_PATH: String = "user://hit_music_import_log.json"
+const IMPORT_LOG_LIMIT: int = 400
 const USER_SONGS_BACKUP_PATH: String = "user://hit_music_user_songs.json.bak"
 const USER_SONGS_TEMP_PATH: String = "user://hit_music_user_songs.json.tmp"
 
@@ -680,6 +686,24 @@ static func scan_usb_packages() -> Array:
 		return str(a.get("name", "")).nocasecmp_to(str(b.get("name", ""))) < 0
 	)
 
+	# Histórico das tentativas anteriores: é o que permite refazer uma
+	# importação em lote sem repetir o que já entrou e sem esquecer o que
+	# falhou da última vez.
+	var log: Dictionary = import_log()
+	for package_value in packages:
+		if not (package_value is Dictionary):
+			continue
+		var package: Dictionary = package_value as Dictionary
+		var entry: Variant = log.get(import_log_key(package), null)
+		if entry is Dictionary:
+			package["log_status"] = str((entry as Dictionary).get("status", ""))
+			package["log_message"] = str((entry as Dictionary).get("message", ""))
+			package["log_time"] = int((entry as Dictionary).get("time", 0))
+		else:
+			package["log_status"] = ""
+			package["log_message"] = ""
+			package["log_time"] = 0
+
 	return packages
 
 
@@ -719,11 +743,23 @@ static func _append_package_if_present(
 
 	var package: Dictionary = inspect_usb_package(folder, installed_index)
 
-	# Qualquer pasta que não seja um pacote completo é ignorada.
-	if package.is_empty() or not bool(package.get("valid", false)):
+	# Pasta sem nenhum arquivo de pacote não é assunto do Hit Music.
+	if package.is_empty():
 		return
 
 	package["drive"] = drive_name
+
+	# Pacote incompleto NÃO é mais escondido. Antes ele sumia da lista e o
+	# operador ficava sem saber por que a música não aparecia; agora entra
+	# marcado como ERRO, com o motivo, e a importação em lote consegue
+	# avisar exatamente quais pastas não estão funcionando.
+	if not bool(package.get("valid", false)):
+		if str(package.get("name", "")).strip_edges().is_empty():
+			package["name"] = folder.get_file()
+		package["installed"] = false
+		package["installed_match"] = {}
+		package["bpm"] = 0.0
+
 	packages.append(package)
 
 
@@ -843,6 +879,80 @@ static func inspect_usb_package(
 	}
 
 
+## ---------------------------------------------------------------
+## HISTORICO DE IMPORTACAO
+## ---------------------------------------------------------------
+
+## Chave estável de um pacote. O hash do MP3 identifica a música mesmo
+## que o operador renomeie a pasta; sem hash (pacote inválido) vale o
+## caminho da pasta.
+static func import_log_key(package: Dictionary) -> String:
+	var hash_value: String = str(package.get("source_hash", "")).strip_edges()
+	if not hash_value.is_empty():
+		return "hash:" + hash_value
+	return "pasta:" + str(package.get("folder", "")).to_lower()
+
+
+static func import_log() -> Dictionary:
+	if not FileAccess.file_exists(IMPORT_LOG_PATH):
+		return {}
+
+	var file := FileAccess.open(IMPORT_LOG_PATH, FileAccess.READ)
+	if file == null:
+		return {}
+
+	var text: String = file.get_as_text()
+	file.close()
+
+	var parsed: Variant = JSON.parse_string(text)
+	if parsed is Dictionary:
+		return parsed as Dictionary
+	return {}
+
+
+static func import_log_entry(package: Dictionary) -> Dictionary:
+	var entry: Variant = import_log().get(import_log_key(package), null)
+	if entry is Dictionary:
+		return entry as Dictionary
+	return {}
+
+
+## status: "ok", "duplicada" ou "erro".
+static func import_log_record(
+	package: Dictionary,
+	status: String,
+	message: String = ""
+) -> void:
+	var log: Dictionary = import_log()
+
+	log[import_log_key(package)] = {
+		"name": str(package.get("name", "")),
+		"folder": str(package.get("folder", "")),
+		"status": status,
+		"message": message,
+		"time": int(Time.get_unix_time_from_system()),
+	}
+
+	# O pendrive de um cliente grande passa por muitas máquinas: o
+	# histórico não pode crescer sem fim. Fica só o mais recente.
+	if log.size() > IMPORT_LOG_LIMIT:
+		var keys: Array = log.keys()
+		keys.sort_custom(func(a: Variant, b: Variant) -> bool:
+			return (
+				int((log[a] as Dictionary).get("time", 0))
+				< int((log[b] as Dictionary).get("time", 0))
+			)
+		)
+		for index in range(log.size() - IMPORT_LOG_LIMIT):
+			log.erase(keys[index])
+
+	var file := FileAccess.open(IMPORT_LOG_PATH, FileAccess.WRITE)
+	if file == null:
+		return
+	file.store_string(JSON.stringify(log, "\t"))
+	file.close()
+
+
 static func import_usb_package(
 	package: Dictionary,
 	bpm_override: float = 0.0
diff --git a/scripts/led_client.gd b/scripts/led_client.gd
index cbf3685..679ee0d 100644
--- a/scripts/led_client.gd
+++ b/scripts/led_client.gd
@@ -246,6 +246,30 @@ func begin_stage() -> void:
 	_last_ui_state = ""
 
 
+## Entrada nas Configuracoes. A tela anterior (abertura/seletor/partida)
+## deixa um estado seu gravado em ui_state.cmd — ATTRACT, MENU da musica
+## escolhida ou o ultimo MULTI do jogo. Sem cancelar esse estado, a mesa
+## continuava rodando a animacao da tela ANTERIOR enquanto o operador ja
+## estava no painel: os LEDs do menu de Configuracoes nunca apareciam.
+##
+## Aqui a serial e devolvida a um estado neutro (CLEAR) e o modo volta
+## para NORMAL — que e o modo do seletor, o unico onde convivem o quadro
+## MENU persistente e os flashes HIT de navegacao. Quem chama envia o
+## proprio quadro logo depois (ver config.gd/_aplicar_leds_menu).
+func begin_settings() -> void:
+	ensure_bridge()
+
+	_mode = LedMode.NORMAL
+	_leave_game_mode()
+	_clear_transient_queue()
+	_last_game_state = ""
+
+	# Forca a escrita mesmo que a tela anterior ja tenha mandado CLEAR:
+	# o proximo quadro precisa sair da fila com a mesa apagada.
+	_last_ui_state = ""
+	_write_ui_state("CLEAR")
+
+
 func begin_game() -> void:
 	ensure_bridge()
 
diff --git a/tools/smoke_final.gd b/tools/smoke_final.gd
new file mode 100644
index 0000000..5162f65
--- /dev/null
+++ b/tools/smoke_final.gd
@@ -0,0 +1,315 @@
+extends Node
+## Teste de fumaca dos ajustes finais:
+##   1) VOLTAR na tela de escolha do modo (dificuldade);
+##   2) LEDs A/E/B nas Configuracoes + entrega da serial entre as telas;
+##   3) importacao em lote do pendrive, com aviso do que nao funcionou e
+##      contagem do que ja tinha entrado.
+##
+## Rodar com:
+##   godot --headless --path . res://tools/smoke_final.tscn
+
+const USER_CATALOG: Script = preload("res://scripts/hit_music_r7/user_catalog.gd")
+const LED_CLIENT: Script = preload("res://scripts/hit_music_r7/led_client.gd")
+
+const USB_FAKE_DIR: String = "user://_smoke_usb"
+const UI_STATE_PATH: String = "user://hit_music_serial/spool/ui_state.cmd"
+
+var _falhas: Array[String] = []
+var _instalada_id: String = ""
+
+
+func _ready() -> void:
+	call_deferred("_rodar")
+
+
+func _checar(condicao: bool, texto: String) -> void:
+	if condicao:
+		print("  OK   ", texto)
+	else:
+		_falhas.append(texto)
+		print("  FALHA ", texto)
+
+
+func _rodar() -> void:
+	await get_tree().process_frame
+
+	await _testar_tela_de_modo()
+	await _testar_configuracoes()
+	await _testar_lote_do_pendrive()
+
+	_limpar()
+
+	if _falhas.is_empty():
+		print("SMOKE_FINAL_OK")
+		get_tree().quit(0)
+	else:
+		print("SMOKE_FINAL_FALHOU: ", _falhas.size())
+		get_tree().quit(1)
+
+
+## ---------------------------------------------------------------
+## 1) TELA DE ESCOLHA DO MODO
+## ---------------------------------------------------------------
+
+func _testar_tela_de_modo() -> void:
+	print("=== TELA DE MODO (DIFICULDADE) ===")
+
+	var base: Script = load("res://scripts/hit_music_r7/stage_v9.gd")
+	var instancia: Object = base.new()
+	_checar(
+		instancia.has_method("_voltar_para_selecao"),
+		"a tela de modo sabe voltar para o seletor"
+	)
+	_checar(
+		instancia.has_method("_toque_no_voltar"),
+		"o VOLTAR tem area de toque propria"
+	)
+	if instancia is Node:
+		(instancia as Node).free()
+
+	var cadeia: Script = load("res://scripts/hit_music_r7/stage_v10.gd")
+	var constantes: Dictionary = cadeia.get_script_constant_map()
+	_checar(
+		int(constantes.get("CURSOR_ITEM_COUNT", 0)) == 3,
+		"o cursor passeia por FACIL, DIFICIL e VOLTAR"
+	)
+	_checar(
+		int(constantes.get("BACK_CURSOR", -1)) == 2,
+		"VOLTAR e o ultimo item do cursor"
+	)
+
+	# O VOLTAR usa o mesmo trio ja aceso na mesa (A sobe, E desce, B
+	# confirma): nenhum botao fisico novo, nenhum LED apagado para o
+	# jogador adivinhar.
+	_checar(LED_CLIENT.NAV_NEXT_ACTION == "input_a", "A continua sendo o SOBE")
+	_checar(LED_CLIENT.NAV_DOWN_ACTION == "input_e", "E continua sendo o DESCE")
+	_checar(LED_CLIENT.NAV_SELECT_ACTION == "input_b", "B continua sendo o CONFIRMA")
+
+	await get_tree().process_frame
+
+
+## ---------------------------------------------------------------
+## 2) CONFIGURACOES: LEDS E SERIAL
+## ---------------------------------------------------------------
+
+func _testar_configuracoes() -> void:
+	print("=== CONFIGURACOES: LEDS A / E / B ===")
+
+	var cliente: Node = get_node_or_null("/root/LedClient")
+	_checar(
+		cliente != null and cliente.has_method("begin_settings"),
+		"o LedClient sabe assumir a serial da tela anterior"
+	)
+
+	# Estado da tela ANTERIOR ainda no ar (a abertura manda ATTRACT).
+	if cliente != null and cliente.has_method("send"):
+		cliente.call("send", "ATTRACT")
+	await get_tree().process_frame
+
+	var painel: Node = load("res://scenes/config.tscn").instantiate()
+	get_tree().root.add_child(painel)
+
+	# O quadro do menu sai logo depois do CLEAR (LED_HANDOFF_SEG).
+	await get_tree().create_timer(0.45).timeout
+
+	var estado: String = _ler_estado_ui()
+	_checar(
+		estado.begins_with("MENU "),
+		"a mesa recebeu o quadro de MENU no lugar do ATTRACT (recebeu: %s)" % estado
+	)
+
+	var esperado: String = " %d %d %d" % [
+		LED_CLIENT.NAV_NEXT_LANE,
+		LED_CLIENT.NAV_SELECT_LANE,
+		LED_CLIENT.NAV_DOWN_LANE,
+	]
+	_checar(
+		estado.contains(esperado),
+		"acendeu A (sobe), B (start) e E (desce) — lanes%s" % esperado
+	)
+
+	_checar(
+		painel.has_method("_aplicar_leds_menu"),
+		"o painel reacende o trio quando volta do teste de LEDs"
+	)
+
+	painel.queue_free()
+	await get_tree().process_frame
+
+
+func _ler_estado_ui() -> String:
+	if not FileAccess.file_exists(UI_STATE_PATH):
+		return ""
+	var arquivo := FileAccess.open(UI_STATE_PATH, FileAccess.READ)
+	if arquivo == null:
+		return ""
+	var texto: String = arquivo.get_as_text().strip_edges()
+	arquivo.close()
+	return texto
+
+
+## ---------------------------------------------------------------
+## 3) IMPORTACAO EM LOTE
+## ---------------------------------------------------------------
+
+func _testar_lote_do_pendrive() -> void:
+	print("=== PENDRIVE: IMPORTAR TODAS ===")
+
+	var completo: String = _criar_pacote_falso("MUSICA_OK", true)
+	var quebrado: String = _criar_pacote_falso("MUSICA_SEM_VIDEO", false)
+
+	var pacote_ok: Dictionary = USER_CATALOG.inspect_usb_package(completo)
+	var pacote_erro: Dictionary = USER_CATALOG.inspect_usb_package(quebrado)
+
+	_checar(bool(pacote_ok.get("valid", false)), "pacote completo e aceito")
+	_checar(
+		not bool(pacote_erro.get("valid", true)),
+		"pacote incompleto e recusado"
+	)
+	_checar(
+		not str(pacote_erro.get("error", "")).is_empty(),
+		"o pacote recusado diz o que falta (%s)" % str(pacote_erro.get("error", ""))
+	)
+
+	# O pacote com problema tambem precisa de nome para aparecer na lista
+	# e no aviso final do lote.
+	pacote_erro["name"] = quebrado.get_file()
+
+	print("=== HISTORICO DE IMPORTACAO ===")
+	USER_CATALOG.import_log_record(pacote_ok, "erro", "teste")
+	var anotacao: Dictionary = USER_CATALOG.import_log_entry(pacote_ok)
+	_checar(
+		str(anotacao.get("status", "")) == "erro",
+		"o historico guarda o resultado de cada pacote"
+	)
+
+	var painel: Node = load("res://scenes/config.tscn").instantiate()
+	get_tree().root.add_child(painel)
+	await get_tree().process_frame
+
+	painel.set("_in_music_view", true)
+	painel.set("_usb_packages", [pacote_ok, pacote_erro])
+	painel.call("_refresh_music_view")
+
+	print("=== NAVEGACAO DA LISTA ===")
+	painel.set("_music_cursor", -1)
+	_checar(
+		int(painel.call("_proximo_cursor_musica", 1)) == 0,
+		"descer sai do IMPORTAR TODAS para o primeiro pacote"
+	)
+	painel.set("_music_cursor", -1)
+	_checar(
+		int(painel.call("_proximo_cursor_musica", -1)) == 1,
+		"subir no IMPORTAR TODAS da a volta na lista"
+	)
+	painel.set("_music_cursor", -1)
+
+	print("=== LOTE: PRIMEIRA PASSADA ===")
+	painel.call("_iniciar_lote")
+	await _esperar_lote(painel)
+
+	_checar(
+		int(painel.get("_batch_ok")) == 1,
+		"a musica nova entrou (ok = %d)" % int(painel.get("_batch_ok"))
+	)
+	_checar(
+		(painel.get("_batch_invalid") as Array).size() == 1,
+		"o pacote que nao funciona foi avisado"
+	)
+
+	var relatorio: String = str(painel.call("_descricao_falha", pacote_erro, "sem video"))
+	_checar(
+		relatorio.contains("SEM_VIDEO"),
+		"o aviso nomeia o pacote com problema (%s)" % relatorio
+	)
+
+	_instalada_id = _achar_id_instalada()
+	_checar(not _instalada_id.is_empty(), "a musica aparece no catalogo do operador")
+
+	print("=== LOTE: REFAZENDO ===")
+	# Refazer com o mesmo pendrive nao pode importar de novo: o que ja
+	# entrou e contado como pulado.
+	var reexame: Dictionary = USER_CATALOG.inspect_usb_package(completo)
+	_checar(
+		bool(reexame.get("installed", false)),
+		"o pacote ja instalado e reconhecido na segunda passada"
+	)
+
+	painel.set("_usb_packages", [reexame, pacote_erro])
+	painel.set("_music_cursor", -1)
+	painel.call("_iniciar_lote")
+	await _esperar_lote(painel)
+
+	_checar(
+		int(painel.get("_batch_total")) == 0,
+		"nada novo para importar na segunda passada"
+	)
+	_checar(
+		int(painel.get("_batch_skipped")) == 1,
+		"a musica que ja tinha entrado foi contada como pulada"
+	)
+
+	painel.queue_free()
+	await get_tree().process_frame
+
+
+func _esperar_lote(painel: Node) -> void:
+	for _quadro in range(600):
+		if not bool(painel.get("_batch_active")):
+			break
+		await get_tree().process_frame
+	await get_tree().process_frame
+
+
+func _achar_id_instalada() -> String:
+	for musica in USER_CATALOG.all_user_songs():
+		if not (musica is Dictionary):
+			continue
+		if str((musica as Dictionary).get("title", "")).contains("SMOKE"):
+			return str((musica as Dictionary).get("id", ""))
+	return ""
+
+
+## Pasta de pendrive de mentira. `com_video` false derruba o pacote de
+## proposito, para provar o aviso do que nao esta funcionando.
+func _criar_pacote_falso(nome: String, com_video: bool) -> String:
+	var pasta: String = USB_FAKE_DIR.path_join(nome)
+	DirAccess.make_dir_recursive_absolute(pasta)
+
+	_gravar(pasta.path_join("audio.mp3"), "MP3-" + nome)
+	_gravar(pasta.path_join("capa.png"), "PNG-" + nome)
+	_gravar(
+		pasta.path_join("dados.txt"),
+		'name="SMOKE %s"\nbpm=128\ncategory=OUTROS\n' % nome
+	)
+	if com_video:
+		_gravar(pasta.path_join("video.ogv"), "OGV-" + nome)
+
+	return ProjectSettings.globalize_path(pasta)
+
+
+func _gravar(caminho: String, conteudo: String) -> void:
+	var arquivo := FileAccess.open(caminho, FileAccess.WRITE)
+	if arquivo == null:
+		return
+	arquivo.store_string(conteudo)
+	arquivo.close()
+
+
+func _limpar() -> void:
+	if not _instalada_id.is_empty():
+		USER_CATALOG.remove_song(_instalada_id)
+
+	var raiz: String = ProjectSettings.globalize_path(USB_FAKE_DIR)
+	_apagar_pasta(raiz)
+
+
+func _apagar_pasta(caminho: String) -> void:
+	var dir := DirAccess.open(caminho)
+	if dir == null:
+		return
+	for arquivo in dir.get_files():
+		dir.remove(arquivo)
+	for sub in dir.get_directories():
+		_apagar_pasta(caminho.path_join(sub))
+	DirAccess.remove_absolute(caminho)
diff --git a/tools/smoke_final.gd.uid b/tools/smoke_final.gd.uid
new file mode 100644
index 0000000..c472681
--- /dev/null
+++ b/tools/smoke_final.gd.uid
@@ -0,0 +1 @@
+uid://43q21qtgt422
diff --git a/tools/smoke_final.tscn b/tools/smoke_final.tscn
new file mode 100644
index 0000000..8fe08f4
--- /dev/null
+++ b/tools/smoke_final.tscn
@@ -0,0 +1,4 @@
+[gd_scene load_steps=2 format=3]
+[ext_resource type="Script" uid="uid://43q21qtgt422" path="res://tools/smoke_final.gd" id="1"]
+[node name="SmokeFinal" type="Node"]
+script = ExtResource("1")
'@

$arquivoPatch = Join-Path $env:TEMP "hit_music_atualizacoes_finais.patch"
$semBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($arquivoPatch, ($patch -replace "`r`n", "`n"), $semBom)
Ok "patch em $arquivoPatch"

Passo "Conferindo se o patch encaixa nos arquivos atuais"

Git-Run apply --check --3way --whitespace=nowarn -- $arquivoPatch | Out-Null
if ($script:GitExit -ne 0) {
    Parar ("O patch nao encaixou. Provavel causa: estes arquivos ja foram alterados a mao " +
           "ou a pasta esta em outra versao do jogo. NADA foi modificado.")
}
Ok "patch confere com os arquivos atuais"

Passo "Indo para a branch $Branch"

Git-Run rev-parse --verify --quiet ("refs/heads/" + $Branch) | Out-Null
if ($script:GitExit -eq 0) {
    Git-Run checkout $Branch | Out-Null
} else {
    Git-Run checkout -b $Branch | Out-Null
}
if ($script:GitExit -ne 0) { Parar "Nao foi possivel entrar na branch $Branch." }
Ok "branch ativa: $Branch"

Passo "Aplicando as alteracoes"

Git-Run apply --3way --whitespace=nowarn -- $arquivoPatch | Out-Null
if ($script:GitExit -ne 0) { Parar "Falha ao aplicar o patch." }
Ok "arquivos atualizados"

Passo "Gravando o commit"

Git-Run add -A | Out-Null
Git-Run commit -m "fecha o jogo: VOLTAR no modo, LEDs das configs e importacao em lote" | Out-Null
if ($script:GitExit -ne 0) {
    Aviso "nada novo para commitar (as alteracoes ja estavam gravadas)"
} else {
    Ok "commit gravado"
}

& git --no-pager log --oneline -1
& git --no-pager diff --stat HEAD~1..HEAD

Write-Host ""
Write-Host "PRONTO." -ForegroundColor Green
Write-Host "  scripts/hit_music_r7/stage_v9.gd     -> botao VOLTAR no painel do modo"
Write-Host "  scripts/hit_music_r7/stage_v10.gd    -> cursor FACIL / DIFICIL / VOLTAR"
Write-Host "  scripts/led_client.gd                -> begin_settings(): cancela a serial da tela anterior"
Write-Host "  scripts/config.gd                    -> LEDs A / E / B + botao IMPORTAR TODAS"
Write-Host "  scripts/hit_music_r7/user_catalog.gd -> pacotes com erro visiveis + historico de importacao"
Write-Host "  tools/smoke_final.gd / .tscn         -> teste de fumaca das tres mudancas"
Write-Host ""
Write-Host "Conferir:" -ForegroundColor Cyan
Write-Host "  godot --headless --path . res://tools/smoke_final.tscn"
Write-Host ""
Write-Host "Enviar para o GitHub:" -ForegroundColor Cyan
Write-Host "  git push -u origin $Branch"
