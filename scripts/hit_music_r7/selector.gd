extends Node2D

const CATALOG: Script = preload("res://scripts/hit_music_r7/catalog.gd")
const LED_CLIENT: Script = preload("res://scripts/hit_music_r7/led_client.gd")
const TAP_PALETTE: Script = preload("res://scripts/hit_music_r7/tap_palette.gd")
const USER_CATALOG: Script = preload("res://scripts/hit_music_r7/user_catalog.gd")

const TOP_MARGIN_RATIO: float = 0.022
const TOP_HEIGHT_RATIO: float = 0.205
const TOP_GAP_RATIO: float = 0.024
const SIDE_MARGIN_RATIO: float = 0.015
const BOTTOM_MARGIN_RATIO: float = 0.012
const CIRCLE_SCALE: float = 0.985
const PREVIEW_DELAY: float = 0.75
const PREVIEW_ALPHA: float = 0.62
const CARD_SPACING_RATIO: float = 0.205
const CATEGORY_ORDER: Array[String] = [
	"ANIME", "INFANTIL", "ROCK", "POP", "ELETRONICA",
	"FUNK", "HIP HOP", "SERTANEJO", "GOSPEL", "CLASSICA", "OUTROS",
]

## Botao que desce na lista — definido em led_client.gd, que e a fonte
## unica do mapeamento fisico. Passou do input_d (lane 3) para o
## input_e (lane 4).
const DOWN_ACTION: String = LED_CLIENT.NAV_DOWN_ACTION
const DOWN_LANE_INDEX: int = LED_CLIENT.NAV_DOWN_LANE

var _songs: Array = []
var _index: int = 0
var _difficulty: String = "easy"
var _center: Vector2 = Vector2.ZERO
var _radius: float = 100.0
var _lane_positions: PackedVector2Array = PackedVector2Array()
var _video_rect: Rect2 = Rect2()
var _preview_wait: float = 0.0
var _transitioning: bool = false
## Ao trocar de cena, Input.is_action_just_pressed ainda pode permanecer
## verdadeiro ate o fim do frame. Sem esta quarentena, o B usado para sair
## do resultado chega ao seletor novo e inicia a musica imediatamente.
const INPUT_RELEASE_ARM_SECONDS: float = 0.18
var _input_armed: bool = false
var _input_release_time: float = 0.0
var _visual_time: float = 0.0

var _video: VideoStreamPlayer
var _preview_audio: AudioStreamPlayer
var _nav_sfx: AudioStreamPlayer
var _ui: CanvasLayer
var _top_panel: Panel
var _brand_label: Label
var _subtitle_label: Label
var _instruction_label: Label
var _difficulty_label: Label
var _content_root: Control
var _list_root: Control
var _info_panel: Panel
var _cover_frame: Panel
var _cover: TextureRect
var _track_badge: Panel
var _track_label: Label
var _category_label: Label
var _song_name: Label
var _bpm_label: Label
var _record_label: Label
var _hard_record_label: Label
var _start_panel: Panel
var _start_label: Label
var _cards: Array[Panel] = []
var _card_labels: Array[Label] = []
var _card_track_labels: Array[Label] = []
var _card_covers: Array[TextureRect] = []
var _nav_up_chip: Panel
var _nav_down_chip: Panel
var _nav_hold_direction: int = 0
var _nav_hold_elapsed: float = 0.0
var _nav_hold_repeat_elapsed: float = 0.0


func _ready() -> void:
	_input_armed = false
	_input_release_time = 0.0
	Engine.max_fps = 60
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	_songs = CATALOG.all_songs()
	if _songs.is_empty():
		push_error("Catalogo Hit Music vazio.")
		return
	_group_songs_by_category()

	if get_tree().has_meta("hit_music_selector_index"):
		_index = clampi(
			int(get_tree().get_meta("hit_music_selector_index")),
			0,
			_songs.size() - 1
		)

	if get_tree().has_meta("hit_music_selector_difficulty"):
		_difficulty = str(get_tree().get_meta("hit_music_selector_difficulty"))

	if _difficulty != "hard":
		_difficulty = "easy"

	_calculate_geometry()
	_build_scene()
	_apply_selection(true)
	get_viewport().size_changed.connect(_on_viewport_size_changed)


func _process(delta: float) -> void:
	_visual_time += delta

	var menu_input_ready: bool = _update_input_arming(delta)
	if not _transitioning and menu_input_ready:
		# A sobe na lista, E desce (ver DOWN_ACTION). O sentido tem que
		# bater com a posicao fisica dos botoes no gabinete.
		if _action_pressed("input_a") or _action_pressed("ui_up") or _action_pressed("ui_left"):
			_change_selection(-1)
		elif _action_pressed(DOWN_ACTION) or _action_pressed("ui_down") or _action_pressed("ui_right"):
			_change_selection(1)

		if _action_pressed("input_b") or _action_pressed("input_start") or _action_pressed("ui_accept"):
			_start_selected()

		_preview_wait += delta
		if _preview_wait >= PREVIEW_DELAY and _video.stream != null and not _video.is_playing():
			_video.play()
			if _preview_audio.stream != null:
				_preview_audio.play()
			var preview_tween: Tween = create_tween()
			preview_tween.set_trans(Tween.TRANS_QUINT)
			preview_tween.set_ease(Tween.EASE_OUT)
			preview_tween.tween_property(_video, "modulate:a", PREVIEW_ALPHA, 0.48)

	_update_card_animation(delta)
	_update_nav_hold(delta)
	_update_live_styles()
	queue_redraw()


## Libera a navegacao somente depois de todos os comandos envolvidos na
## troca de tela permanecerem soltos. A trava vale tanto para B quanto START,
## portanto nenhum botao residual reinicia uma fase ao voltar ao catalogo.
func _update_input_arming(delta: float) -> bool:
	if _input_armed:
		return true

	var actions: Array[String] = [
		"input_a", "input_b", DOWN_ACTION, "input_start",
		"ui_up", "ui_down", "ui_left", "ui_right", "ui_accept",
	]
	for action in actions:
		if InputMap.has_action(action) and Input.is_action_pressed(action):
			_input_release_time = 0.0
			return false

	_input_release_time += delta
	if _input_release_time >= INPUT_RELEASE_ARM_SECONDS:
		_input_armed = true
	return _input_armed


func _draw() -> void:
	var screen: Vector2 = get_viewport_rect().size
	var primary: Color = _song_primary(_songs[_index] as Dictionary)
	var accent: Color = _song_accent(_songs[_index] as Dictionary)
	var pulse: float = 0.5 + 0.5 * sin(_visual_time * 1.7)

	draw_rect(Rect2(Vector2.ZERO, screen), Color.BLACK, true)
	draw_circle(_center, _radius * 1.028, Color(primary.r, primary.g, primary.b, 0.040), true)
	draw_circle(_center, _radius * 1.010, Color(0.0, 0.0, 0.0, 0.98), true)
	draw_circle(_center, _radius * 0.997, _dark_color(), true)

	draw_arc(
		_center,
		_radius * 1.003,
		0.0,
		TAU,
		260,
		Color(primary.r, primary.g, primary.b, 0.18 + pulse * 0.06),
		maxf(4.0, _radius * 0.012),
		true
	)
	draw_arc(
		_center,
		_radius * 0.982,
		0.0,
		TAU,
		260,
		Color(accent.r, accent.g, accent.b, 0.12),
		maxf(1.0, _radius * 0.0025),
		true
	)

	# Fundo exclusivo do seletor: radar quadrado + constelacao orbital.
	# Sao poucas primitivas, sem o renderer pesado do gameplay.
	var grid_rotation: float = _visual_time * 0.035
	for layer in range(1, 5):
		var half_size: float = _radius * (0.16 + float(layer) * 0.15)
		var points := PackedVector2Array()
		for corner in range(5):
			var square_angle: float = grid_rotation * (-1.0 if layer % 2 == 0 else 1.0) + PI * 0.25 + TAU * float(corner) / 4.0
			points.append(_center + Vector2(cos(square_angle), sin(square_angle)) * half_size)
		draw_polyline(points, Color(primary.r, primary.g, primary.b, 0.055 + float(layer) * 0.012), maxf(1.0, _radius * 0.0018), true)

	for index in range(24):
		var angle: float = -_visual_time * 0.055 + TAU * float(index) / 24.0
		var direction := Vector2(cos(angle), sin(angle))
		var orbit: float = _radius * (0.28 + 0.025 * float(index % 6))
		var point_position: Vector2 = _center + direction * orbit
		var color: Color = primary if index % 2 == 0 else accent
		var sparkle: float = 0.5 + 0.5 * sin(_visual_time * 1.8 + float(index) * 0.73)
		draw_circle(point_position, _radius * (0.003 + sparkle * 0.002), Color(color.r, color.g, color.b, 0.28 + sparkle * 0.32), true)

	_draw_nav_arrows()


func _input(event: InputEvent) -> void:
	if _transitioning:
		return

	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed:
			_handle_touch(touch.position)
		else:
			_stop_nav_hold()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse: InputEventMouseButton = event
		if mouse.pressed:
			_handle_touch(mouse.position)
		else:
			_stop_nav_hold()


func _handle_touch(position_value: Vector2) -> void:
	if _nav_up_chip != null and Rect2(
		_nav_up_chip.global_position,
		_nav_up_chip.size
	).has_point(position_value):
		_start_nav_hold(-1)
		return
	if _nav_down_chip != null and Rect2(
		_nav_down_chip.global_position,
		_nav_down_chip.size
	).has_point(position_value):
		_start_nav_hold(1)
		return

	if _difficulty_label != null and Rect2(
		_difficulty_label.global_position,
		_difficulty_label.size
	).has_point(position_value):
		_toggle_difficulty()
		return

	for card_index in range(_cards.size()):
		var card: Panel = _cards[card_index]
		if not card.visible:
			continue
		if Rect2(card.global_position, card.size).has_point(position_value):
			if card_index == _index:
				_start_selected()
			else:
				_index = card_index
				_apply_selection(false)
			return

	if _start_panel != null and Rect2(_start_panel.global_position, _start_panel.size).has_point(position_value):
		_start_selected()
		return

	if _info_panel != null and Rect2(_info_panel.global_position, _info_panel.size).has_point(position_value):
		_start_selected()


func _calculate_geometry() -> void:
	var screen: Vector2 = get_viewport_rect().size
	var side_margin: float = maxf(4.0, screen.x * SIDE_MARGIN_RATIO)
	var bottom_margin: float = maxf(4.0, screen.y * BOTTOM_MARGIN_RATIO)
	var top_reserved: float = screen.y * (
		TOP_MARGIN_RATIO + TOP_HEIGHT_RATIO + TOP_GAP_RATIO
	)
	var radius_by_width: float = (screen.x - side_margin * 2.0) * 0.5
	var radius_by_height: float = (screen.y - top_reserved - bottom_margin) * 0.5

	_radius = maxf(120.0, minf(radius_by_width, radius_by_height) * CIRCLE_SCALE)
	_center = Vector2(screen.x * 0.5, screen.y - bottom_margin - _radius)

	_lane_positions = PackedVector2Array()
	for lane in range(8):
		var angle: float = -PI * 0.5 + TAU * float(lane) / 8.0
		_lane_positions.append(
			_center + Vector2(cos(angle), sin(angle)) * _radius * 0.905
		)

	_video_rect = Rect2(
		_center - Vector2.ONE * _radius,
		Vector2.ONE * (_radius * 2.0)
	)


func _build_scene() -> void:
	_preview_audio = AudioStreamPlayer.new()
	_preview_audio.name = "ScenarioPreviewAudio"
	_preview_audio.bus = "Master"
	_preview_audio.volume_db = -7.0
	add_child(_preview_audio)

	_nav_sfx = AudioStreamPlayer.new()
	_nav_sfx.name = "NavigationFeedback"
	_nav_sfx.bus = "Master"
	_nav_sfx.volume_db = -4.0
	_nav_sfx.stream = _make_navigation_tone()
	add_child(_nav_sfx)

	_video = VideoStreamPlayer.new()
	_video.position = _video_rect.position
	_video.size = _video_rect.size
	_video.expand = true
	_video.loop = true
	_video.volume_db = -80.0
	_video.modulate.a = 0.0
	_video.z_index = 2
	_video.material = _circular_video_material()
	add_child(_video)

	_ui = CanvasLayer.new()
	_ui.layer = 30
	add_child(_ui)

	var screen: Vector2 = get_viewport_rect().size
	var margin: float = screen.x * TOP_MARGIN_RATIO
	var top_height: float = screen.y * TOP_HEIGHT_RATIO
	var font: Font = _load_font()

	_top_panel = Panel.new()
	_top_panel.position = Vector2(margin, margin)
	_top_panel.size = Vector2(screen.x - margin * 2.0, top_height)
	_top_panel.pivot_offset = _top_panel.size * 0.5
	_top_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_top_panel)

	_brand_label = _make_label(
		"HIT MUSIC",
		int(top_height * 0.235),
		HORIZONTAL_ALIGNMENT_LEFT,
		font
	)
	_brand_label.position = Vector2(top_height * 0.12, top_height * 0.055)
	_brand_label.size = Vector2(_top_panel.size.x * 0.84, top_height * 0.34)
	_top_panel.add_child(_brand_label)

	_subtitle_label = _make_label(
		"ESCOLHA SUA MÚSICA  •  RITMO  •  PRECISÃO  •  ENERGIA",
		int(top_height * 0.105),
		HORIZONTAL_ALIGNMENT_LEFT,
		font
	)
	_subtitle_label.position = Vector2(top_height * 0.13, top_height * 0.34)
	_subtitle_label.size = Vector2(_top_panel.size.x * 0.84, top_height * 0.20)
	_subtitle_label.clip_text = true
	_fit_label_to_width(_subtitle_label, _subtitle_label.size.x, int(top_height * 0.105), int(top_height * 0.072))
	_subtitle_label.add_theme_color_override("font_color", Color(0.72, 0.78, 0.90, 1.0))
	_top_panel.add_child(_subtitle_label)

	_instruction_label = _make_label(
		"LED A  SUBIR     LED B  JOGAR     LED E  DESCER",
		int(top_height * 0.10),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	_instruction_label.position = Vector2(top_height * 0.10, top_height * 0.65)
	_instruction_label.size = Vector2(_top_panel.size.x - top_height * 0.20, top_height * 0.22)
	_instruction_label.add_theme_color_override("font_color", Color(0.78, 0.83, 0.93, 1.0))
	_instruction_label.clip_text = true
	_fit_label_to_width(_instruction_label, _instruction_label.size.x, int(top_height * 0.10), int(top_height * 0.07))
	_top_panel.add_child(_instruction_label)

	_content_root = Control.new()
	_content_root.position = _center - Vector2(_radius, _radius)
	_content_root.size = Vector2(_radius * 2.0, _radius * 2.0)
	_content_root.pivot_offset = _content_root.size * 0.5
	_content_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_content_root)

	_list_root = Control.new()
	_list_root.position = Vector2.ZERO
	_list_root.size = _content_root.size
	_list_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_root.add_child(_list_root)

	_build_cards(font)
	_build_info_panel(font)
	_build_nav_hints(font)


## Coordenadas (em espaco do _content_root) das dicas de navegacao.
## Ficam TODAS dentro do circulo e proximas do botao fisico que
## representam: subir em cima da lista, descer embaixo da lista e
## start a direita, embaixo do painel da musica. A lista ocupa
## x 0.19R..0.97R (centro 0.58R) e o painel de info x 1.03R..1.78R.
const NAV_LIST_CENTER_X: float = 0.58
const NAV_UP_CHIP_Y: float = 0.335
const NAV_DOWN_CHIP_Y: float = 1.485
const NAV_UP_ARROW_Y: float = 0.235
const NAV_DOWN_ARROW_Y: float = 1.545
## Dicas de navegacao com a acao escrita em vez da letra do botao —
## quem joga nao precisa conhecer o mapeamento A/D do gabinete.
func _build_nav_hints(font: Font) -> void:
	var hints := [
		{
			"text": "SUBIR",
			"center": Vector2(NAV_LIST_CENTER_X, NAV_UP_CHIP_Y),
			"size": Vector2(0.30, 0.082),
			"accent": false,
		},
		{
			"text": "DESCER",
			"center": Vector2(NAV_LIST_CENTER_X, NAV_DOWN_CHIP_Y),
			"size": Vector2(0.30, 0.082),
			"accent": false,
		},
		# O START real fica abaixo da playlist. Mantemos uma unica leitura
		# visual, alinhada ao botao fisico, sem duplicar a acao no painel.
	]

	for hint_value in hints:
		var hint: Dictionary = hint_value
		var chip_size: Vector2 = Vector2(hint["size"]) * _radius
		var chip_center: Vector2 = Vector2(hint["center"]) * _radius
		var is_accent: bool = bool(hint["accent"])

		var chip := Panel.new()
		chip.size = chip_size
		chip.position = chip_center - chip_size * 0.5
		chip.pivot_offset = chip_size * 0.5
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_theme_stylebox_override("panel", _nav_hint_style(is_accent))
		_content_root.add_child(chip)
		if str(hint["text"]) == "SUBIR":
			_nav_up_chip = chip
		elif str(hint["text"]) == "DESCER":
			_nav_down_chip = chip

		var label := _make_label(
			str(hint["text"]),
			int(_radius * (0.034 if is_accent else 0.029)),
			HORIZONTAL_ALIGNMENT_CENTER,
			font
		)
		label.position = Vector2.ZERO
		label.size = chip_size
		label.add_theme_color_override(
			"font_color",
			Color(1.0, 0.90, 0.42, 1.0) if is_accent else Color(0.82, 0.89, 1.0, 1.0)
		)
		_fit_label_to_width(
			label,
			chip_size.x * 0.86,
			int(_radius * (0.034 if is_accent else 0.029)),
			int(_radius * 0.015)
		)
		chip.add_child(label)


## Pilula moderna: cantos totalmente arredondados, fundo quase preto
## translucido e borda fina. O chip de START usa a cor de destaque
## pra se diferenciar dos dois de navegacao.
func _nav_hint_style(accent: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = (
		Color(0.10, 0.075, 0.015, 0.88)
		if accent
		else Color(0.015, 0.030, 0.060, 0.84)
	)
	style.border_color = (
		Color(1.0, 0.82, 0.22, 0.72)
		if accent
		else Color(0.34, 0.66, 0.95, 0.42)
	)
	style.set_border_width_all(2)
	style.set_corner_radius_all(999)
	return style


## Converte coordenada local do _content_root para a tela, pra que o
## _draw() (Node2D) desenhe alinhado com os chips (Control).
func _content_to_screen(local_position: Vector2) -> Vector2:
	return _center - Vector2(_radius, _radius) + local_position


## Setas acima e abaixo da lista. Desenhadas como triangulos em vez
## de caracteres "▲/▼" porque a fonte do jogo (Bungee) nao tem esses
## glifos — viraria quadradinho vazio na tela.
func _draw_nav_arrows() -> void:
	var pulse: float = 0.5 + 0.5 * sin(_visual_time * 3.1)
	var color := Color(0.42, 0.78, 1.0, 0.55 + pulse * 0.40)
	var size: float = _radius * 0.032

	_draw_triangle(
		_content_to_screen(Vector2(NAV_LIST_CENTER_X, NAV_UP_ARROW_Y) * _radius),
		size,
		true,
		color
	)
	_draw_triangle(
		_content_to_screen(Vector2(NAV_LIST_CENTER_X, NAV_DOWN_ARROW_Y) * _radius),
		size,
		false,
		color
	)


func _draw_triangle(
	position_value: Vector2,
	size: float,
	pointing_up: bool,
	color: Color
) -> void:
	var direction: float = -1.0 if pointing_up else 1.0
	var points := PackedVector2Array([
		position_value + Vector2(0.0, size * direction),
		position_value + Vector2(-size * 1.15, -size * 0.62 * direction),
		position_value + Vector2(size * 1.15, -size * 0.62 * direction),
	])
	draw_colored_polygon(points, color)

	var outline := points.duplicate()
	outline.append(outline[0])
	draw_polyline(
		outline,
		Color(1.0, 1.0, 1.0, color.a * 0.55),
		maxf(1.5, size * 0.16),
		true
	)


func _build_cards(font: Font) -> void:
	_cards.clear()
	_card_labels.clear()
	_card_track_labels.clear()
	_card_covers.clear()

	var card_size := Vector2(_radius * 0.78, _radius * 0.145)
	for song_index in range(_songs.size()):
		var song: Dictionary = _songs[song_index] as Dictionary
		var card := Panel.new()
		card.size = card_size
		card.pivot_offset = card.size * 0.5
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_list_root.add_child(card)

		var cover := TextureRect.new()
		cover.position = Vector2(card.size.y * 0.09, card.size.y * 0.09)
		cover.size = Vector2(card.size.y * 0.82, card.size.y * 0.82)
		cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		# Exibe a arte inteira no espaco da propria musica: sem zoom e sem corte.
		cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cover.texture = _load_texture(str(song.get("cover", "")))
		card.add_child(cover)

		var text_x: float = cover.position.x + cover.size.x + card.size.x * 0.045
		var text_width: float = card.size.x - text_x - card.size.x * 0.035
		var track := _make_label(
			"TRACK %02d" % (song_index + 1),
			int(_radius * 0.025),
			HORIZONTAL_ALIGNMENT_LEFT,
			font
		)
		track.position = Vector2(text_x, card.size.y * 0.04)
		track.size = Vector2(text_width * 0.48, card.size.y * 0.30)
		track.add_theme_color_override("font_color", Color(0.64, 0.72, 0.84, 1.0))
		card.add_child(track)

		var card_category := _make_label(
			_song_category(song),
			int(_radius * 0.021),
			HORIZONTAL_ALIGNMENT_RIGHT,
			font
		)
		card_category.position = Vector2(text_x + text_width * 0.48, card.size.y * 0.04)
		card_category.size = Vector2(text_width * 0.52, card.size.y * 0.30)
		card_category.add_theme_color_override("font_color", _category_color(_song_category(song)))
		_fit_label_to_width(card_category, card_category.size.x, int(_radius * 0.021), int(_radius * 0.015))
		card.add_child(card_category)

		var label := _make_label(
			str(song.get("title", "TRACK")),
			int(_radius * 0.043),
			HORIZONTAL_ALIGNMENT_LEFT,
			font
		)
		label.position = Vector2(text_x, card.size.y * 0.30)
		label.size = Vector2(card.size.x - text_x - card.size.x * 0.035, card.size.y * 0.66)
		label.clip_text = true
		_fit_label_to_width(label, label.size.x, int(_radius * 0.043), int(_radius * 0.023))
		card.add_child(label)

		_cards.append(card)
		_card_labels.append(label)
		_card_track_labels.append(track)
		_card_covers.append(cover)


func _build_info_panel(font: Font) -> void:
	_info_panel = Panel.new()
	_info_panel.position = Vector2(_radius * 1.03, _radius * 0.365)
	_info_panel.size = Vector2(_radius * 0.75, _radius * 1.19)
	_info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_root.add_child(_info_panel)

	_cover_frame = Panel.new()
	# Mantem o card no mesmo tamanho, mas recupera espaco vertical que antes
	# ficava preso em margens e intervalos grandes demais.
	_cover_frame.position = Vector2(_info_panel.size.x * 0.055, _info_panel.size.y * 0.018)
	_cover_frame.size = Vector2(_info_panel.size.x * 0.89, _info_panel.size.y * 0.315)
	_cover_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info_panel.add_child(_cover_frame)

	_cover = TextureRect.new()
	_cover.position = Vector2(_cover_frame.size.x * 0.025, _cover_frame.size.y * 0.04)
	_cover.size = Vector2(_cover_frame.size.x * 0.95, _cover_frame.size.y * 0.92)
	_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# Mostra 100% da capa no quadro, preservando a proporcao original.
	_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover_frame.add_child(_cover)

	_track_badge = Panel.new()
	_track_badge.position = Vector2(_info_panel.size.x * 0.055, _info_panel.size.y * 0.345)
	_track_badge.size = Vector2(_info_panel.size.x * 0.46, _info_panel.size.y * 0.086)
	_info_panel.add_child(_track_badge)

	_track_label = _make_label(
		"TRACK 01",
		int(_radius * 0.034),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	_track_label.size = _track_badge.size
	_track_badge.add_child(_track_label)

	# Um unico indicador integrado ao card substitui as duas janelas do topo.
	# Alem de mais limpo, ele continua permitindo alternar o nivel por toque.
	_difficulty_label = _make_label(
		"NÍVEL  •  FÁCIL",
		int(_radius * 0.032),
		HORIZONTAL_ALIGNMENT_RIGHT,
		font
	)
	_difficulty_label.position = Vector2(_info_panel.size.x * 0.535, _info_panel.size.y * 0.345)
	_difficulty_label.size = Vector2(_info_panel.size.x * 0.41, _info_panel.size.y * 0.086)
	_difficulty_label.clip_text = true
	_info_panel.add_child(_difficulty_label)

	_category_label = _make_label(
		"CATEGORIA  •  ANIME",
		int(_radius * 0.034),
		HORIZONTAL_ALIGNMENT_LEFT,
		font
	)
	_category_label.position = Vector2(_info_panel.size.x * 0.055, _info_panel.size.y * 0.590)
	_category_label.size = Vector2(_info_panel.size.x * 0.89, _info_panel.size.y * 0.062)
	_category_label.clip_text = true
	_info_panel.add_child(_category_label)

	_song_name = _make_label(
		"TRACK",
		int(_radius * 0.074),
		HORIZONTAL_ALIGNMENT_LEFT,
		font
	)
	_song_name.position = Vector2(_info_panel.size.x * 0.055, _info_panel.size.y * 0.432)
	_song_name.size = Vector2(_info_panel.size.x * 0.89, _info_panel.size.y * 0.156)
	_song_name.autowrap_mode = TextServer.AUTOWRAP_OFF
	_song_name.clip_text = true
	_info_panel.add_child(_song_name)

	_bpm_label = _make_label(
		"120 BPM",
		int(_radius * 0.046),
		HORIZONTAL_ALIGNMENT_LEFT,
		font
	)
	_bpm_label.position = Vector2(_info_panel.size.x * 0.055, _info_panel.size.y * 0.652)
	_bpm_label.size = Vector2(_info_panel.size.x * 0.89, _info_panel.size.y * 0.078)
	_bpm_label.clip_text = true
	_bpm_label.add_theme_color_override("font_color", Color(0.72, 0.86, 1.0, 1.0))
	_info_panel.add_child(_bpm_label)

	_record_label = _make_label(
		"RECORDE FÁCIL  0.00%",
		int(_radius * 0.033),
		HORIZONTAL_ALIGNMENT_LEFT,
		font
	)
	_record_label.position = Vector2(_info_panel.size.x * 0.055, _info_panel.size.y * 0.731)
	_record_label.size = Vector2(_info_panel.size.x * 0.89, _info_panel.size.y * 0.074)
	_record_label.clip_text = true
	_info_panel.add_child(_record_label)

	_hard_record_label = _make_label(
		"RECORDE DIFÍCIL  0.00%",
		int(_radius * 0.033),
		HORIZONTAL_ALIGNMENT_LEFT,
		font
	)
	_hard_record_label.position = Vector2(_info_panel.size.x * 0.055, _info_panel.size.y * 0.808)
	_hard_record_label.size = Vector2(_info_panel.size.x * 0.89, _info_panel.size.y * 0.074)
	_hard_record_label.clip_text = true
	_info_panel.add_child(_hard_record_label)

	_start_panel = Panel.new()
	_start_panel.position = Vector2(_info_panel.size.x * 0.055, _info_panel.size.y * 0.895)
	_start_panel.size = Vector2(_info_panel.size.x * 0.89, _info_panel.size.y * 0.088)
	_info_panel.add_child(_start_panel)

	_start_label = _make_label(
		"LED B  •  JOGAR",
		int(_radius * 0.041),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	_start_label.size = _start_panel.size
	_start_label.clip_text = true
	_start_panel.add_child(_start_label)


func _change_selection(direction: int) -> void:
	_index = posmod(_index + direction, _songs.size())
	_apply_selection(false)
	_play_navigation_feedback(direction)


func _start_nav_hold(direction: int) -> void:
	_nav_hold_direction = -1 if direction < 0 else 1
	_nav_hold_elapsed = 0.0
	_nav_hold_repeat_elapsed = 0.0
	_set_nav_pressed(_nav_hold_direction, true)
	_change_selection(_nav_hold_direction)


func _stop_nav_hold() -> void:
	if _nav_hold_direction == 0:
		return
	_set_nav_pressed(_nav_hold_direction, false)
	_nav_hold_direction = 0
	_nav_hold_elapsed = 0.0
	_nav_hold_repeat_elapsed = 0.0


func _update_nav_hold(delta: float) -> void:
	if _nav_hold_direction == 0:
		return
	_nav_hold_elapsed += delta
	if _nav_hold_elapsed < 0.42:
		return
	_nav_hold_repeat_elapsed += delta
	if _nav_hold_repeat_elapsed >= 0.16:
		_nav_hold_repeat_elapsed = 0.0
		_change_selection(_nav_hold_direction)


func _set_nav_pressed(direction: int, pressed: bool) -> void:
	var chip: Panel = _nav_up_chip if direction < 0 else _nav_down_chip
	if chip == null:
		return
	chip.add_theme_stylebox_override("panel", _nav_hint_style(pressed))
	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(chip, "scale", Vector2.ONE * (0.92 if pressed else 1.0), 0.10)


func _play_navigation_feedback(direction: int) -> void:
	if _nav_sfx != null:
		_nav_sfx.stop()
		_nav_sfx.pitch_scale = 1.18 if direction < 0 else 0.82
		_nav_sfx.play()
	if direction < 0:
		LED_CLIENT.hit_lane(LED_CLIENT.NAV_NEXT_LANE, _song_primary(_songs[_index] as Dictionary), 170)
	else:
		LED_CLIENT.hit_lane(LED_CLIENT.NAV_DOWN_LANE, _song_accent(_songs[_index] as Dictionary), 170)


func _toggle_difficulty() -> void:
	_difficulty = "hard" if _difficulty == "easy" else "easy"
	_apply_selection(false)


func _apply_selection(immediate: bool) -> void:
	if _songs.is_empty():
		return

	var song: Dictionary = _songs[_index] as Dictionary
	_track_label.text = "TRACK %02d / %02d" % [_index + 1, _songs.size()]
	_difficulty_label.text = "NÍVEL  •  " + ("DIFÍCIL" if _difficulty == "hard" else "FÁCIL")
	_fit_label_to_width(_difficulty_label, _difficulty_label.size.x, int(_radius * 0.032), int(_radius * 0.023))
	_category_label.text = "CATEGORIA  •  " + _song_category(song)
	_fit_label_to_width(_category_label, _category_label.size.x, int(_radius * 0.034), int(_radius * 0.024))
	_song_name.text = str(song.get("title", "TRACK"))
	_bpm_label.text = "%d BPM" % int(round(float(song.get("bpm", 120.0))))
	_record_label.text = "RECORDE FÁCIL   " + _best_record(song, "easy")
	_hard_record_label.text = "RECORDE DIFÍCIL   " + _best_record(song, "hard")
	_cover.texture = _load_texture(str(song.get("cover", "")))
	_fit_label_to_width(_song_name, _song_name.size.x, int(_radius * 0.074), int(_radius * 0.035))
	_fit_label_to_width(_record_label, _record_label.size.x, int(_radius * 0.033), int(_radius * 0.024))
	_fit_label_to_width(_hard_record_label, _hard_record_label.size.x, int(_radius * 0.033), int(_radius * 0.024))

	_load_preview(song)
	_update_cards(immediate)
	_update_live_styles()
	LED_CLIENT.menu_state_three(
		_song_primary(song),
		LED_CLIENT.MENU_SELECT_COLOR,
		_song_accent(song),
		LED_CLIENT.NAV_NEXT_LANE,
		LED_CLIENT.NAV_SELECT_LANE,
		LED_CLIENT.NAV_DOWN_LANE
	)
func _update_cards(immediate: bool) -> void:
	var total: int = _cards.size()
	for card_index in range(total):
		var card: Panel = _cards[card_index]
		var relative: int = card_index - _index
		if relative > total / 2:
			relative -= total
		elif relative < -total / 2:
			relative += total

		var target_y: float = _radius * 0.91 + float(relative) * _radius * CARD_SPACING_RATIO
		# Todos os cards compartilham exatamente o eixo dos botoes SUBIR/DESCER.
		# O destaque cresce pelo pivot central, sem empurrar o item selecionado.
		var card_width_ratio: float = 0.78
		var target_x: float = _radius * (NAV_LIST_CENTER_X - card_width_ratio * 0.5)
		var visible_range: bool = abs(relative) <= 2
		var target_scale: Vector2 = (
			Vector2(1.055, 1.055)
			if relative == 0
			else Vector2(0.91, 0.91)
		)
		var target_alpha: float = (
			1.0
			if relative == 0
			else (0.62 if visible_range else 0.0)
		)

		card.set_meta("target_position", Vector2(target_x, target_y))
		card.set_meta("target_scale", target_scale)
		card.set_meta("target_alpha", target_alpha)
		card.set_meta("relative", relative)
		card.add_theme_stylebox_override(
			"panel",
			_card_style(_songs[card_index] as Dictionary, relative == 0)
		)

		_card_labels[card_index].add_theme_color_override(
			"font_color",
			Color.WHITE if relative == 0 else Color(0.72, 0.77, 0.86, 1.0)
		)

		if immediate:
			card.position = card.get_meta("target_position")
			card.scale = card.get_meta("target_scale")
			card.modulate.a = float(card.get_meta("target_alpha"))
			card.visible = card.modulate.a > 0.01


func _update_card_animation(delta: float) -> void:
	var position_factor: float = 1.0 - exp(-12.0 * delta)
	var alpha_factor: float = 1.0 - exp(-15.0 * delta)
	var scale_factor: float = 1.0 - exp(-10.0 * delta)

	for card in _cards:
		var target_position: Vector2 = card.get_meta("target_position", card.position)
		var target_scale: Vector2 = card.get_meta("target_scale", card.scale)
		var target_alpha: float = float(card.get_meta("target_alpha", card.modulate.a))

		card.position = card.position.lerp(target_position, position_factor)
		card.scale = card.scale.lerp(target_scale, scale_factor)
		card.modulate.a = lerpf(card.modulate.a, target_alpha, alpha_factor)
		card.visible = card.modulate.a > 0.01


func _update_live_styles() -> void:
	if _songs.is_empty():
		return

	var song: Dictionary = _songs[_index] as Dictionary
	var primary: Color = _song_primary(song)
	var accent: Color = _song_accent(song)
	var pulse: float = 0.5 + 0.5 * sin(_visual_time * 2.2)

	_top_panel.add_theme_stylebox_override("panel", _top_style(song, pulse))
	_info_panel.add_theme_stylebox_override("panel", _info_style(song, pulse))
	_cover_frame.add_theme_stylebox_override("panel", _cover_style(song))
	_track_badge.add_theme_stylebox_override("panel", _badge_style(primary))
	_start_panel.add_theme_stylebox_override("panel", _start_style(song, pulse))
	_brand_label.add_theme_color_override("font_color", Color.WHITE)
	_subtitle_label.add_theme_color_override(
		"font_color",
		Color(primary.r, primary.g, primary.b, 0.92)
	)
	_track_label.add_theme_color_override("font_color", Color.WHITE)
	_difficulty_label.add_theme_color_override(
		"font_color",
		accent if _difficulty == "hard" else primary.lerp(Color.WHITE, 0.24)
	)
	_category_label.add_theme_color_override("font_color", _category_color(_song_category(song)))
	_bpm_label.add_theme_color_override("font_color", primary)
	_record_label.add_theme_color_override("font_color", Color.WHITE)
	_hard_record_label.add_theme_color_override("font_color", accent.lerp(Color.WHITE, 0.35))
	_start_label.add_theme_color_override("font_color", Color.WHITE)


## Categorias sao dados reais do catalogo. A ordem fixa cria blocos continuos
## na playlist e evita que musicas infantis se misturem com anime ou rock.
func _song_category(song: Dictionary) -> String:
	var category: String = str(song.get("category", "OUTROS")).strip_edges().to_upper()
	return category if not category.is_empty() else "OUTROS"


func _group_songs_by_category() -> void:
	var original_songs: Array = _songs.duplicate()
	var grouped_songs: Array = []
	for category in CATEGORY_ORDER:
		for song_value in original_songs:
			var song_item: Dictionary = song_value as Dictionary
			if _song_category(song_item) == category:
				grouped_songs.append(song_item)

	# Mantem musicas futuras sem categoria no fim, sem remove-las do menu.
	for remaining_value in original_songs:
		var remaining_song: Dictionary = remaining_value as Dictionary
		if not CATEGORY_ORDER.has(_song_category(remaining_song)):
			grouped_songs.append(remaining_song)
	_songs = grouped_songs


func _category_color(category: String) -> Color:
	match category.to_upper():
		"ANIME":
			return Color8(255, 79, 184)
		"ROCK":
			return Color8(255, 106, 42)
		"INFANTIL":
			return Color8(36, 216, 255)
		"POP":
			return Color8(255, 86, 178)
		"ELETRONICA":
			return Color8(42, 235, 220)
		"FUNK":
			return Color8(188, 86, 255)
		"HIP HOP":
			return Color8(255, 191, 54)
		"SERTANEJO":
			return Color8(255, 136, 56)
		"GOSPEL":
			return Color8(98, 173, 255)
		"CLASSICA":
			return Color8(210, 200, 255)
		_:
			return Color8(154, 168, 199)


func _load_preview(song: Dictionary) -> void:
	_preview_wait = 0.0
	if _video.is_playing():
		_video.stop()
	_video.stream = null
	_video.modulate.a = 0.0
	if _preview_audio.playing:
		_preview_audio.stop()
	_preview_audio.stream = null

	# Passa pelo USER_CATALOG: a musica pode ser de fabrica (res://) ou
	# cadastrada pelo operador (user://, sem importacao do Godot).
	_video.stream = USER_CATALOG.load_video(str(song.get("video", "")))
	_preview_audio.stream = USER_CATALOG.load_audio(str(song.get("audio", "")))


func _start_selected() -> void:
	if _transitioning or _songs.is_empty():
		return

	_transitioning = true
	var song: Dictionary = _songs[_index] as Dictionary
	get_tree().set_meta("hit_music_song_id", str(song.get("id", "")))
	get_tree().set_meta("hit_music_difficulty", _difficulty)
	get_tree().set_meta("hit_music_selector_index", _index)
	get_tree().set_meta("hit_music_selector_difficulty", _difficulty)
	LED_CLIENT.clear_all()

	var scene_path: String = str(song.get("scene", ""))
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		_transitioning = false
		push_error("Scene nao encontrada: " + scene_path)
		return

	if _preview_audio.playing:
		var audio_fade: Tween = create_tween()
		audio_fade.tween_property(_preview_audio, "volume_db", -28.0, 0.42)

	# Transicao nos proprios elementos: nenhum desenho ou mascara por cima.
	var exit_tween: Tween = create_tween()
	exit_tween.set_parallel(true)
	exit_tween.set_trans(Tween.TRANS_QUINT)
	exit_tween.set_ease(Tween.EASE_IN_OUT)
	exit_tween.tween_property(self, "modulate:a", 0.0, 0.48)
	exit_tween.tween_property(_top_panel, "modulate:a", 0.0, 0.40)
	exit_tween.tween_property(_content_root, "modulate:a", 0.0, 0.44)
	exit_tween.finished.connect(
		func() -> void:
			get_tree().change_scene_to_file(scene_path)
	)


func _best_record(song: Dictionary, difficulty_name: String) -> String:
	var path: String = "user://hit_music_records.json"
	if not FileAccess.file_exists(path):
		return "0.00%"

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "0.00%"

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return "0.00%"

	var song_id: String = str(song.get("id", ""))
	var value: Variant = (parsed as Dictionary).get(song_id, {})
	if not value is Dictionary:
		return "0.00%"

	var record: Dictionary = value as Dictionary
	var key: String = "dificil" if difficulty_name == "hard" else "facil"
	return "%.2f%%" % float(record.get(key, 0.0))


func _on_viewport_size_changed() -> void:
	get_tree().set_meta("hit_music_selector_index", _index)
	get_tree().set_meta("hit_music_selector_difficulty", _difficulty)
	call_deferred("_reload_after_resize")


func _reload_after_resize() -> void:
	get_tree().reload_current_scene()


func _action_pressed(action: String) -> bool:
	return InputMap.has_action(action) and Input.is_action_just_pressed(action)


func _circular_video_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;

void fragment() {
	vec4 source_color = texture(TEXTURE, UV);
	float distance_value = distance(UV, vec2(0.5));
	float mask_value = 1.0 - smoothstep(0.488, 0.500, distance_value);
	COLOR = vec4(source_color.rgb, source_color.a * mask_value);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material


func _load_font() -> Font:
	for path in [
		"res://fonts/Bungee-Regular.ttf",
		"res://fonts/Oxanium-VariableFont_wght.ttf",
	]:
		if ResourceLoader.exists(path):
			var resource: Resource = load(path)
			if resource is Font:
				return resource as Font
	return ThemeDB.fallback_font


## Som curto e limpo gerado no proprio jogo. A subida usa pitch mais alto e
## a descida mais baixo, permitindo reconhecer a direcao sem olhar a tela.
func _make_navigation_tone() -> AudioStreamWAV:
	var mix_rate: int = 44100
	var duration: float = 0.095
	var sample_count: int = int(float(mix_rate) * duration)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for index in range(sample_count):
		var time_value: float = float(index) / float(mix_rate)
		var progress: float = float(index) / float(maxi(1, sample_count - 1))
		var envelope: float = sin(PI * progress) * (1.0 - progress * 0.28)
		var wave: float = (
			sin(TAU * 720.0 * time_value)
			+ sin(TAU * 1440.0 * time_value) * 0.22
		) * 0.72 * envelope
		data.encode_s16(index * 2, int(clampf(wave, -1.0, 1.0) * 32767.0))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = data
	return stream


func _load_texture(path: String) -> Texture2D:
	return USER_CATALOG.load_cover(path)


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
	label.add_theme_font_size_override("font_size", maxi(12, font_size))
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.98))
	label.add_theme_constant_override("outline_size", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## Encolhe a fonte do label ate o texto caber na largura reservada.
## Titulos de musica tem tamanhos bem diferentes ("SOUL" x "CARMINE -
## ONE PIECE"); com tamanho fixo os longos vazavam o card ou eram
## cortados no meio da palavra pelo clip_text. Aqui o texto sempre
## aparece inteiro, so menor quando precisa.
func _fit_label_to_width(
	label: Label,
	max_width: float,
	base_font_size: int,
	min_font_size: int = 10
) -> void:
	if label == null or not is_instance_valid(label):
		return
	if max_width <= 0.0 or label.text.is_empty():
		return

	var font: Font = label.get_theme_font("font")
	if font == null:
		return

	var size_value: int = maxi(base_font_size, min_font_size)
	while size_value > min_font_size:
		var measured: float = font.get_string_size(
			label.text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			size_value
		).x
		if measured <= max_width:
			break
		size_value -= 1

	label.add_theme_font_size_override("font_size", size_value)


func _song_primary(song: Dictionary) -> Color:
	var colors_value: Variant = song.get("colors", {})
	if colors_value is Dictionary:
		return TAP_PALETTE.vivid_theme(
			(colors_value as Dictionary).get("primary", TAP_PALETTE.TAP_CYAN)
		)
	return TAP_PALETTE.TAP_CYAN


func _song_accent(song: Dictionary) -> Color:
	var colors_value: Variant = song.get("colors", {})
	if colors_value is Dictionary:
		return TAP_PALETTE.vivid_theme(
			(colors_value as Dictionary).get("accent", TAP_PALETTE.TAP_YELLOW)
		)
	return TAP_PALETTE.TAP_YELLOW


func _dark_color() -> Color:
	if _songs.is_empty():
		return Color(0.01, 0.02, 0.05, 1.0)
	var colors_value: Variant = (_songs[_index] as Dictionary).get("colors", {})
	if colors_value is Dictionary:
		return (colors_value as Dictionary).get("dark", Color(0.01, 0.02, 0.05, 1.0))
	return Color(0.01, 0.02, 0.05, 1.0)


func _top_style(song: Dictionary, pulse: float) -> StyleBoxFlat:
	var primary: Color = _song_primary(song)
	var accent: Color = _song_accent(song)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.004, 0.008, 0.022, 0.975)
	style.border_color = primary.lerp(accent, pulse * 0.22)
	style.border_color.a = 0.78
	style.set_border_width_all(3)
	style.set_corner_radius_all(28)
	style.shadow_color = Color(primary.r, primary.g, primary.b, 0.16 + pulse * 0.06)
	style.shadow_size = 16
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	return style


func _info_style(song: Dictionary, pulse: float) -> StyleBoxFlat:
	var primary: Color = _song_primary(song)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.004, 0.008, 0.021, 0.94)
	style.border_color = Color(primary.r, primary.g, primary.b, 0.54 + pulse * 0.12)
	style.set_border_width_all(2)
	style.set_corner_radius_all(28)
	style.shadow_color = Color(primary.r, primary.g, primary.b, 0.18)
	style.shadow_size = 13
	return style


func _cover_style(song: Dictionary) -> StyleBoxFlat:
	var primary: Color = _song_primary(song)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.75)
	style.border_color = Color(primary.r, primary.g, primary.b, 0.72)
	style.set_border_width_all(2)
	style.set_corner_radius_all(20)
	style.shadow_color = Color(primary.r, primary.g, primary.b, 0.16)
	style.shadow_size = 8
	return style


func _badge_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.r, color.g, color.b, 0.16)
	style.border_color = Color(color.r, color.g, color.b, 0.72)
	style.set_border_width_all(2)
	style.set_corner_radius_all(18)
	return style


func _difficulty_style(song: Dictionary, selected: bool) -> StyleBoxFlat:
	var primary: Color = _song_primary(song)
	var accent: Color = _song_accent(song)
	var color: Color = accent if selected else primary
	var style := StyleBoxFlat.new()
	style.bg_color = (
		Color(color.r, color.g, color.b, 0.24)
		if selected
		else Color(0.009, 0.016, 0.034, 0.90)
	)
	style.border_color = (
		Color(color.r, color.g, color.b, 0.96)
		if selected
		else Color(0.50, 0.58, 0.72, 0.20)
	)
	style.set_border_width_all(2)
	style.set_corner_radius_all(20)
	style.shadow_color = Color(color.r, color.g, color.b, 0.18 if selected else 0.0)
	style.shadow_size = 8 if selected else 0
	return style


func _start_style(song: Dictionary, pulse: float) -> StyleBoxFlat:
	var primary: Color = _song_primary(song)
	var accent: Color = _song_accent(song)
	var color: Color = primary.lerp(accent, 0.30 + pulse * 0.22)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.r, color.g, color.b, 0.20 + pulse * 0.05)
	style.border_color = Color(color.r, color.g, color.b, 0.98)
	style.set_border_width_all(3)
	style.set_corner_radius_all(22)
	style.shadow_color = Color(color.r, color.g, color.b, 0.30 + pulse * 0.10)
	style.shadow_size = 12
	return style


func _card_style(song: Dictionary, selected: bool) -> StyleBoxFlat:
	var primary: Color = _song_primary(song)
	var accent: Color = _song_accent(song)
	var style := StyleBoxFlat.new()
	style.bg_color = (
		Color(0.015, 0.027, 0.055, 0.98)
		if selected
		else Color(0.005, 0.010, 0.024, 0.88)
	)
	style.border_color = (
		Color(accent.r, accent.g, accent.b, 0.98)
		if selected
		else Color(primary.r, primary.g, primary.b, 0.22)
	)
	style.border_width_left = 7 if selected else 2
	style.border_width_top = 3 if selected else 1
	style.border_width_right = 3 if selected else 1
	style.border_width_bottom = 3 if selected else 1
	style.set_corner_radius_all(24)
	style.shadow_color = Color(primary.r, primary.g, primary.b, 0.26 if selected else 0.06)
	style.shadow_size = 12 if selected else 3
	return style
