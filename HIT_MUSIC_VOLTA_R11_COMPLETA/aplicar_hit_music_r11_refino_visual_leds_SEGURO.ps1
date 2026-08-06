param(
    [string]$ProjectRoot = (Get-Location).Path,
    [switch]$Push
)

$ErrorActionPreference = "Stop"
$Version = "R11_REFINO_VISUAL_GAMEPLAY_LEDS_20260806"

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
Write-Host " HIT MUSIC R11 - REFINO VISUAL E LEDS" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Versao: $Version" -ForegroundColor DarkGray
Write-Host "Projeto: $ProjectRoot"
Write-Host ""

Require-File "project.godot"
Require-File "scripts\hit_music_r7\stage_v10.gd"
Require-File "scripts\hit_music_r7\selector_v10.gd"
Require-File "scripts\hit_music_r7\led_client.gd"

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupRoot = Project-Path "_backup_hit_music_r11_$Stamp"
New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null

$FilesToBackup = @(
    "scripts\hit_music_r7\led_client.gd",
    "scripts\hit_music_r7\stage_v10.gd",
    "scripts\hit_music_r7\selector_v10.gd",
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

Write-Host "Aplicando R11..." -ForegroundColor Yellow

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

Write-Utf8NoBom (Project-Path "scripts\hit_music_r7\theme_overlay_v11.gd") @'
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

	var t: float = song_time
	if game_state == "presentation":
		t = float(Time.get_ticks_msec()) / 1000.0

	match song_id:
		"carmine":
			_draw_carmine_mandala(t)
		"dragon_ball":
			_draw_dragon_energy(t)
		"naruto":
			_draw_naruto_seal(t)
		"demon":
			_draw_demon_crystal(t)
		"fairy":
			_draw_fairy_glyph(t)
		"rick_morty":
			_draw_portal_lab(t)
		"soul":
			_draw_soul_orbit(t)
		_:
			_draw_carmine_mandala(t)


func _draw_carmine_mandala(t: float) -> void:
	var pulse: float = 0.5 + 0.5 * sin(t * 2.1)
	var rot_a: float = t * 0.18
	var rot_b: float = -t * 0.12

	for ring in range(1, 6):
		var ring_radius: float = radius * (0.16 + 0.12 * float(ring))
		var count: int = 8 if ring % 2 == 0 else 12
		var poly_sides: int = 4 if ring % 2 == 0 else 6
		var rot: float = rot_a if ring % 2 == 0 else rot_b
		var col: Color = primary if ring % 2 == 0 else accent
		col.a = 0.08 + 0.01 * float(ring)

		for i in range(count):
			var ang: float = rot + TAU * float(i) / float(count)
			var pos: Vector2 = center + Vector2(cos(ang), sin(ang)) * ring_radius
			_draw_polygon_outline(
				pos,
				radius * (0.030 + 0.002 * float(ring)),
				poly_sides,
				ang + PI * 0.25,
				col,
				maxf(1.0, radius * 0.0023)
			)

	for spoke in range(16):
		var ang: float = rot_a * 0.55 + TAU * float(spoke) / 16.0
		var dir: Vector2 = Vector2(cos(ang), sin(ang))
		draw_line(
			center + dir * radius * 0.16,
			center + dir * radius * (0.72 + pulse * 0.03),
			Color(primary.r, primary.g, primary.b, 0.07),
			maxf(1.0, radius * 0.0019),
			true
		)

	for ring2 in range(4):
		draw_arc(
			center,
			radius * (0.18 + 0.15 * float(ring2)),
			rot_b + float(ring2) * 0.20,
			TAU + rot_b + float(ring2) * 0.20,
			96,
			Color(accent.r, accent.g, accent.b, 0.06 + 0.01 * float(ring2)),
			maxf(1.0, radius * 0.0022),
			true
		)

	for diamond_ring in range(1, 4):
		var rr: float = radius * (0.20 + 0.16 * float(diamond_ring))
		for j in range(4):
			var a: float = rot_b + PI * 0.25 + TAU * float(j) / 4.0
			var p: Vector2 = center + Vector2(cos(a), sin(a)) * rr
			_draw_polygon_outline(
				p,
				radius * 0.055,
				4,
				a,
				Color(secondary.r, secondary.g, secondary.b, 0.085),
				maxf(1.0, radius * 0.0025)
			)

	_draw_center_flower(rot_a, pulse)


func _draw_center_flower(rot: float, pulse: float) -> void:
	for k in range(8):
		var a: float = rot + TAU * float(k) / 8.0
		var pos: Vector2 = center + Vector2(cos(a), sin(a)) * radius * 0.10
		_draw_polygon_outline(
			pos,
			radius * 0.05,
			4,
			a + PI * 0.25,
			Color(primary.r, primary.g, primary.b, 0.13),
			maxf(1.0, radius * 0.0024)
		)

	draw_arc(
		center,
		radius * (0.09 + pulse * 0.01),
		rot,
		TAU + rot,
		96,
		Color(accent.r, accent.g, accent.b, 0.10),
		maxf(1.0, radius * 0.003),
		true
	)
	_draw_polygon_outline(
		center,
		radius * 0.075,
		8,
		rot * 0.8,
		Color(secondary.r, secondary.g, secondary.b, 0.10),
		maxf(1.0, radius * 0.0027)
	)


func _draw_dragon_energy(t: float) -> void:
	var rot: float = t * 0.22
	for ring in range(2, 6):
		var rr: float = radius * (0.20 + 0.12 * float(ring))
		var count: int = 6 + ring * 3
		for i in range(count):
			var a: float = rot + TAU * float(i) / float(count)
			var p: Vector2 = center + Vector2(cos(a), sin(a)) * rr
			_draw_polygon_outline(
				p,
				radius * 0.028,
				6,
				rot + a,
				Color(primary.r, primary.g, primary.b, 0.08),
				maxf(1.0, radius * 0.002)
			)
			draw_line(
				center + Vector2(cos(a), sin(a)) * radius * 0.12,
				p,
				Color(accent.r, accent.g, accent.b, 0.04),
				maxf(1.0, radius * 0.0017),
				true
			)


func _draw_naruto_seal(t: float) -> void:
	var rot: float = -t * 0.16
	for ring in range(1, 6):
		var rr: float = radius * (0.18 + 0.12 * float(ring))
		draw_arc(
			center,
			rr,
			rot + float(ring) * 0.3,
			rot + TAU - float(ring) * 0.22,
			96,
			Color(primary.r, primary.g, primary.b, 0.07),
			maxf(1.0, radius * 0.002),
			true
		)
	for i in range(12):
		var a: float = rot + TAU * float(i) / 12.0
		draw_line(
			center + Vector2(cos(a), sin(a)) * radius * 0.18,
			center + Vector2(cos(a), sin(a)) * radius * 0.72,
			Color(accent.r, accent.g, accent.b, 0.06),
			maxf(1.0, radius * 0.0019),
			true
		)
	_draw_polygon_outline(
		center,
		radius * 0.09,
		6,
		rot,
		Color(secondary.r, secondary.g, secondary.b, 0.11),
		maxf(1.0, radius * 0.0024)
	)


func _draw_demon_crystal(t: float) -> void:
	var rot: float = t * 0.10
	for ring in range(2, 7):
		var rr: float = radius * (0.16 + 0.10 * float(ring))
		var count: int = 8 + ring
		for i in range(count):
			var a: float = rot * (1.0 if ring % 2 == 0 else -1.0) + TAU * float(i) / float(count)
			var p: Vector2 = center + Vector2(cos(a), sin(a)) * rr
			_draw_polygon_outline(
				p,
				radius * 0.032,
				4,
				a,
				Color(primary.r, primary.g, primary.b, 0.08),
				maxf(1.0, radius * 0.0021)
			)


func _draw_fairy_glyph(t: float) -> void:
	var rot: float = t * 0.14
	for ring in range(1, 5):
		var rr: float = radius * (0.22 + 0.13 * float(ring))
		var count: int = 5 + ring * 2
		for i in range(count):
			var a: float = rot + TAU * float(i) / float(count)
			var p: Vector2 = center + Vector2(cos(a), sin(a)) * rr
			_draw_star_outline(
				p,
				radius * 0.036,
				a,
				Color(accent.r, accent.g, accent.b, 0.08)
			)


func _draw_portal_lab(t: float) -> void:
	var rot: float = t * 0.20
	for ring in range(1, 7):
		var rr: float = radius * (0.14 + 0.11 * float(ring))
		draw_arc(
			center,
			rr,
			rot + float(ring) * 0.3,
			rot + PI * 1.55 + float(ring) * 0.3,
			72,
			Color(primary.r, primary.g, primary.b, 0.08),
			maxf(1.0, radius * 0.003),
			true
		)
		if ring < 6:
			_draw_polygon_outline(
				center,
				rr * 0.16,
				6,
				rot + float(ring),
				Color(secondary.r, secondary.g, secondary.b, 0.05),
				maxf(1.0, radius * 0.0018)
			)


func _draw_soul_orbit(t: float) -> void:
	var rot: float = t * 0.08
	for ring in range(1, 6):
		var rr: float = radius * (0.18 + 0.12 * float(ring))
		var wobble: float = sin(t * 0.8 + float(ring)) * radius * 0.012
		draw_arc(
			center + Vector2(wobble, -wobble),
			rr,
			rot * (1.0 if ring % 2 == 0 else -1.0),
			TAU + rot * (1.0 if ring % 2 == 0 else -1.0),
			96,
			Color(secondary.r, secondary.g, secondary.b, 0.06),
			maxf(1.0, radius * 0.002),
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
		var angle: float = rotation_value + TAU * float(index) / float(sides)
		points.append(
			position_value + Vector2(cos(angle), sin(angle)) * size
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
		var angle: float = rotation_value - PI * 0.5 + PI * float(index) / 5.0
		var point_radius: float = size if index % 2 == 0 else size * 0.42
		points.append(
			position_value + Vector2(cos(angle), sin(angle)) * point_radius
		)
	draw_polyline(
		points,
		color,
		maxf(1.0, radius * 0.0021),
		true
	)

'@

Write-Utf8NoBom (Project-Path "scripts\hit_music_r7\stage_v11.gd") @'
extends "res://scripts/hit_music_r7/stage_v10.gd"

const GUIDE_PRELIGHT_SEC: float = 0.95
const GUIDE_LATE_CUTOFF_SEC: float = 0.14
const THEME_OVERLAY_V11: Script = preload(
	"res://scripts/hit_music_r7/theme_overlay_v11.gd"
)

var _theme_overlay_v11
var _lane_led_cache_active: Array = []
var _lane_led_cache_colors: Array = []


func _ready() -> void:
	Engine.max_fps = 144
	super._ready()

	_lane_led_cache_active.resize(8)
	_lane_led_cache_colors.resize(8)
	for lane in range(8):
		_lane_led_cache_active[lane] = false
		_lane_led_cache_colors[lane] = Color.BLACK

	if _theme_overlay_v10 != null:
		_theme_overlay_v10.queue_free()
		_theme_overlay_v10 = null

	_build_theme_overlay_v11()
	_apply_scene_led_theme()


func _process(delta: float) -> void:
	super._process(delta)

	if _theme_overlay_v11 != null:
		_theme_overlay_v11.set_runtime(
			_song_time,
			_state_name()
		)

	_update_gameplay_lane_leds(delta)


func _start_countdown() -> void:
	_apply_scene_led_theme()
	super._start_countdown()


func _start_playing() -> void:
	_apply_scene_led_theme()
	super._start_playing()


func _build_theme_overlay_v11() -> void:
	_theme_overlay_v11 = THEME_OVERLAY_V11.new()
	_theme_overlay_v11.name = "ThemeOverlayV11"
	_theme_overlay_v11.z_index = 8
	add_child(_theme_overlay_v11)
	_theme_overlay_v11.configure(
		_center,
		_radius,
		_song
	)


func _on_viewport_size_changed() -> void:
	super._on_viewport_size_changed()

	if _theme_overlay_v11 != null:
		_theme_overlay_v11.configure(
			_center,
			_radius,
			_song
		)


func _apply_scene_led_theme() -> void:
	LED_CLIENT.scene_state(
		_primary_color(),
		_accent_color()
	)


func _update_gameplay_lane_leds(_delta: float) -> void:
	var state_name: String = _state_name()
	if state_name != "countdown" and state_name != "playing":
		_clear_gameplay_lane_leds()
		return

	if _events.is_empty():
		return

	var now: float = 0.0 if state_name == "countdown" else _song_time
	var desired_active: Array = []
	var desired_colors: Array = []
	var best_dt: Array = []

	desired_active.resize(8)
	desired_colors.resize(8)
	best_dt.resize(8)

	for lane in range(8):
		desired_active[lane] = false
		desired_colors[lane] = Color.BLACK
		best_dt[lane] = 99999.0

	for event_value in _events:
		if not (event_value is Dictionary):
			continue

		var event: Dictionary = event_value as Dictionary
		var type_name: String = str(event.get("type", "tap"))
		if type_name != "tap" and type_name != "hold":
			continue

		var lane: int = int(event.get("lane", -1))
		if lane < 0 or lane > 7:
			continue

		var start_time: float = _event_start_time(event)
		var end_time: float = _event_end_time(event, start_time)

		if type_name == "hold" and now >= start_time and now <= end_time:
			desired_active[lane] = true
			desired_colors[lane] = _event_color(event)
			best_dt[lane] = -1.0
			continue

		var dt: float = start_time - now
		if dt < -GUIDE_LATE_CUTOFF_SEC:
			continue
		if dt > GUIDE_PRELIGHT_SEC:
			continue
		if dt < float(best_dt[lane]):
			desired_active[lane] = true
			desired_colors[lane] = _event_color(event)
			best_dt[lane] = dt

	for lane2 in range(8):
		var should_enable: bool = bool(desired_active[lane2])
		var last_enable: bool = bool(_lane_led_cache_active[lane2])

		if should_enable:
			var desired_color: Color = desired_colors[lane2]
			var last_color: Color = _lane_led_cache_colors[lane2]

			if not last_enable or last_color != desired_color:
				LED_CLIENT.set_lane(lane2, desired_color)

			_lane_led_cache_active[lane2] = true
			_lane_led_cache_colors[lane2] = desired_color
		else:
			if last_enable:
				LED_CLIENT.clear_lane(lane2)

			_lane_led_cache_active[lane2] = false
			_lane_led_cache_colors[lane2] = Color.BLACK


func _clear_gameplay_lane_leds() -> void:
	for lane in range(8):
		if (
			_lane_led_cache_active.size() > lane
			and bool(_lane_led_cache_active[lane])
		):
			LED_CLIENT.clear_lane(lane)

	if _lane_led_cache_active.is_empty():
		return

	for lane2 in range(8):
		_lane_led_cache_active[lane2] = false
		_lane_led_cache_colors[lane2] = Color.BLACK


func _event_start_time(event: Dictionary) -> float:
	if event.has("time"):
		return float(event.get("time", 0.0))
	if event.has("start"):
		return float(event.get("start", 0.0))
	if event.has("start_time"):
		return float(event.get("start_time", 0.0))
	return 0.0


func _event_end_time(
	event: Dictionary,
	start_time: float
) -> float:
	if event.has("end_time"):
		return float(event.get("end_time", start_time))
	if event.has("end"):
		return float(event.get("end", start_time))
	if event.has("duration"):
		return start_time + float(event.get("duration", 0.0))
	return start_time

'@

Write-Utf8NoBom (Project-Path "scripts\hit_music_r7\selector_v11.gd") @'
extends "res://scripts/hit_music_r7/selector_v10.gd"

var _drag_total: float = 0.0


func _ready() -> void:
	Engine.max_fps = 144
	super._ready()


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
			_drag_total = 0.0
		else:
			_touch_dragging = false
			if absf(_drag_total) > _radius * 0.08:
				_change_selection(
					1 if _drag_total < 0.0 else -1
				)
			else:
				_handle_touch(touch.position)

	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		if _touch_dragging:
			var movement: float = drag.position.y - _touch_last.y
			_drag_total += movement
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
			_touch_velocity = 0.0
			_drag_total = 0.0
		else:
			_touch_dragging = false
			if absf(_drag_total) > _radius * 0.08:
				_change_selection(
					1 if _drag_total < 0.0 else -1
				)
			else:
				_handle_touch(mouse.position)

	elif event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event
		if _touch_dragging:
			var move_y: float = motion.position.y - _touch_last.y
			_drag_total += move_y
			_touch_velocity = move_y
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
extends "res://scripts/hit_music_r7/stage_v11.gd"

func _song_id() -> String:
	return "$SongId"
"@
    Write-Utf8NoBom (Project-Path $RelativePath) $Content
}

Write-Utf8NoBom (Project-Path "scripts\change_scenes.gd") @'
extends "res://scripts/hit_music_r7/selector_v11.gd"
'@

$GeneratedFiles = @(
    "scripts\hit_music_r7\led_client.gd",
    "scripts\hit_music_r7\theme_overlay_v11.gd",
    "scripts\hit_music_r7\stage_v11.gd",
    "scripts\hit_music_r7\selector_v11.gd",
    "scripts\change_scenes.gd"
)

Write-Host ""
Write-Host "VALIDANDO..." -ForegroundColor Cyan
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

$GitAvailable = $null -ne (Get-Command git -ErrorAction SilentlyContinue)
$GitRepository = Test-Path -LiteralPath (Project-Path ".git")

if ($GitAvailable -and $GitRepository) {
    git add scripts/hit_music_r7/led_client.gd
    git add scripts/hit_music_r7/theme_overlay_v11.gd
    git add scripts/hit_music_r7/stage_v11.gd
    git add scripts/hit_music_r7/selector_v11.gd
    git add scripts/change_scenes.gd
    git add scripts/carmine.gd
    git add scripts/dragon_ball.gd
    git add scripts/demon.gd
    git add scripts/fairy.gd
    git add scripts/naruto.gd
    git add scripts/rick_morty.gd
    git add scripts/soul.gd

    git commit -m "R11 refina visual, mandalas e leds de gameplay" 2>$null

    if ($Push) {
        git push origin main
    }
}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Green
Write-Host " R11 APLICADA COM SUCESSO" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "Backup: $BackupRoot"
Write-Host ""
Write-Host "Agora compile o Arduino R11 e rode F5 no Godot." -ForegroundColor Yellow
