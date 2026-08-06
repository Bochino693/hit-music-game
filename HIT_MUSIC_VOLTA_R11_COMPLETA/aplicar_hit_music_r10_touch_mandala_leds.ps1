param(
    [string]$ProjectRoot = (Get-Location).Path,
    [switch]$Push
)

$ErrorActionPreference = "Stop"
$Version = "R10_TOUCH_MANDALA_LEDS_20260806"

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
Write-Host " HIT MUSIC R10 - TOUCH, MANDALA E LEDS" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Versao: $Version" -ForegroundColor DarkGray
Write-Host "Projeto: $ProjectRoot"
Write-Host ""

Require-File "project.godot"
Require-File "scripts\hit_music_r7\stage_v9.gd"
Require-File "scripts\hit_music_r7\selector_v9.gd"
Require-File "scripts\hit_music_r7\led_client.gd"

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupRoot = Project-Path "_backup_hit_music_r10_$Stamp"
New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null

$FilesToBackup = @(
    "scripts\hit_music_r7\led_client.gd",
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

Write-Host "Embutindo os arquivos R10..." -ForegroundColor Yellow

Write-Utf8NoBom (Project-Path "scripts\hit_music_r7\led_client.gd") @'
extends RefCounted

const MENU_NEXT_COLOR: Color = Color(0.0, 0.72, 1.0, 1.0)
const MENU_SELECT_COLOR: Color = Color(1.0, 0.82, 0.08, 1.0)


static func clear_all() -> void:
	send_raw("CLEAR")


static func set_lane(lane: int, color: Color) -> void:
	var rgb: Vector3i = _rgb(color)
	send_raw(
		"LED %d %d %d %d"
		% [clampi(lane, 0, 7), rgb.x, rgb.y, rgb.z]
	)


static func clear_lane(lane: int) -> void:
	send_raw("LED %d 0 0 0" % clampi(lane, 0, 7))


static func hit_lane(
	lane: int,
	color: Color,
	duration_ms: int = 180
) -> void:
	var rgb: Vector3i = _rgb(color)
	send_raw(
		"HIT %d %d %d %d %d"
		% [
			clampi(lane, 0, 7),
			rgb.x,
			rgb.y,
			rgb.z,
			clampi(duration_ms, 90, 1200),
		]
	)


static func error_lane(lane: int) -> void:
	send_raw("ERR %d" % clampi(lane, 0, 7))


static func pulse_lane(lane: int) -> void:
	send_raw("PULSE %d" % clampi(lane, 0, 7))


static func menu_state(
	_index: int = 0,
	_color: Color = Color.WHITE
) -> void:
	var next_rgb: Vector3i = _rgb(MENU_NEXT_COLOR)
	var select_rgb: Vector3i = _rgb(MENU_SELECT_COLOR)
	send_raw(
		"MENU %d %d %d %d %d %d"
		% [
			next_rgb.x,
			next_rgb.y,
			next_rgb.z,
			select_rgb.x,
			select_rgb.y,
			select_rgb.z,
		]
	)


static func menu_next_feedback() -> void:
	hit_lane(0, MENU_NEXT_COLOR, 140)


static func menu_select_feedback() -> void:
	hit_lane(1, MENU_SELECT_COLOR, 160)


static func scene_state(
	primary: Color,
	secondary: Color
) -> void:
	var a: Vector3i = _rgb(primary)
	var b: Vector3i = _rgb(secondary)
	send_raw(
		"SCENE2 %d %d %d %d %d %d"
		% [a.x, a.y, a.z, b.x, b.y, b.z]
	)


static func countdown_start() -> void:
	send_raw("BLINKALL")


static func countdown_value(value: int) -> void:
	send_raw("COUNT %d" % clampi(value, 0, 9))


static func ready() -> void:
	send_raw("READY")


static func send_raw(command: String) -> void:
	var clean: String = command.strip_edges()
	if clean.is_empty():
		return

	var base_dir: String = ProjectSettings.globalize_path(
		"user://hit_music_serial"
	)
	var spool_dir: String = base_dir.path_join("spool")
	DirAccess.make_dir_recursive_absolute(spool_dir)

	var name: String = "cmd_%020d_%d.cmd" % [
		Time.get_ticks_usec(),
		OS.get_process_id(),
	]
	var final_path: String = spool_dir.path_join(name)
	var temporary_path: String = final_path + ".tmp"
	var file := FileAccess.open(
		temporary_path,
		FileAccess.WRITE
	)
	if file == null:
		return

	file.store_string(clean + "\n")
	file.flush()
	file.close()

	if FileAccess.file_exists(final_path):
		DirAccess.remove_absolute(final_path)

	var error: Error = DirAccess.rename_absolute(
		temporary_path,
		final_path
	)
	if (
		error != OK
		and FileAccess.file_exists(temporary_path)
	):
		DirAccess.remove_absolute(temporary_path)


static func _rgb(color: Color) -> Vector3i:
	return Vector3i(
		int(round(clampf(color.r, 0.0, 1.0) * 255.0)),
		int(round(clampf(color.g, 0.0, 1.0) * 255.0)),
		int(round(clampf(color.b, 0.0, 1.0) * 255.0))
	)

'@

Write-Utf8NoBom (Project-Path "scripts\hit_music_r7\theme_overlay_v10.gd") @'
extends Node2D

var center: Vector2 = Vector2.ZERO
var radius: float = 100.0
var song_id: String = "carmine"
var primary: Color = Color(0.05, 0.92, 1.0, 1.0)
var secondary: Color = Color.WHITE
var accent: Color = Color(1.0, 0.84, 0.05, 1.0)
var song_time: float = 0.0
var game_state: String = "presentation"


func configure(
	new_center: Vector2,
	new_radius: float,
	song: Dictionary
) -> void:
	center = new_center
	radius = new_radius
	song_id = str(song.get("id", "carmine"))

	var colors_value: Variant = song.get("colors", {})
	if colors_value is Dictionary:
		var colors: Dictionary = colors_value as Dictionary
		primary = colors.get("primary", primary)
		secondary = colors.get("secondary", secondary)
		accent = colors.get("accent", accent)

	queue_redraw()


func set_runtime(
	new_song_time: float,
	new_game_state: String
) -> void:
	song_time = new_song_time
	game_state = new_game_state
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if radius <= 0.0:
		return

	var time_value: float = song_time
	if game_state == "presentation":
		time_value = float(Time.get_ticks_msec()) / 1000.0

	match song_id:
		"carmine":
			_draw_carmine_mandala(time_value)
		"dragon_ball":
			_draw_energy_hex(time_value)
		"naruto":
			_draw_ninja_seal(time_value)
		"demon":
			_draw_demon_diamonds(time_value)
		"fairy":
			_draw_magic_stars(time_value)
		"rick_morty":
			_draw_portal_science(time_value)
		"soul":
			_draw_soul_orbits(time_value)
		_:
			_draw_carmine_mandala(time_value)


func _draw_carmine_mandala(time_value: float) -> void:
	var rotation: float = time_value * 0.08
	var beat: float = 0.5 + 0.5 * sin(time_value * 2.8)

	for ring in range(1, 7):
		var ring_radius: float = radius * (
			0.12 + float(ring) * 0.105
		)
		var sides: int = 4 if ring % 2 == 0 else 8
		var color: Color = (
			primary
			if ring % 2 == 0
			else accent
		)
		color.a = 0.08 + float(ring) * 0.012

		for index in range(sides):
			var angle: float = rotation * (
				1.0 if ring % 2 == 0 else -0.72
			)
			angle += TAU * float(index) / float(sides)
			var p: Vector2 = center + Vector2(
				cos(angle),
				sin(angle)
			) * ring_radius
			_draw_polygon_outline(
				p,
				radius * (
					0.035 + float(ring) * 0.004
				),
				4 if ring % 3 != 0 else 6,
				angle + PI * 0.25,
				color,
				maxf(1.0, radius * 0.0024)
			)

	for ray in range(16):
		var angle: float = rotation * 0.45
		angle += TAU * float(ray) / 16.0
		var direction := Vector2(cos(angle), sin(angle))
		var start: Vector2 = center + direction * radius * 0.17
		var end: Vector2 = center + direction * radius * (
			0.70 + beat * 0.025
		)
		draw_line(
			start,
			end,
			Color(
				primary.r,
				primary.g,
				primary.b,
				0.055
			),
			maxf(1.0, radius * 0.0018),
			true
		)

	for ring in range(4):
		draw_arc(
			center,
			radius * (0.23 + float(ring) * 0.14),
			rotation * (0.7 if ring % 2 == 0 else -0.5),
			TAU + rotation * (
				0.7 if ring % 2 == 0 else -0.5
			),
			128,
			Color(
				accent.r,
				accent.g,
				accent.b,
				0.055 + float(ring) * 0.012
			),
			maxf(1.0, radius * 0.002),
			true
		)

	_draw_center_rosette(
		rotation,
		radius * (0.16 + beat * 0.008),
		primary,
		accent
	)


func _draw_energy_hex(time_value: float) -> void:
	var rotation: float = time_value * 0.13
	for ring in range(2, 7):
		var count: int = 6 + ring * 2
		var ring_radius: float = radius * (
			0.12 + float(ring) * 0.105
		)
		for index in range(count):
			var angle: float = rotation
			angle += TAU * float(index) / float(count)
			var p: Vector2 = center + Vector2(
				cos(angle),
				sin(angle)
			) * ring_radius
			var color: Color = primary.lerp(
				accent,
				float(index % 4) * 0.10
			)
			color.a = 0.08
			_draw_polygon_outline(
				p,
				radius * 0.032,
				6,
				rotation,
				color,
				maxf(1.0, radius * 0.002)
			)


func _draw_ninja_seal(time_value: float) -> void:
	var rotation: float = -time_value * 0.10
	for ring in range(1, 6):
		var ring_radius: float = radius * (
			0.14 + float(ring) * 0.12
		)
		draw_arc(
			center,
			ring_radius,
			rotation + float(ring) * 0.24,
			rotation + TAU - float(ring) * 0.16,
			96,
			Color(
				primary.r,
				primary.g,
				primary.b,
				0.07
			),
			maxf(1.0, radius * 0.002),
			true
		)

	for index in range(12):
		var angle: float = rotation
		angle += TAU * float(index) / 12.0
		var direction := Vector2(cos(angle), sin(angle))
		draw_line(
			center + direction * radius * 0.20,
			center + direction * radius * 0.70,
			Color(
				accent.r,
				accent.g,
				accent.b,
				0.055
			),
			maxf(1.0, radius * 0.0017),
			true
		)


func _draw_demon_diamonds(time_value: float) -> void:
	var rotation: float = time_value * 0.07
	for ring in range(2, 7):
		var count: int = 8 + ring
		var ring_radius: float = radius * (
			0.11 + float(ring) * 0.105
		)
		for index in range(count):
			var angle: float = rotation * (
				1.0 if ring % 2 == 0 else -0.8
			)
			angle += TAU * float(index) / float(count)
			var p: Vector2 = center + Vector2(
				cos(angle),
				sin(angle)
			) * ring_radius
			_draw_polygon_outline(
				p,
				radius * 0.030,
				4,
				angle,
				Color(
					primary.r,
					primary.g,
					primary.b,
					0.07
				),
				maxf(1.0, radius * 0.002)
			)


func _draw_magic_stars(time_value: float) -> void:
	var rotation: float = time_value * 0.09
	for ring in range(2, 6):
		var count: int = 5 + ring * 2
		var ring_radius: float = radius * (
			0.16 + float(ring) * 0.11
		)
		for index in range(count):
			var angle: float = rotation
			angle += TAU * float(index) / float(count)
			var p: Vector2 = center + Vector2(
				cos(angle),
				sin(angle)
			) * ring_radius
			_draw_star_outline(
				p,
				radius * 0.035,
				angle,
				Color(
					accent.r,
					accent.g,
					accent.b,
					0.08
				)
			)


func _draw_portal_science(time_value: float) -> void:
	var rotation: float = time_value * 0.16
	for ring in range(1, 7):
		var ring_radius: float = radius * (
			0.12 + float(ring) * 0.105
		)
		draw_arc(
			center,
			ring_radius,
			rotation + float(ring) * 0.3,
			rotation + PI * 1.55 + float(ring) * 0.3,
			72,
			Color(
				primary.r,
				primary.g,
				primary.b,
				0.08
			),
			maxf(1.0, radius * 0.003),
			true
		)


func _draw_soul_orbits(time_value: float) -> void:
	var rotation: float = time_value * 0.06
	for ring in range(1, 7):
		var ring_radius: float = radius * (
			0.13 + float(ring) * 0.10
		)
		var wobble: float = sin(
			time_value * 0.7 + float(ring)
		) * radius * 0.012
		draw_arc(
			center + Vector2(wobble, -wobble),
			ring_radius,
			rotation * (
				1.0 if ring % 2 == 0 else -1.0
			),
			TAU + rotation * (
				1.0 if ring % 2 == 0 else -1.0
			),
			96,
			Color(
				secondary.r,
				secondary.g,
				secondary.b,
				0.055
			),
			maxf(1.0, radius * 0.002),
			true
		)


func _draw_center_rosette(
	rotation: float,
	size: float,
	color_a: Color,
	color_b: Color
) -> void:
	for index in range(8):
		var angle: float = rotation
		angle += TAU * float(index) / 8.0
		var p: Vector2 = center + Vector2(
			cos(angle),
			sin(angle)
		) * size * 0.58
		_draw_polygon_outline(
			p,
			size * 0.42,
			4,
			angle,
			Color(
				color_a.r,
				color_a.g,
				color_a.b,
				0.12
			),
			maxf(1.0, radius * 0.0025)
		)

	draw_arc(
		center,
		size,
		rotation,
		TAU + rotation,
		96,
		Color(
			color_b.r,
			color_b.g,
			color_b.b,
			0.10
		),
		maxf(1.0, radius * 0.003),
		true
	)


func _draw_polygon_outline(
	position_value: Vector2,
	size: float,
	sides: int,
	rotation_value: float,
	color: Color,
	width: float
) -> void:
	var points := PackedVector2Array()
	for index in range(sides + 1):
		var angle: float = rotation_value
		angle += TAU * float(index) / float(sides)
		points.append(
			position_value + Vector2(
				cos(angle),
				sin(angle)
			) * size
		)
	draw_polyline(points, color, width, true)


func _draw_star_outline(
	position_value: Vector2,
	size: float,
	rotation_value: float,
	color: Color
) -> void:
	var points := PackedVector2Array()
	for index in range(11):
		var angle: float = rotation_value - PI * 0.5
		angle += PI * float(index) / 5.0
		var point_radius: float = (
			size
			if index % 2 == 0
			else size * 0.42
		)
		points.append(
			position_value + Vector2(
				cos(angle),
				sin(angle)
			) * point_radius
		)
	draw_polyline(
		points,
		color,
		maxf(1.0, radius * 0.0022),
		true
	)

'@

Write-Utf8NoBom (Project-Path "scripts\hit_music_r7\stage_v10.gd") @'
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

'@

Write-Utf8NoBom (Project-Path "scripts\hit_music_r7\selector_v10.gd") @'
extends "res://scripts/hit_music_r7/selector_v9.gd"

var _touch_dragging: bool = false
var _touch_start: Vector2 = Vector2.ZERO
var _touch_last: Vector2 = Vector2.ZERO
var _touch_velocity: float = 0.0


func _ready() -> void:
	Engine.max_fps = 120
	super._ready()
	LED_CLIENT.menu_state(
		_index,
		_song_primary(_songs[_index] as Dictionary)
	)


func _process(delta: float) -> void:
	super._process(delta)
	_touch_velocity = lerpf(
		_touch_velocity,
		0.0,
		1.0 - exp(-7.0 * delta)
	)


func _toggle_difficulty() -> void:
	LED_CLIENT.menu_select_feedback()
	_start_selected()


func _change_selection(direction: int) -> void:
	super._change_selection(direction)
	LED_CLIENT.menu_next_feedback()
	LED_CLIENT.menu_state(
		_index,
		_song_primary(_songs[_index] as Dictionary)
	)


func _input(event: InputEvent) -> void:
	if _transitioning:
		return

	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed:
			_touch_dragging = true
			_touch_start = touch.position
			_touch_last = touch.position
			_touch_velocity = 0.0
		else:
			var delta_y: float = (
				touch.position.y - _touch_start.y
			)
			_touch_dragging = false

			if absf(delta_y) > _radius * 0.08:
				_change_selection(
					1 if delta_y < 0.0 else -1
				)
			else:
				_handle_touch(touch.position)

	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		var movement: float = (
			drag.position.y - _touch_last.y
		)
		_touch_velocity = movement
		_touch_last = drag.position

	elif (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
	):
		var mouse: InputEventMouseButton = event
		if mouse.pressed:
			_touch_dragging = true
			_touch_start = mouse.position
			_touch_last = mouse.position
		else:
			var delta_y: float = (
				mouse.position.y - _touch_start.y
			)
			_touch_dragging = false

			if absf(delta_y) > _radius * 0.08:
				_change_selection(
					1 if delta_y < 0.0 else -1
				)
			else:
				_handle_touch(mouse.position)

	elif event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event
		if _touch_dragging:
			_touch_velocity = (
				motion.position.y - _touch_last.y
			)
			_touch_last = motion.position

	elif event is InputEventMouseButton:
		var wheel: InputEventMouseButton = event
		if wheel.pressed:
			if wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_change_selection(1)
			elif wheel.button_index == MOUSE_BUTTON_WHEEL_UP:
				_change_selection(-1)

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
extends "res://scripts/hit_music_r7/stage_v10.gd"

func _song_id() -> String:
	return "$SongId"
"@

    Write-Utf8NoBom (Project-Path $RelativePath) $Content
}

Write-Utf8NoBom (Project-Path "scripts\change_scenes.gd") @'
extends "res://scripts/hit_music_r7/selector_v10.gd"
'@

$GeneratedFiles = @(
    "scripts\hit_music_r7\led_client.gd",
    "scripts\hit_music_r7\theme_overlay_v10.gd",
    "scripts\hit_music_r7\stage_v10.gd",
    "scripts\hit_music_r7\selector_v10.gd",
    "scripts\change_scenes.gd"
)

Write-Host ""
Write-Host "VALIDANDO:" -ForegroundColor Cyan

foreach ($RelativePath in $GeneratedFiles) {
    $FullPath = Project-Path $RelativePath

    if (-not (Test-Path -LiteralPath $FullPath)) {
        throw "Falha ao criar: $RelativePath"
    }

    $Length = (Get-Item -LiteralPath $FullPath).Length
    if ($Length -le 20) {
        throw "Arquivo invalido: $RelativePath"
    }

    Write-Host "[OK] $RelativePath - $Length bytes" -ForegroundColor Green
}

$LedContent = Get-Content -LiteralPath (
    Project-Path "scripts\hit_music_r7\led_client.gd"
) -Raw

if ($LedContent -notmatch "MENU %d %d %d %d %d %d") {
    throw "O comando MENU de seis cores nao foi instalado."
}

$GitAvailable = $null -ne (
    Get-Command git -ErrorAction SilentlyContinue
)
$GitRepository = Test-Path -LiteralPath (
    Project-Path ".git"
)

if ($GitAvailable -and $GitRepository) {
    $CurrentBranch = git branch --show-current

    if ($CurrentBranch -ne "main") {
        throw "Use a branch main. Branch atual: $CurrentBranch"
    }

    git add scripts/hit_music_r7/led_client.gd
    git add scripts/hit_music_r7/theme_overlay_v10.gd
    git add scripts/hit_music_r7/stage_v10.gd
    git add scripts/hit_music_r7/selector_v10.gd
    git add scripts/change_scenes.gd
    git add scripts/carmine.gd
    git add scripts/dragon_ball.gd
    git add scripts/demon.gd
    git add scripts/fairy.gd
    git add scripts/naruto.gd
    git add scripts/rick_morty.gd
    git add scripts/soul.gd

    git commit -m "R10 adiciona score progressivo, mandala, touch e leds por input"

    if ($Push) {
        git push origin main
    }
}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Green
Write-Host " R10 EMBUTIDA COM SUCESSO" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "Backup: $BackupRoot"
Write-Host ""
Write-Host "Agora compile o arquivo Arduino R10 e rode o Godot com F5." -ForegroundColor Yellow
