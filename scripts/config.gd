extends Node2D
## Tela de Configuracoes (F9) — acesso de servico/operador, nao um
## botao do painel do jogador. Deixa escolher Modo Livre / Modo
## Credito, testar LEDs e inputs fisicos, e forcar a porta COM da
## bridge quando ela conecta errado.

const SETTINGS_GATE: Script = preload("res://scripts/hit_music_r7/settings_gate.gd")

const LANE_COUNT: int = 8
const LANE_ACTIONS: Array[String] = [
	"input_a", "input_b", "input_c", "input_d",
	"input_e", "input_f", "input_g", "input_h",
]
const LANE_LABELS: Array[String] = ["A", "B", "C", "D", "E", "F", "G", "H"]

enum MenuItem {
	MODE,
	CREDITS,
	LED_INPUT_TEST,
	COM_PORT,
	BACK,
}

var _return_path: String = "res://scenes/opening.tscn"
var _cursor: int = 0
var _in_test_view: bool = false

var _hud_layer: CanvasLayer
var _panel: Panel
var _menu_labels: Array[Label] = []

var _test_layer: CanvasLayer
var _test_status_label: Label
var _lane_boxes: Array[Panel] = []
var _lane_pressed_state: Array[bool] = []
var _start_box: Panel
var _start_pressed_state: bool = false


func _ready() -> void:
	_return_path = SETTINGS_GATE.return_path()

	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)

	var client := get_node_or_null("/root/LedClient")
	if client != null and client.has_method("begin_menu"):
		client.call("begin_menu")

	var screen: Vector2 = get_viewport_rect().size
	_build_background(screen)
	_build_menu(screen)
	_build_test_view(screen)
	_refresh_menu_texts()


func _process(_delta: float) -> void:
	if _in_test_view:
		_update_test_view()
		return
	_process_physical_inputs()


func _process_physical_inputs() -> void:
	if Input.is_action_just_pressed("input_a"):
		_move_cursor(1)
	if Input.is_action_just_pressed("input_b"):
		_activate_cursor()
	if Input.is_action_just_pressed("input_start"):
		_close_settings()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (
			event.keycode == KEY_F9
			or event.keycode == KEY_ESCAPE
			or event.keycode == KEY_BACKSPACE
		):
			_handle_back()


func _handle_back() -> void:
	if _in_test_view:
		_close_test_view()
	else:
		_close_settings()


func _close_settings() -> void:
	var client := get_node_or_null("/root/LedClient")
	if client != null and client.has_method("clear_all"):
		client.call("clear_all")
	get_tree().change_scene_to_file(_return_path)


# ---------------------------------------------------------------
# MENU PRINCIPAL
# ---------------------------------------------------------------
func _move_cursor(direction: int) -> void:
	var count: int = _menu_labels.size()
	if count <= 0:
		return
	_cursor = posmod(_cursor + direction, count)
	_refresh_menu_texts()
	_menu_feedback("menu_next_feedback")


func _activate_cursor() -> void:
	match _cursor:
		MenuItem.MODE:
			ArcadeSettings.toggle_mode()
		MenuItem.CREDITS:
			ArcadeSettings.add_credit(1)
		MenuItem.LED_INPUT_TEST:
			_open_test_view()
		MenuItem.COM_PORT:
			_toggle_com_port()
		MenuItem.BACK:
			_close_settings()
			return

	_refresh_menu_texts()
	_menu_feedback("menu_select_feedback")


func _menu_feedback(method_name: String) -> void:
	var client := get_node_or_null("/root/LedClient")
	if client != null and client.has_method(method_name):
		client.call(method_name)


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


func _refresh_menu_texts() -> void:
	if _menu_labels.size() < 5:
		return

	_menu_labels[MenuItem.MODE].text = (
		"MODO: CRÉDITO" if ArcadeSettings.is_credit_mode() else "MODO: LIVRE"
	)
	_menu_labels[MenuItem.CREDITS].text = "CRÉDITOS: %d   (B: +1)" % ArcadeSettings.credits
	_menu_labels[MenuItem.LED_INPUT_TEST].text = "TESTE DE LEDS E INPUTS"

	var client := get_node_or_null("/root/LedClient")
	var forced: String = ""
	if client != null and client.has_method("forced_port"):
		forced = str(client.call("forced_port"))
	_menu_labels[MenuItem.COM_PORT].text = (
		"PORTA: COM5 (FORÇADA)" if not forced.is_empty() else "PORTA: AUTOMÁTICA"
	)
	_menu_labels[MenuItem.BACK].text = "VOLTAR"

	for i in range(_menu_labels.size()):
		var label: Label = _menu_labels[i]
		if i == _cursor:
			label.text = "> " + label.text
			label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.20, 1.0))
		else:
			label.add_theme_color_override("font_color", Color.WHITE)


func _build_background(screen: Vector2) -> void:
	var background := ColorRect.new()
	background.color = Color(0.01, 0.015, 0.03, 1.0)
	background.size = screen
	background.position = Vector2.ZERO
	background.z_index = -10
	add_child(background)


func _build_menu(screen: Vector2) -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 10
	add_child(_hud_layer)

	var font: Font = _load_font()
	var panel_size := Vector2(screen.x * 0.48, screen.y * 0.62)

	_panel = Panel.new()
	_panel.position = (screen - panel_size) * 0.5
	_panel.size = panel_size
	_panel.add_theme_stylebox_override("panel", _panel_style())
	_hud_layer.add_child(_panel)

	var title: Label = _make_label(
		"CONFIGURAÇÕES",
		int(panel_size.x * 0.075),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	title.position = Vector2(panel_size.x * 0.06, panel_size.y * 0.05)
	title.size = Vector2(panel_size.x * 0.88, panel_size.y * 0.10)
	title.add_theme_color_override("font_color", Color(0.10, 0.85, 1.0, 1.0))
	_panel.add_child(title)

	var start_y: float = panel_size.y * 0.22
	var row_height: float = panel_size.y * 0.13
	for i in range(5):
		var label: Label = _make_label(
			"",
			int(panel_size.x * 0.045),
			HORIZONTAL_ALIGNMENT_CENTER,
			font
		)
		label.position = Vector2(panel_size.x * 0.06, start_y + row_height * float(i))
		label.size = Vector2(panel_size.x * 0.88, row_height * 0.86)
		_panel.add_child(label)
		_menu_labels.append(label)

	var hint: Label = _make_label(
		"A: NAVEGAR    B: CONFIRMAR    F9/ESC: FECHAR",
		int(panel_size.x * 0.030),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	hint.position = Vector2(panel_size.x * 0.06, panel_size.y * 0.90)
	hint.size = Vector2(panel_size.x * 0.88, panel_size.y * 0.08)
	hint.add_theme_color_override("font_color", Color(0.60, 0.66, 0.78, 1.0))
	_panel.add_child(hint)


# ---------------------------------------------------------------
# TESTE DE LEDS E INPUTS
# ---------------------------------------------------------------
func _open_test_view() -> void:
	_in_test_view = true
	_panel.visible = false
	_test_layer.visible = true

	# Sai do modo MENU (que bloqueia comandos LED soltos) e vai pro
	# modo NORMAL, onde LED %d ... realmente chega na bridge — sem
	# isso o teste de LED nunca acenderia nada de verdade.
	var client := get_node_or_null("/root/LedClient")
	if client != null and client.has_method("begin_stage"):
		client.call("begin_stage")


func _close_test_view() -> void:
	_in_test_view = false
	_test_layer.visible = false
	_panel.visible = true

	var client := get_node_or_null("/root/LedClient")
	if client != null and client.has_method("clear_all"):
		client.call("clear_all")
	if client != null and client.has_method("begin_menu"):
		client.call("begin_menu")

	for i in range(_lane_pressed_state.size()):
		_lane_pressed_state[i] = false
		_set_lane_box_active(i, false)
	_start_pressed_state = false
	_set_start_box_active(false)


func _update_test_view() -> void:
	var client := get_node_or_null("/root/LedClient")

	for i in range(LANE_COUNT):
		var action: String = LANE_ACTIONS[i]
		var pressed: bool = InputMap.has_action(action) and Input.is_action_pressed(action)
		if pressed == _lane_pressed_state[i]:
			continue
		_lane_pressed_state[i] = pressed
		_set_lane_box_active(i, pressed)
		if client != null and client.has_method("send"):
			if pressed:
				client.call("send", "LED %d 255 255 255" % i)
			else:
				client.call("send", "LED %d 0 0 0" % i)

	var start_pressed: bool = (
		InputMap.has_action("input_start")
		and Input.is_action_pressed("input_start")
	)
	if start_pressed != _start_pressed_state:
		_start_pressed_state = start_pressed
		_set_start_box_active(start_pressed)

	if _test_status_label == null:
		return

	var bridge_ok: bool = (
		client != null
		and client.has_method("bridge_ready")
		and bool(client.call("bridge_ready"))
	)
	var forced: String = ""
	if client != null and client.has_method("forced_port"):
		forced = str(client.call("forced_port"))
	var port_text: String = "COM5 (forçada)" if not forced.is_empty() else "automática"

	_test_status_label.text = (
		("BRIDGE: OK" if bridge_ok else "BRIDGE: OFFLINE / SEM RESPOSTA")
		+ "   |   PORTA: "
		+ port_text
	)
	_test_status_label.add_theme_color_override(
		"font_color",
		Color(0.20, 1.0, 0.45, 1.0) if bridge_ok else Color(1.0, 0.25, 0.28, 1.0)
	)


func _build_test_view(screen: Vector2) -> void:
	_test_layer = CanvasLayer.new()
	_test_layer.layer = 11
	_test_layer.visible = false
	add_child(_test_layer)

	var font: Font = _load_font()

	var background := ColorRect.new()
	background.color = Color(0.006, 0.010, 0.022, 0.98)
	background.size = screen
	background.position = Vector2.ZERO
	_test_layer.add_child(background)

	var title: Label = _make_label(
		"TESTE DE LEDS E INPUTS",
		int(screen.x * 0.032),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	title.position = Vector2(screen.x * 0.05, screen.y * 0.06)
	title.size = Vector2(screen.x * 0.90, screen.y * 0.08)
	title.add_theme_color_override("font_color", Color(0.10, 0.85, 1.0, 1.0))
	_test_layer.add_child(title)

	_test_status_label = _make_label(
		"",
		int(screen.x * 0.022),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	_test_status_label.position = Vector2(screen.x * 0.05, screen.y * 0.15)
	_test_status_label.size = Vector2(screen.x * 0.90, screen.y * 0.05)
	_test_layer.add_child(_test_status_label)

	var grid_top: float = screen.y * 0.26
	var box_size := Vector2(screen.x * 0.15, screen.y * 0.15)
	var spacing_x: float = screen.x * 0.19
	var spacing_y: float = screen.y * 0.20
	var start_x: float = screen.x * 0.5 - spacing_x * 1.5

	for i in range(LANE_COUNT):
		var col: int = i % 4
		var row: int = int(i / 4)
		var box := Panel.new()
		box.position = Vector2(
			start_x + spacing_x * float(col) - box_size.x * 0.5,
			grid_top + spacing_y * float(row)
		)
		box.size = box_size
		box.add_theme_stylebox_override("panel", _box_style(false))
		_test_layer.add_child(box)
		_lane_boxes.append(box)
		_lane_pressed_state.append(false)

		var label: Label = _make_label(
			LANE_LABELS[i],
			int(box_size.y * 0.36),
			HORIZONTAL_ALIGNMENT_CENTER,
			font
		)
		label.size = box_size
		box.add_child(label)

	_start_box = Panel.new()
	_start_box.size = box_size * 1.15
	_start_box.position = Vector2(
		screen.x * 0.5 - _start_box.size.x * 0.5,
		grid_top + spacing_y * 2.35
	)
	_start_box.add_theme_stylebox_override("panel", _box_style(false))
	_test_layer.add_child(_start_box)

	var start_label: Label = _make_label(
		"START",
		int(_start_box.size.y * 0.28),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	start_label.size = _start_box.size
	_start_box.add_child(start_label)

	var hint: Label = _make_label(
		"APERTE OS BOTÕES FÍSICOS PRA TESTAR   —   F9/ESC: VOLTAR",
		int(screen.x * 0.020),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	hint.position = Vector2(screen.x * 0.05, screen.y * 0.90)
	hint.size = Vector2(screen.x * 0.90, screen.y * 0.06)
	hint.add_theme_color_override("font_color", Color(0.60, 0.66, 0.78, 1.0))
	_test_layer.add_child(hint)


func _set_lane_box_active(index: int, active: bool) -> void:
	if index < 0 or index >= _lane_boxes.size():
		return
	_lane_boxes[index].add_theme_stylebox_override("panel", _box_style(active))


func _set_start_box_active(active: bool) -> void:
	if _start_box == null or not is_instance_valid(_start_box):
		return
	_start_box.add_theme_stylebox_override("panel", _box_style(active))


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
	style.set_corner_radius_all(24)
	style.shadow_color = Color(0.10, 0.85, 1.0, 0.20)
	style.shadow_size = 14
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
