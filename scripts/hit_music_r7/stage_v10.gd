extends "res://scripts/hit_music_r7/stage_v9.gd"

const THEME_OVERLAY_V10: Script = preload(
	"res://scripts/hit_music_r7/theme_overlay_v10.gd"
)

var _difficulty_cursor: int = -1
var _display_score: float = 0.0
var _theme_overlay_v10


func _ready() -> void:
	Engine.max_fps = 120
	super._ready()

	_difficulty_cursor = -1
	_difficulty_name = ""
	_difficulty_confirmed = false
	_display_score = 0.0

	if _pre_game_title != null:
		_pre_game_title.text = "ESCOLHA A DIFICULDADE"
	if _pre_game_subtitle != null:
		_pre_game_subtitle.text = (
			"A: MOVER     B: SELECIONAR\n"
			+ "TOQUE EM FACIL OU DIFICIL PARA INICIAR"
		)

	_update_pre_game_styles()
	_set_center_hud_visible(false)
	_build_theme_overlay_v10()

	LED_CLIENT.scene_state(
		_primary_color(),
		_accent_color()
	)


func _process(delta: float) -> void:
	super._process(delta)

	if _theme_overlay_v10 != null:
		_theme_overlay_v10.set_runtime(
			_song_time,
			_state_name()
		)


func _process_pre_game_inputs() -> void:
	if _action_pressed("input_a"):
		_move_difficulty_cursor()
	elif _action_pressed("input_b"):
		_confirm_difficulty()
	elif _action_pressed("ui_down"):
		_move_difficulty_cursor()
	elif _action_pressed("ui_accept"):
		_confirm_difficulty()


func _handle_pre_game_touch(
	position_value: Vector2
) -> void:
	if (
		_easy_button != null
		and Rect2(
			_easy_button.global_position,
			_easy_button.size
		).has_point(position_value)
	):
		_difficulty_cursor = 0
		_select_difficulty("easy")
		_confirm_difficulty()
		return

	if (
		_hard_button != null
		and Rect2(
			_hard_button.global_position,
			_hard_button.size
		).has_point(position_value)
	):
		_difficulty_cursor = 1
		_select_difficulty("hard")
		_confirm_difficulty()


func _move_difficulty_cursor() -> void:
	_difficulty_cursor = (
		0
		if _difficulty_cursor < 0
		else (_difficulty_cursor + 1) % 2
	)

	_select_difficulty(
		"easy"
		if _difficulty_cursor == 0
		else "hard"
	)

	LED_CLIENT.menu_next_feedback()


func _confirm_difficulty() -> void:
	if _difficulty_cursor < 0:
		return

	LED_CLIENT.menu_select_feedback()
	super._confirm_difficulty()


func _select_difficulty(
	name_value: String,
	immediate: bool = false
) -> void:
	super._select_difficulty(
		name_value,
		immediate
	)

	_difficulty["background_intensity"] = 0.045

	if _renderer != null:
		_renderer.configure(
			_center,
			_radius,
			_lane_positions,
			_song,
			_difficulty
		)


func _update_pre_game_styles() -> void:
	if _easy_button == null:
		return

	var easy_selected: bool = _difficulty_cursor == 0
	var hard_selected: bool = _difficulty_cursor == 1

	_easy_button.add_theme_stylebox_override(
		"panel",
		_difficulty_button_style(
			easy_selected,
			Color(0.13, 0.90, 1.0, 1.0)
		)
	)
	_hard_button.add_theme_stylebox_override(
		"panel",
		_difficulty_button_style(
			hard_selected,
			_accent_color()
		)
	)
	_play_button.visible = false

	_easy_button_label.add_theme_color_override(
		"font_color",
		Color.WHITE
		if easy_selected
		else Color(0.58, 0.65, 0.76, 1.0)
	)
	_hard_button_label.add_theme_color_override(
		"font_color",
		Color.WHITE
		if hard_selected
		else Color(0.58, 0.65, 0.76, 1.0)
	)


func _score_percent() -> float:
	var total_notes: int = _events.size()
	if total_notes <= 0:
		return 0.0

	return clampf(
		100.0
		* _score_quality_sum
		/ float(total_notes),
		0.0,
		100.0
	)


func _update_hud() -> void:
	super._update_hud()

	var target_score: float = _score_percent()
	_display_score = lerpf(
		_display_score,
		target_score,
		0.18
	)

	if absf(_display_score - target_score) < 0.005:
		_display_score = target_score

	if _center_score != null:
		_center_score.text = "%.2f%%" % _display_score

	if _label_score != null:
		_label_score.visible = false
	if _label_combo != null:
		_label_combo.visible = false


func _set_gameplay_hud_visible(value: bool) -> void:
	super._set_gameplay_hud_visible(value)

	if _label_score != null:
		_label_score.visible = false
	if _label_combo != null:
		_label_combo.visible = false


func _handle_lane_press(
	lane: int,
	source: String
) -> void:
	LED_CLIENT.pulse_lane(lane)
	super._handle_lane_press(lane, source)


func _resolve_hit(
	event: Dictionary,
	kind: String,
	quality: float
) -> void:
	var type_name: String = str(
		event.get("type", kind)
	)

	if type_name == "tap" or type_name == "hold":
		LED_CLIENT.hit_lane(
			int(event.get("lane", 0)),
			_event_color(event),
			220 if type_name == "hold" else 180
		)

	super._resolve_hit(
		event,
		kind,
		quality
	)


func _resolve_miss(event: Dictionary) -> void:
	var type_name: String = str(
		event.get("type", "tap")
	)

	if type_name == "tap" or type_name == "hold":
		LED_CLIENT.error_lane(
			int(event.get("lane", 0))
		)

	super._resolve_miss(event)


func _start_countdown() -> void:
	LED_CLIENT.countdown_start()
	super._start_countdown()


func _start_playing() -> void:
	LED_CLIENT.ready()
	super._start_playing()


func _build_theme_overlay_v10() -> void:
	_theme_overlay_v10 = THEME_OVERLAY_V10.new()
	_theme_overlay_v10.name = "ThemeOverlayV10"
	_theme_overlay_v10.z_index = 8
	add_child(_theme_overlay_v10)
	_theme_overlay_v10.configure(
		_center,
		_radius,
		_song
	)


func _on_viewport_size_changed() -> void:
	super._on_viewport_size_changed()

	if _theme_overlay_v10 != null:
		_theme_overlay_v10.configure(
			_center,
			_radius,
			_song
		)
