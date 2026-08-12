extends Node2D
## Tela de Configuracoes (F9) — acesso de servico/operador, nao um
## botao do painel do jogador. Deixa escolher Modo Livre / Modo
## Credito, testar LEDs e inputs fisicos, e forcar a porta COM da
## bridge quando ela conecta errado.

const SETTINGS_GATE: Script = preload("res://scripts/hit_music_r7/settings_gate.gd")
const USER_CATALOG: Script = preload("res://scripts/hit_music_r7/user_catalog.gd")

const LANE_COUNT: int = 8
const LANE_ACTIONS: Array[String] = [
	"input_a", "input_b", "input_c", "input_d",
	"input_e", "input_f", "input_g", "input_h",
]
const LANE_LABELS: Array[String] = ["A", "B", "C", "D", "E", "F", "G", "H"]

enum MenuItem {
	MODE,
	CREDITS,
	NEW_SONG,
	LED_INPUT_TEST,
	COM_PORT,
	BACK,
}

const MENU_ITEM_COUNT: int = 6

var _return_path: String = "res://scenes/opening.tscn"
var _cursor: int = 0
var _in_test_view: bool = false

var _hud_layer: CanvasLayer
var _top_panel: Panel
var _top_status_label: Label
var _panel: Panel
var _menu_labels: Array[Label] = []
var _menu_rows: Array[Panel] = []

var _screen: Vector2 = Vector2.ZERO
var _center: Vector2 = Vector2.ZERO
var _radius: float = 100.0
var _select_can_close: bool = false

var _test_layer: CanvasLayer
var _test_status_label: Label
var _lane_boxes: Array[Panel] = []
var _lane_pressed_state: Array[bool] = []
var _start_box: Panel
var _start_pressed_state: bool = false

var _song_layer: CanvasLayer
var _song_panel: Panel
var _song_name_edit: LineEdit
var _song_bpm_edit: SpinBox
var _song_audio_label: Label
var _song_video_label: Label
var _song_cover_label: Label
var _song_status_label: Label
var _song_list_label: Label
var _song_audio_path: String = ""
var _song_video_path: String = ""
var _song_cover_path: String = ""
var _in_song_form: bool = false


func _ready() -> void:
	_return_path = SETTINGS_GATE.return_path()

	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)

	var client := get_node_or_null("/root/LedClient")
	if client != null and client.has_method("begin_menu"):
		client.call("begin_menu")

	var screen: Vector2 = get_viewport_rect().size
	_calculate_machine_geometry(screen)
	_build_background(screen)
	_build_menu(screen)
	_build_test_view(screen)
	_refresh_menu_texts()
	ArcadeSettings.changed.connect(_refresh_menu_texts)
	get_viewport().size_changed.connect(_reload_for_resize)


func _process(_delta: float) -> void:
	queue_redraw()
	# Ao entrar por SELECT, espera o botao ser solto antes de permitir
	# que um novo toque feche a tela. Evita abrir e fechar no mesmo frame.
	if InputMap.has_action("input_select"):
		if not Input.is_action_pressed("input_select"):
			_select_can_close = true
		elif _select_can_close and Input.is_action_just_pressed("input_select"):
			if _in_song_form:
				_close_song_form()
			else:
				_close_settings()
			return

	if _in_song_form:
		# O formulario usa teclado e mouse (e acesso de servico). Os
		# botoes fisicos ficam inertes aqui para nao mexerem no menu que
		# esta atras enquanto o operador digita.
		return

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


func _reload_for_resize() -> void:
	call_deferred("_reload_current_scene")


func _reload_current_scene() -> void:
	get_tree().reload_current_scene()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	var key: InputEventKey = event as InputEventKey
	# Com o formulario aberto o operador esta digitando: BACKSPACE tem
	# de apagar caractere, nao fechar a tela. So F9 e ESC saem.
	if _in_song_form:
		if key.keycode == KEY_F9 or key.keycode == KEY_ESCAPE:
			_handle_back()
		return

	if (
		key.keycode == KEY_F9
		or key.keycode == KEY_ESCAPE
		or key.keycode == KEY_BACKSPACE
	):
		_handle_back()


func _handle_back() -> void:
	if _in_song_form:
		_close_song_form()
		return
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
		MenuItem.NEW_SONG:
			_open_song_form()
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
	if _menu_labels.size() < MENU_ITEM_COUNT:
		return

	_menu_labels[MenuItem.MODE].text = (
		"MODO: CRÉDITO" if ArcadeSettings.is_credit_mode() else "MODO: LIVRE"
	)
	_menu_labels[MenuItem.CREDITS].text = "CRÉDITOS: %d   (B: +1)" % ArcadeSettings.credits
	_menu_labels[MenuItem.NEW_SONG].text = "MÚSICAS: %d CADASTRADA(S)" % (
		USER_CATALOG.all_user_songs().size()
	)
	_menu_labels[MenuItem.LED_INPUT_TEST].text = "TESTE DE LEDS E INPUTS"

	var client := get_node_or_null("/root/LedClient")
	var forced: String = ""
	if client != null and client.has_method("forced_port"):
		forced = str(client.call("forced_port"))
	_menu_labels[MenuItem.COM_PORT].text = (
		"PORTA: COM5 (FORÇADA)" if not forced.is_empty() else "PORTA: AUTOMÁTICA"
	)
	_menu_labels[MenuItem.BACK].text = "VOLTAR"
	if _top_status_label != null:
		_top_status_label.text = (
			"MODO CRÉDITO  •  %02d CRÉDITOS" % ArcadeSettings.credits
			if ArcadeSettings.is_credit_mode()
			else "MODO LIVRE  •  START LIBERADO"
		)

	for i in range(_menu_labels.size()):
		var label: Label = _menu_labels[i]
		if i == _cursor:
			label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.20, 1.0))
		else:
			label.add_theme_color_override("font_color", Color.WHITE)
		if i < _menu_rows.size():
			_menu_rows[i].add_theme_stylebox_override("panel", _row_style(i == _cursor))


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
	_center = Vector2(screen.x * 0.5, screen.y - bottom_margin - _radius)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, _screen), Color(0.001, 0.003, 0.010, 1.0), true)
	draw_circle(_center, _radius * 1.012, Color(0.04, 0.48, 0.72, 0.20), true)
	draw_circle(_center, _radius, Color(0.004, 0.010, 0.028, 1.0), true)

	var now: float = float(Time.get_ticks_msec()) / 1000.0
	for index in range(34):
		var seed: float = float(index) * 17.173
		var angle: float = fmod(absf(sin(seed) * 931.77), TAU) + now * (0.006 + float(index % 3) * 0.004)
		var orbit: float = _radius * (0.12 + fmod(absf(cos(seed * 0.73)) * 7.31, 0.78))
		var sparkle: float = 0.5 + 0.5 * sin(now * (1.1 + float(index % 4) * 0.21) + seed)
		var position_value: Vector2 = _center + Vector2(cos(angle), sin(angle)) * orbit
		var color: Color = Color(0.32, 0.82, 1.0) if index % 3 != 0 else Color(0.86, 0.44, 1.0)
		draw_circle(position_value, maxf(1.0, _radius * (0.0022 + sparkle * 0.0018)), Color(color.r, color.g, color.b, 0.28 + sparkle * 0.55), true)

	draw_arc(_center, _radius * 0.985, 0.0, TAU, 220, Color(0.20, 0.86, 1.0, 0.55), maxf(3.0, _radius * 0.008), true)
	draw_arc(_center, _radius * 0.955, 0.0, TAU, 220, Color(0.82, 0.28, 1.0, 0.22), maxf(1.0, _radius * 0.0025), true)


func _build_menu(screen: Vector2) -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 10
	add_child(_hud_layer)

	var font: Font = _load_font()
	var margin: float = screen.x * 0.022
	var top_height: float = screen.y * 0.205

	_top_panel = Panel.new()
	_top_panel.position = Vector2(margin, margin)
	_top_panel.size = Vector2(screen.x - margin * 2.0, top_height)
	_top_panel.add_theme_stylebox_override("panel", _top_panel_style())
	_hud_layer.add_child(_top_panel)

	var top_title: Label = _make_label("CONFIGURAÇÕES DA MÁQUINA", int(top_height * 0.22), HORIZONTAL_ALIGNMENT_LEFT, font)
	top_title.position = Vector2(top_height * 0.13, top_height * 0.08)
	top_title.size = Vector2(_top_panel.size.x * 0.58, top_height * 0.34)
	top_title.add_theme_color_override("font_color", Color(0.18, 0.88, 1.0, 1.0))
	_top_panel.add_child(top_title)

	var top_hint: Label = _make_label("SELECT / F9 PARA FECHAR  •  PAINEL DO OPERADOR", int(top_height * 0.10), HORIZONTAL_ALIGNMENT_LEFT, font)
	top_hint.position = Vector2(top_height * 0.14, top_height * 0.47)
	top_hint.size = Vector2(_top_panel.size.x * 0.58, top_height * 0.24)
	top_hint.add_theme_color_override("font_color", Color(0.68, 0.75, 0.88, 1.0))
	_top_panel.add_child(top_hint)

	_top_status_label = _make_label("", int(top_height * 0.13), HORIZONTAL_ALIGNMENT_CENTER, font)
	_top_status_label.position = Vector2(_top_panel.size.x * 0.66, top_height * 0.20)
	_top_status_label.size = Vector2(_top_panel.size.x * 0.30, top_height * 0.45)
	_top_status_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.24, 1.0))
	_top_panel.add_child(_top_status_label)

	var panel_size := Vector2(_radius * 1.58, _radius * 1.58)

	_panel = Panel.new()
	_panel.position = _center - panel_size * 0.5
	_panel.size = panel_size
	_panel.add_theme_stylebox_override("panel", _panel_style())
	_hud_layer.add_child(_panel)

	var title: Label = _make_label(
		"CONFIGURAÇÕES",
		int(_radius * 0.075),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	title.position = Vector2(panel_size.x * 0.08, panel_size.y * 0.055)
	title.size = Vector2(panel_size.x * 0.84, panel_size.y * 0.12)
	title.add_theme_color_override("font_color", Color(0.10, 0.85, 1.0, 1.0))
	_panel.add_child(title)

	var start_y: float = panel_size.y * 0.205
	var row_height: float = panel_size.y * 0.102
	for i in range(MENU_ITEM_COUNT):
		var row := Panel.new()
		row.position = Vector2(panel_size.x * 0.14, start_y + row_height * float(i))
		row.size = Vector2(panel_size.x * 0.72, row_height * 0.78)
		row.add_theme_stylebox_override("panel", _row_style(false))
		_panel.add_child(row)
		_menu_rows.append(row)

		var label: Label = _make_label(
			"",
			int(_radius * 0.044),
			HORIZONTAL_ALIGNMENT_CENTER,
			font
		)
		label.size = row.size
		label.clip_text = true
		row.add_child(label)
		_menu_labels.append(label)

	var hint: Label = _make_label(
		"A: NAVEGAR    B: CONFIRMAR    SELECT: VOLTAR",
		int(_radius * 0.026),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	hint.position = Vector2(panel_size.x * 0.10, panel_size.y * 0.84)
	hint.size = Vector2(panel_size.x * 0.80, panel_size.y * 0.08)
	hint.add_theme_color_override("font_color", Color(0.60, 0.66, 0.78, 1.0))
	_panel.add_child(hint)


# ---------------------------------------------------------------
# CADASTRO RAPIDO DE MUSICA
# ---------------------------------------------------------------
## Formulario de servico: nome, audio, video, capa e BPM. Os arquivos
## escolhidos sao COPIADOS para user:// (ver user_catalog.gd), entao a
## musica continua funcionando mesmo que o operador mova ou apague o
## arquivo original depois.
func _open_song_form() -> void:
	if _song_layer == null or not is_instance_valid(_song_layer):
		_build_song_form(get_viewport_rect().size)

	_in_song_form = true
	_panel.visible = false
	_song_layer.visible = true
	# O formulario precisa de mouse e teclado; o resto do gabinete roda
	# com o cursor escondido.
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_refresh_song_form()
	_song_name_edit.grab_focus()


func _close_song_form() -> void:
	_in_song_form = false
	if _song_layer != null and is_instance_valid(_song_layer):
		_song_layer.visible = false
	if _panel != null and is_instance_valid(_panel):
		_panel.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	_refresh_menu_texts()


func _build_song_form(screen: Vector2) -> void:
	var font: Font = _load_font()

	_song_layer = CanvasLayer.new()
	_song_layer.layer = 30
	_song_layer.visible = false
	add_child(_song_layer)

	var panel_size := Vector2(
		minf(screen.x * 0.78, _radius * 2.30),
		minf(screen.y * 0.74, _radius * 1.86)
	)
	_song_panel = Panel.new()
	_song_panel.position = _center - panel_size * 0.5
	_song_panel.size = panel_size
	_song_panel.add_theme_stylebox_override("panel", _panel_style())
	_song_layer.add_child(_song_panel)

	var margin: float = panel_size.x * 0.055
	var width: float = panel_size.x - margin * 2.0
	var line: float = panel_size.y * 0.082

	var title: Label = _make_label(
		"NOVA MÚSICA",
		int(panel_size.y * 0.070),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	title.position = Vector2(margin, panel_size.y * 0.035)
	title.size = Vector2(width, line)
	title.add_theme_color_override("font_color", Color(0.10, 0.85, 1.0, 1.0))
	_song_panel.add_child(title)

	var y: float = panel_size.y * 0.145

	# --- nome ---
	_add_form_caption(font, "NOME DA MÚSICA", margin, y, width, line * 0.52)
	_song_name_edit = LineEdit.new()
	_song_name_edit.position = Vector2(margin, y + line * 0.50)
	_song_name_edit.size = Vector2(width * 0.66, line * 0.86)
	_song_name_edit.placeholder_text = "EX: MINHA MÚSICA"
	_song_name_edit.max_length = 40
	_song_panel.add_child(_song_name_edit)

	# --- bpm ---
	var bpm_caption: Label = _make_label(
		"BPM",
		int(panel_size.y * 0.030),
		HORIZONTAL_ALIGNMENT_LEFT,
		font
	)
	bpm_caption.position = Vector2(margin + width * 0.70, y)
	bpm_caption.size = Vector2(width * 0.30, line * 0.52)
	bpm_caption.add_theme_color_override("font_color", Color(0.66, 0.74, 0.88, 1.0))
	_song_panel.add_child(bpm_caption)

	_song_bpm_edit = SpinBox.new()
	_song_bpm_edit.position = Vector2(margin + width * 0.70, y + line * 0.50)
	_song_bpm_edit.size = Vector2(width * 0.30, line * 0.86)
	_song_bpm_edit.min_value = 40
	_song_bpm_edit.max_value = 260
	_song_bpm_edit.step = 1
	_song_bpm_edit.value = 120
	_song_panel.add_child(_song_bpm_edit)

	y += line * 1.65

	# --- arquivos ---
	_song_audio_label = _add_file_row(
		font, "ÁUDIO (obrigatório)", margin, y, width, line, "_pick_audio"
	)
	y += line * 1.30
	_song_video_label = _add_file_row(
		font, "VÍDEO .ogv (opcional)", margin, y, width, line, "_pick_video"
	)
	y += line * 1.30
	_song_cover_label = _add_file_row(
		font, "CAPA (opcional)", margin, y, width, line, "_pick_cover"
	)
	y += line * 1.42

	# --- acoes ---
	var save_button := Button.new()
	save_button.text = "CADASTRAR MÚSICA"
	save_button.position = Vector2(margin, y)
	save_button.size = Vector2(width * 0.48, line * 0.95)
	save_button.pressed.connect(_save_new_song)
	_song_panel.add_child(save_button)

	var close_button := Button.new()
	close_button.text = "FECHAR"
	close_button.position = Vector2(margin + width * 0.52, y)
	close_button.size = Vector2(width * 0.22, line * 0.95)
	close_button.pressed.connect(_close_song_form)
	_song_panel.add_child(close_button)

	var remove_button := Button.new()
	remove_button.text = "APAGAR ÚLTIMA"
	remove_button.position = Vector2(margin + width * 0.76, y)
	remove_button.size = Vector2(width * 0.24, line * 0.95)
	remove_button.pressed.connect(_remove_last_song)
	_song_panel.add_child(remove_button)

	y += line * 1.20

	_song_status_label = _make_label("", int(panel_size.y * 0.030), HORIZONTAL_ALIGNMENT_LEFT, font)
	_song_status_label.position = Vector2(margin, y)
	_song_status_label.size = Vector2(width, line * 0.60)
	_song_status_label.clip_text = true
	_song_panel.add_child(_song_status_label)

	_song_list_label = _make_label("", int(panel_size.y * 0.026), HORIZONTAL_ALIGNMENT_LEFT, font)
	_song_list_label.position = Vector2(margin, y + line * 0.62)
	_song_list_label.size = Vector2(width, line * 0.80)
	_song_list_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_song_list_label.clip_text = true
	_song_list_label.add_theme_color_override("font_color", Color(0.62, 0.70, 0.84, 1.0))
	_song_panel.add_child(_song_list_label)


func _add_form_caption(
	font: Font,
	text_value: String,
	x: float,
	y: float,
	width: float,
	height: float
) -> Label:
	var caption: Label = _make_label(
		text_value,
		int(_song_panel.size.y * 0.030),
		HORIZONTAL_ALIGNMENT_LEFT,
		font
	)
	caption.position = Vector2(x, y)
	caption.size = Vector2(width, height)
	caption.add_theme_color_override("font_color", Color(0.66, 0.74, 0.88, 1.0))
	_song_panel.add_child(caption)
	return caption


## Linha de arquivo: legenda, caminho escolhido e botao que abre o
## seletor de arquivos do sistema.
func _add_file_row(
	font: Font,
	caption_text: String,
	x: float,
	y: float,
	width: float,
	line: float,
	handler: String
) -> Label:
	_add_form_caption(font, caption_text, x, y, width, line * 0.52)

	var value: Label = _make_label(
		"— nenhum arquivo —",
		int(_song_panel.size.y * 0.028),
		HORIZONTAL_ALIGNMENT_LEFT,
		font
	)
	value.position = Vector2(x, y + line * 0.50)
	value.size = Vector2(width * 0.72, line * 0.62)
	value.clip_text = true
	value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_song_panel.add_child(value)

	var button := Button.new()
	button.text = "ESCOLHER..."
	button.position = Vector2(x + width * 0.76, y + line * 0.44)
	button.size = Vector2(width * 0.24, line * 0.72)
	button.pressed.connect(Callable(self, handler))
	_song_panel.add_child(button)

	return value


func _pick_audio() -> void:
	_open_file_dialog(
		"Escolha o áudio da música",
		PackedStringArray(["*.mp3 ; MP3", "*.ogg ; OGG", "*.wav ; WAV"]),
		"_on_audio_chosen"
	)


func _pick_video() -> void:
	_open_file_dialog(
		"Escolha o vídeo de fundo",
		PackedStringArray(["*.ogv ; Vídeo Theora (.ogv)"]),
		"_on_video_chosen"
	)


func _pick_cover() -> void:
	_open_file_dialog(
		"Escolha a capa",
		PackedStringArray(["*.png ; PNG", "*.jpg, *.jpeg ; JPG", "*.webp ; WEBP"]),
		"_on_cover_chosen"
	)


func _open_file_dialog(
	title: String,
	filters: PackedStringArray,
	handler: String
) -> void:
	var dialog := FileDialog.new()
	dialog.title = title
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	# ACCESS_FILESYSTEM: o operador escolhe de qualquer pasta do
	# computador, nao so de dentro do projeto.
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = filters
	dialog.use_native_dialog = true
	dialog.size = Vector2i(900, 600)
	dialog.file_selected.connect(Callable(self, handler))
	dialog.close_requested.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()


func _on_audio_chosen(path: String) -> void:
	_song_audio_path = path
	if _song_name_edit != null and _song_name_edit.text.strip_edges().is_empty():
		# Sugere o nome pelo proprio arquivo: na pratica e o que o
		# operador digitaria de qualquer jeito.
		_song_name_edit.text = path.get_file().get_basename().replace("_", " ").to_upper()
	_refresh_song_form()


func _on_video_chosen(path: String) -> void:
	_song_video_path = path
	_refresh_song_form()


func _on_cover_chosen(path: String) -> void:
	_song_cover_path = path
	_refresh_song_form()


func _refresh_song_form() -> void:
	if _song_audio_label == null or not is_instance_valid(_song_audio_label):
		return

	_song_audio_label.text = (
		_song_audio_path.get_file() if not _song_audio_path.is_empty() else "— nenhum arquivo —"
	)
	_song_video_label.text = (
		_song_video_path.get_file() if not _song_video_path.is_empty() else "— sem vídeo —"
	)
	_song_cover_label.text = (
		_song_cover_path.get_file() if not _song_cover_path.is_empty() else "— sem capa —"
	)

	var user_songs: Array = USER_CATALOG.all_user_songs()
	if user_songs.is_empty():
		_song_list_label.text = "Nenhuma música cadastrada ainda."
	else:
		var names: Array[String] = []
		for value in user_songs:
			if value is Dictionary:
				names.append(str((value as Dictionary).get("title", "?")))
		_song_list_label.text = "Cadastradas: " + ", ".join(names)


func _save_new_song() -> void:
	var result: Dictionary = USER_CATALOG.add_song(
		_song_name_edit.text,
		_song_audio_path,
		_song_video_path,
		_song_cover_path,
		float(_song_bpm_edit.value)
	)

	if not bool(result.get("ok", false)):
		_song_status_label.add_theme_color_override("font_color", Color(1.0, 0.42, 0.42, 1.0))
		_song_status_label.text = str(result.get("erro", "Falha ao cadastrar."))
		return

	_song_status_label.add_theme_color_override("font_color", Color(0.32, 1.0, 0.62, 1.0))
	_song_status_label.text = "Música cadastrada! Já aparece no seletor."
	_song_name_edit.text = ""
	_song_audio_path = ""
	_song_video_path = ""
	_song_cover_path = ""
	_refresh_song_form()


func _remove_last_song() -> void:
	var user_songs: Array = USER_CATALOG.all_user_songs()
	if user_songs.is_empty():
		_song_status_label.add_theme_color_override("font_color", Color(1.0, 0.72, 0.30, 1.0))
		_song_status_label.text = "Não há música cadastrada para apagar."
		return

	var last: Variant = user_songs[user_songs.size() - 1]
	if not last is Dictionary:
		return

	var title: String = str((last as Dictionary).get("title", "?"))
	if USER_CATALOG.remove_song(str((last as Dictionary).get("id", ""))):
		_song_status_label.add_theme_color_override("font_color", Color(0.32, 1.0, 0.62, 1.0))
		_song_status_label.text = "Removida: " + title
	else:
		_song_status_label.add_theme_color_override("font_color", Color(1.0, 0.42, 0.42, 1.0))
		_song_status_label.text = "Não foi possível remover."
	_refresh_song_form()


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

	var margin: float = screen.x * 0.022
	var top_height: float = screen.y * 0.205
	var test_top := Panel.new()
	test_top.position = Vector2(margin, margin)
	test_top.size = Vector2(screen.x - margin * 2.0, top_height)
	test_top.add_theme_stylebox_override("panel", _top_panel_style())
	_test_layer.add_child(test_top)

	var title: Label = _make_label(
		"TESTE DE LEDS E INPUTS",
		int(top_height * 0.22),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	title.position = Vector2(top_height * 0.13, top_height * 0.08)
	title.size = Vector2(test_top.size.x * 0.55, top_height * 0.34)
	title.add_theme_color_override("font_color", Color(0.10, 0.85, 1.0, 1.0))
	test_top.add_child(title)

	_test_status_label = _make_label(
		"",
		int(top_height * 0.12),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	_test_status_label.position = Vector2(test_top.size.x * 0.52, top_height * 0.20)
	_test_status_label.size = Vector2(test_top.size.x * 0.44, top_height * 0.40)
	test_top.add_child(_test_status_label)

	var box_size := Vector2.ONE * (_radius * 0.23)
	var lane_orbit: float = _radius * 0.60

	for i in range(LANE_COUNT):
		var angle: float = -PI * 0.5 + TAU * float(i) / float(LANE_COUNT)
		var box := Panel.new()
		box.position = _center + Vector2(cos(angle), sin(angle)) * lane_orbit - box_size * 0.5
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
	_start_box.size = box_size * 1.35
	_start_box.position = _center - _start_box.size * 0.5
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
		"APERTE OS BOTÕES FÍSICOS   •   SELECT / F9: VOLTAR",
		int(_radius * 0.027),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	hint.position = Vector2(_center.x - _radius * 0.68, _center.y + _radius * 0.76)
	hint.size = Vector2(_radius * 1.36, _radius * 0.10)
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
	style.set_corner_radius_all(999)
	style.shadow_color = Color(0.10, 0.85, 1.0, 0.20)
	style.shadow_size = 14
	return style


func _top_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.006, 0.014, 0.038, 0.97)
	style.border_color = Color(0.16, 0.84, 1.0, 0.72)
	style.set_border_width_all(3)
	style.set_corner_radius_all(30)
	style.shadow_color = Color(0.10, 0.72, 1.0, 0.24)
	style.shadow_size = 16
	return style


func _row_style(selected: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.07, 0.015, 0.92) if selected else Color(0.012, 0.028, 0.065, 0.88)
	style.border_color = Color(1.0, 0.82, 0.20, 0.90) if selected else Color(0.24, 0.62, 0.90, 0.38)
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
