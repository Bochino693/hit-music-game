extends Node2D
## Configurações da máquina — F9 / SELECT.
##
## Controles do gabinete:
##   input_a = sobe uma opção
##   input_e = desce uma opção
##   input_b = confirma / START
##   SELECT ou F9 = volta
##
## A interface respeita duas áreas:
## 1) retângulo superior de operação, totalmente recortado (clip_contents);
## 2) área circular da mesa, onde ficam menu, músicas, teste e contadores.
##
## Nenhum FileDialog é usado na tela de músicas. O operador não vê Explorer
## nem cursor: o jogo escaneia os drives montados e encontra os pacotes.

const SETTINGS_GATE: Script = preload("res://scripts/hit_music_r7/settings_gate.gd")
const USER_CATALOG: Script = preload("res://scripts/hit_music_r7/user_catalog.gd")
const LED_CLIENT: Script = preload("res://scripts/hit_music_r7/led_client.gd")

## Atraso entre o CLEAR que cancela a serial da tela anterior e o primeiro
## quadro de LED desta tela. A bridge le o ui_state.cmd a cada 5 ms; sem a
## pausa os dois estados sairiam na mesma escrita e o CLEAR nunca chegaria
## ao Arduino — a mesa continuaria com o ATTRACT da abertura.
const LED_HANDOFF_SEG: float = 0.12

const LANE_COUNT: int = 8
const LANE_ACTIONS: Array[String] = [
	"input_a", "input_b", "input_c", "input_d",
	"input_e", "input_f", "input_g", "input_h",
]
const LANE_LABELS: Array[String] = ["A", "B", "C", "D", "E", "F", "G", "H"]

const BPM_BUS_NAME: String = "HIT_MUSIC_BPM_SCAN"
const BPM_ANALYSIS_SECONDS: float = 16.0
const BPM_MIN: float = 70.0
const BPM_MAX: float = 180.0

enum MenuItem {
	MODE,
	CREDITS,
	MUSIC,
	LED_INPUT_TEST,
	COUNTERS,
	COM_PORT,
	BACK,
}

const MENU_ITEM_COUNT: int = 7

## Posição do botão IMPORTAR TODAS na navegação da tela de músicas: ele
## fica ANTES do primeiro pacote, por isso o índice -1.
const IMPORT_ALL_INDEX: int = -1

## Quantos nomes de pacote com problema cabem no relatório final.
const REPORT_NAME_LIMIT: int = 3

var _return_path: String = "res://scenes/opening.tscn"
var _cursor: int = 0

var _screen: Vector2 = Vector2.ZERO
var _center: Vector2 = Vector2.ZERO
var _radius: float = 100.0
var _select_can_close: bool = false

var _hud_layer: CanvasLayer
var _top_panel: Panel
var _top_title_label: Label
var _top_hint_label: Label
var _top_status_card: Panel
var _top_status_label: Label

var _panel: Panel
var _menu_labels: Array[Label] = []
var _menu_rows: Array[Panel] = []

# Views internas
var _in_music_view: bool = false
var _in_test_view: bool = false
var _in_counters_view: bool = false

# Música / pendrive
var _music_layer: CanvasLayer
var _music_panel: Panel
var _music_title: Label
var _music_status: Label
var _music_detail: Label
var _music_hint: Label
var _music_rows: Array[Panel] = []
var _music_labels: Array[Label] = []
var _music_row_indices: Array[int] = []
var _usb_packages: Array = []

# Botão IMPORTAR TODAS: primeira parada do cursor na tela de músicas.
var _import_all_panel: Panel
var _import_all_label: Label

# Importação em lote (pendrive cheio de músicas).
var _batch_active: bool = false
var _batch_queue: Array[int] = []
var _batch_position: int = 0
var _batch_total: int = 0
var _batch_ok: int = 0
var _batch_skipped: int = 0
var _batch_failures: Array[String] = []
var _batch_invalid: Array[String] = []

# Botão VOLTAR dedicado ao touch nas telas internas.
var _touch_layer: CanvasLayer
var _touch_back_panel: Panel
var _touch_back_label: Label
var _music_cursor: int = 0
var _music_scan_busy: bool = false

# Análise real de BPM
var _bpm_player: AudioStreamPlayer
var _bpm_analyzer_instance: AudioEffectSpectrumAnalyzerInstance
var _bpm_analysis_active: bool = false
var _bpm_analysis_elapsed: float = 0.0
var _bpm_baseline: float = 0.0
var _bpm_last_peak_time: float = -10.0
var _bpm_peaks: Array[float] = []
var _bpm_pending_package: Dictionary = {}

# Teste
var _test_layer: CanvasLayer
var _test_status_label: Label
var _lane_boxes: Array[Panel] = []
var _lane_pressed_state: Array[bool] = []
var _credito_box: Panel
var _credito_pressed_state: bool = false

# Contadores
var _counters_layer: CanvasLayer
var _counters_title: Label
var _counters_body: Label


func _ready() -> void:
	_return_path = SETTINGS_GATE.return_path()
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)

	_iniciar_serial_da_tela()

	var screen: Vector2 = get_viewport_rect().size
	_calculate_machine_geometry(screen)
	_build_background(screen)
	_build_top_panel(screen)
	_build_menu()
	_build_music_view()
	_build_test_view()
	_build_counters_view()
	_build_touch_back()
	_ensure_bpm_analyzer()

	_refresh_menu_texts()
	_set_main_top_context()

	if ArcadeSettings.changed.is_connected(_refresh_menu_texts) == false:
		ArcadeSettings.changed.connect(_refresh_menu_texts)
	if ArcadeCounters.changed.is_connected(_refresh_menu_texts) == false:
		ArcadeCounters.changed.connect(_refresh_menu_texts)

	get_viewport().size_changed.connect(_reload_for_resize)


func _process(delta: float) -> void:
	queue_redraw()

	if InputMap.has_action("input_select"):
		if not Input.is_action_pressed("input_select"):
			_select_can_close = true
		elif _select_can_close and Input.is_action_just_pressed("input_select"):
			_handle_back()
			return

	if _bpm_analysis_active:
		_process_bpm_analysis(delta)
		return

	if _batch_active:
		# Um pacote por quadro: o painel continua respondendo e o
		# contador anda na tela enquanto o pendrive é copiado.
		_passo_lote()
		return

	if _in_music_view:
		_process_music_inputs()
		return

	if _in_counters_view:
		return

	if _in_test_view:
		_update_test_view()
		return

	_process_main_inputs()


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			if (
				key.keycode == KEY_F9
				or key.keycode == KEY_ESCAPE
				or key.keycode == KEY_BACKSPACE
			):
				_handle_back()
		return

	# Touch funciona mesmo com o cursor escondido.
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_handle_touch(touch.position)
		return

	# Alguns controladores touch do Windows chegam como clique esquerdo.
	# Mantemos o mouse HIDDEN, mas aceitamos o evento.
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			_handle_touch(mouse.position)


func _handle_touch(position_value: Vector2) -> void:
	# VOLTAR é sempre a primeira zona testada nas telas internas.
	if (
		_touch_back_panel != null
		and is_instance_valid(_touch_back_panel)
		and _touch_back_panel.visible
		and Rect2(
			_touch_back_panel.global_position,
			_touch_back_panel.size
		).has_point(position_value)
	):
		_handle_back()
		return

	if _bpm_analysis_active or _batch_active:
		return

	if _in_music_view:
		if (
			_import_all_panel != null
			and is_instance_valid(_import_all_panel)
			and _import_all_panel.visible
			and Rect2(
				_import_all_panel.global_position,
				_import_all_panel.size
			).has_point(position_value)
		):
			_music_cursor = IMPORT_ALL_INDEX
			_refresh_music_view()
			_activate_music_cursor()
			return

		for slot in range(_music_rows.size()):
			var row: Panel = _music_rows[slot]
			if not row.visible:
				continue
			if not Rect2(row.global_position, row.size).has_point(position_value):
				continue

			if slot >= _music_row_indices.size():
				return

			var package_index: int = _music_row_indices[slot]
			if package_index < 0 or package_index >= _usb_packages.size():
				return

			# Primeiro toque seleciona. Tocar novamente na selecionada
			# equivale ao B e instala (ou informa que já está instalada).
			if package_index == _music_cursor:
				_activate_music_cursor()
			else:
				_music_cursor = package_index
				_refresh_music_view()
				_menu_feedback("menu_next_feedback")
			return
		return

	if _in_test_view or _in_counters_view:
		return

	# Menu principal do F9: tocar uma linha ativa diretamente a opção.
	for index in range(_menu_rows.size()):
		var row: Panel = _menu_rows[index]
		if Rect2(row.global_position, row.size).has_point(position_value):
			_cursor = index
			_refresh_menu_texts()
			_activate_cursor()
			return


func _build_touch_back() -> void:
	_touch_layer = CanvasLayer.new()
	_touch_layer.layer = 50
	add_child(_touch_layer)

	var font: Font = _load_font()

	_touch_back_panel = Panel.new()
	_touch_back_panel.visible = false
	_touch_back_panel.position = Vector2(
		_center.x - _radius * 0.27,
		_center.y + _radius * 0.835
	)
	_touch_back_panel.size = Vector2(
		_radius * 0.54,
		_radius * 0.090
	)
	_touch_back_panel.clip_contents = true
	_touch_back_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_touch_back_panel.add_theme_stylebox_override(
		"panel",
		_row_style(false)
	)
	_touch_layer.add_child(_touch_back_panel)

	_touch_back_label = _make_label(
		"VOLTAR",
		int(_radius * 0.030),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	_touch_back_label.size = _touch_back_panel.size
	_touch_back_label.add_theme_color_override(
		"font_color",
		Color(0.85, 0.92, 1.0, 1.0)
	)
	_touch_back_panel.add_child(_touch_back_label)
	_fit_label_to_width(
		_touch_back_label,
		int(_radius * 0.030),
		10
	)


func _set_touch_back_visible(value: bool) -> void:
	if _touch_back_panel != null and is_instance_valid(_touch_back_panel):
		_touch_back_panel.visible = value


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_cleanup_bpm_bus()


## ---------------------------------------------------------------
## NAVEGAÇÃO
## ---------------------------------------------------------------

func _process_main_inputs() -> void:
	# A sobe, E desce.
	if Input.is_action_just_pressed("input_a"):
		_move_cursor(-1)
		return
	if Input.is_action_just_pressed("input_e"):
		_move_cursor(1)
		return

	# B continua sendo o START/CONFIRMAR do menu.
	if Input.is_action_just_pressed("input_b"):
		_activate_cursor()
		return

	# Se existir um START dedicado, ele confirma a mesma opção.
	if InputMap.has_action("input_start") and Input.is_action_just_pressed("input_start"):
		_activate_cursor()


func _move_cursor(direction: int) -> void:
	if _menu_labels.is_empty():
		return
	_cursor = posmod(_cursor + direction, _menu_labels.size())
	_refresh_menu_texts()
	_nav_feedback(direction)


func _activate_cursor() -> void:
	match _cursor:
		MenuItem.MODE:
			ArcadeSettings.toggle_mode()
		MenuItem.CREDITS:
			ArcadeSettings.add_credit(1)
		MenuItem.MUSIC:
			_open_music_view()
			return
		MenuItem.LED_INPUT_TEST:
			_open_test_view()
			return
		MenuItem.COUNTERS:
			_open_counters_view()
			return
		MenuItem.COM_PORT:
			_toggle_com_port()
		MenuItem.BACK:
			_close_settings()
			return

	_refresh_menu_texts()
	_menu_feedback("menu_select_feedback")


func _handle_back() -> void:
	if _batch_active:
		# Interrompe o lote sem sair da tela: o operador vê o relatório
		# do que entrou até aqui e pode retomar depois.
		_encerrar_lote(true)
		return
	if _bpm_analysis_active:
		_cancel_bpm_analysis("ANÁLISE CANCELADA")
		return
	if _in_music_view:
		_close_music_view()
		return
	if _in_counters_view:
		_close_counters_view()
		return
	if _in_test_view:
		_close_test_view()
		return
	_close_settings()


func _close_settings() -> void:
	_cancel_bpm_analysis("")
	_cleanup_bpm_bus()

	# Apaga a mesa ANTES de trocar de cena: a proxima tela (abertura ou
	# seletor) grava o proprio quadro no _ready() e nao herda o menu
	# aceso do painel.
	LED_CLIENT.clear_all()

	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	get_tree().change_scene_to_file(_return_path)


## ---------------------------------------------------------------
## LEDS DA MESA NA TELA DE CONFIGURACOES
##
## Os tres botoes que comandam este painel ficam ACESOS o tempo todo,
## com a mesma logica do seletor de musicas:
##   A (lane 0) = sobe            B (lane 1) = confirma / START
##   E (lane 4) = desce
##
## Antes nada acendia aqui. Dois motivos, os dois corrigidos:
##   1. o painel chamava metodos (`menu_next_feedback`, `clear_all`) que
##      so existem no ADAPTADOR res://scripts/hit_music_r7/led_client.gd,
##      nunca no Autoload /root/LedClient — protegidos por has_method(),
##      falhavam calados;
##   2. a tela entrava em LedMode.MENU sem nunca mandar um quadro MENU,
##      entao a mesa seguia rodando o ATTRACT gravado pela abertura.
## ---------------------------------------------------------------

## Cancela a serial da tela anterior e sobe o quadro desta. O CLEAR sai
## primeiro (dentro de begin_settings) e o MENU logo depois, com a pausa
## que a bridge precisa para enxergar os dois estados.
func _iniciar_serial_da_tela() -> void:
	var client := get_node_or_null("/root/LedClient")
	if client != null and client.has_method("begin_settings"):
		client.call("begin_settings")
	elif client != null and client.has_method("begin_stage"):
		# Compatibilidade com versoes do Autoload sem begin_settings().
		client.call("begin_stage")
		LED_CLIENT.clear_all()

	_agendar_leds_menu()


func _agendar_leds_menu() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		_aplicar_leds_menu()
		return

	var timer: SceneTreeTimer = tree.create_timer(LED_HANDOFF_SEG, false)
	timer.timeout.connect(_aplicar_leds_menu)


## Quadro persistente do painel: A sobe, B confirma, E desce.
func _aplicar_leds_menu() -> void:
	if not is_inside_tree():
		return
	if _in_test_view:
		# O teste governa lane a lane; nao pisa nele.
		return

	LED_CLIENT.menu_state_three(
		LED_CLIENT.MENU_NEXT_COLOR,
		LED_CLIENT.MENU_SELECT_COLOR,
		LED_CLIENT.MENU_NEXT_COLOR,
		LED_CLIENT.NAV_NEXT_LANE,
		LED_CLIENT.NAV_SELECT_LANE,
		LED_CLIENT.NAV_DOWN_LANE
	)


## Flash curto no botao que o operador acabou de apertar. Depois do flash
## o firmware devolve o quadro MENU, entao os tres continuam acesos.
func _menu_feedback(method_name: String) -> void:
	if method_name == "menu_select_feedback":
		LED_CLIENT.menu_select_feedback()
	else:
		LED_CLIENT.menu_next_feedback()


## Feedback de navegacao no botao certo: A quando sobe, E quando desce.
func _nav_feedback(direction: int) -> void:
	if direction < 0:
		LED_CLIENT.hit_lane(
			LED_CLIENT.NAV_NEXT_LANE,
			LED_CLIENT.MENU_NEXT_COLOR,
			170
		)
	else:
		LED_CLIENT.hit_lane(
			LED_CLIENT.NAV_DOWN_LANE,
			LED_CLIENT.MENU_NEXT_COLOR,
			170
		)


## ---------------------------------------------------------------
## GEOMETRIA / FUNDO
## ---------------------------------------------------------------

func _reload_for_resize() -> void:
	call_deferred("_reload_current_scene")


func _reload_current_scene() -> void:
	get_tree().reload_current_scene()


func _build_background(screen: Vector2) -> void:
	_screen = screen
	queue_redraw()


func _calculate_machine_geometry(screen: Vector2) -> void:
	var margin: float = maxf(4.0, screen.x * 0.022)
	var top_height: float = screen.y * 0.205
	var top_reserved: float = margin + top_height + screen.y * 0.024
	var bottom_margin: float = maxf(4.0, screen.y * 0.012)

	_radius = minf(
		(screen.x - margin * 2.0) * 0.5,
		(screen.y - top_reserved - bottom_margin) * 0.5
	) * 0.985

	_center = Vector2(
		screen.x * 0.5,
		screen.y - bottom_margin - _radius
	)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, _screen), Color(0.001, 0.003, 0.010, 1.0), true)
	draw_circle(_center, _radius * 1.012, Color(0.04, 0.48, 0.72, 0.20), true)
	draw_circle(_center, _radius, Color(0.004, 0.010, 0.028, 1.0), true)

	var now: float = float(Time.get_ticks_msec()) / 1000.0
	for index in range(28):
		var seed: float = float(index) * 17.173
		var angle: float = fmod(absf(sin(seed) * 931.77), TAU)
		angle += now * (0.006 + float(index % 3) * 0.004)
		var orbit: float = _radius * (0.14 + fmod(absf(cos(seed * 0.73)) * 7.31, 0.73))
		var sparkle: float = 0.5 + 0.5 * sin(now * (1.1 + float(index % 4) * 0.21) + seed)
		var pos: Vector2 = _center + Vector2(cos(angle), sin(angle)) * orbit
		var color: Color = (
			Color(0.32, 0.82, 1.0)
			if index % 3 != 0
			else Color(0.86, 0.44, 1.0)
		)
		draw_circle(
			pos,
			maxf(1.0, _radius * (0.0022 + sparkle * 0.0015)),
			Color(color.r, color.g, color.b, 0.22 + sparkle * 0.48),
			true
		)

	draw_arc(
		_center,
		_radius * 0.985,
		0.0,
		TAU,
		220,
		Color(0.20, 0.86, 1.0, 0.55),
		maxf(3.0, _radius * 0.008),
		true
	)


## ---------------------------------------------------------------
## RETÂNGULO SUPERIOR
## ---------------------------------------------------------------

func _build_top_panel(screen: Vector2) -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 10
	add_child(_hud_layer)

	var font: Font = _load_font()
	var margin: float = screen.x * 0.022
	var top_height: float = screen.y * 0.205

	_top_panel = Panel.new()
	_top_panel.position = Vector2(margin, margin)
	_top_panel.size = Vector2(screen.x - margin * 2.0, top_height)
	_top_panel.clip_contents = true
	_top_panel.add_theme_stylebox_override("panel", _top_panel_style())
	_hud_layer.add_child(_top_panel)

	# Esquerda: título e controles. Tudo com clip + ellipsis.
	_top_title_label = _make_label(
		"CONFIGURAÇÕES DA MÁQUINA",
		int(top_height * 0.18),
		HORIZONTAL_ALIGNMENT_LEFT,
		font
	)
	_top_title_label.position = Vector2(top_height * 0.13, top_height * 0.10)
	_top_title_label.size = Vector2(_top_panel.size.x * 0.56, top_height * 0.32)
	_top_title_label.add_theme_color_override("font_color", Color(0.18, 0.88, 1.0, 1.0))
	_top_title_label.clip_text = true
	_top_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_top_panel.add_child(_top_title_label)

	_top_hint_label = _make_label(
		"A: SUBIR   •   E: DESCER   •   B: CONFIRMAR   •   SELECT/F9: VOLTAR",
		int(top_height * 0.082),
		HORIZONTAL_ALIGNMENT_LEFT,
		font
	)
	_top_hint_label.position = Vector2(top_height * 0.14, top_height * 0.51)
	_top_hint_label.size = Vector2(_top_panel.size.x * 0.56, top_height * 0.26)
	_top_hint_label.add_theme_color_override("font_color", Color(0.68, 0.75, 0.88, 1.0))
	_top_hint_label.clip_text = true
	_top_hint_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_top_panel.add_child(_top_hint_label)

	# Direita: cartão de status separado. Assim nenhum texto invade o título.
	_top_status_card = Panel.new()
	_top_status_card.position = Vector2(_top_panel.size.x * 0.65, top_height * 0.13)
	_top_status_card.size = Vector2(_top_panel.size.x * 0.31, top_height * 0.66)
	_top_status_card.clip_contents = true
	_top_status_card.add_theme_stylebox_override("panel", _status_card_style())
	_top_panel.add_child(_top_status_card)

	_top_status_label = _make_label(
		"",
		int(top_height * 0.105),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	_top_status_label.position = Vector2(
		_top_status_card.size.x * 0.05,
		_top_status_card.size.y * 0.08
	)
	_top_status_label.size = Vector2(
		_top_status_card.size.x * 0.90,
		_top_status_card.size.y * 0.84
	)
	_top_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_top_status_label.clip_text = true
	_top_status_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.24, 1.0))
	_top_status_card.add_child(_top_status_label)


func _set_top_context(title: String, hint: String, status: String) -> void:
	_top_title_label.text = title
	_top_hint_label.text = hint
	_top_status_label.text = status
	_fit_label_to_width(_top_title_label, int(_top_panel.size.y * 0.18), 12)
	_fit_label_to_width(_top_hint_label, int(_top_panel.size.y * 0.082), 10)
	_fit_multiline_label(_top_status_label, int(_top_panel.size.y * 0.105), 10)


func _set_main_top_context() -> void:
	var status: String = (
		"MODO CRÉDITO\n%02d CRÉDITO(S)" % ArcadeSettings.credits
		if ArcadeSettings.is_credit_mode()
		else "MODO LIVRE\nSTART LIBERADO"
	)
	_set_top_context(
		"CONFIGURAÇÕES DA MÁQUINA",
		"A: SUBIR   •   E: DESCER   •   B: CONFIRMAR   •   SELECT/F9: VOLTAR",
		status
	)


## ---------------------------------------------------------------
## MENU PRINCIPAL
## ---------------------------------------------------------------

func _build_menu() -> void:
	var font: Font = _load_font()
	var panel_size := Vector2(_radius * 1.52, _radius * 1.52)

	_panel = Panel.new()
	_panel.position = _center - panel_size * 0.5
	_panel.size = panel_size
	_panel.clip_contents = true
	_panel.add_theme_stylebox_override("panel", _panel_style())
	_hud_layer.add_child(_panel)

	var title: Label = _make_label(
		"CONFIGURAÇÕES",
		int(_radius * 0.065),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	title.position = Vector2(panel_size.x * 0.10, panel_size.y * 0.055)
	title.size = Vector2(panel_size.x * 0.80, panel_size.y * 0.095)
	title.add_theme_color_override("font_color", Color(0.10, 0.85, 1.0, 1.0))
	title.clip_text = true
	_panel.add_child(title)

	var start_y: float = panel_size.y * 0.180
	var row_pitch: float = panel_size.y * 0.092
	var row_height: float = panel_size.y * 0.070

	for i in range(MENU_ITEM_COUNT):
		var row := Panel.new()
		row.position = Vector2(
			panel_size.x * 0.145,
			start_y + row_pitch * float(i)
		)
		row.size = Vector2(panel_size.x * 0.71, row_height)
		row.clip_contents = true
		row.add_theme_stylebox_override("panel", _row_style(false))
		_panel.add_child(row)
		_menu_rows.append(row)

		var label: Label = _make_label(
			"",
			int(_radius * 0.036),
			HORIZONTAL_ALIGNMENT_CENTER,
			font
		)
		label.size = row.size
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(label)
		_menu_labels.append(label)

	var hint: Label = _make_label(
		"A ↑      E ↓      B CONFIRMA",
		int(_radius * 0.025),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	hint.position = Vector2(panel_size.x * 0.14, panel_size.y * 0.855)
	hint.size = Vector2(panel_size.x * 0.72, panel_size.y * 0.065)
	hint.add_theme_color_override("font_color", Color(0.60, 0.66, 0.78, 1.0))
	hint.clip_text = true
	_panel.add_child(hint)


func _refresh_menu_texts() -> void:
	if _menu_labels.size() < MENU_ITEM_COUNT:
		return

	_menu_labels[MenuItem.MODE].text = (
		"MODO: CRÉDITO"
		if ArcadeSettings.is_credit_mode()
		else "MODO: LIVRE"
	)
	_menu_labels[MenuItem.CREDITS].text = "CRÉDITOS: %d   (B = +1)" % ArcadeSettings.credits
	_menu_labels[MenuItem.MUSIC].text = "MÚSICAS / PENDRIVE: %d INSTALADA(S)" % (
		USER_CATALOG.all_user_songs().size()
	)
	_menu_labels[MenuItem.LED_INPUT_TEST].text = "TESTE DE LEDS E INPUTS"

	var current_count: Dictionary = ArcadeCounters.contagem_atual()
	_menu_labels[MenuItem.COUNTERS].text = "CONTADOR DE PARTIDAS: %d" % int(
		current_count.get("total", 0)
	)

	var client := get_node_or_null("/root/LedClient")
	var forced: String = ""
	if client != null and client.has_method("forced_port"):
		forced = str(client.call("forced_port"))

	_menu_labels[MenuItem.COM_PORT].text = (
		"PORTA: COM5 (FORÇADA)"
		if not forced.is_empty()
		else "PORTA: AUTOMÁTICA"
	)
	_menu_labels[MenuItem.BACK].text = "VOLTAR"

	for i in range(_menu_labels.size()):
		var selected: bool = i == _cursor
		_menu_labels[i].add_theme_color_override(
			"font_color",
			Color(1.0, 0.86, 0.20, 1.0) if selected else Color.WHITE
		)
		if i < _menu_rows.size():
			_menu_rows[i].add_theme_stylebox_override("panel", _row_style(selected))
		_fit_label_to_width(_menu_labels[i], int(_radius * 0.036), 11)

	if not _in_music_view and not _in_test_view and not _in_counters_view:
		_set_main_top_context()


func _toggle_com_port() -> void:
	var client := get_node_or_null("/root/LedClient")
	if client == null:
		return

	var current: String = ""
	if client.has_method("forced_port"):
		current = str(client.call("forced_port"))

	if current.is_empty():
		if client.has_method("set_forced_port"):
			client.call("set_forced_port", "COM5")
	else:
		if client.has_method("clear_forced_port"):
			client.call("clear_forced_port")


## ---------------------------------------------------------------
## MÚSICAS / PENDRIVE
## ---------------------------------------------------------------

func _build_music_view() -> void:
	_music_layer = CanvasLayer.new()
	_music_layer.layer = 20
	_music_layer.visible = false
	add_child(_music_layer)

	var font: Font = _load_font()
	var panel_size := Vector2(_radius * 1.58, _radius * 1.58)

	_music_panel = Panel.new()
	_music_panel.position = _center - panel_size * 0.5
	_music_panel.size = panel_size
	_music_panel.clip_contents = true
	_music_panel.add_theme_stylebox_override("panel", _panel_style())
	_music_layer.add_child(_music_panel)

	_music_title = _make_label(
		"MÚSICAS DO PENDRIVE",
		int(_radius * 0.058),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	_music_title.position = Vector2(panel_size.x * 0.12, panel_size.y * 0.045)
	_music_title.size = Vector2(panel_size.x * 0.76, panel_size.y * 0.078)
	_music_title.add_theme_color_override("font_color", Color(0.10, 0.85, 1.0, 1.0))
	_music_title.clip_text = true
	_music_panel.add_child(_music_title)

	_music_status = _make_label(
		"INSIRA O PENDRIVE",
		int(_radius * 0.030),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	_music_status.position = Vector2(panel_size.x * 0.14, panel_size.y * 0.128)
	_music_status.size = Vector2(panel_size.x * 0.72, panel_size.y * 0.070)
	_music_status.clip_text = true
	_music_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_music_status.add_theme_color_override("font_color", Color(0.70, 0.78, 0.90, 1.0))
	_music_panel.add_child(_music_status)

	# Botão de lote: um pendrive de cliente chega com dezenas de pastas e
	# importar uma a uma (com 16 s de análise de BPM em cada) era o gargalo
	# da instalação. Ele fica no topo da lista, como primeira parada do
	# cursor, para o operador achar sem procurar.
	_import_all_panel = Panel.new()
	_import_all_panel.position = Vector2(panel_size.x * 0.145, panel_size.y * 0.210)
	_import_all_panel.size = Vector2(panel_size.x * 0.71, panel_size.y * 0.074)
	_import_all_panel.clip_contents = true
	_import_all_panel.add_theme_stylebox_override("panel", _row_style(false))
	_music_panel.add_child(_import_all_panel)

	_import_all_label = _make_label(
		"IMPORTAR TODAS",
		int(_radius * 0.031),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	_import_all_label.size = _import_all_panel.size
	_import_all_label.clip_text = true
	_import_all_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_import_all_panel.add_child(_import_all_label)

	var row_y: float = panel_size.y * 0.310
	var row_pitch: float = panel_size.y * 0.081
	var row_height: float = panel_size.y * 0.066

	# Cinco linhas visíveis; listas maiores são paginadas pelo cursor.
	for i in range(5):
		var row := Panel.new()
		row.position = Vector2(panel_size.x * 0.145, row_y + row_pitch * float(i))
		row.size = Vector2(panel_size.x * 0.71, row_height)
		row.clip_contents = true
		row.add_theme_stylebox_override("panel", _row_style(false))
		_music_panel.add_child(row)
		_music_rows.append(row)

		var label: Label = _make_label(
			"",
			int(_radius * 0.031),
			HORIZONTAL_ALIGNMENT_CENTER,
			font
		)
		label.size = row.size
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(label)
		_music_labels.append(label)

	_music_detail = _make_label(
		"",
		int(_radius * 0.026),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	_music_detail.position = Vector2(panel_size.x * 0.13, panel_size.y * 0.716)
	_music_detail.size = Vector2(panel_size.x * 0.74, panel_size.y * 0.115)
	_music_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_music_detail.clip_text = true
	_music_detail.add_theme_color_override("font_color", Color(0.72, 0.80, 0.92, 1.0))
	_music_panel.add_child(_music_detail)

	_music_hint = _make_label(
		"A ↑   E ↓   B IMPORTA   •   IMPORTAR TODAS NO TOPO   •   VOLTAR",
		int(_radius * 0.021),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	_music_hint.position = Vector2(panel_size.x * 0.14, panel_size.y * 0.855)
	_music_hint.size = Vector2(panel_size.x * 0.72, panel_size.y * 0.060)
	_music_hint.clip_text = true
	_music_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_music_hint.add_theme_color_override("font_color", Color(0.60, 0.66, 0.78, 1.0))
	_music_panel.add_child(_music_hint)


func _open_music_view() -> void:
	_in_music_view = true
	_panel.visible = false
	_music_layer.visible = true
	_set_touch_back_visible(true)
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)

	# Abre com o cursor no botão de lote: é a ação que o operador usa em
	# 9 de 10 instalações.
	_music_cursor = IMPORT_ALL_INDEX

	_set_top_context(
		"INSTALAÇÃO DE MÚSICAS",
		"A: SUBIR   •   E: DESCER   •   B: IMPORTAR   •   SELECT/F9: VOLTAR",
		"PENDRIVE\nESCANEAMENTO"
	)
	_scan_usb()


func _close_music_view() -> void:
	_cancelar_lote(true)
	_cancel_bpm_analysis("")
	_in_music_view = false
	_music_layer.visible = false
	_panel.visible = true
	_set_touch_back_visible(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	_refresh_menu_texts()
	_set_main_top_context()


func _scan_usb() -> void:
	if _music_scan_busy:
		return

	_music_scan_busy = true
	_music_status.text = "ESCANEANDO PENDRIVES..."
	_music_status.add_theme_color_override("font_color", Color(0.20, 0.88, 1.0, 1.0))
	_usb_packages = USER_CATALOG.scan_usb_packages()
	# O -1 (IMPORTAR TODAS) é uma posição válida do cursor e precisa
	# sobreviver ao reescaneamento que roda depois de cada importação.
	if _music_cursor >= 0:
		_music_cursor = clampi(_music_cursor, 0, maxi(0, _usb_packages.size() - 1))
	_music_scan_busy = false
	_refresh_music_view()


func _process_music_inputs() -> void:
	if _batch_active:
		# Durante o lote os botões de navegação ficam parados de
		# propósito: só VOLTAR/SELECT/F9 interrompe.
		return
	if Input.is_action_just_pressed("input_a"):
		_move_music_cursor(-1)
		return
	if Input.is_action_just_pressed("input_e"):
		_move_music_cursor(1)
		return
	if Input.is_action_just_pressed("input_b"):
		_activate_music_cursor()
		return
	if InputMap.has_action("input_start") and Input.is_action_just_pressed("input_start"):
		_activate_music_cursor()


## Navegação da tela de músicas: [IMPORTAR TODAS] + um item por pacote.
func _proximo_cursor_musica(direction: int) -> int:
	var total: int = _usb_packages.size() + 1
	var posicao: int = posmod((_music_cursor + 1) + direction, total)
	return posicao - 1


func _move_music_cursor(direction: int) -> void:
	if _batch_active:
		return
	if _usb_packages.is_empty():
		return
	_music_cursor = _proximo_cursor_musica(direction)
	_refresh_music_view()
	_nav_feedback(direction)


func _activate_music_cursor() -> void:
	if _batch_active:
		return

	if _music_cursor == IMPORT_ALL_INDEX:
		if _usb_packages.is_empty():
			_scan_usb()
			return
		_iniciar_lote()
		return

	if _usb_packages.is_empty():
		_scan_usb()
		return

	if _music_cursor < 0 or _music_cursor >= _usb_packages.size():
		_music_cursor = 0

	var package: Dictionary = _usb_packages[_music_cursor]
	if not bool(package.get("valid", false)):
		_music_status.add_theme_color_override("font_color", Color(1.0, 0.42, 0.42, 1.0))
		_music_status.text = "PACOTE INVÁLIDO: " + str(package.get("error", ""))
		return

	if bool(package.get("installed", false)):
		var existing: Dictionary = package.get("installed_match", {}) as Dictionary
		_music_status.add_theme_color_override(
			"font_color",
			Color(0.32, 1.0, 0.62, 1.0)
		)
		_music_status.text = "JÁ INSTALADA: %s" % str(
			existing.get("title", package.get("name", ""))
		)
		_music_detail.text = "%s   •   %s" % [
			str(existing.get("source", "INSTALADA")),
			str(existing.get("reason", "DUPLICADA")),
		]
		return

	var bpm: float = float(package.get("bpm", 0.0))
	if bpm >= 40.0 and bpm <= 260.0:
		_import_package(package, bpm)
		return

	_start_bpm_analysis(package)


func _refresh_music_view() -> void:
	var count: int = _usb_packages.size()

	if count == 0:
		_music_row_indices.clear()
		_music_cursor = IMPORT_ALL_INDEX
		_music_status.text = "NENHUM PACOTE ENCONTRADO — B PARA REESCANEAR"
		_music_status.add_theme_color_override("font_color", Color(1.0, 0.72, 0.30, 1.0))
		_music_detail.text = (
			"Cada pasta deve conter: 1 MP3 + 1 OGV + 1 CAPA + 1 TXT "
			+ 'com name="NOME DA MUSICA".'
		)
		for i in range(_music_labels.size()):
			_music_rows[i].visible = false
		_atualizar_botao_lote(0, 0, 0)
		_fit_multiline_label(_music_detail, int(_radius * 0.026), 10)
		return

	for row in _music_rows:
		row.visible = true

	var usb_installed: int = 0
	var usb_invalid: int = 0
	for package_value in _usb_packages:
		if not (package_value is Dictionary):
			continue
		var item: Dictionary = package_value as Dictionary
		if not bool(item.get("valid", false)):
			usb_invalid += 1
		elif bool(item.get("installed", false)):
			usb_installed += 1

	var new_count: int = count - usb_installed - usb_invalid

	if _batch_active:
		_music_status.text = "IMPORTANDO %d/%d   •   %d OK   •   %d FALHA(S)" % [
			mini(_batch_position + 1, _batch_total),
			_batch_total,
			_batch_ok,
			_batch_failures.size(),
		]
		_music_status.add_theme_color_override("font_color", Color(1.0, 0.84, 0.24, 1.0))
	else:
		_music_status.text = "%d NOVA(S)   •   %d JÁ INSTALADA(S)   •   %d COM ERRO" % [
			new_count,
			usb_installed,
			usb_invalid,
		]
		_music_status.add_theme_color_override(
			"font_color",
			Color(1.0, 0.72, 0.30, 1.0)
			if usb_invalid > 0
			else Color(0.32, 1.0, 0.62, 1.0)
		)

	_atualizar_botao_lote(new_count, usb_installed, usb_invalid)

	var visible_count: int = _music_labels.size()
	_music_row_indices.clear()
	for _slot in range(visible_count):
		_music_row_indices.append(-1)

	var first: int = clampi(
		_music_cursor - int(visible_count / 2),
		0,
		maxi(0, count - visible_count)
	)

	for slot in range(visible_count):
		var index: int = first + slot
		if index >= count:
			_music_rows[slot].visible = false
			_music_row_indices[slot] = -1
			continue

		_music_row_indices[slot] = index

		var package: Dictionary = _usb_packages[index]
		var valid: bool = bool(package.get("valid", false))
		var installed: bool = bool(package.get("installed", false))
		var bpm: float = float(package.get("bpm", 0.0))
		var bpm_text: String = (
			"%d BPM" % roundi(bpm)
			if bpm > 0.0
			else "BPM: ANALISAR"
		)

		# "JÁ IMPORTADA" vem do histórico em disco: mesmo que o operador
		# tenha apagado a música da máquina, a lista lembra que aquela
		# pasta já passou por aqui e o que aconteceu com ela.
		var log_status: String = str(package.get("log_status", ""))
		var situacao: String = (
			"JÁ INSTALADA"
			if installed
			else ("NOVA" if valid else "ERRO")
		)
		if not installed and valid and log_status == "erro":
			situacao = "FALHOU ANTES"

		_music_labels[slot].text = "%s   •   %s   •   %s" % [
			str(package.get("name", "?")).to_upper(),
			bpm_text,
			situacao,
		]

		var selected: bool = index == _music_cursor
		_music_rows[slot].add_theme_stylebox_override("panel", _row_style(selected))
		_music_labels[slot].add_theme_color_override(
			"font_color",
			Color(1.0, 0.86, 0.20, 1.0)
			if selected
			else (
				Color(0.42, 1.0, 0.68, 1.0)
				if installed
				else (Color.WHITE if valid else Color(1.0, 0.48, 0.48, 1.0))
			)
		)
		_fit_label_to_width(_music_labels[slot], int(_radius * 0.031), 10)

	if _music_cursor == IMPORT_ALL_INDEX:
		_music_detail.text = _texto_detalhe_lote(new_count, usb_installed, usb_invalid)
		_fit_multiline_label(_music_detail, int(_radius * 0.026), 10)
		return

	var selected_package: Dictionary = _usb_packages[_music_cursor]
	if bool(selected_package.get("installed", false)):
		var existing: Dictionary = selected_package.get("installed_match", {}) as Dictionary
		_music_detail.text = "JÁ EXISTE COMO: %s   •   %s" % [
			str(existing.get("title", "?")),
			str(existing.get("source", "INSTALADA")),
		]
	elif bool(selected_package.get("valid", false)):
		var original_category: String = str(
			selected_package.get("category_original", "")
		)
		var clean_category: String = str(
			selected_package.get("category", "OUTROS")
		)
		var category_note: String = (
			"   •   %s → %s" % [original_category.to_upper(), clean_category]
			if not original_category.is_empty()
			and original_category.to_upper() != clean_category
			else ""
		)
		_music_detail.text = (
			"DRIVE %s   •   PACOTE OK%s"
			% [
				str(selected_package.get("drive", "?")),
				category_note,
			]
		)
	else:
		_music_detail.text = "ERRO: " + str(selected_package.get("error", "Pacote inválido."))

	_fit_multiline_label(_music_detail, int(_radius * 0.026), 10)


func _import_package(package: Dictionary, bpm: float) -> void:
	var result: Dictionary = _importar_pacote_resultado(package, bpm)

	if bool(result.get("ok", false)):
		_music_status.add_theme_color_override("font_color", Color(0.32, 1.0, 0.62, 1.0))
		_music_status.text = "IMPORTADA: %s   •   %d BPM" % [
			str(package.get("name", "?")).to_upper(),
			roundi(bpm),
		]
		_menu_feedback("menu_select_feedback")
		_refresh_menu_texts()
		_scan_usb()
		return
	else:
		_music_status.add_theme_color_override("font_color", Color(1.0, 0.42, 0.42, 1.0))
		_music_status.text = str(result.get("erro", "Falha ao importar."))

	_refresh_menu_texts()


## Importa e ANOTA o resultado no histórico em disco. É essa anotação que
## permite refazer uma importação em lote sem repetir trabalho e sem
## perder de vista o pacote que falhou na tentativa anterior.
func _importar_pacote_resultado(package: Dictionary, bpm: float) -> Dictionary:
	var result: Dictionary = USER_CATALOG.import_usb_package(package, bpm)

	if bool(result.get("ok", false)):
		USER_CATALOG.import_log_record(package, "ok", "%d BPM" % roundi(bpm))
	elif bool(result.get("already_installed", false)):
		USER_CATALOG.import_log_record(
			package,
			"duplicada",
			str(result.get("erro", ""))
		)
	else:
		USER_CATALOG.import_log_record(
			package,
			"erro",
			str(result.get("erro", "Falha ao importar."))
		)

	return result


## ---------------------------------------------------------------
## IMPORTACAO EM LOTE (PENDRIVE CHEIO)
##
## Um pacote por quadro: o painel continua desenhando, o contador anda na
## tela e VOLTAR interrompe a qualquer momento. Pacotes sem BPM gravado
## passam pela análise de áudio (~16 s) e o lote continua sozinho quando
## ela termina.
##
## Nada é importado duas vezes: o que já está na máquina é PULADO (e
## contado), e cada resultado vai para o histórico em disco — então
## repetir a importação depois de trocar o pendrive, ou depois de um
## cancelamento, retoma exatamente de onde parou.
## ---------------------------------------------------------------

func _iniciar_lote() -> void:
	if _batch_active or _bpm_analysis_active:
		return

	_batch_queue.clear()
	_batch_failures.clear()
	_batch_invalid.clear()
	_batch_ok = 0
	_batch_skipped = 0
	_batch_position = 0

	for index in range(_usb_packages.size()):
		var package_value: Variant = _usb_packages[index]
		if not (package_value is Dictionary):
			continue

		var package: Dictionary = package_value as Dictionary

		if not bool(package.get("valid", false)):
			_batch_invalid.append(_descricao_falha(package, str(package.get("error", ""))))
			continue

		if bool(package.get("installed", false)):
			_batch_skipped += 1
			continue

		_batch_queue.append(index)

	_batch_total = _batch_queue.size()

	if _batch_total == 0:
		_menu_feedback("menu_next_feedback")
		_mostrar_relatorio_lote(false)
		return

	_batch_active = true
	_menu_feedback("menu_select_feedback")
	_refresh_music_view()


func _passo_lote() -> void:
	if not _batch_active or _bpm_analysis_active:
		return

	if _batch_position >= _batch_queue.size():
		_encerrar_lote(false)
		return

	var index: int = _batch_queue[_batch_position]
	if index < 0 or index >= _usb_packages.size():
		_batch_position += 1
		return

	var package_value: Variant = _usb_packages[index]
	if not (package_value is Dictionary):
		_batch_position += 1
		return

	var package: Dictionary = package_value as Dictionary
	_refresh_music_view()

	var bpm: float = float(package.get("bpm", 0.0))
	if bpm >= 40.0 and bpm <= 260.0:
		_registrar_resultado_lote(package, _importar_pacote_resultado(package, bpm))
		_batch_position += 1
		return

	# Sem BPM no arquivo: a análise de áudio assume e o lote continua em
	# _finish_bpm_analysis().
	if not _start_bpm_analysis(package):
		_batch_failures.append(
			_descricao_falha(package, "MP3 não pôde ser analisado")
		)
		USER_CATALOG.import_log_record(package, "erro", "MP3 não pôde ser analisado")
		_batch_position += 1


func _registrar_resultado_lote(package: Dictionary, result: Dictionary) -> void:
	if bool(result.get("ok", false)):
		_batch_ok += 1
	elif bool(result.get("already_installed", false)):
		_batch_skipped += 1
	else:
		_batch_failures.append(
			_descricao_falha(package, str(result.get("erro", "Falha ao importar.")))
		)


func _cancelar_lote(silencioso: bool) -> void:
	if not _batch_active:
		return
	_encerrar_lote(true, silencioso)


func _encerrar_lote(cancelado: bool, silencioso: bool = false) -> void:
	_batch_active = false
	_cancel_bpm_analysis("")
	_refresh_menu_texts()

	if silencioso:
		return

	# Reescaneia para que as recém-instaladas apareçam como JÁ INSTALADA:
	# é o que faz uma segunda tentativa pular o que já entrou.
	_scan_usb()
	_mostrar_relatorio_lote(cancelado)


## Relatório final: quantas entraram, quantas foram puladas e — o ponto
## que o operador precisa levar para o cliente — QUAIS não funcionaram.
func _mostrar_relatorio_lote(cancelado: bool) -> void:
	if _music_status == null or not is_instance_valid(_music_status):
		return

	var problemas: Array[String] = []
	problemas.append_array(_batch_failures)
	problemas.append_array(_batch_invalid)

	if cancelado:
		_music_status.text = "IMPORTAÇÃO CANCELADA EM %d/%d   •   %d OK   •   %d FALHA(S)" % [
			mini(_batch_position, _batch_total),
			_batch_total,
			_batch_ok,
			problemas.size(),
		]
		_music_status.add_theme_color_override("font_color", Color(1.0, 0.72, 0.30, 1.0))
	elif _batch_total == 0:
		_music_status.text = "NADA NOVO PARA IMPORTAR   •   %d JÁ INSTALADA(S)   •   %d COM ERRO" % [
			_batch_skipped,
			_batch_invalid.size(),
		]
		_music_status.add_theme_color_override("font_color", Color(0.32, 1.0, 0.62, 1.0))
	else:
		_music_status.text = "IMPORTAÇÃO CONCLUÍDA   •   %d OK   •   %d PULADA(S)   •   %d FALHA(S)" % [
			_batch_ok,
			_batch_skipped,
			problemas.size(),
		]
		_music_status.add_theme_color_override(
			"font_color",
			Color(1.0, 0.72, 0.30, 1.0)
			if not problemas.is_empty()
			else Color(0.32, 1.0, 0.62, 1.0)
		)

	if _music_detail == null or not is_instance_valid(_music_detail):
		return

	if problemas.is_empty():
		_music_detail.text = (
			"Nenhum pacote com problema. Importar de novo é seguro: "
			+ "as músicas que já entraram são puladas automaticamente."
		)
	else:
		var mostrados: Array[String] = []
		for texto in problemas:
			if mostrados.size() >= REPORT_NAME_LIMIT:
				break
			mostrados.append(texto)

		var restante: int = problemas.size() - mostrados.size()
		_music_detail.text = (
			"NÃO FUNCIONARAM: "
			+ "   |   ".join(mostrados)
			+ ("   |   + %d PACOTE(S)" % restante if restante > 0 else "")
		)

	_fit_multiline_label(_music_detail, int(_radius * 0.026), 10)


func _descricao_falha(package: Dictionary, motivo: String) -> String:
	var nome: String = str(package.get("name", "")).strip_edges()
	if nome.is_empty():
		nome = str(package.get("folder", "?")).get_file()
	var texto: String = nome.to_upper()
	if not motivo.strip_edges().is_empty():
		texto += " (" + motivo.strip_edges() + ")"
	return texto


func _atualizar_botao_lote(
	novas: int,
	instaladas: int,
	invalidas: int
) -> void:
	if _import_all_panel == null or not is_instance_valid(_import_all_panel):
		return

	var selecionado: bool = _music_cursor == IMPORT_ALL_INDEX

	if _batch_active:
		_import_all_label.text = "IMPORTANDO %d/%d   •   VOLTAR CANCELA" % [
			mini(_batch_position + 1, _batch_total),
			_batch_total,
		]
	elif novas > 0:
		_import_all_label.text = "IMPORTAR TODAS   •   %d NOVA(S)" % novas
	elif instaladas > 0 or invalidas > 0:
		_import_all_label.text = "IMPORTAR TODAS   •   NADA NOVO"
	else:
		_import_all_label.text = "IMPORTAR TODAS   •   REESCANEAR"

	_import_all_panel.add_theme_stylebox_override("panel", _row_style(selecionado))
	_import_all_label.add_theme_color_override(
		"font_color",
		Color(1.0, 0.86, 0.20, 1.0)
		if selecionado
		else (
			Color(0.42, 1.0, 0.68, 1.0)
			if novas > 0
			else Color(0.70, 0.78, 0.90, 1.0)
		)
	)
	_fit_label_to_width(_import_all_label, int(_radius * 0.031), 10)


func _texto_detalhe_lote(
	novas: int,
	instaladas: int,
	invalidas: int
) -> String:
	if _batch_active:
		return (
			"Importando o pendrive inteiro. Não retire o pendrive. "
			+ "VOLTAR interrompe — o que já entrou continua instalado."
		)

	if novas <= 0 and invalidas <= 0:
		return (
			"Todas as %d músicas do pendrive já estão na máquina." % instaladas
			+ "   B reescaneia o pendrive."
		)

	var texto: String = "B importa as %d música(s) nova(s) de uma vez." % novas
	if instaladas > 0:
		texto += "   %d já instalada(s) serão puladas." % instaladas
	if invalidas > 0:
		texto += "   %d pasta(s) com erro serão listadas no final." % invalidas
	return texto


## ---------------------------------------------------------------
## DETECÇÃO AUTOMÁTICA DE BPM
## ---------------------------------------------------------------

func _ensure_bpm_analyzer() -> void:
	_cleanup_bpm_bus()

	AudioServer.add_bus()
	var bus_index: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus_index, BPM_BUS_NAME)

	# Ordem dos efeitos:
	# 0) analisador recebe o sinal em nível normal;
	# 1) amplify reduz a saída para -80 dB.
	# Assim a análise continua forte e o operador praticamente não escuta o MP3.
	AudioServer.set_bus_volume_db(bus_index, 0.0)

	var analyzer := AudioEffectSpectrumAnalyzer.new()
	analyzer.buffer_length = 2.0
	analyzer.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_1024
	AudioServer.add_bus_effect(bus_index, analyzer, 0)

	var silence := AudioEffectAmplify.new()
	silence.volume_db = -80.0
	AudioServer.add_bus_effect(bus_index, silence, 1)

	_bpm_analyzer_instance = (
		AudioServer.get_bus_effect_instance(bus_index, 0)
		as AudioEffectSpectrumAnalyzerInstance
	)

	_bpm_player = AudioStreamPlayer.new()
	_bpm_player.name = "BpmAnalysisPlayer"
	_bpm_player.bus = BPM_BUS_NAME
	add_child(_bpm_player)


func _cleanup_bpm_bus() -> void:
	var existing: int = AudioServer.get_bus_index(BPM_BUS_NAME)
	if existing >= 0:
		AudioServer.remove_bus(existing)


## Devolve `true` quando a análise realmente começou. O lote depende
## dessa resposta: um MP3 ilegível precisa virar falha registrada, não
## uma chamada repetida a cada quadro.
func _start_bpm_analysis(package: Dictionary) -> bool:
	var audio_path: String = str(package.get("audio", ""))
	if audio_path.is_empty() or not FileAccess.file_exists(audio_path):
		_music_status.add_theme_color_override("font_color", Color(1.0, 0.42, 0.42, 1.0))
		_music_status.text = "MP3 NÃO ENCONTRADO PARA ANÁLISE"
		return false

	if _bpm_player == null or not is_instance_valid(_bpm_player):
		_ensure_bpm_analyzer()

	var stream: AudioStreamMP3 = AudioStreamMP3.load_from_file(audio_path)
	if stream == null:
		_music_status.add_theme_color_override("font_color", Color(1.0, 0.42, 0.42, 1.0))
		_music_status.text = "NÃO FOI POSSÍVEL ABRIR O MP3"
		return false

	_bpm_pending_package = package.duplicate(true)
	_bpm_analysis_active = true
	_bpm_analysis_elapsed = 0.0
	_bpm_baseline = 0.0
	_bpm_last_peak_time = -10.0
	_bpm_peaks.clear()

	_bpm_player.stream = stream

	# Evita introduções longas quando possível.
	var length: float = stream.get_length()
	var start_at: float = 0.0
	if length > BPM_ANALYSIS_SECONDS + 8.0:
		start_at = minf(30.0, length * 0.15)
		start_at = minf(start_at, maxf(0.0, length - BPM_ANALYSIS_SECONDS - 1.0))

	_bpm_player.play(start_at)
	_music_status.add_theme_color_override("font_color", Color(1.0, 0.84, 0.24, 1.0))
	_music_status.text = "ANALISANDO BPM... 0%"
	_music_detail.text = "O áudio está sendo analisado em silêncio. Não retire o pendrive."
	return true


func _process_bpm_analysis(delta: float) -> void:
	if not _bpm_analysis_active:
		return

	_bpm_analysis_elapsed += delta

	if _bpm_analyzer_instance != null:
		var low: Vector2 = _bpm_analyzer_instance.get_magnitude_for_frequency_range(
			45.0,
			180.0,
			AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_MAX
		)
		var mid: Vector2 = _bpm_analyzer_instance.get_magnitude_for_frequency_range(
			180.0,
			1200.0,
			AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_AVERAGE
		)

		var low_energy: float = (low.x + low.y) * 0.5
		var mid_energy: float = (mid.x + mid.y) * 0.5
		var energy: float = low_energy * 0.82 + mid_energy * 0.18

		if _bpm_baseline <= 0.000001:
			_bpm_baseline = energy
		else:
			_bpm_baseline = lerpf(_bpm_baseline, energy, 0.045)

		var threshold: float = maxf(0.0006, _bpm_baseline * 1.48)
		var refractory: float = 0.245

		if (
			_bpm_analysis_elapsed > 0.75
			and energy > threshold
			and (_bpm_analysis_elapsed - _bpm_last_peak_time) >= refractory
		):
			_bpm_peaks.append(_bpm_analysis_elapsed)
			_bpm_last_peak_time = _bpm_analysis_elapsed

	var progress: int = clampi(
		roundi((_bpm_analysis_elapsed / BPM_ANALYSIS_SECONDS) * 100.0),
		0,
		100
	)
	_music_status.text = (
		("LOTE %d/%d   •   " % [mini(_batch_position + 1, _batch_total), _batch_total])
		if _batch_active
		else ""
	) + "ANALISANDO BPM... %d%%" % progress

	if (
		_bpm_analysis_elapsed >= BPM_ANALYSIS_SECONDS
		or (_bpm_player != null and not _bpm_player.playing)
	):
		_finish_bpm_analysis()


func _finish_bpm_analysis() -> void:
	if _bpm_player != null:
		_bpm_player.stop()

	var bpm: float = _estimate_bpm_from_peaks(_bpm_peaks)
	_bpm_analysis_active = false

	if bpm < 40.0:
		if _batch_active:
			var recusado: Dictionary = _bpm_pending_package.duplicate(true)
			_batch_failures.append(
				_descricao_falha(recusado, "BPM não detectado")
			)
			USER_CATALOG.import_log_record(recusado, "erro", "BPM não detectado")
			_bpm_pending_package.clear()
			_batch_position += 1
			_refresh_music_view()
			return

		_music_status.add_theme_color_override("font_color", Color(1.0, 0.55, 0.28, 1.0))
		_music_status.text = "BPM NÃO CONFIÁVEL — USE TBPM NO MP3 OU bpm= NO TXT"
		_music_detail.text = (
			"Para os pacotes vendidos, grave o BPM no campo TBPM do MP3. "
			+ "A máquina continuará tentando detectar quando ele não existir."
		)
		return

	_bpm_pending_package["bpm"] = bpm

	if _batch_active:
		var pacote: Dictionary = _bpm_pending_package.duplicate(true)
		_bpm_pending_package.clear()
		_registrar_resultado_lote(pacote, _importar_pacote_resultado(pacote, bpm))
		_batch_position += 1
		_refresh_music_view()
		return

	_music_status.text = "BPM DETECTADO: %d" % roundi(bpm)
	_import_package(_bpm_pending_package, bpm)


func _cancel_bpm_analysis(message: String) -> void:
	if _bpm_player != null and is_instance_valid(_bpm_player):
		_bpm_player.stop()
	_bpm_analysis_active = false
	_bpm_pending_package.clear()
	_bpm_peaks.clear()
	if not message.is_empty() and _music_status != null:
		_music_status.text = message


func _estimate_bpm_from_peaks(peaks: Array[float]) -> float:
	if peaks.size() < 6:
		return 0.0

	var histogram: Dictionary = {}

	# Intervalos entre onsets próximos. Considera também picos com um onset
	# perdido no meio; depois normaliza para uma faixa musical jogável.
	for span in [1, 2]:
		for i in range(span, peaks.size()):
			var interval: float = peaks[i] - peaks[i - span]
			if interval <= 0.0:
				continue

			var bpm: float = (60.0 * float(span)) / interval
			while bpm < BPM_MIN:
				bpm *= 2.0
			while bpm > BPM_MAX:
				bpm *= 0.5

			if bpm < BPM_MIN or bpm > BPM_MAX:
				continue

			var center: int = roundi(bpm)
			for offset in range(-2, 3):
				var key: int = center + offset
				var weight: float = 1.0 - absf(float(offset)) * 0.16
				histogram[key] = float(histogram.get(key, 0.0)) + weight

	if histogram.is_empty():
		return 0.0

	var best_bpm: int = 0
	var best_score: float = -1.0
	for key_value in histogram.keys():
		var key: int = int(key_value)
		var score: float = float(histogram[key_value])
		if score > best_score:
			best_score = score
			best_bpm = key

	if best_bpm <= 0:
		return 0.0

	# Média refinada dos intervalos que caem perto do vencedor.
	var values: Array[float] = []
	for i in range(1, peaks.size()):
		var interval: float = peaks[i] - peaks[i - 1]
		if interval <= 0.0:
			continue

		var bpm: float = 60.0 / interval
		while bpm < BPM_MIN:
			bpm *= 2.0
		while bpm > BPM_MAX:
			bpm *= 0.5

		if absf(bpm - float(best_bpm)) <= 4.0:
			values.append(bpm)

	if values.is_empty():
		return float(best_bpm)

	values.sort()
	var median: float = values[int(values.size() / 2)]
	return clampf(median, BPM_MIN, BPM_MAX)


## ---------------------------------------------------------------
## CONTADORES
## ---------------------------------------------------------------

func _build_counters_view() -> void:
	_counters_layer = CanvasLayer.new()
	_counters_layer.layer = 20
	_counters_layer.visible = false
	add_child(_counters_layer)

	var font: Font = _load_font()
	var panel_size := Vector2(_radius * 1.55, _radius * 1.30)

	var panel := Panel.new()
	panel.position = _center - panel_size * 0.5
	panel.size = panel_size
	panel.clip_contents = true
	panel.add_theme_stylebox_override("panel", _panel_style())
	_counters_layer.add_child(panel)

	_counters_title = _make_label(
		"CONTADOR DE PARTIDAS",
		int(_radius * 0.052),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	_counters_title.position = Vector2(panel_size.x * 0.12, panel_size.y * 0.08)
	_counters_title.size = Vector2(panel_size.x * 0.76, panel_size.y * 0.12)
	_counters_title.add_theme_color_override("font_color", Color(0.10, 0.85, 1.0, 1.0))
	panel.add_child(_counters_title)

	_counters_body = _make_label(
		"",
		int(_radius * 0.038),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	_counters_body.position = Vector2(panel_size.x * 0.10, panel_size.y * 0.22)
	_counters_body.size = Vector2(panel_size.x * 0.80, panel_size.y * 0.62)
	_counters_body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_counters_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_counters_body.clip_text = true
	panel.add_child(_counters_body)

	var hint := _make_label(
		"SELECT / F9: VOLTAR",
		int(_radius * 0.025),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	hint.position = Vector2(panel_size.x * 0.18, panel_size.y * 0.86)
	hint.size = Vector2(panel_size.x * 0.64, panel_size.y * 0.07)
	hint.add_theme_color_override("font_color", Color(0.60, 0.66, 0.78, 1.0))
	panel.add_child(hint)


func _open_counters_view() -> void:
	_in_counters_view = true
	_panel.visible = false
	_counters_layer.visible = true
	_set_touch_back_visible(true)
	_refresh_counters_view()


func _close_counters_view() -> void:
	_in_counters_view = false
	_counters_layer.visible = false
	_panel.visible = true
	_set_touch_back_visible(false)
	_refresh_menu_texts()
	_set_main_top_context()


func _refresh_counters_view() -> void:
	var factory: Dictionary = ArcadeCounters.contagem("fabrica")
	var client: Dictionary = ArcadeCounters.contagem("cliente")
	var current_bucket: String = ArcadeCounters.balde_atual()

	_counters_body.text = (
		"DESENVOLVIMENTO / FÁBRICA\n"
		+ "STARTS: %d    LIVRE: %d    CRÉDITO: %d\n\n"
		+ "CLIENTE / PRODUÇÃO\n"
		+ "STARTS: %d    LIVRE: %d    CRÉDITO: %d"
	) % [
		int(factory.get("total", 0)),
		int(factory.get("livre", 0)),
		int(factory.get("credito", 0)),
		int(client.get("total", 0)),
		int(client.get("livre", 0)),
		int(client.get("credito", 0)),
	]
	_fit_multiline_label(_counters_body, int(_radius * 0.038), 11)

	_set_top_context(
		"CONTADOR DE PARTIDAS",
		"SELECT / F9: VOLTAR",
		"AMBIENTE ATIVO\n%s" % (
			"CLIENTE"
			if current_bucket == "cliente"
			else "DESENVOLVIMENTO"
		)
	)


## ---------------------------------------------------------------
## TESTE DE LEDS / INPUTS
## ---------------------------------------------------------------

func _build_test_view() -> void:
	_test_layer = CanvasLayer.new()
	_test_layer.layer = 20
	_test_layer.visible = false
	add_child(_test_layer)

	var font: Font = _load_font()
	var lane_orbit: float = _radius * 0.62
	var box_size := Vector2(_radius * 0.24, _radius * 0.18)

	for i in range(LANE_COUNT):
		var angle: float = -PI * 0.5 + TAU * float(i) / float(LANE_COUNT)
		var box := Panel.new()
		box.position = (
			_center
			+ Vector2(cos(angle), sin(angle)) * lane_orbit
			- box_size * 0.5
		)
		box.size = box_size
		box.clip_contents = true
		box.add_theme_stylebox_override("panel", _box_style(false))
		_test_layer.add_child(box)
		_lane_boxes.append(box)
		_lane_pressed_state.append(false)

		var label := _make_label(
			LANE_LABELS[i],
			int(box_size.y * 0.36),
			HORIZONTAL_ALIGNMENT_CENTER,
			font
		)
		label.size = box_size
		box.add_child(label)

	_credito_box = Panel.new()
	_credito_box.size = box_size * 1.35
	_credito_box.position = _center - _credito_box.size * 0.5
	_credito_box.clip_contents = true
	_credito_box.add_theme_stylebox_override("panel", _box_style(false))
	_test_layer.add_child(_credito_box)

	var credito_label := _make_label(
		"CRÉDITO",
		int(_credito_box.size.y * 0.26),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	credito_label.size = _credito_box.size
	_credito_label_fit(credito_label)
	_credito_box.add_child(credito_label)

	_test_status_label = _make_label(
		"",
		int(_radius * 0.025),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	_test_status_label.position = Vector2(
		_center.x - _radius * 0.62,
		_center.y + _radius * 0.75
	)
	_test_status_label.size = Vector2(_radius * 1.24, _radius * 0.08)
	_test_status_label.clip_text = true
	_test_layer.add_child(_test_status_label)


func _credito_label_fit(label: Label) -> void:
	_fit_label_to_width(label, int(_radius * 0.040), 10)


func _open_test_view() -> void:
	_in_test_view = true
	_panel.visible = false
	_test_layer.visible = true
	_set_touch_back_visible(true)

	var client := get_node_or_null("/root/LedClient")
	if client != null and client.has_method("begin_stage"):
		client.call("begin_stage")

	_set_top_context(
		"TESTE DE LEDS E INPUTS",
		"APERTE OS BOTÕES FÍSICOS   •   SELECT/F9: VOLTAR",
		"TESTE\nATIVO"
	)


func _close_test_view() -> void:
	_in_test_view = false
	_test_layer.visible = false
	_panel.visible = true
	_set_touch_back_visible(false)

	# O teste deixa lanes acesas uma a uma; o trio do menu so volta
	# depois de apagar tudo.
	LED_CLIENT.clear_all()
	_agendar_leds_menu()

	for i in range(_lane_pressed_state.size()):
		_lane_pressed_state[i] = false
		_set_lane_box_active(i, false)

	_credito_pressed_state = false
	_set_credito_box_active(false)
	_set_main_top_context()


func _update_test_view() -> void:
	var client := get_node_or_null("/root/LedClient")

	for i in range(LANE_COUNT):
		var action: String = LANE_ACTIONS[i]
		var pressed: bool = (
			InputMap.has_action(action)
			and Input.is_action_pressed(action)
		)

		if pressed == _lane_pressed_state[i]:
			continue

		_lane_pressed_state[i] = pressed
		_set_lane_box_active(i, pressed)

		if client != null and client.has_method("send"):
			if pressed:
				client.call("send", "LED %d 255 255 255" % i)
			else:
				client.call("send", "LED %d 0 0 0" % i)

	var credit_pressed: bool = (
		InputMap.has_action("input_credito")
		and Input.is_action_pressed("input_credito")
	)

	if credit_pressed != _credito_pressed_state:
		_credito_pressed_state = credit_pressed
		_set_credito_box_active(credit_pressed)

	var bridge_ok: bool = (
		client != null
		and client.has_method("bridge_ready")
		and bool(client.call("bridge_ready"))
	)

	var forced: String = ""
	if client != null and client.has_method("forced_port"):
		forced = str(client.call("forced_port"))

	_test_status_label.text = (
		("BRIDGE OK" if bridge_ok else "BRIDGE OFFLINE")
		+ "   •   "
		+ ("COM5 FORÇADA" if not forced.is_empty() else "PORTA AUTOMÁTICA")
	)
	_test_status_label.add_theme_color_override(
		"font_color",
		Color(0.20, 1.0, 0.45, 1.0)
		if bridge_ok
		else Color(1.0, 0.25, 0.28, 1.0)
	)
	_fit_label_to_width(_test_status_label, int(_radius * 0.025), 10)


func _set_lane_box_active(index: int, active: bool) -> void:
	if index < 0 or index >= _lane_boxes.size():
		return
	_lane_boxes[index].add_theme_stylebox_override("panel", _box_style(active))


func _set_credito_box_active(active: bool) -> void:
	if _credito_box == null or not is_instance_valid(_credito_box):
		return
	_credito_box.add_theme_stylebox_override("panel", _box_style(active))


## ---------------------------------------------------------------
## ESTILOS / TEXTO
## ---------------------------------------------------------------

func _box_style(active: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = (
		Color(0.10, 0.95, 0.55, 0.85)
		if active
		else Color(0.02, 0.03, 0.06, 0.92)
	)
	style.border_color = (
		Color(0.10, 0.95, 0.55, 1.0)
		if active
		else Color(0.30, 0.36, 0.48, 0.70)
	)
	style.set_border_width_all(3)
	style.set_corner_radius_all(14)
	return style


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.006, 0.010, 0.024, 0.97)
	style.border_color = Color(0.10, 0.85, 1.0, 0.65)
	style.set_border_width_all(3)
	style.set_corner_radius_all(999)
	style.shadow_color = Color(0.10, 0.85, 1.0, 0.20)
	style.shadow_size = 14
	return style


func _top_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.006, 0.014, 0.038, 0.97)
	style.border_color = Color(0.16, 0.84, 1.0, 0.72)
	style.set_border_width_all(3)
	style.set_corner_radius_all(24)
	style.shadow_color = Color(0.10, 0.72, 1.0, 0.24)
	style.shadow_size = 16
	return style


func _status_card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.012, 0.030, 0.070, 0.94)
	style.border_color = Color(1.0, 0.80, 0.20, 0.52)
	style.set_border_width_all(2)
	style.set_corner_radius_all(18)
	return style


func _row_style(selected: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = (
		Color(0.10, 0.07, 0.015, 0.92)
		if selected
		else Color(0.012, 0.028, 0.065, 0.88)
	)
	style.border_color = (
		Color(1.0, 0.82, 0.20, 0.90)
		if selected
		else Color(0.24, 0.62, 0.90, 0.38)
	)
	style.set_border_width_all(2 if selected else 1)
	style.set_corner_radius_all(999)
	if selected:
		style.shadow_color = Color(1.0, 0.70, 0.10, 0.22)
		style.shadow_size = 10
	return style


func _load_font() -> Font:
	var path: String = "res://fonts/Bungee-Regular.ttf"
	if ResourceLoader.exists(path):
		var resource: Resource = load(path)
		if resource is Font:
			return resource as Font
	return ThemeDB.fallback_font


func _make_label(
	text_value: String,
	font_size: int,
	alignment: HorizontalAlignment,
	font: Font
) -> Label:
	var label := Label.new()
	label.text = text_value
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", maxi(10, font_size))
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.95))
	label.add_theme_constant_override("outline_size", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _fit_label_to_width(label: Label, preferred_size: int, minimum_size: int) -> void:
	if label == null or not is_instance_valid(label):
		return

	var font: Font = label.get_theme_font("font")
	var size_value: int = maxi(preferred_size, minimum_size)
	var usable_width: float = maxf(1.0, label.size.x * 0.96)

	while size_value > minimum_size:
		var measured: Vector2 = font.get_string_size(
			label.text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			size_value
		)
		if measured.x <= usable_width:
			break
		size_value -= 1

	label.add_theme_font_size_override("font_size", size_value)


func _fit_multiline_label(label: Label, preferred_size: int, minimum_size: int) -> void:
	if label == null or not is_instance_valid(label):
		return

	var font: Font = label.get_theme_font("font")
	var size_value: int = maxi(preferred_size, minimum_size)
	var usable_width: float = maxf(1.0, label.size.x * 0.94)
	var usable_height: float = maxf(1.0, label.size.y * 0.92)

	while size_value > minimum_size:
		var widest: float = 0.0
		var line_count: int = 0

		for line_value in label.text.split("\n"):
			var line: String = str(line_value)
			widest = maxf(
				widest,
				font.get_string_size(
					line,
					HORIZONTAL_ALIGNMENT_LEFT,
					-1.0,
					size_value
				).x
			)
			line_count += 1

		var estimated_height: float = float(maxi(1, line_count)) * float(size_value) * 1.34
		if widest <= usable_width and estimated_height <= usable_height:
			break

		size_value -= 1

	label.add_theme_font_size_override("font_size", size_value)
