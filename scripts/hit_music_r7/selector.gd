extends Node2D

const CATALOG: Script = preload("res://scripts/hit_music_r7/catalog.gd")
const RENDERER_SCRIPT: Script = preload("res://scripts/hit_music_r7/playfield_renderer.gd")
const LED_CLIENT: Script = preload("res://scripts/hit_music_r7/led_client.gd")

const TOP_MARGIN_RATIO: float = 0.022
const TOP_HEIGHT_RATIO: float = 0.205
const TOP_GAP_RATIO: float = 0.024
const SIDE_MARGIN_RATIO: float = 0.015
const BOTTOM_MARGIN_RATIO: float = 0.012
const CIRCLE_SCALE: float = 0.985
const PREVIEW_DELAY: float = 1.2

var _songs: Array = []
var _index: int = 0
var _difficulty: String = "easy"
var _center: Vector2 = Vector2.ZERO
var _radius: float = 100.0
var _lane_positions: PackedVector2Array = PackedVector2Array()
var _video_rect: Rect2 = Rect2()
var _preview_wait: float = 0.0
var _transitioning: bool = false

var _video: VideoStreamPlayer
var _renderer
var _ui: CanvasLayer
var _top_panel: Panel
var _title: Label
var _difficulty_label: Label
var _instructions: Label
var _list_root: Control
var _info_panel: Panel
var _cover: TextureRect
var _song_name: Label
var _song_counter: Label
var _record_label: Label
var _start_label: Label
var _cards: Array[Panel] = []


func _ready() -> void:
	Engine.max_fps = 60
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_songs = CATALOG.all_songs()
	if _songs.is_empty():
		push_error("Hit Music catalog is empty.")
		return

	if get_tree().has_meta("hit_music_selector_index"):
		_index = clampi(int(get_tree().get_meta("hit_music_selector_index")), 0, _songs.size() - 1)
	if get_tree().has_meta("hit_music_selector_difficulty"):
		_difficulty = str(get_tree().get_meta("hit_music_selector_difficulty"))
	if _difficulty != "hard":
		_difficulty = "easy"

	_calculate_geometry()
	_build_scene()
	_apply_selection(true)
	get_viewport().size_changed.connect(_on_viewport_size_changed)


func _process(delta: float) -> void:
	if _transitioning:
		return

	if _action_pressed("input_a") or _action_pressed("ui_down") or _action_pressed("ui_right"):
		_change_selection(1)
	elif _action_pressed("ui_up") or _action_pressed("ui_left"):
		_change_selection(-1)

	if _action_pressed("input_b"):
		_toggle_difficulty()

	if _action_pressed("input_start") or _action_pressed("ui_accept"):
		_start_selected()

	_preview_wait += delta
	if _preview_wait >= PREVIEW_DELAY and _video.stream != null and not _video.is_playing():
		_video.play()

	_renderer.set_runtime([], 0.0, "selector", Vector2.ZERO, false)
	_update_card_animation(delta)
	queue_redraw()


func _draw() -> void:
	var screen: Vector2 = get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, screen), Color.BLACK, true)
	draw_circle(_center, _radius * 1.012, Color(0.0, 0.0, 0.0, 0.98), true)
	draw_circle(_center, _radius * 0.995, _dark_color(), true)


func _input(event: InputEvent) -> void:
	if _transitioning:
		return

	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if not touch.pressed:
			return
		_handle_touch(touch.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse: InputEventMouseButton = event
		if mouse.pressed:
			_handle_touch(mouse.position)


func _handle_touch(position_value: Vector2) -> void:
	if _top_panel != null:
		var difficulty_rect := Rect2(
			_difficulty_label.global_position,
			_difficulty_label.size
		)
		if difficulty_rect.has_point(position_value):
			_toggle_difficulty()
			return

	for card_index in range(_cards.size()):
		var card: Panel = _cards[card_index]
		if not card.visible:
			continue
		var rect := Rect2(card.global_position, card.size)
		if rect.has_point(position_value):
			if card_index == _index:
				_start_selected()
			else:
				_index = card_index
				_apply_selection(false)
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
		_center - Vector2(_radius * 0.75, _radius * 0.29),
		Vector2(_radius * 1.50, _radius * 0.58)
	)


func _build_scene() -> void:
	_video = VideoStreamPlayer.new()
	_video.position = _video_rect.position
	_video.size = _video_rect.size
	_video.expand = true
	_video.loop = true
	_video.volume_db = -80.0
	_video.z_index = 2
	add_child(_video)

	_renderer = RENDERER_SCRIPT.new()
	_renderer.z_index = 10
	add_child(_renderer)

	_ui = CanvasLayer.new()
	_ui.layer = 30
	add_child(_ui)

	var screen: Vector2 = get_viewport_rect().size
	var margin: float = screen.x * TOP_MARGIN_RATIO
	var top_height: float = screen.y * TOP_HEIGHT_RATIO

	_top_panel = Panel.new()
	_top_panel.position = Vector2(margin, margin)
	_top_panel.size = Vector2(screen.x - margin * 2.0, top_height)
	_ui.add_child(_top_panel)

	var font: Font = _load_font()
	_title = _make_label("SELECT MUSIC", int(top_height * 0.25), HORIZONTAL_ALIGNMENT_LEFT, font)
	_title.position = Vector2(top_height * 0.12, top_height * 0.08)
	_title.size = Vector2(_top_panel.size.x * 0.54, top_height * 0.38)
	_top_panel.add_child(_title)

	_difficulty_label = _make_label("FACIL", int(top_height * 0.21), HORIZONTAL_ALIGNMENT_RIGHT, font)
	_difficulty_label.position = Vector2(_top_panel.size.x * 0.64, top_height * 0.08)
	_difficulty_label.size = Vector2(_top_panel.size.x * 0.31, top_height * 0.38)
	_top_panel.add_child(_difficulty_label)

	_instructions = _make_label(
		"A: NEXT    B: DIFFICULTY    START: PLAY",
		int(top_height * 0.12),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	_instructions.position = Vector2(top_height * 0.08, top_height * 0.57)
	_instructions.size = Vector2(_top_panel.size.x - top_height * 0.16, top_height * 0.25)
	_top_panel.add_child(_instructions)

	_list_root = Control.new()
	_list_root.position = _center - Vector2(_radius, _radius)
	_list_root.size = Vector2(_radius * 2.0, _radius * 2.0)
	_list_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_list_root)

	_build_cards(font)
	_build_info_panel(font)


func _build_cards(font: Font) -> void:
	_cards.clear()
	var list_position := Vector2(_radius * 0.22, _radius * 0.39)
	var list_size := Vector2(_radius * 0.72, _radius * 1.15)
	var card_height: float = list_size.y / 5.25

	for song_index in range(_songs.size()):
		var card := Panel.new()
		card.position = list_position + Vector2(0.0, float(song_index) * card_height)
		card.size = Vector2(list_size.x, card_height * 0.80)
		card.pivot_offset = card.size * 0.5
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_list_root.add_child(card)

		var label := _make_label(
			str((_songs[song_index] as Dictionary).get("title", "TRACK")),
			int(_radius * 0.032),
			HORIZONTAL_ALIGNMENT_LEFT,
			font
		)
		label.position = Vector2(card.size.x * 0.06, 0.0)
		label.size = Vector2(card.size.x * 0.88, card.size.y)
		label.clip_text = true
		card.add_child(label)
		_cards.append(card)


func _build_info_panel(font: Font) -> void:
	_info_panel = Panel.new()
	_info_panel.position = Vector2(_radius * 1.02, _radius * 0.39)
	_info_panel.size = Vector2(_radius * 0.74, _radius * 1.15)
	_info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list_root.add_child(_info_panel)

	_cover = TextureRect.new()
	_cover.position = Vector2(_info_panel.size.x * 0.07, _info_panel.size.y * 0.06)
	_cover.size = Vector2(_info_panel.size.x * 0.86, _info_panel.size.y * 0.35)
	_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info_panel.add_child(_cover)

	_song_counter = _make_label("TRACK 01", int(_radius * 0.027), HORIZONTAL_ALIGNMENT_LEFT, font)
	_song_counter.position = Vector2(_info_panel.size.x * 0.07, _info_panel.size.y * 0.44)
	_song_counter.size = Vector2(_info_panel.size.x * 0.86, _info_panel.size.y * 0.08)
	_info_panel.add_child(_song_counter)

	_song_name = _make_label("SONG", int(_radius * 0.043), HORIZONTAL_ALIGNMENT_LEFT, font)
	_song_name.position = Vector2(_info_panel.size.x * 0.07, _info_panel.size.y * 0.52)
	_song_name.size = Vector2(_info_panel.size.x * 0.86, _info_panel.size.y * 0.17)
	_song_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_panel.add_child(_song_name)

	_record_label = _make_label("BEST 0.00%", int(_radius * 0.029), HORIZONTAL_ALIGNMENT_LEFT, font)
	_record_label.position = Vector2(_info_panel.size.x * 0.07, _info_panel.size.y * 0.72)
	_record_label.size = Vector2(_info_panel.size.x * 0.86, _info_panel.size.y * 0.09)
	_info_panel.add_child(_record_label)

	_start_label = _make_label("TOUCH OR START", int(_radius * 0.030), HORIZONTAL_ALIGNMENT_CENTER, font)
	_start_label.position = Vector2(_info_panel.size.x * 0.07, _info_panel.size.y * 0.85)
	_start_label.size = Vector2(_info_panel.size.x * 0.86, _info_panel.size.y * 0.10)
	_info_panel.add_child(_start_label)


func _change_selection(direction: int) -> void:
	_index = posmod(_index + direction, _songs.size())
	_apply_selection(false)


func _toggle_difficulty() -> void:
	_difficulty = "hard" if _difficulty == "easy" else "easy"
	_difficulty_label.text = "DIFICIL" if _difficulty == "hard" else "FACIL"
	_apply_selection(false)


func _apply_selection(immediate: bool) -> void:
	if _songs.is_empty():
		return

	var song: Dictionary = _songs[_index] as Dictionary
	var difficulty_data: Dictionary = CATALOG.get_difficulty(song, _difficulty)
	_difficulty_label.text = "DIFICIL" if _difficulty == "hard" else "FACIL"
	_renderer.configure(_center, _radius, _lane_positions, song, difficulty_data)
	_top_panel.add_theme_stylebox_override("panel", _top_panel_style(song))
	_info_panel.add_theme_stylebox_override("panel", _info_style(song))
	_difficulty_label.add_theme_color_override("font_color", _song_accent(song))
	_start_label.add_theme_color_override("font_color", _song_primary(song))

	_song_counter.text = "TRACK %02d / %02d" % [_index + 1, _songs.size()]
	_song_name.text = str(song.get("title", "TRACK"))
	_record_label.text = "BEST " + _best_record(song)
	_load_cover(song)
	_load_preview(song)
	_update_cards(immediate)
	LED_CLIENT.menu_state(_index, _song_primary(song))


func _update_cards(immediate: bool) -> void:
	for card_index in range(_cards.size()):
		var card: Panel = _cards[card_index]
		var relative: int = card_index - _index
		var target_y: float = _radius * 0.70 + float(relative) * _radius * 0.205
		var target_x: float = _radius * 0.22 + (0.035 * _radius if relative == 0 else 0.0)
		card.set_meta("target_position", Vector2(target_x, target_y))
		card.set_meta("target_scale", Vector2.ONE if relative == 0 else Vector2(0.94, 0.94))
		card.set_meta("target_alpha", 1.0 if abs(relative) <= 2 else 0.0)
		card.add_theme_stylebox_override(
			"panel",
			_card_style(_songs[_index], relative == 0)
		)
		if immediate:
			card.position = card.get_meta("target_position")
			card.scale = card.get_meta("target_scale")
			card.modulate.a = float(card.get_meta("target_alpha"))
			card.visible = card.modulate.a > 0.01


func _update_card_animation(delta: float) -> void:
	var factor: float = 1.0 - exp(-10.0 * delta)
	for card in _cards:
		var target_position: Vector2 = card.get_meta("target_position", card.position)
		var target_scale: Vector2 = card.get_meta("target_scale", card.scale)
		var target_alpha: float = float(card.get_meta("target_alpha", card.modulate.a))
		card.position = card.position.lerp(target_position, factor)
		card.scale = card.scale.lerp(target_scale, factor)
		card.modulate.a = lerpf(card.modulate.a, target_alpha, factor)
		card.visible = card.modulate.a > 0.01


func _load_cover(song: Dictionary) -> void:
	_cover.texture = null
	var path: String = str(song.get("cover", ""))
	if not ResourceLoader.exists(path):
		return
	var resource: Resource = load(path)
	if resource is Texture2D:
		_cover.texture = resource as Texture2D


func _load_preview(song: Dictionary) -> void:
	_preview_wait = 0.0
	if _video.is_playing():
		_video.stop()
	_video.stream = null

	var path: String = str(song.get("video", ""))
	if not ResourceLoader.exists(path):
		return
	var resource: Resource = load(path)
	if resource is VideoStream:
		_video.stream = resource as VideoStream


func _start_selected() -> void:
	if _transitioning or _songs.is_empty():
		return
	_transitioning = true

	var song: Dictionary = _songs[_index] as Dictionary
	get_tree().set_meta("hit_music_song_id", str(song.get("id", "")))
	get_tree().set_meta("hit_music_difficulty", _difficulty)
	LED_CLIENT.clear_all()

	var scene_path: String = str(song.get("scene", ""))
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		_transitioning = false
		push_error("Scene not found: " + scene_path)
		return

	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUINT)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(_top_panel, "position:y", _top_panel.position.y - get_viewport_rect().size.y * 0.03, 0.25)
	tween.tween_property(_top_panel, "modulate:a", 0.0, 0.25)
	tween.tween_property(_list_root, "modulate:a", 0.0, 0.25)
	tween.tween_property(_video, "modulate:a", 0.0, 0.25)
	tween.finished.connect(
		func() -> void:
			get_tree().change_scene_to_file(scene_path)
	)


func _best_record(song: Dictionary) -> String:
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
	var key: String = "dificil" if _difficulty == "hard" else "facil"
	return "%.2f%%" % float(record.get(key, 0.0))


func _on_viewport_size_changed() -> void:
	get_tree().set_meta("hit_music_selector_index", _index)
	get_tree().set_meta("hit_music_selector_difficulty", _difficulty)
	call_deferred("_reload_after_resize")


func _reload_after_resize() -> void:
	get_tree().reload_current_scene()


func _action_pressed(action: String) -> bool:
	return InputMap.has_action(action) and Input.is_action_just_pressed(action)


func _song_primary(song: Dictionary) -> Color:
	var colors_value: Variant = song.get("colors", {})
	if colors_value is Dictionary:
		return (colors_value as Dictionary).get("primary", Color(0.05, 0.92, 1.0, 1.0))
	return Color(0.05, 0.92, 1.0, 1.0)


func _song_accent(song: Dictionary) -> Color:
	var colors_value: Variant = song.get("colors", {})
	if colors_value is Dictionary:
		return (colors_value as Dictionary).get("accent", Color(1.0, 0.84, 0.05, 1.0))
	return Color(1.0, 0.84, 0.05, 1.0)


func _dark_color() -> Color:
	if _songs.is_empty():
		return Color(0.01, 0.02, 0.05, 1.0)
	var colors_value: Variant = (_songs[_index] as Dictionary).get("colors", {})
	if colors_value is Dictionary:
		return (colors_value as Dictionary).get("dark", Color(0.01, 0.02, 0.05, 1.0))
	return Color(0.01, 0.02, 0.05, 1.0)


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
	label.add_theme_font_size_override("font_size", maxi(12, font_size))
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.96))
	label.add_theme_constant_override("outline_size", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _top_panel_style(song: Dictionary) -> StyleBoxFlat:
	var color: Color = _song_primary(song)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.005, 0.010, 0.024, 0.96)
	style.border_color = Color(color.r, color.g, color.b, 0.72)
	style.set_border_width_all(3)
	style.set_corner_radius_all(18)
	style.shadow_color = Color(color.r, color.g, color.b, 0.18)
	style.shadow_size = 12
	return style


func _info_style(song: Dictionary) -> StyleBoxFlat:
	var color: Color = _song_primary(song)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.006, 0.010, 0.022, 0.92)
	style.border_color = Color(color.r, color.g, color.b, 0.65)
	style.set_border_width_all(2)
	style.set_corner_radius_all(15)
	style.shadow_color = Color(color.r, color.g, color.b, 0.18)
	style.shadow_size = 8
	return style


func _card_style(song: Dictionary, selected: bool) -> StyleBoxFlat:
	var primary: Color = _song_primary(song)
	var accent: Color = _song_accent(song)
	var style := StyleBoxFlat.new()
	style.bg_color = (
		Color(0.018, 0.030, 0.055, 0.96)
		if selected
		else Color(0.006, 0.012, 0.026, 0.88)
	)
	style.border_color = (
		Color(accent.r, accent.g, accent.b, 0.95)
		if selected
		else Color(primary.r, primary.g, primary.b, 0.22)
	)
	style.border_width_left = 6 if selected else 1
	style.border_width_top = 2 if selected else 1
	style.border_width_right = 2 if selected else 1
	style.border_width_bottom = 2 if selected else 1
	style.set_corner_radius_all(16)
	style.shadow_color = Color(primary.r, primary.g, primary.b, 0.18 if selected else 0.05)
	style.shadow_size = 7 if selected else 2
	return style