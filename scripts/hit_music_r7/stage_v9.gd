extends "res://scripts/hit_music_r7/stage.gd"

const CHART_FACTORY_V9: Script = preload(
	"res://scripts/hit_music_r7/chart_factory_v9.gd"
)
const SETTINGS_GATE: Script = preload(
	"res://scripts/hit_music_r7/settings_gate.gd"
)

const ERROR_LIMIT_RATIO: float = 0.30
const DEFAULT_PLAYER_NAME: String = "PLAYER 1"
const RANKING_LIMIT: int = 10

var _difficulty_confirmed: bool = false
var _missed_time: float = 0.0
var _missed_slots: Dictionary = {}
var _player_name: String = DEFAULT_PLAYER_NAME

var _pre_game_panel: Panel
var _pre_game_title: Label
var _pre_game_subtitle: Label
var _easy_button: Panel
var _hard_button: Panel
var _easy_button_label: Label
var _hard_button_label: Label
var _play_button: Panel
var _play_button_label: Label

var _center_hud: Control
var _center_score: Label
var _center_combo: Label
var _center_error: Label


func _ready() -> void:
	super._ready()
	if _song.is_empty():
		return

	_difficulty_confirmed = false
	_missed_time = 0.0
	_missed_slots.clear()
	_build_pre_game_overlay()
	_build_center_hud()
	_select_difficulty(_difficulty_name, true)
	_show_pre_game_overlay(true)
	_set_center_hud_visible(false)
	_fade_in_difficulty_panel()


func _fade_in_difficulty_panel() -> void:
	# Entrada suave no proprio painel; nada e desenhado sobre a tela.
	if _pre_game_panel == null:
		return
	_pre_game_panel.modulate.a = 0.0
	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_QUINT)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(_pre_game_panel, "modulate:a", 1.0, 0.52)


func _process(delta: float) -> void:
	if _state == GameState.PRESENTATION and not _difficulty_confirmed:
		if SETTINGS_GATE.try_open_from_action():
			return
		_process_pre_game_inputs()
		_update_pre_game_styles()
		_renderer.set_runtime(
			_events,
			0.0,
			"presentation",
			Vector2.ZERO,
			false
		)
		queue_redraw()
		return

	super._process(delta)


func _input(event: InputEvent) -> void:
	if _state == GameState.PRESENTATION and not _difficulty_confirmed:
		if SETTINGS_GATE.try_open_from_keyboard(event):
			return
		if event is InputEventScreenTouch:
			var touch: InputEventScreenTouch = event
			if touch.pressed:
				_handle_pre_game_touch(touch.position)
		elif event is InputEventMouseButton:
			var mouse: InputEventMouseButton = event
			if mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed:
				_handle_pre_game_touch(mouse.position)
		return

	super._input(event)


func _prepare_chart() -> void:
	_events = CHART_FACTORY_V9.build(
		_song,
		_difficulty_name,
		_song_duration
	)

	for event_value in _events:
		if not event_value is Dictionary:
			continue

		var event: Dictionary = event_value as Dictionary
		event["_spawned"] = false
		event["_resolved"] = false
		event["_active"] = false
		event["_holding"] = false
		event["_visual_progress"] = 0.0
		event["_draw_progress"] = 0.0

		if str(event.get("type", "")) == "slide":
			var path_points: PackedVector2Array = PATH_BUILDER.build(
				event,
				_center,
				_radius,
				_lane_positions
			)
			event["_path_points"] = path_points
			# Mesmo pre-calculo do stage base: o comprimento acumulado
			# evita refazer a soma do trajeto inteiro a cada amostra, e os
			# gates permitem concluir o arrasto pelos botoes fisicos.
			event["_path_lengths"] = PATH_BUILDER.build_lengths(path_points)
			event["_lane_gates"] = _build_lane_gates(event, path_points)
			event["_last_pointer"] = (
				path_points[0] if path_points.size() > 0 else _center
			)


func _process_pre_game_inputs() -> void:
	if _action_pressed("input_a") or _action_pressed("ui_left"):
		_select_difficulty("easy")
	elif _action_pressed("input_b") or _action_pressed("ui_right"):
		_select_difficulty("hard")

	if _action_pressed("input_start") or _action_pressed("ui_accept"):
		_confirm_difficulty()


func _handle_pre_game_touch(position_value: Vector2) -> void:
	if (
		_easy_button != null
		and Rect2(
			_easy_button.global_position,
			_easy_button.size
		).has_point(position_value)
	):
		_select_difficulty("easy")
		return

	if (
		_hard_button != null
		and Rect2(
			_hard_button.global_position,
			_hard_button.size
		).has_point(position_value)
	):
		_select_difficulty("hard")
		return

	if (
		_play_button != null
		and Rect2(
			_play_button.global_position,
			_play_button.size
		).has_point(position_value)
	):
		_confirm_difficulty()


func _select_difficulty(name_value: String, immediate: bool = false) -> void:
	_difficulty_name = "hard" if name_value.to_lower() == "hard" else "easy"
	_difficulty = CATALOG.get_difficulty(_song, _difficulty_name)
	_prepare_chart()

	if _renderer != null:
		_renderer.configure(
			_center,
			_radius,
			_lane_positions,
			_song,
			_difficulty
		)

	if _label_difficulty != null:
		_label_difficulty.text = (
			"DIFICIL" if _difficulty_name == "hard" else "FACIL"
		)
		_label_difficulty.add_theme_color_override(
			"font_color",
			_accent_color()
		)

	get_tree().set_meta("hit_music_difficulty", _difficulty_name)
	_update_pre_game_styles()

	if not immediate and _pre_game_panel != null:
		var tween: Tween = create_tween()
		tween.set_trans(Tween.TRANS_BACK)
		tween.set_ease(Tween.EASE_OUT)
		_pre_game_panel.scale = Vector2(0.985, 0.985)
		tween.tween_property(_pre_game_panel, "scale", Vector2.ONE, 0.16)


func _confirm_difficulty() -> void:
	if _difficulty_confirmed:
		return

	# So aqui o credito e de fato gasto — apertar Start na abertura so
	# adiciona credito (modo credito) ou so avanca (modo livre); e ao
	# confirmar a musica/dificuldade que a partida realmente comeca.
	if not ArcadeSettings.try_consume_credit():
		_show_insert_coin_warning()
		return

	_difficulty_confirmed = true
	_show_pre_game_overlay(false)
	_state_time = 0.0
	_start_countdown()


var _insert_coin_label: Label
var _insert_coin_tween: Tween


## Aviso "INSIRA FICHA" quando o jogador tenta comecar sem credito no
## modo credito — pisca por cima do painel de dificuldade e some
## sozinho, sem travar a tela nem exigir mais nenhuma acao.
func _show_insert_coin_warning() -> void:
	if _insert_coin_label == null or not is_instance_valid(_insert_coin_label):
		if _hud_layer == null:
			return
		var font: Font = _load_font()
		_insert_coin_label = _make_label(
			"INSIRA FICHA",
			int(_radius * 0.058),
			HORIZONTAL_ALIGNMENT_CENTER,
			font
		)
		_insert_coin_label.add_theme_color_override("font_color", Color(1.0, 0.20, 0.24, 1.0))
		_insert_coin_label.size = Vector2(_radius * 1.0, _radius * 0.16)
		_insert_coin_label.position = _center - _insert_coin_label.size * 0.5
		_insert_coin_label.modulate.a = 0.0
		_insert_coin_label.z_index = 60
		_hud_layer.add_child(_insert_coin_label)

	if _insert_coin_tween != null and _insert_coin_tween.is_valid():
		_insert_coin_tween.kill()

	LED_CLIENT.menu_next_feedback()
	_insert_coin_label.visible = true
	_insert_coin_label.modulate.a = 1.0
	_insert_coin_tween = create_tween()
	_insert_coin_tween.tween_interval(0.9)
	_insert_coin_tween.tween_property(_insert_coin_label, "modulate:a", 0.0, 0.35)


func _build_pre_game_overlay() -> void:
	if _hud_layer == null:
		return

	var font: Font = _load_font()
	var panel_size := Vector2(_radius * 1.22, _radius * 0.72)

	_pre_game_panel = Panel.new()
	_pre_game_panel.position = _center - panel_size * 0.5
	_pre_game_panel.size = panel_size
	_pre_game_panel.pivot_offset = panel_size * 0.5
	_pre_game_panel.add_theme_stylebox_override(
		"panel",
		_pre_game_panel_style()
	)
	_hud_layer.add_child(_pre_game_panel)

	_pre_game_title = _make_label(
		"ESCOLHA A DIFICULDADE",
		int(_radius * 0.052),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	_pre_game_title.position = Vector2(
		panel_size.x * 0.06,
		panel_size.y * 0.055
	)
	_pre_game_title.size = Vector2(
		panel_size.x * 0.88,
		panel_size.y * 0.15
	)
	_pre_game_panel.add_child(_pre_game_title)

	_pre_game_subtitle = _make_label(
		"Mesmo ritmo. Cadeias e densidade diferentes.",
		int(_radius * 0.024),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	_pre_game_subtitle.position = Vector2(
		panel_size.x * 0.06,
		panel_size.y * 0.20
	)
	_pre_game_subtitle.size = Vector2(
		panel_size.x * 0.88,
		panel_size.y * 0.10
	)
	_pre_game_subtitle.add_theme_color_override(
		"font_color",
		Color(0.76, 0.82, 0.92, 1.0)
	)
	_pre_game_panel.add_child(_pre_game_subtitle)

	var button_size := Vector2(
		panel_size.x * 0.38,
		panel_size.y * 0.22
	)

	_easy_button = Panel.new()
	_easy_button.position = Vector2(
		panel_size.x * 0.085,
		panel_size.y * 0.36
	)
	_easy_button.size = button_size
	_pre_game_panel.add_child(_easy_button)

	_easy_button_label = _make_label(
		"FACIL",
		int(_radius * 0.041),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	_easy_button_label.size = button_size
	_easy_button.add_child(_easy_button_label)

	_hard_button = Panel.new()
	_hard_button.position = Vector2(
		panel_size.x * 0.535,
		panel_size.y * 0.36
	)
	_hard_button.size = button_size
	_pre_game_panel.add_child(_hard_button)

	_hard_button_label = _make_label(
		"DIFICIL",
		int(_radius * 0.041),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	_hard_button_label.size = button_size
	_hard_button.add_child(_hard_button_label)

	_play_button = Panel.new()
	_play_button.position = Vector2(
		panel_size.x * 0.255,
		panel_size.y * 0.67
	)
	_play_button.size = Vector2(
		panel_size.x * 0.49,
		panel_size.y * 0.19
	)
	_pre_game_panel.add_child(_play_button)

	_play_button_label = _make_label(
		"JOGAR",
		int(_radius * 0.036),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	_play_button_label.size = _play_button.size
	_play_button.add_child(_play_button_label)


func _build_center_hud() -> void:
	if _hud_layer == null:
		return

	var font: Font = _load_font()

	_center_hud = Control.new()
	_center_hud.position = _center - Vector2(
		_radius * 0.36,
		_radius * 0.20
	)
	_center_hud.size = Vector2(
		_radius * 0.72,
		_radius * 0.40
	)
	_center_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(_center_hud)

	_center_score = _make_label(
		"100.00%",
		int(_radius * 0.080),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	_center_score.position = Vector2.ZERO
	_center_score.size = Vector2(
		_center_hud.size.x,
		_center_hud.size.y * 0.48
	)
	_center_score.add_theme_color_override(
		"font_color",
		Color.WHITE
	)
	_center_score.add_theme_constant_override("outline_size", 7)
	_center_hud.add_child(_center_score)

	_center_combo = _make_label(
		"COMBO 0",
		int(_radius * 0.038),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	_center_combo.position = Vector2(
		0.0,
		_center_hud.size.y * 0.45
	)
	_center_combo.size = Vector2(
		_center_hud.size.x,
		_center_hud.size.y * 0.27
	)
	_center_combo.add_theme_color_override(
		"font_color",
		_accent_color()
	)
	_center_hud.add_child(_center_combo)

	_center_error = _make_label(
		"ERROS 0.0 / 0.0s",
		int(_radius * 0.021),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	_center_error.position = Vector2(
		0.0,
		_center_hud.size.y * 0.71
	)
	_center_error.size = Vector2(
		_center_hud.size.x,
		_center_hud.size.y * 0.20
	)
	_center_error.add_theme_color_override(
		"font_color",
		Color(0.72, 0.80, 0.92, 1.0)
	)
	_center_hud.add_child(_center_error)


func _show_pre_game_overlay(value: bool) -> void:
	if _pre_game_panel != null:
		_pre_game_panel.visible = value

	if _cover != null:
		_cover.visible = not value

	if value:
		_set_gameplay_hud_visible(false)
		_set_center_hud_visible(false)


func _set_center_hud_visible(value: bool) -> void:
	if _center_hud != null:
		_center_hud.visible = value


func _set_gameplay_hud_visible(value: bool) -> void:
	super._set_gameplay_hud_visible(value)
	_set_center_hud_visible(
		value
		and _difficulty_confirmed
		and _state == GameState.PLAYING
	)


func _start_playing() -> void:
	super._start_playing()
	_set_center_hud_visible(true)
	_update_hud()


func _resolve_hit(
	event: Dictionary,
	kind: String,
	quality: float
) -> void:
	super._resolve_hit(event, kind, quality)
	_recalculate_error_performance()


func _resolve_miss(event: Dictionary) -> void:
	if bool(event.get("_resolved", false)):
		return

	event["_resolved"] = true
	event["_active"] = false
	event["_holding"] = false

	var position_value: Vector2 = _event_end_position(event)
	_renderer.add_effect(
		"miss",
		position_value,
		Color(1.0, 0.12, 0.16, 1.0)
	)
	# Flash vermelho, curto, so na lane errada — diferente dos flashes
	# de acerto (que duram mais e sao mais fortes), pra nao poluir a
	# leitura da proxima nota que ja esta chegando naquela posicao.
	_renderer.flash_ring_at(
		position_value,
		Color(1.0, 0.16, 0.20, 1.0),
		0.70,
		5.4
	)
	_remove_tap_node(event)
	_clear_event_led(event)

	_judgement_count += 1
	_misses += 1
	_combo = 0

	# Errar ABAIXA a musica (energia em stage.gd), mas a partida NAO e
	# mais cancelada por acumulo de erro: o jogador sempre toca ate o
	# fim da musica.
	_music_energy = maxf(0.0, _music_energy - MUSIC_ENERGY_MISS_PENALTY)

	_register_error_time(event)
	_recalculate_error_performance()


func _register_error_time(event: Dictionary) -> void:
	var rhythm_slot: int = int(event.get("rhythm_slot", -1))
	if rhythm_slot >= 0:
		if _missed_slots.has(rhythm_slot):
			return
		_missed_slots[rhythm_slot] = true

	var bpm: float = maxf(float(_song.get("bpm", 120.0)), 1.0)
	var beat: float = 60.0 / bpm
	var step_beats: float = maxf(
		float(_difficulty.get("step_beats", 1.0)),
		0.25
	)
	var error_seconds: float = beat * step_beats

	var type_name: String = str(event.get("type", "tap"))
	if type_name == "hold" or type_name == "slide":
		var start_time: float = float(event.get("time", 0.0))
		var end_time: float = float(
			event.get("end_time", start_time + error_seconds)
		)
		error_seconds = maxf(error_seconds, end_time - start_time)

	_missed_time = minf(
		_error_limit_seconds(),
		_missed_time + maxf(error_seconds, 0.05)
	)


func _error_limit_seconds() -> float:
	return maxf(_song_duration * ERROR_LIMIT_RATIO, 1.0)


func _recalculate_error_performance() -> void:
	var limit: float = _error_limit_seconds()
	_performance = clampf(
		100.0 * (1.0 - _missed_time / limit),
		0.0,
		100.0
	)


func _update_hud() -> void:
	super._update_hud()

	if _center_score == null:
		return

	_center_score.text = "%.2f%%" % _score_percent()
	_center_combo.text = "COMBO %d" % _combo
	# O combo nao fica fixo na tela: so aparece a partir de 2 acertos
	# seguidos (pra nao poluir com "COMBO 0"/"COMBO 1" o tempo todo) e
	# vai auto-somando ate o proximo erro, quando some de novo. O
	# maximo (_max_combo) continua sendo contabilizado por baixo dos
	# panos e aparece no resultado final.
	_center_combo.visible = _combo >= 2
	_center_combo.add_theme_color_override(
		"font_color",
		_accent_color() if _combo > 0 else Color.WHITE
	)
	# Contador de erro/limite removido da tela: nao existe mais
	# cancelamento por desempenho, entao mostrar "ERROS x / ys" e
	# "LIMITE" so poluia o HUD com uma regra que nao existe mais.
	if _center_error != null:
		_center_error.visible = false

	if _label_performance != null:
		_label_performance.visible = false


func _finish_game(failed: bool) -> void:
	super._finish_game(failed)
	_set_center_hud_visible(false)

	if _result_details != null:
		_result_details.text = (
			"PARTIDA ATUAL • %s\nACERTOS %d   ERROS %d\nMAX COMBO %d\n%s\n%s"
			% [
				_player_name,
				_hits,
				_misses,
				_max_combo,
				_result_qualification_text(),
				_result_action_hint(),
			]
		)


func _save_record(score: float) -> void:
	var data: Dictionary = {}
	if FileAccess.file_exists(RECORD_PATH):
		var read_file := FileAccess.open(
			RECORD_PATH,
			FileAccess.READ
		)
		if read_file != null:
			var parsed: Variant = JSON.parse_string(
				read_file.get_as_text()
			)
			if parsed is Dictionary:
				data = parsed as Dictionary

	var song_id: String = str(
		_song.get("id", _song_id())
	)
	var current_value: Variant = data.get(song_id, {})
	var song_record: Dictionary = (
		current_value as Dictionary
		if current_value is Dictionary
		else {}
	)
	var key: String = (
		"dificil"
		if _difficulty_name == "hard"
		else "facil"
	)

	song_record[key] = maxf(
		float(song_record.get(key, 0.0)),
		score
	)

	var ranking_value: Variant = song_record.get("ranking", {})
	var ranking_root: Dictionary = (
		ranking_value as Dictionary
		if ranking_value is Dictionary
		else {}
	)
	var list_value: Variant = ranking_root.get(key, [])
	var ranking: Array = (
		(list_value as Array).duplicate(true)
		if list_value is Array
		else []
	)

	ranking.append({
		"name": _player_name,
		"score": score,
		"combo": _max_combo,
		"hits": _hits,
		"misses": _misses,
	})

	ranking.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var score_a: float = float(a.get("score", 0.0))
			var score_b: float = float(b.get("score", 0.0))
			if is_equal_approx(score_a, score_b):
				return int(a.get("combo", 0)) > int(b.get("combo", 0))
			return score_a > score_b
	)

	if ranking.size() > RANKING_LIMIT:
		ranking.resize(RANKING_LIMIT)

	ranking_root[key] = ranking
	song_record["ranking"] = ranking_root
	data[song_id] = song_record

	var write_file := FileAccess.open(
		RECORD_PATH,
		FileAccess.WRITE
	)
	if write_file != null:
		write_file.store_string(
			JSON.stringify(data, "\t")
		)


func _update_pre_game_styles() -> void:
	if _easy_button == null:
		return

	var easy_selected: bool = _difficulty_name == "easy"
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
			not easy_selected,
			_accent_color()
		)
	)
	_play_button.add_theme_stylebox_override(
		"panel",
		_play_button_style()
	)

	_easy_button_label.add_theme_color_override(
		"font_color",
		Color.WHITE
		if easy_selected
		else Color(0.58, 0.65, 0.76, 1.0)
	)
	_hard_button_label.add_theme_color_override(
		"font_color",
		Color.WHITE
		if not easy_selected
		else Color(0.58, 0.65, 0.76, 1.0)
	)


func _pre_game_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.004, 0.009, 0.024, 0.96)
	style.border_color = Color(
		_primary_color().r,
		_primary_color().g,
		_primary_color().b,
		0.76
	)
	style.set_border_width_all(3)
	style.set_corner_radius_all(30)
	style.shadow_color = Color(
		_primary_color().r,
		_primary_color().g,
		_primary_color().b,
		0.25
	)
	style.shadow_size = 18
	return style


func _difficulty_button_style(
	selected: bool,
	color: Color
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = (
		Color(color.r, color.g, color.b, 0.25)
		if selected
		else Color(0.008, 0.015, 0.032, 0.92)
	)
	style.border_color = (
		Color(color.r, color.g, color.b, 1.0)
		if selected
		else Color(0.48, 0.56, 0.70, 0.24)
	)
	style.set_border_width_all(3 if selected else 2)
	style.set_corner_radius_all(24)
	style.shadow_color = Color(
		color.r,
		color.g,
		color.b,
		0.28 if selected else 0.0
	)
	style.shadow_size = 12 if selected else 0
	return style


func _play_button_style() -> StyleBoxFlat:
	var color: Color = _primary_color().lerp(
		_accent_color(),
		0.34
	)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(
		color.r,
		color.g,
		color.b,
		0.24
	)
	style.border_color = color
	style.set_border_width_all(3)
	style.set_corner_radius_all(22)
	style.shadow_color = Color(
		color.r,
		color.g,
		color.b,
		0.34
	)
	style.shadow_size = 13
	return style


func _on_viewport_size_changed() -> void:
	super._on_viewport_size_changed()

	if _pre_game_panel != null:
		var panel_size := Vector2(
			_radius * 1.22,
			_radius * 0.72
		)
		_pre_game_panel.position = _center - panel_size * 0.5
		_pre_game_panel.size = panel_size
		_pre_game_panel.pivot_offset = panel_size * 0.5

	if _center_hud != null:
		_center_hud.position = _center - Vector2(
			_radius * 0.36,
			_radius * 0.20
		)
