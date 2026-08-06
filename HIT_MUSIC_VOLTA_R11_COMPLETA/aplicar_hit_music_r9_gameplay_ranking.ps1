param(
    [string]$ProjectRoot = (Get-Location).Path,
    [switch]$Push
)

$ErrorActionPreference = "Stop"
$Version = "R9_GAMEPLAY_RANKING_20260806"

function Project-Path {
    param([Parameter(Mandatory = $true)][string]$RelativePath)
    return Join-Path $ProjectRoot $RelativePath
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $Parent = Split-Path -Parent $Path
    if ($Parent -and -not (Test-Path -LiteralPath $Parent)) {
        New-Item -ItemType Directory -Path $Parent -Force | Out-Null
    }

    $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $Utf8NoBom)
}

function Require-File {
    param([Parameter(Mandatory = $true)][string]$RelativePath)
    if (-not (Test-Path -LiteralPath (Project-Path $RelativePath))) {
        throw "Arquivo obrigatorio nao encontrado: $RelativePath"
    }
}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " HIT MUSIC R9 - GAMEPLAY, RANKING E DUAS MAOS" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Versao: $Version" -ForegroundColor DarkGray
Write-Host "Projeto: $ProjectRoot"
Write-Host ""

Require-File "project.godot"
Require-File "scripts\hit_music_r7\stage.gd"
Require-File "scripts\hit_music_r7\selector.gd"
Require-File "scripts\hit_music_r7\chart_factory.gd"
Require-File "scripts\change_scenes.gd"

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupRoot = Project-Path "_backup_hit_music_r9_$Stamp"
New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null

$FilesToBackup = @(
    "scripts\change_scenes.gd",
    "scripts\carmine.gd",
    "scripts\dragon_ball.gd",
    "scripts\demon.gd",
    "scripts\fairy.gd",
    "scripts\naruto.gd",
    "scripts\rick_morty.gd",
    "scripts\soul.gd"
)

foreach ($RelativePath in $FilesToBackup) {
    $Source = Project-Path $RelativePath
    if (Test-Path -LiteralPath $Source) {
        $Destination = Join-Path $BackupRoot $RelativePath
        $Parent = Split-Path -Parent $Destination
        New-Item -ItemType Directory -Path $Parent -Force | Out-Null
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
    }
}

Write-Host "Criando o motor compartilhado R9..." -ForegroundColor Yellow

Write-Utf8NoBom (Project-Path "scripts\hit_music_r7\chart_factory_v9.gd") @'
extends RefCounted

static func build(song: Dictionary, difficulty_name: String, duration: float) -> Array:
	var hard_mode: bool = difficulty_name.to_lower() == "hard"
	var profile_value: Variant = song.get("hard" if hard_mode else "easy", {})
	if not profile_value is Dictionary:
		return []

	var profile: Dictionary = profile_value as Dictionary
	var easy_value: Variant = song.get("easy", {})
	var hard_value: Variant = song.get("hard", {})
	var easy_profile: Dictionary = easy_value as Dictionary if easy_value is Dictionary else {}
	var hard_profile: Dictionary = hard_value as Dictionary if hard_value is Dictionary else {}

	var bpm: float = maxf(float(song.get("bpm", 120.0)), 1.0)
	var beat: float = 60.0 / bpm

	var easy_step_beats: float = maxf(float(easy_profile.get("step_beats", 2.0)), 0.25)
	var hard_step_beats: float = maxf(float(hard_profile.get("step_beats", 1.0)), 0.25)
	var rhythm_step_beats: float = minf(easy_step_beats, hard_step_beats)
	var rhythm_step: float = beat * rhythm_step_beats

	var selected_step_beats: float = maxf(
		float(profile.get("step_beats", rhythm_step_beats)),
		rhythm_step_beats
	)
	var stride: int = maxi(1, int(round(selected_step_beats / rhythm_step_beats)))

	var start_time: float = maxf(float(song.get("chart_start", 4.0)), 3.2)
	var end_time: float = maxf(start_time + rhythm_step, duration - 2.2)

	var lane_pattern: Array = _array_value(
		song.get(
			"lane_pattern_hard" if hard_mode else "lane_pattern_easy",
			[0, 2, 4, 6, 1, 3, 5, 7]
		)
	)
	if lane_pattern.is_empty():
		lane_pattern = [0, 2, 4, 6, 1, 3, 5, 7]

	var slide_patterns: Array = _array_value(
		song.get(
			"slides_hard" if hard_mode else "slides_easy",
			[
				{"path": [0, 4], "shape": "cross"},
				{"path": [2, 6], "shape": "straight"},
			]
		)
	)

	var slide_every: int = maxi(int(profile.get("slide_every", 10)), 0)
	var hold_every: int = maxi(int(profile.get("hold_every", 14)), 0)
	var configured_double_every: int = maxi(int(profile.get("double_every", 0)), 0)
	var two_hand_every: int = configured_double_every
	if two_hand_every <= 0:
		two_hand_every = 8 if hard_mode else 14

	var slide_beats: float = maxf(float(profile.get("slide_beats", 3.0)), 1.0)
	var hold_beats: float = maxf(float(profile.get("hold_beats", 3.0)), 1.0)
	var double_distance: int = clampi(int(profile.get("double_distance", 4)), 1, 7)

	var events: Array = []
	var grid_index: int = 0
	var note_index: int = 0
	var time_value: float = start_time

	while time_value < end_time:
		if grid_index % stride != 0:
			grid_index += 1
			time_value += rhythm_step
			continue

		var base_lane: int = posmod(
			int(lane_pattern[note_index % lane_pattern.size()]),
			8
		)
		var event_time: float = time_value
		var made_special: bool = false

		if (
			slide_every > 0
			and note_index > 0
			and note_index % slide_every == 0
			and not slide_patterns.is_empty()
		):
			var pattern_value: Variant = slide_patterns[
				int(note_index / slide_every) % slide_patterns.size()
			]
			if pattern_value is Dictionary:
				var pattern: Dictionary = (pattern_value as Dictionary).duplicate(true)
				var path: Array = _array_value(
					pattern.get("path", [base_lane, (base_lane + 4) % 8])
				)
				if path.size() >= 2:
					events.append({
						"type": "slide",
						"time": event_time,
						"end_time": minf(
							event_time + beat * slide_beats,
							end_time + beat
						),
						"path": path,
						"shape": str(pattern.get("shape", "straight")),
						"curve": float(pattern.get("curve", 0.55)),
						"color_index": note_index % 3,
						"rhythm_slot": grid_index,
					})
					made_special = true

		if (
			not made_special
			and hold_every > 0
			and note_index > 0
			and note_index % hold_every == 0
		):
			events.append({
				"type": "hold",
				"time": event_time,
				"end_time": minf(
					event_time + beat * hold_beats,
					end_time + beat
				),
				"lane": base_lane,
				"color_index": note_index % 3,
				"rhythm_slot": grid_index,
			})
			made_special = true

		if not made_special:
			events.append({
				"type": "tap",
				"time": event_time,
				"lane": base_lane,
				"color_index": note_index % 3,
				"rhythm_slot": grid_index,
			})

			if (
				two_hand_every > 0
				and note_index > 0
				and note_index % two_hand_every == 0
			):
				var second_lane: int = posmod(base_lane + double_distance, 8)
				events.append({
					"type": "tap",
					"time": event_time,
					"lane": second_lane,
					"color_index": (note_index + 1) % 3,
					"rhythm_slot": grid_index,
					"two_hand_pair": true,
				})

		note_index += 1
		grid_index += 1
		time_value += rhythm_step

	events.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var time_a: float = float(a.get("time", 0.0))
			var time_b: float = float(b.get("time", 0.0))
			if is_equal_approx(time_a, time_b):
				return int(a.get("lane", 0)) < int(b.get("lane", 0))
			return time_a < time_b
	)

	return events


static func _array_value(value: Variant) -> Array:
	if value is Array:
		return (value as Array).duplicate(true)
	return []

'@

Write-Utf8NoBom (Project-Path "scripts\hit_music_r7\stage_v9.gd") @'
extends "res://scripts/hit_music_r7/stage.gd"

const CHART_FACTORY_V9: Script = preload(
	"res://scripts/hit_music_r7/chart_factory_v9.gd"
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


func _process(delta: float) -> void:
	if _state == GameState.PRESENTATION and not _difficulty_confirmed:
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

		if str(event.get("type", "")) == "slide":
			event["_path_points"] = PATH_BUILDER.build(
				event,
				_center,
				_radius,
				_lane_positions
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

	_difficulty_confirmed = true
	_show_pre_game_overlay(false)
	_state_time = 0.0
	_start_countdown()


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
	_remove_tap_node(event)
	_clear_event_led(event)

	_judgement_count += 1
	_misses += 1
	_combo = 0

	_register_error_time(event)
	_recalculate_error_performance()

	if _missed_time >= _error_limit_seconds():
		_finish_game(true)


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
	_center_combo.add_theme_color_override(
		"font_color",
		_accent_color() if _combo > 0 else Color.WHITE
	)
	_center_error.text = "ERROS %.1f / %.1fs" % [
		_missed_time,
		_error_limit_seconds(),
	]

	if _label_performance != null:
		_label_performance.text = "LIMITE %.1fs" % _error_limit_seconds()
		_label_performance.add_theme_color_override(
			"font_color",
			_primary_color()
			if _performance > 25.0
			else Color(1.0, 0.15, 0.18, 1.0)
		)


func _finish_game(failed: bool) -> void:
	super._finish_game(failed)
	_set_center_hud_visible(false)

	if _result_details != null:
		_result_details.text = (
			"%s\nHITS %d   MISSES %d   MAX COMBO %d\n%s"
			% [
				_player_name,
				_hits,
				_misses,
				_max_combo,
				_ranking_text(),
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


func _ranking_text() -> String:
	if not FileAccess.file_exists(RECORD_PATH):
		return "RANKING\n1. %s  %.2f%%" % [
			_player_name,
			_score_percent(),
		]

	var read_file := FileAccess.open(
		RECORD_PATH,
		FileAccess.READ
	)
	if read_file == null:
		return "RANKING INDISPONIVEL"

	var parsed: Variant = JSON.parse_string(
		read_file.get_as_text()
	)
	if not parsed is Dictionary:
		return "RANKING INDISPONIVEL"

	var song_id: String = str(
		_song.get("id", _song_id())
	)
	var song_value: Variant = (
		parsed as Dictionary
	).get(song_id, {})
	if not song_value is Dictionary:
		return "RANKING\nSEM REGISTROS"

	var key: String = (
		"dificil"
		if _difficulty_name == "hard"
		else "facil"
	)
	var ranking_root_value: Variant = (
		song_value as Dictionary
	).get("ranking", {})
	if not ranking_root_value is Dictionary:
		return "RANKING\nSEM REGISTROS"

	var list_value: Variant = (
		ranking_root_value as Dictionary
	).get(key, [])
	if not list_value is Array:
		return "RANKING\nSEM REGISTROS"

	var ranking: Array = list_value as Array
	var lines: Array[String] = ["RANKING " + key.to_upper()]
	var count: int = mini(ranking.size(), 5)

	for index in range(count):
		var item_value: Variant = ranking[index]
		if not item_value is Dictionary:
			continue
		var item: Dictionary = item_value as Dictionary
		lines.append(
			"%d. %s  %.2f%%"
			% [
				index + 1,
				str(item.get("name", "PLAYER")),
				float(item.get("score", 0.0)),
			]
		)

	if lines.size() == 1:
		lines.append("SEM REGISTROS")

	return "\n".join(lines)


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

'@

Write-Utf8NoBom (Project-Path "scripts\hit_music_r7\selector_v9.gd") @'
extends "res://scripts/hit_music_r7/selector.gd"

func _ready() -> void:
	super._ready()

	if _easy_chip != null:
		_easy_chip.visible = false
	if _hard_chip != null:
		_hard_chip.visible = false
	if _instruction_label != null:
		_instruction_label.text = (
			"A  PROXIMA MUSICA     START  SELECIONAR"
		)
	if _mode_label != null:
		_mode_label.text = "DIFICULDADE NA FASE"


func _toggle_difficulty() -> void:
	pass


func _handle_touch(position_value: Vector2) -> void:
	for card_index in range(_cards.size()):
		var card: Panel = _cards[card_index]
		if not card.visible:
			continue

		if Rect2(
			card.global_position,
			card.size
		).has_point(position_value):
			if card_index == _index:
				_start_selected()
			else:
				_index = card_index
				_apply_selection(false)
			return

	if (
		_start_panel != null
		and Rect2(
			_start_panel.global_position,
			_start_panel.size
		).has_point(position_value)
	):
		_start_selected()
		return

	if (
		_info_panel != null
		and Rect2(
			_info_panel.global_position,
			_info_panel.size
		).has_point(position_value)
	):
		_start_selected()

'@

$SongWrappers = @{
    "scripts\carmine.gd" = "carmine"
    "scripts\dragon_ball.gd" = "dragon_ball"
    "scripts\demon.gd" = "demon"
    "scripts\fairy.gd" = "fairy"
    "scripts\naruto.gd" = "naruto"
    "scripts\rick_morty.gd" = "rick_morty"
    "scripts\soul.gd" = "soul"
}

foreach ($RelativePath in $SongWrappers.Keys) {
    $SongId = $SongWrappers[$RelativePath]
    $Content = @"
extends "res://scripts/hit_music_r7/stage_v9.gd"

func _song_id() -> String:
	return "$SongId"
"@
    Write-Utf8NoBom (Project-Path $RelativePath) $Content
}

Write-Utf8NoBom (Project-Path "scripts\change_scenes.gd") @'
extends "res://scripts/hit_music_r7/selector_v9.gd"
'@

$GitAvailable = $null -ne (Get-Command git -ErrorAction SilentlyContinue)
$GitRepository = Test-Path -LiteralPath (Project-Path ".git")

if ($GitAvailable -and $GitRepository) {
    $CurrentBranch = git branch --show-current
    if ($CurrentBranch -ne "main") {
        throw "A versao atual deve estar na branch main. Branch atual: $CurrentBranch"
    }

    git add scripts/hit_music_r7/chart_factory_v9.gd
    git add scripts/hit_music_r7/stage_v9.gd
    git add scripts/hit_music_r7/selector_v9.gd
    git add scripts/change_scenes.gd
    git add scripts/carmine.gd
    git add scripts/dragon_ball.gd
    git add scripts/demon.gd
    git add scripts/fairy.gd
    git add scripts/naruto.gd
    git add scripts/rick_morty.gd
    git add scripts/soul.gd

    git commit -m "R9 adiciona limite de erro por tempo, ranking e dificuldade na fase"

    if ($Push) {
        git push origin main
    }
}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Green
Write-Host " R9 APLICADO COM SUCESSO" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "Backup local: $BackupRoot"
Write-Host ""
Write-Host "IMPLEMENTADO:" -ForegroundColor Cyan
Write-Host "- Perde somente ao acumular 30% da duracao em tempo de erro."
Write-Host "- Musica de 60 segundos permite 18 segundos acumulados de erro."
Write-Host "- Escolha Facil/Dificil dentro da scene, no centro do circulo."
Write-Host "- Mesmo BPM e mesma grade ritmica nas duas dificuldades."
Write-Host "- Cadeias e densidade diferentes para Facil e Dificil."
Write-Host "- Jogadas duplas para uso das duas maos."
Write-Host "- Percentual e combo no centro da pista."
Write-Host "- Ranking por musica e dificuldade."
Write-Host "- Nome temporario registrado como PLAYER 1."
Write-Host "- Todas as sete musicas usam exatamente o mesmo motor R9."
Write-Host ""
Write-Host "Abra o Godot, aguarde a importacao e rode com F5." -ForegroundColor Yellow
