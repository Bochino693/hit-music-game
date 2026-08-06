param(
    [string]$ProjectRoot = (Get-Location).Path
)

$ErrorActionPreference = "Stop"
$Version = "R7_EFFECTS_PRO_20260806"

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
    $FullPath = Project-Path $RelativePath
    if (-not (Test-Path -LiteralPath $FullPath)) {
        throw "Arquivo obrigatorio nao encontrado: $RelativePath"
    }
}

Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host " HIT MUSIC R7 - EFFECTS PRO / MENU MODERNO" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "Versao: $Version" -ForegroundColor DarkGray
Write-Host "Projeto: $ProjectRoot"
Write-Host ""

Require-File "project.godot"
Require-File "scripts\hit_music_r7\stage.gd"
Require-File "scripts\hit_music_r7\catalog.gd"
Require-File "scripts\hit_music_r7\path_builder.gd"
Require-File "scripts\hit_music_r7\selector.gd"
Require-File "scripts\hit_music_r7\playfield_renderer.gd"
Require-File "scripts\hit_music_r7\tap_visual.gd"
Require-File "data\hit_music_songs.json"
Require-File "entities\tazo.tscn"

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupRoot = Project-Path "_backup_hit_music_r7_effects_$Stamp"
New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null

$FilesToBackup = @(
    "scripts\hit_music_r7\selector.gd",
    "scripts\hit_music_r7\playfield_renderer.gd",
    "scripts\hit_music_r7\tap_visual.gd",
    "scripts\change_scenes.gd"
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

$GitAvailable = $null -ne (Get-Command git -ErrorAction SilentlyContinue)
if ($GitAvailable -and (Test-Path -LiteralPath (Project-Path ".git"))) {
    $Dirty = git status --porcelain
    if ($Dirty) {
        git add -A
        git commit -m "Checkpoint before R7 effects pro"
    }

    $BackupBranch = "backup/pre-r7-effects-$Stamp"
    git branch $BackupBranch HEAD

    $TargetBranch = "r7-effects-pro"
    $BranchExists = git branch --list $TargetBranch
    if ($BranchExists) {
        git switch $TargetBranch
    }
    else {
        git switch -c $TargetBranch
    }

    Write-Host "Branch de backup: $BackupBranch" -ForegroundColor DarkGray
    Write-Host "Branch de trabalho: $TargetBranch" -ForegroundColor DarkGray
}

Write-Host "Gravando efeitos e seletor profissional..." -ForegroundColor Yellow

Write-Utf8NoBom (Project-Path "scripts\hit_music_r7\tap_visual.gd") @'
extends Node2D

const TAZO_SCENE: PackedScene = preload("res://entities/tazo.tscn")

var origin: Vector2 = Vector2.ZERO
var target: Vector2 = Vector2.ZERO
var spawn_time: float = 0.0
var hit_time: float = 1.0
var desired_diameter: float = 100.0
var frame_index: int = 0

var _sprite: AnimatedSprite2D
var _progress: float = 0.0
var _current_scale: float = 1.0
var _visual_color: Color = Color(0.10, 0.92, 1.0, 1.0)


func _ready() -> void:
	var instance: Node = TAZO_SCENE.instantiate()
	if not instance is Node2D:
		push_error("res://entities/tazo.tscn precisa ter raiz Node2D.")
		instance.queue_free()
		return

	add_child(instance)
	_sprite = _find_sprite(instance)
	if _sprite != null:
		_sprite.animation = &"idle"
		_sprite.stop()
		_sprite.frame = clampi(frame_index, 0, 2)
		_sprite.centered = true
		_sprite.position = Vector2.ZERO

	z_index = 30
	queue_redraw()


func configure(
	new_origin: Vector2,
	new_target: Vector2,
	new_spawn_time: float,
	new_hit_time: float,
	new_diameter: float,
	new_frame_index: int
) -> void:
	origin = new_origin
	target = new_target
	spawn_time = new_spawn_time
	hit_time = new_hit_time
	desired_diameter = new_diameter
	frame_index = clampi(new_frame_index, 0, 2)
	position = origin
	_visual_color = _frame_color(frame_index)

	if _sprite != null:
		_sprite.frame = frame_index

	queue_redraw()


func update_visual(song_time: float) -> void:
	var duration: float = maxf(hit_time - spawn_time, 0.001)
	_progress = clampf((song_time - spawn_time) / duration, 0.0, 1.0)

	var eased: float = 1.0 - pow(1.0 - _progress, 4.0)
	position = origin.lerp(target, eased)

	var source_diameter: float = 160.0
	_current_scale = desired_diameter / source_diameter
	_current_scale *= lerpf(0.58, 1.0, eased)
	scale = Vector2.ONE * _current_scale

	var pulse: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.016)
	modulate = Color(1.0, 1.0, 1.0, 0.90 + pulse * 0.10)
	queue_redraw()


func _draw() -> void:
	var pulse: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.018)
	var local_origin: Vector2 = origin - position
	var path_vector: Vector2 = local_origin
	var path_length: float = path_vector.length()

	if path_length > 1.0:
		var direction: Vector2 = path_vector / path_length
		for index in range(4):
			var t: float = 0.18 + float(index) * 0.16
			var ghost_position: Vector2 = direction * path_length * t
			var ghost_size: float = 19.0 - float(index) * 2.7
			var alpha: float = (0.18 - float(index) * 0.028) * (0.35 + _progress * 0.65)
			_draw_diamond(
				ghost_position,
				ghost_size,
				Color(_visual_color.r, _visual_color.g, _visual_color.b, alpha),
				3.2
			)

	var ring_radius: float = 76.0 + pulse * 6.0
	draw_circle(
		Vector2.ZERO,
		ring_radius * 0.78,
		Color(_visual_color.r, _visual_color.g, _visual_color.b, 0.075),
		true
	)
	draw_arc(
		Vector2.ZERO,
		ring_radius,
		0.0,
		TAU,
		44,
		Color(_visual_color.r, _visual_color.g, _visual_color.b, 0.36),
		5.0,
		true
	)
	draw_arc(
		Vector2.ZERO,
		ring_radius * 0.84,
		-PI * 0.68,
		PI * 0.10,
		26,
		Color.WHITE,
		3.0,
		true
	)

	for index in range(4):
		var angle: float = PI * 0.25 + float(index) * PI * 0.5
		var direction := Vector2(cos(angle), sin(angle))
		var inner: Vector2 = direction * (ring_radius * 0.94)
		var outer: Vector2 = direction * (ring_radius * 1.18)
		draw_line(
			inner,
			outer,
			Color(_visual_color.r, _visual_color.g, _visual_color.b, 0.38),
			3.0,
			true
		)


func _draw_diamond(
	position_value: Vector2,
	size: float,
	color: Color,
	width: float
) -> void:
	var points := PackedVector2Array([
		position_value + Vector2(0.0, -size),
		position_value + Vector2(size, 0.0),
		position_value + Vector2(0.0, size),
		position_value + Vector2(-size, 0.0),
		position_value + Vector2(0.0, -size),
	])
	draw_polyline(points, color, width, true)


func _frame_color(index: int) -> Color:
	match index:
		1:
			return Color(1.0, 0.84, 0.08, 1.0)
		2:
			return Color(1.0, 0.14, 0.45, 1.0)
		_:
			return Color(0.08, 0.92, 1.0, 1.0)


func _find_sprite(node: Node) -> AnimatedSprite2D:
	if node is AnimatedSprite2D:
		return node as AnimatedSprite2D
	for child in node.get_children():
		var result: AnimatedSprite2D = _find_sprite(child)
		if result != null:
			return result
	return null
'@

Write-Utf8NoBom (Project-Path "scripts\hit_music_r7\playfield_renderer.gd") @'
extends Node2D

const PATH_BUILDER: Script = preload("res://scripts/hit_music_r7/path_builder.gd")

var center: Vector2 = Vector2.ZERO
var radius: float = 100.0
var lane_positions: PackedVector2Array = PackedVector2Array()
var song: Dictionary = {}
var difficulty: Dictionary = {}
var events: Array = []
var song_time: float = 0.0
var game_state: String = "presentation"
var pointer_position: Vector2 = Vector2.ZERO
var pointer_active: bool = false
var effects: Array = []

var _video_style: StyleBoxFlat
var _video_inner_style: StyleBoxFlat


func _ready() -> void:
	_video_style = StyleBoxFlat.new()
	_video_style.bg_color = Color(0.002, 0.004, 0.012, 0.78)
	_video_style.border_color = Color(1.0, 1.0, 1.0, 0.22)
	_video_style.set_border_width_all(3)
	_video_style.set_corner_radius_all(24)
	_video_style.shadow_color = Color(0.0, 0.0, 0.0, 0.70)
	_video_style.shadow_size = 14

	_video_inner_style = StyleBoxFlat.new()
	_video_inner_style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	_video_inner_style.border_color = Color(1.0, 1.0, 1.0, 0.15)
	_video_inner_style.set_border_width_all(1)
	_video_inner_style.set_corner_radius_all(19)


func configure(
	new_center: Vector2,
	new_radius: float,
	new_lanes: PackedVector2Array,
	new_song: Dictionary,
	new_difficulty: Dictionary
) -> void:
	center = new_center
	radius = new_radius
	lane_positions = new_lanes
	song = new_song
	difficulty = new_difficulty
	queue_redraw()


func set_runtime(
	new_events: Array,
	new_song_time: float,
	new_state: String,
	new_pointer_position: Vector2,
	new_pointer_active: bool
) -> void:
	events = new_events
	song_time = new_song_time
	game_state = new_state
	pointer_position = new_pointer_position
	pointer_active = new_pointer_active
	queue_redraw()


func add_effect(kind: String, position_value: Vector2, color: Color) -> void:
	var duration: float = 0.46
	if kind == "slide":
		duration = 0.64
	elif kind == "hold":
		duration = 0.56
	elif kind == "miss":
		duration = 0.48

	effects.append({
		"kind": kind,
		"position": position_value,
		"color": color,
		"start": float(Time.get_ticks_msec()) / 1000.0,
		"duration": duration,
		"rotation": fmod(position_value.x * 0.017 + position_value.y * 0.013, TAU),
	})
	queue_redraw()


func _process(_delta: float) -> void:
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	for index in range(effects.size() - 1, -1, -1):
		var effect: Dictionary = effects[index]
		if now - float(effect.get("start", now)) >= float(effect.get("duration", 0.5)):
			effects.remove_at(index)

	if not effects.is_empty() or game_state == "playing" or game_state == "selector":
		queue_redraw()


func _draw() -> void:
	if radius <= 0.0:
		return

	_draw_circle_base()
	_draw_theme_geometry()
	_draw_video_frame()
	_draw_inner_technical_rings()
	_draw_ring()
	_draw_lane_energy()

	if game_state == "playing" or game_state == "countdown":
		for event_value in events:
			if not event_value is Dictionary:
				continue
			var event: Dictionary = event_value as Dictionary
			if bool(event.get("_resolved", false)):
				continue

			var type_name: String = str(event.get("type", "tap"))
			if type_name == "hold":
				_draw_hold(event)
			elif type_name == "slide":
				_draw_slide(event)

	_draw_effects()

	if pointer_active and game_state == "playing":
		_draw_pointer(pointer_position)


func _colors() -> Dictionary:
	var value: Variant = song.get("colors", {})
	if value is Dictionary:
		return value as Dictionary
	return {}


func _primary() -> Color:
	return _colors().get("primary", Color(0.05, 0.92, 1.0, 1.0))


func _secondary() -> Color:
	return _colors().get("secondary", Color.WHITE)


func _accent() -> Color:
	return _colors().get("accent", Color(1.0, 0.84, 0.05, 1.0))


func _dark() -> Color:
	return _colors().get("dark", Color(0.01, 0.02, 0.05, 1.0))


func _idle_time() -> float:
	if game_state == "selector" or game_state == "presentation":
		return float(Time.get_ticks_msec()) / 1000.0
	return song_time


func _beat_pulse() -> float:
	var bpm: float = maxf(float(song.get("bpm", 120.0)), 1.0)
	var beat_position: float = fmod(maxf(_idle_time(), 0.0) * bpm / 60.0, 1.0)
	return pow(maxf(0.0, 1.0 - beat_position * 5.5), 2.0)


func _draw_circle_base() -> void:
	var pulse: float = _beat_pulse()
	draw_circle(center, radius * 0.996, Color(0.002, 0.004, 0.012, 1.0), true)
	draw_circle(
		center,
		radius * (0.86 + pulse * 0.012),
		Color(_primary().r, _primary().g, _primary().b, 0.025 + pulse * 0.018),
		true
	)


func _draw_theme_geometry() -> void:
	var pattern: String = str(song.get("pattern", "diamonds")).to_lower()
	var intensity: float = clampf(float(difficulty.get("background_intensity", 0.18)), 0.04, 0.38)
	var time_value: float = _idle_time()
	var speed: float = float(difficulty.get("background_speed", 0.22))
	var rotation: float = time_value * speed
	var beat: float = _beat_pulse()
	var section: int = int(floor(time_value / 12.0)) % 4
	var primary: Color = _primary()
	var secondary: Color = _secondary()
	var accent: Color = _accent()

	for ring in range(1, 6):
		var ring_radius: float = radius * (0.13 + float(ring) * 0.115)
		var alpha: float = intensity * (0.045 + float(ring) * 0.012) + beat * 0.018
		draw_arc(
			center,
			ring_radius,
			rotation * (0.20 if ring % 2 == 0 else -0.16),
			TAU + rotation * (0.20 if ring % 2 == 0 else -0.16),
			120,
			Color(primary.r, primary.g, primary.b, alpha),
			maxf(1.0, radius * 0.0017),
			true
		)

	match pattern:
		"hex":
			_draw_hex_field(rotation, intensity, primary, accent, section)
		"radial":
			_draw_radial_field(rotation, intensity, primary, secondary, beat)
		"grid":
			_draw_grid_field(rotation, intensity, primary, accent)
		_:
			_draw_diamond_field(rotation, intensity, primary, secondary, section)

	_draw_orbit_nodes(rotation, intensity, accent)


func _draw_diamond_field(
	rotation: float,
	intensity: float,
	primary: Color,
	secondary: Color,
	section: int
) -> void:
	for ring in range(2, 6):
		var count: int = 8 + section * 2
		var ring_radius: float = radius * (0.16 + float(ring) * 0.115)
		for index in range(count):
			var angle: float = rotation * (1.0 if ring % 2 == 0 else -0.65)
			angle += TAU * float(index) / float(count)
			var position_value: Vector2 = center + Vector2(cos(angle), sin(angle)) * ring_radius
			var size: float = radius * (0.026 + float(ring) * 0.0025)
			var color: Color = primary.lerp(secondary, float(index % 3) * 0.16)
			color.a = intensity * (0.27 + float(ring) * 0.025)
			_draw_diamond(position_value, size, color, maxf(1.0, radius * 0.0022))


func _draw_hex_field(
	rotation: float,
	intensity: float,
	primary: Color,
	accent: Color,
	section: int
) -> void:
	for ring in range(2, 6):
		var count: int = 6 + (section % 2) * 6
		var ring_radius: float = radius * (0.14 + float(ring) * 0.125)
		for index in range(count):
			var angle: float = rotation * (0.65 if ring % 2 == 0 else -0.44)
			angle += TAU * float(index) / float(count)
			var position_value: Vector2 = center + Vector2(cos(angle), sin(angle)) * ring_radius
			var color: Color = primary.lerp(accent, float(index % 4) * 0.08)
			color.a = intensity * 0.34
			_draw_regular_polygon(
				position_value,
				radius * (0.032 + float(ring) * 0.002),
				6,
				rotation * 0.30,
				color,
				maxf(1.0, radius * 0.002)
			)


func _draw_radial_field(
	rotation: float,
	intensity: float,
	primary: Color,
	secondary: Color,
	beat: float
) -> void:
	for index in range(32):
		var angle: float = rotation * 0.30 + TAU * float(index) / 32.0
		var direction := Vector2(cos(angle), sin(angle))
		var length_factor: float = 0.54 + 0.11 * absf(sin(float(index) * 0.72 + rotation))
		var color: Color = primary.lerp(secondary, float(index % 4) * 0.10)
		color.a = intensity * (0.12 + beat * 0.08)
		draw_line(
			center + direction * radius * 0.20,
			center + direction * radius * length_factor,
			color,
			maxf(1.0, radius * 0.0018),
			true
		)


func _draw_grid_field(
	rotation: float,
	intensity: float,
	primary: Color,
	accent: Color
) -> void:
	var spacing: float = radius * 0.115
	var offset: float = fmod(rotation * radius * 0.08, spacing)
	for index in range(-6, 7):
		var value: float = float(index) * spacing + offset
		draw_line(
			center + Vector2(value, -radius * 0.68),
			center + Vector2(value, radius * 0.68),
			Color(primary.r, primary.g, primary.b, intensity * 0.12),
			maxf(1.0, radius * 0.0015),
			true
		)
		draw_line(
			center + Vector2(-radius * 0.68, value),
			center + Vector2(radius * 0.68, value),
			Color(accent.r, accent.g, accent.b, intensity * 0.09),
			maxf(1.0, radius * 0.0015),
			true
		)


func _draw_orbit_nodes(rotation: float, intensity: float, color: Color) -> void:
	for index in range(12):
		var angle: float = -rotation * 0.48 + TAU * float(index) / 12.0
		var orbit_radius: float = radius * (0.28 + 0.028 * float(index % 4))
		var position_value: Vector2 = center + Vector2(cos(angle), sin(angle)) * orbit_radius
		draw_circle(
			position_value,
			maxf(1.5, radius * 0.004),
			Color(color.r, color.g, color.b, intensity * 0.30),
			true
		)


func _draw_video_frame() -> void:
	var rect := Rect2(
		center - Vector2(radius * 0.755, radius * 0.295),
		Vector2(radius * 1.51, radius * 0.59)
	)
	var primary: Color = _primary()
	var beat: float = _beat_pulse()

	_video_style.border_color = Color(
		primary.r,
		primary.g,
		primary.b,
		0.44 + beat * 0.18
	)
	_video_style.shadow_color = Color(
		primary.r,
		primary.g,
		primary.b,
		0.13 + beat * 0.08
	)
	_video_style.shadow_size = int(maxf(8.0, radius * (0.018 + beat * 0.008)))
	draw_style_box(_video_style, rect.grow(radius * 0.012))
	draw_style_box(_video_inner_style, rect.grow(-radius * 0.009))

	var top_left: Vector2 = rect.position
	var top_right: Vector2 = rect.position + Vector2(rect.size.x, 0.0)
	draw_line(
		top_left + Vector2(radius * 0.05, 0.0),
		top_right - Vector2(radius * 0.05, 0.0),
		Color.WHITE,
		maxf(1.0, radius * 0.002),
		true
	)

	for index in range(4):
		var x: float = rect.position.x + rect.size.x * (0.16 + float(index) * 0.22)
		draw_circle(
			Vector2(x, rect.position.y + radius * 0.015),
			maxf(1.5, radius * 0.004),
			Color(primary.r, primary.g, primary.b, 0.46),
			true
		)


func _draw_inner_technical_rings() -> void:
	var time_value: float = _idle_time()
	var primary: Color = _primary()
	var accent: Color = _accent()

	for ring in range(3):
		var ring_radius: float = radius * (0.34 + float(ring) * 0.12)
		var start_angle: float = time_value * (0.18 + float(ring) * 0.05)
		for segment in range(8):
			var angle_a: float = start_angle + TAU * float(segment) / 8.0
			var angle_b: float = angle_a + TAU / 8.0 * 0.56
			var color: Color = primary if (segment + ring) % 2 == 0 else accent
			draw_arc(
				center,
				ring_radius,
				angle_a,
				angle_b,
				18,
				Color(color.r, color.g, color.b, 0.075),
				maxf(1.0, radius * 0.002),
				true
			)


func _draw_ring() -> void:
	var ring_radius: float = radius * 0.905
	var width: float = maxf(3.5, radius * 0.0070)
	var marker_radius: float = maxf(7.0, radius * 0.022)
	var pulse: float = _beat_pulse()
	var primary: Color = _primary()

	draw_arc(
		center,
		ring_radius + radius * 0.006,
		0.0,
		TAU,
		288,
		Color(primary.r, primary.g, primary.b, 0.12 + pulse * 0.08),
		width * 4.5,
		true
	)
	draw_arc(
		center,
		ring_radius,
		0.0,
		TAU,
		288,
		Color.WHITE,
		width,
		true
	)
	draw_arc(
		center,
		ring_radius - width * 1.5,
		0.0,
		TAU,
		288,
		Color(primary.r, primary.g, primary.b, 0.46),
		maxf(1.2, width * 0.24),
		true
	)

	for position_value in lane_positions:
		draw_circle(
			position_value,
			marker_radius * 2.15,
			Color(primary.r, primary.g, primary.b, 0.08),
			true
		)
		draw_circle(
			position_value,
			marker_radius * 1.48,
			Color(1.0, 1.0, 1.0, 0.10),
			true
		)
		draw_circle(position_value, marker_radius, Color.WHITE, true)
		draw_circle(position_value, marker_radius * 0.28, _dark(), true)


func _draw_lane_energy() -> void:
	if events.is_empty():
		return

	var approach: float = maxf(float(difficulty.get("approach", 1.0)), 0.001)
	for event_value in events:
		if not event_value is Dictionary:
			continue
		var event: Dictionary = event_value as Dictionary
		if bool(event.get("_resolved", false)):
			continue

		var type_name: String = str(event.get("type", "tap"))
		if type_name != "tap" and type_name != "hold":
			continue

		var lane: int = clampi(int(event.get("lane", 0)), 0, lane_positions.size() - 1)
		var hit_time: float = float(event.get("time", 0.0))
		var progress: float = clampf(
			(song_time - (hit_time - approach)) / approach,
			0.0,
			1.0
		)
		if progress <= 0.0 or progress >= 1.0:
			continue

		var position_value: Vector2 = lane_positions[lane]
		var color: Color = _accent() if type_name == "hold" else _primary()
		var size: float = radius * (0.028 + progress * 0.032)
		draw_arc(
			position_value,
			size,
			-PI * 0.5,
			-PI * 0.5 + TAU * progress,
			32,
			Color(color.r, color.g, color.b, 0.22 + progress * 0.62),
			maxf(2.0, radius * 0.006),
			true
		)


func _draw_hold(event: Dictionary) -> void:
	if not bool(event.get("_spawned", false)):
		return

	var hit_time: float = float(event.get("time", 0.0))
	var end_time: float = float(event.get("end_time", hit_time + 1.0))
	var approach: float = float(difficulty.get("approach", 1.0))
	if song_time < hit_time - approach or song_time > end_time + 0.25:
		return

	var lane: int = clampi(int(event.get("lane", 0)), 0, lane_positions.size() - 1)
	var target: Vector2 = lane_positions[lane]
	var direction: Vector2 = (target - center).normalized()
	var start_time: float = hit_time - approach
	var arrival: float = clampf((song_time - start_time) / maxf(approach, 0.001), 0.0, 1.0)
	var eased: float = 1.0 - pow(1.0 - arrival, 4.0)
	var head: Vector2 = center.lerp(target, eased)

	var hold_progress: float = 0.0
	if song_time >= hit_time:
		hold_progress = clampf(
			(song_time - hit_time) / maxf(end_time - hit_time, 0.001),
			0.0,
			1.0
		)
		head = target

	var remaining: float = 1.0 - hold_progress
	var length: float = radius * (0.46 if song_time < hit_time else maxf(0.072, 0.46 * remaining))
	var tail: Vector2 = head - direction * length
	var width: float = radius * 0.058 * float(difficulty.get("hold_width", 1.0))
	var color: Color = _accent()
	var holding: bool = bool(event.get("_holding", false))
	if holding:
		color = color.lerp(Color.WHITE, 0.16)

	_draw_capsule(tail, head, width, color, holding, hold_progress)


func _draw_capsule(
	tail: Vector2,
	head: Vector2,
	half_width: float,
	color: Color,
	active: bool,
	progress: float
) -> void:
	var direction: Vector2 = (head - tail).normalized()
	var length: float = tail.distance_to(head)
	var glow: float = 0.30 if active else 0.17
	var dark: Color = Color(0.003, 0.006, 0.018, 0.98)

	draw_line(tail, head, Color(color.r, color.g, color.b, glow), half_width * 4.7, true)
	draw_circle(tail, half_width * 2.35, Color(color.r, color.g, color.b, glow), true)
	draw_circle(head, half_width * 2.35, Color(color.r, color.g, color.b, glow), true)

	draw_line(tail, head, Color.WHITE, half_width * 2.65, true)
	draw_circle(tail, half_width * 1.33, Color.WHITE, true)
	draw_circle(head, half_width * 1.33, Color.WHITE, true)

	draw_line(tail, head, color, half_width * 2.30, true)
	draw_circle(tail, half_width * 1.15, color, true)
	draw_circle(head, half_width * 1.15, color, true)

	draw_line(tail, head, dark, half_width * 1.28, true)
	draw_circle(tail, half_width * 0.64, dark, true)
	draw_circle(head, half_width * 0.64, dark, true)

	var dash_spacing: float = half_width * 1.45
	var dash_count: int = maxi(2, int(length / maxf(dash_spacing, 1.0)))
	var phase: float = fmod(_idle_time() * (1.8 if active else 0.85), 1.0)
	for index in range(dash_count):
		var t: float = fmod((float(index) + phase) / float(dash_count), 1.0)
		var dash_position: Vector2 = tail.lerp(head, t)
		var dash_size: float = half_width * (0.22 + 0.05 * sin(float(index)))
		draw_circle(
			dash_position,
			dash_size,
			Color(color.r, color.g, color.b, 0.42 if active else 0.20),
			true
		)

	var head_pulse: float = 0.5 + 0.5 * sin(_idle_time() * 8.0)
	draw_arc(
		head,
		half_width * (0.80 + head_pulse * 0.08),
		0.0,
		TAU,
		42,
		Color.WHITE,
		maxf(2.0, half_width * 0.13),
		true
	)
	draw_arc(
		head,
		half_width * 0.58,
		-PI * 0.5,
		-PI * 0.5 + TAU * progress,
		36,
		color,
		maxf(2.0, half_width * 0.14),
		true
	)
	draw_circle(head, half_width * 0.12, Color.WHITE, true)

	var tail_indicator: Vector2 = tail - direction * half_width * 0.15
	_draw_diamond(
		tail_indicator,
		half_width * 0.42,
		Color.WHITE,
		maxf(2.0, half_width * 0.12)
	)


func _draw_slide(event: Dictionary) -> void:
	if not bool(event.get("_spawned", false)):
		return

	var path_value: Variant = event.get("_path_points", PackedVector2Array())
	if not path_value is PackedVector2Array:
		return

	var points: PackedVector2Array = path_value as PackedVector2Array
	if points.size() < 2:
		return

	var hit_time: float = float(event.get("time", 0.0))
	var end_time: float = float(event.get("end_time", hit_time + 1.0))
	var approach: float = float(difficulty.get("approach", 1.0))
	if song_time < hit_time - approach or song_time > end_time + 0.35:
		return

	var color: Color = _primary()
	var accent: Color = _accent()
	var visual_progress: float = clampf(float(event.get("_visual_progress", 0.0)), 0.0, 1.0)
	var active: bool = bool(event.get("_active", false))
	var arrows_from: float = visual_progress if active else 0.0

	_draw_slide_rail(points, color)
	_draw_chevrons(points, arrows_from, color, accent)

	var star_position: Vector2
	var tangent: Vector2
	var star_progress: float = visual_progress

	if song_time < hit_time:
		var arrival: float = clampf(
			(song_time - (hit_time - approach)) / maxf(approach, 0.001),
			0.0,
			1.0
		)
		var eased: float = 1.0 - pow(1.0 - arrival, 4.0)
		star_position = center.lerp(points[0], eased)
		tangent = (points[0] - center).normalized()
		star_progress = 0.0
	else:
		star_position = PATH_BUILDER.point_at(points, visual_progress)
		tangent = PATH_BUILDER.tangent_at(points, visual_progress)

	if active:
		for ghost_index in range(1, 4):
			var ghost_progress: float = maxf(0.0, star_progress - float(ghost_index) * 0.035)
			var ghost_position: Vector2 = PATH_BUILDER.point_at(points, ghost_progress)
			var ghost_tangent: Vector2 = PATH_BUILDER.tangent_at(points, ghost_progress)
			_draw_star(
				ghost_position,
				ghost_tangent.angle(),
				radius * (0.080 - float(ghost_index) * 0.008),
				Color(color.r, color.g, color.b, 0.14),
				Color(accent.r, accent.g, accent.b, 0.08)
			)

	_draw_star(
		star_position,
		tangent.angle(),
		radius * 0.088 * float(difficulty.get("star_scale", 1.0)),
		color,
		accent
	)


func _draw_slide_rail(points: PackedVector2Array, color: Color) -> void:
	for index in range(points.size() - 1):
		draw_line(
			points[index],
			points[index + 1],
			Color(0.0, 0.0, 0.0, 0.76),
			maxf(8.0, radius * 0.026),
			true
		)
		draw_line(
			points[index],
			points[index + 1],
			Color(color.r, color.g, color.b, 0.16),
			maxf(3.0, radius * 0.008),
			true
		)


func _draw_chevrons(
	points: PackedVector2Array,
	start_progress: float,
	color: Color,
	accent: Color
) -> void:
	var spacing: float = radius * 0.047
	var estimated_length: float = 0.0
	for index in range(points.size() - 1):
		estimated_length += points[index].distance_to(points[index + 1])

	var count: int = maxi(5, int(ceil(estimated_length / maxf(spacing, 1.0))))
	var start_index: int = clampi(int(floor(start_progress * float(count))), 0, count - 1)

	for index in range(start_index, count):
		var progress: float = (float(index) + 0.50) / float(count)
		var position_value: Vector2 = PATH_BUILDER.point_at(points, progress)
		var tangent: Vector2 = PATH_BUILDER.tangent_at(points, progress)
		var mix_value: float = 0.10 + 0.18 * float(index % 3)
		var arrow_color: Color = color.lerp(accent, mix_value)
		_draw_chevron(position_value, tangent, radius * 0.046, arrow_color)


func _draw_chevron(
	position_value: Vector2,
	direction: Vector2,
	size: float,
	color: Color
) -> void:
	var tangent: Vector2 = direction.normalized()
	var perpendicular := Vector2(-tangent.y, tangent.x)
	var length: float = size * 2.05
	var width: float = size * 1.02
	var tip: Vector2 = position_value + tangent * length * 0.58
	var back: Vector2 = position_value - tangent * length * 0.42
	var notch: Vector2 = position_value - tangent * length * 0.02

	var polygon := PackedVector2Array([
		back + perpendicular * width,
		notch + perpendicular * width * 0.47,
		tip,
		notch - perpendicular * width * 0.47,
		back - perpendicular * width,
		back - tangent * length * 0.14,
		position_value - tangent * length * 0.02,
		back - tangent * length * 0.14,
	])

	var shadow := PackedVector2Array()
	var shadow_offset := Vector2(radius * 0.008, radius * 0.009)
	for point in polygon:
		shadow.append(point + shadow_offset)

	draw_colored_polygon(shadow, Color(0.0, 0.0, 0.0, 0.92))
	draw_polyline(
		PackedVector2Array([
			shadow[0],
			shadow[1],
			shadow[2],
			shadow[3],
			shadow[4],
		]),
		Color(0.0, 0.0, 0.0, 0.98),
		maxf(4.0, size * 0.20),
		true
	)
	draw_colored_polygon(polygon, color)
	draw_polyline(
		PackedVector2Array([
			polygon[0],
			polygon[1],
			polygon[2],
			polygon[3],
			polygon[4],
		]),
		Color(0.86, 1.0, 1.0, 0.96),
		maxf(2.0, size * 0.10),
		true
	)
	draw_line(
		back,
		tip - tangent * length * 0.18,
		Color.WHITE,
		maxf(1.2, size * 0.055),
		true
	)


func _draw_star(
	position_value: Vector2,
	rotation_value: float,
	size: float,
	color: Color,
	accent: Color
) -> void:
	var pulse: float = 0.5 + 0.5 * sin(_idle_time() * 9.0)
	var outer: PackedVector2Array = _star_points(
		size * (1.0 + pulse * 0.045),
		size * 0.44,
		rotation_value,
		position_value
	)
	var middle: PackedVector2Array = _star_points(
		size * 0.73,
		size * 0.31,
		rotation_value,
		position_value
	)
	var inner: PackedVector2Array = _star_points(
		size * 0.48,
		size * 0.20,
		rotation_value,
		position_value
	)
	outer.append(outer[0])
	middle.append(middle[0])
	inner.append(inner[0])

	draw_polyline(outer, Color(0.0, 0.0, 0.0, 0.90), maxf(12.0, size * 0.30), true)
	draw_polyline(outer, Color.WHITE, maxf(7.0, size * 0.16), true)
	draw_polyline(middle, color, maxf(5.0, size * 0.13), true)
	draw_polyline(inner, accent, maxf(3.5, size * 0.10), true)
	draw_circle(position_value, size * 0.18, Color(0.002, 0.006, 0.016, 0.96), true)
	draw_circle(position_value, size * 0.075, Color.WHITE, true)


func _draw_effects() -> void:
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	for effect_value in effects:
		if not effect_value is Dictionary:
			continue

		var effect: Dictionary = effect_value as Dictionary
		var duration: float = maxf(float(effect.get("duration", 0.5)), 0.001)
		var progress: float = clampf(
			(now - float(effect.get("start", now))) / duration,
			0.0,
			1.0
		)
		var life: float = 1.0 - progress
		var position_value: Vector2 = effect.get("position", center)
		var color: Color = effect.get("color", Color.WHITE)
		var kind: String = str(effect.get("kind", "tap"))
		var rotation_value: float = float(effect.get("rotation", 0.0))

		if kind == "slide":
			_draw_slide_burst(position_value, color, progress, life, rotation_value)
		elif kind == "hold":
			_draw_hold_burst(position_value, color, progress, life)
		elif kind == "miss":
			_draw_miss_burst(position_value, progress, life, rotation_value)
		else:
			_draw_tap_prism(position_value, color, progress, life, rotation_value)


func _draw_tap_prism(
	position_value: Vector2,
	color: Color,
	progress: float,
	life: float,
	rotation_value: float
) -> void:
	var flash_radius: float = radius * (0.025 + progress * 0.105)
	draw_circle(
		position_value,
		flash_radius,
		Color(1.0, 1.0, 1.0, life * 0.16),
		true
	)

	for layer in range(4):
		var size: float = radius * (0.055 + float(layer) * 0.022)
		size *= 0.22 + progress * 1.18
		var alpha: float = life * (1.0 - float(layer) * 0.17)
		var layer_color: Color = Color.WHITE.lerp(color, 0.22 + float(layer) * 0.22)
		layer_color.a = alpha
		_draw_rotated_diamond(
			position_value,
			size,
			rotation_value + float(layer) * PI * 0.25,
			layer_color,
			maxf(3.0, radius * (0.010 - float(layer) * 0.0014))
		)

	for index in range(8):
		var angle: float = rotation_value + TAU * float(index) / 8.0
		var direction := Vector2(cos(angle), sin(angle))
		var shard_center: Vector2 = position_value + direction * radius * (0.040 + progress * 0.145)
		var shard_size: float = radius * (0.016 + progress * 0.020)
		_draw_rotated_diamond(
			shard_center,
			shard_size,
			angle,
			Color(color.r, color.g, color.b, life * 0.76),
			maxf(2.0, radius * 0.0045)
		)

	for ring in range(2):
		draw_arc(
			position_value,
			radius * (0.045 + float(ring) * 0.035 + progress * 0.12),
			rotation_value + float(ring) * PI * 0.5,
			rotation_value + float(ring) * PI * 0.5 + PI * 1.36,
			38,
			Color(1.0, 1.0, 1.0, life * (0.48 - float(ring) * 0.14)),
			maxf(2.0, radius * 0.005),
			true
		)


func _draw_slide_burst(
	position_value: Vector2,
	color: Color,
	progress: float,
	life: float,
	rotation_value: float
) -> void:
	for layer in range(4):
		var size: float = radius * (0.080 + float(layer) * 0.022)
		size *= 0.30 + progress * 1.10
		var points: PackedVector2Array = _star_points(
			size,
			size * 0.43,
			rotation_value + progress * (1.4 if layer % 2 == 0 else -1.1),
			position_value
		)
		points.append(points[0])
		draw_polyline(
			points,
			Color(color.r, color.g, color.b, life * (0.96 - float(layer) * 0.16)),
			maxf(3.0, radius * (0.010 - float(layer) * 0.0012)),
			true
		)

	for index in range(6):
		var angle: float = rotation_value + TAU * float(index) / 6.0
		var direction := Vector2(cos(angle), sin(angle))
		var p: Vector2 = position_value + direction * radius * (0.055 + progress * 0.14)
		_draw_chevron(
			p,
			direction,
			radius * (0.018 + progress * 0.012),
			Color(color.r, color.g, color.b, life * 0.72)
		)


func _draw_hold_burst(
	position_value: Vector2,
	color: Color,
	progress: float,
	life: float
) -> void:
	for ring in range(4):
		draw_arc(
			position_value,
			radius * (0.030 + float(ring) * 0.026 + progress * 0.11),
			0.0,
			TAU,
			56,
			Color(color.r, color.g, color.b, life * (0.94 - float(ring) * 0.19)),
			maxf(2.0, radius * (0.010 - float(ring) * 0.0014)),
			true
		)

	for index in range(4):
		var angle: float = PI * 0.25 + float(index) * PI * 0.5
		var direction := Vector2(cos(angle), sin(angle))
		var inner: Vector2 = position_value + direction * radius * (0.025 + progress * 0.03)
		var outer: Vector2 = position_value + direction * radius * (0.075 + progress * 0.12)
		draw_line(
			inner,
			outer,
			Color.WHITE,
			maxf(2.0, radius * 0.006),
			true
		)


func _draw_miss_burst(
	position_value: Vector2,
	progress: float,
	life: float,
	rotation_value: float
) -> void:
	var size: float = radius * (0.040 + progress * 0.095)
	var a: Vector2 = Vector2(cos(rotation_value), sin(rotation_value)) * size
	var b: Vector2 = Vector2(-a.y, a.x)
	draw_line(
		position_value - a,
		position_value + a,
		Color(1.0, 0.08, 0.13, life),
		maxf(4.0, radius * 0.012),
		true
	)
	draw_line(
		position_value - b,
		position_value + b,
		Color(1.0, 0.08, 0.13, life),
		maxf(4.0, radius * 0.012),
		true
	)
	draw_arc(
		position_value,
		size * 1.18,
		0.0,
		TAU,
		40,
		Color(1.0, 0.12, 0.18, life * 0.42),
		maxf(2.0, radius * 0.005),
		true
	)


func _draw_pointer(position_value: Vector2) -> void:
	var color: Color = _primary()
	var pulse: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.025)
	var outer_radius: float = radius * (0.044 + pulse * 0.006)

	draw_circle(
		position_value,
		outer_radius * 1.28,
		Color(color.r, color.g, color.b, 0.09),
		true
	)
	draw_arc(
		position_value,
		outer_radius,
		0.0,
		TAU,
		40,
		Color.WHITE,
		maxf(2.0, radius * 0.0045),
		true
	)
	draw_arc(
		position_value,
		outer_radius * 0.70,
		-PI * 0.5,
		-PI * 0.5 + PI * 1.30,
		28,
		Color(color.r, color.g, color.b, 0.92),
		maxf(2.0, radius * 0.005),
		true
	)

	for index in range(4):
		var angle: float = PI * 0.25 + float(index) * PI * 0.5
		var direction := Vector2(cos(angle), sin(angle))
		var side := Vector2(-direction.y, direction.x)
		var corner: Vector2 = position_value + direction * outer_radius * 1.20
		draw_line(
			corner - side * outer_radius * 0.20,
			corner + side * outer_radius * 0.20,
			Color(color.r, color.g, color.b, 0.75),
			maxf(2.0, radius * 0.004),
			true
		)


func _draw_diamond(
	position_value: Vector2,
	size: float,
	color: Color,
	width: float
) -> void:
	var points := PackedVector2Array([
		position_value + Vector2(0.0, -size),
		position_value + Vector2(size, 0.0),
		position_value + Vector2(0.0, size),
		position_value + Vector2(-size, 0.0),
		position_value + Vector2(0.0, -size),
	])
	draw_polyline(points, color, width, true)


func _draw_rotated_diamond(
	position_value: Vector2,
	size: float,
	rotation_value: float,
	color: Color,
	width: float
) -> void:
	var points := PackedVector2Array()
	for index in range(5):
		var angle: float = rotation_value - PI * 0.5 + float(index) * PI * 0.5
		points.append(position_value + Vector2(cos(angle), sin(angle)) * size)
	draw_polyline(points, color, width, true)


func _draw_regular_polygon(
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
		points.append(position_value + Vector2(cos(angle), sin(angle)) * size)
	draw_polyline(points, color, width, true)


func _star_points(
	outer_radius: float,
	inner_radius: float,
	rotation_value: float,
	position_value: Vector2
) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(10):
		var angle: float = rotation_value - PI * 0.5 + PI * float(index) / 5.0
		var point_radius: float = outer_radius if index % 2 == 0 else inner_radius
		points.append(position_value + Vector2(cos(angle), sin(angle)) * point_radius)
	return points
'@

Write-Utf8NoBom (Project-Path "scripts\hit_music_r7\selector.gd") @'
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
const PREVIEW_DELAY: float = 0.75
const PREVIEW_ALPHA: float = 0.48
const CARD_SPACING_RATIO: float = 0.205

var _songs: Array = []
var _index: int = 0
var _difficulty: String = "easy"
var _center: Vector2 = Vector2.ZERO
var _radius: float = 100.0
var _lane_positions: PackedVector2Array = PackedVector2Array()
var _video_rect: Rect2 = Rect2()
var _preview_wait: float = 0.0
var _transitioning: bool = false
var _visual_time: float = 0.0

var _video: VideoStreamPlayer
var _renderer
var _ui: CanvasLayer
var _top_panel: Panel
var _brand_label: Label
var _subtitle_label: Label
var _instruction_label: Label
var _easy_chip: Panel
var _hard_chip: Panel
var _easy_label: Label
var _hard_label: Label
var _content_root: Control
var _list_root: Control
var _info_panel: Panel
var _cover_frame: Panel
var _cover: TextureRect
var _track_badge: Panel
var _track_label: Label
var _song_name: Label
var _category_label: Label
var _bpm_label: Label
var _mode_label: Label
var _record_label: Label
var _start_panel: Panel
var _start_label: Label
var _cards: Array[Panel] = []
var _card_labels: Array[Label] = []
var _card_track_labels: Array[Label] = []
var _card_covers: Array[TextureRect] = []


func _ready() -> void:
	Engine.max_fps = 60
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	_songs = CATALOG.all_songs()
	if _songs.is_empty():
		push_error("Catalogo Hit Music vazio.")
		return

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

	if not _transitioning:
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
			var preview_tween: Tween = create_tween()
			preview_tween.set_trans(Tween.TRANS_QUINT)
			preview_tween.set_ease(Tween.EASE_OUT)
			preview_tween.tween_property(_video, "modulate:a", PREVIEW_ALPHA, 0.48)

	_update_card_animation(delta)
	_update_live_styles()
	_renderer.set_runtime([], _visual_time, "selector", Vector2.ZERO, false)
	queue_redraw()


func _draw() -> void:
	var screen: Vector2 = get_viewport_rect().size
	var primary: Color = _song_primary(_songs[_index] as Dictionary)
	var accent: Color = _song_accent(_songs[_index] as Dictionary)
	var pulse: float = 0.5 + 0.5 * sin(_visual_time * 1.7)

	draw_rect(Rect2(Vector2.ZERO, screen), Color.BLACK, true)
	draw_circle(_center, _radius * 1.028, Color(primary.r, primary.g, primary.b, 0.055), true)
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

	for index in range(32):
		var angle: float = TAU * float(index) / 32.0
		var direction := Vector2(cos(angle), sin(angle))
		var inner: Vector2 = _center + direction * _radius * 0.953
		var outer: Vector2 = _center + direction * _radius * (
			0.970 + 0.006 * absf(sin(_visual_time * 1.2 + float(index)))
		)
		var color: Color = primary if index % 2 == 0 else accent
		draw_line(
			inner,
			outer,
			Color(color.r, color.g, color.b, 0.24),
			maxf(1.0, _radius * 0.002),
			true
		)


func _input(event: InputEvent) -> void:
	if _transitioning:
		return

	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed:
			_handle_touch(touch.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse: InputEventMouseButton = event
		if mouse.pressed:
			_handle_touch(mouse.position)


func _handle_touch(position_value: Vector2) -> void:
	if _easy_chip != null and Rect2(_easy_chip.global_position, _easy_chip.size).has_point(position_value):
		if _difficulty != "easy":
			_difficulty = "easy"
			_apply_selection(false)
		return

	if _hard_chip != null and Rect2(_hard_chip.global_position, _hard_chip.size).has_point(position_value):
		if _difficulty != "hard":
			_difficulty = "hard"
			_apply_selection(false)
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
		_center - Vector2(_radius * 0.755, _radius * 0.295),
		Vector2(_radius * 1.51, _radius * 0.59)
	)


func _build_scene() -> void:
	_video = VideoStreamPlayer.new()
	_video.position = _video_rect.position
	_video.size = _video_rect.size
	_video.expand = true
	_video.loop = true
	_video.volume_db = -80.0
	_video.modulate.a = 0.0
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
	var font: Font = _load_font()

	_top_panel = Panel.new()
	_top_panel.position = Vector2(margin, margin)
	_top_panel.size = Vector2(screen.x - margin * 2.0, top_height)
	_top_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_top_panel)

	_brand_label = _make_label(
		"HIT MUSIC",
		int(top_height * 0.235),
		HORIZONTAL_ALIGNMENT_LEFT,
		font
	)
	_brand_label.position = Vector2(top_height * 0.12, top_height * 0.055)
	_brand_label.size = Vector2(_top_panel.size.x * 0.50, top_height * 0.34)
	_top_panel.add_child(_brand_label)

	_subtitle_label = _make_label(
		"SELECT YOUR TRACK",
		int(top_height * 0.105),
		HORIZONTAL_ALIGNMENT_LEFT,
		font
	)
	_subtitle_label.position = Vector2(top_height * 0.13, top_height * 0.34)
	_subtitle_label.size = Vector2(_top_panel.size.x * 0.48, top_height * 0.20)
	_subtitle_label.add_theme_color_override("font_color", Color(0.72, 0.78, 0.90, 1.0))
	_top_panel.add_child(_subtitle_label)

	_easy_chip = Panel.new()
	_easy_chip.position = Vector2(_top_panel.size.x * 0.62, top_height * 0.11)
	_easy_chip.size = Vector2(_top_panel.size.x * 0.145, top_height * 0.34)
	_top_panel.add_child(_easy_chip)

	_easy_label = _make_label(
		"FACIL",
		int(top_height * 0.13),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	_easy_label.size = _easy_chip.size
	_easy_chip.add_child(_easy_label)

	_hard_chip = Panel.new()
	_hard_chip.position = Vector2(_top_panel.size.x * 0.775, top_height * 0.11)
	_hard_chip.size = Vector2(_top_panel.size.x * 0.17, top_height * 0.34)
	_top_panel.add_child(_hard_chip)

	_hard_label = _make_label(
		"DIFICIL",
		int(top_height * 0.13),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	_hard_label.size = _hard_chip.size
	_hard_chip.add_child(_hard_label)

	_instruction_label = _make_label(
		"A  NEXT TRACK     B  DIFFICULTY     START  PLAY",
		int(top_height * 0.10),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	_instruction_label.position = Vector2(top_height * 0.10, top_height * 0.65)
	_instruction_label.size = Vector2(_top_panel.size.x - top_height * 0.20, top_height * 0.22)
	_instruction_label.add_theme_color_override("font_color", Color(0.78, 0.83, 0.93, 1.0))
	_top_panel.add_child(_instruction_label)

	_content_root = Control.new()
	_content_root.position = _center - Vector2(_radius, _radius)
	_content_root.size = Vector2(_radius * 2.0, _radius * 2.0)
	_content_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_content_root)

	_list_root = Control.new()
	_list_root.position = Vector2.ZERO
	_list_root.size = _content_root.size
	_list_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_root.add_child(_list_root)

	_build_cards(font)
	_build_info_panel(font)


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
		cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cover.texture = _load_texture(str(song.get("cover", "")))
		card.add_child(cover)

		var text_x: float = cover.position.x + cover.size.x + card.size.x * 0.045
		var track := _make_label(
			"TRACK %02d" % (song_index + 1),
			int(_radius * 0.019),
			HORIZONTAL_ALIGNMENT_LEFT,
			font
		)
		track.position = Vector2(text_x, card.size.y * 0.08)
		track.size = Vector2(card.size.x - text_x - card.size.x * 0.05, card.size.y * 0.29)
		track.add_theme_color_override("font_color", Color(0.64, 0.72, 0.84, 1.0))
		card.add_child(track)

		var label := _make_label(
			str(song.get("title", "TRACK")),
			int(_radius * 0.032),
			HORIZONTAL_ALIGNMENT_LEFT,
			font
		)
		label.position = Vector2(text_x, card.size.y * 0.34)
		label.size = Vector2(card.size.x - text_x - card.size.x * 0.05, card.size.y * 0.57)
		label.clip_text = true
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
	_cover_frame.position = Vector2(_info_panel.size.x * 0.055, _info_panel.size.y * 0.045)
	_cover_frame.size = Vector2(_info_panel.size.x * 0.89, _info_panel.size.y * 0.35)
	_cover_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info_panel.add_child(_cover_frame)

	_cover = TextureRect.new()
	_cover.position = Vector2(_cover_frame.size.x * 0.025, _cover_frame.size.y * 0.04)
	_cover.size = Vector2(_cover_frame.size.x * 0.95, _cover_frame.size.y * 0.92)
	_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover_frame.add_child(_cover)

	_track_badge = Panel.new()
	_track_badge.position = Vector2(_info_panel.size.x * 0.055, _info_panel.size.y * 0.425)
	_track_badge.size = Vector2(_info_panel.size.x * 0.37, _info_panel.size.y * 0.075)
	_info_panel.add_child(_track_badge)

	_track_label = _make_label(
		"TRACK 01",
		int(_radius * 0.022),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	_track_label.size = _track_badge.size
	_track_badge.add_child(_track_label)

	_song_name = _make_label(
		"TRACK",
		int(_radius * 0.046),
		HORIZONTAL_ALIGNMENT_LEFT,
		font
	)
	_song_name.position = Vector2(_info_panel.size.x * 0.06, _info_panel.size.y * 0.51)
	_song_name.size = Vector2(_info_panel.size.x * 0.88, _info_panel.size.y * 0.16)
	_song_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_panel.add_child(_song_name)

	_category_label = _make_label(
		"ANIME MUSIC",
		int(_radius * 0.022),
		HORIZONTAL_ALIGNMENT_LEFT,
		font
	)
	_category_label.position = Vector2(_info_panel.size.x * 0.06, _info_panel.size.y * 0.675)
	_category_label.size = Vector2(_info_panel.size.x * 0.88, _info_panel.size.y * 0.055)
	_category_label.add_theme_color_override("font_color", Color(0.70, 0.76, 0.86, 1.0))
	_info_panel.add_child(_category_label)

	_bpm_label = _make_label(
		"BPM 120",
		int(_radius * 0.022),
		HORIZONTAL_ALIGNMENT_LEFT,
		font
	)
	_bpm_label.position = Vector2(_info_panel.size.x * 0.06, _info_panel.size.y * 0.735)
	_bpm_label.size = Vector2(_info_panel.size.x * 0.43, _info_panel.size.y * 0.055)
	_info_panel.add_child(_bpm_label)

	_mode_label = _make_label(
		"MODE FACIL",
		int(_radius * 0.022),
		HORIZONTAL_ALIGNMENT_RIGHT,
		font
	)
	_mode_label.position = Vector2(_info_panel.size.x * 0.48, _info_panel.size.y * 0.735)
	_mode_label.size = Vector2(_info_panel.size.x * 0.46, _info_panel.size.y * 0.055)
	_info_panel.add_child(_mode_label)

	_record_label = _make_label(
		"BEST 0.00%",
		int(_radius * 0.026),
		HORIZONTAL_ALIGNMENT_LEFT,
		font
	)
	_record_label.position = Vector2(_info_panel.size.x * 0.06, _info_panel.size.y * 0.80)
	_record_label.size = Vector2(_info_panel.size.x * 0.88, _info_panel.size.y * 0.07)
	_info_panel.add_child(_record_label)

	_start_panel = Panel.new()
	_start_panel.position = Vector2(_info_panel.size.x * 0.055, _info_panel.size.y * 0.89)
	_start_panel.size = Vector2(_info_panel.size.x * 0.89, _info_panel.size.y * 0.075)
	_info_panel.add_child(_start_panel)

	_start_label = _make_label(
		"PRESS START",
		int(_radius * 0.028),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	_start_label.size = _start_panel.size
	_start_panel.add_child(_start_label)


func _change_selection(direction: int) -> void:
	_index = posmod(_index + direction, _songs.size())
	_apply_selection(false)


func _toggle_difficulty() -> void:
	_difficulty = "hard" if _difficulty == "easy" else "easy"
	_apply_selection(false)


func _apply_selection(immediate: bool) -> void:
	if _songs.is_empty():
		return

	var song: Dictionary = _songs[_index] as Dictionary
	var difficulty_data: Dictionary = CATALOG.get_difficulty(song, _difficulty)

	_renderer.configure(_center, _radius, _lane_positions, song, difficulty_data)
	_track_label.text = "TRACK %02d / %02d" % [_index + 1, _songs.size()]
	_song_name.text = str(song.get("title", "TRACK"))
	_category_label.text = "ANIME / RHYTHM"
	_bpm_label.text = "BPM %d" % int(round(float(song.get("bpm", 120.0))))
	_mode_label.text = "MODE " + ("DIFICIL" if _difficulty == "hard" else "FACIL")
	_record_label.text = "BEST " + _best_record(song)
	_cover.texture = _load_texture(str(song.get("cover", "")))

	_load_preview(song)
	_update_cards(immediate)
	_update_live_styles()
	LED_CLIENT.menu_state(_index, _song_primary(song))


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
		var target_x: float = _radius * 0.19 + (_radius * 0.055 if relative == 0 else 0.0)
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
	_easy_chip.add_theme_stylebox_override(
		"panel",
		_difficulty_style(song, _difficulty == "easy")
	)
	_hard_chip.add_theme_stylebox_override(
		"panel",
		_difficulty_style(song, _difficulty == "hard")
	)

	_brand_label.add_theme_color_override("font_color", Color.WHITE)
	_subtitle_label.add_theme_color_override(
		"font_color",
		Color(primary.r, primary.g, primary.b, 0.92)
	)
	_easy_label.add_theme_color_override(
		"font_color",
		Color.WHITE if _difficulty == "easy" else Color(0.58, 0.64, 0.74, 1.0)
	)
	_hard_label.add_theme_color_override(
		"font_color",
		Color.WHITE if _difficulty == "hard" else Color(0.58, 0.64, 0.74, 1.0)
	)
	_track_label.add_theme_color_override("font_color", Color.WHITE)
	_bpm_label.add_theme_color_override("font_color", primary)
	_mode_label.add_theme_color_override("font_color", accent)
	_record_label.add_theme_color_override("font_color", Color.WHITE)
	_start_label.add_theme_color_override("font_color", Color.WHITE)


func _load_preview(song: Dictionary) -> void:
	_preview_wait = 0.0
	if _video.is_playing():
		_video.stop()
	_video.stream = null
	_video.modulate.a = 0.0

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
	get_tree().set_meta("hit_music_selector_index", _index)
	get_tree().set_meta("hit_music_selector_difficulty", _difficulty)
	LED_CLIENT.clear_all()

	var scene_path: String = str(song.get("scene", ""))
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		_transitioning = false
		push_error("Scene nao encontrada: " + scene_path)
		return

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUINT)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(_top_panel, "position:y", _top_panel.position.y - get_viewport_rect().size.y * 0.035, 0.30)
	tween.tween_property(_top_panel, "modulate:a", 0.0, 0.25)
	tween.tween_property(_content_root, "scale", Vector2(0.94, 0.94), 0.32)
	tween.tween_property(_content_root, "modulate:a", 0.0, 0.27)
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


func _load_texture(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var resource: Resource = load(path)
	if resource is Texture2D:
		return resource as Texture2D
	return null


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
'@

Write-Utf8NoBom (Project-Path "scripts\change_scenes.gd") @'
extends "res://scripts/hit_music_r7/selector.gd"
'@

Write-Host ""
Write-Host "Validando arquivos criados..." -ForegroundColor Yellow

$GeneratedFiles = @(
    "scripts\hit_music_r7\tap_visual.gd",
    "scripts\hit_music_r7\playfield_renderer.gd",
    "scripts\hit_music_r7\selector.gd",
    "scripts\change_scenes.gd"
)

foreach ($RelativePath in $GeneratedFiles) {
    $FullPath = Project-Path $RelativePath
    if (-not (Test-Path -LiteralPath $FullPath)) {
        throw "Falha ao criar: $RelativePath"
    }
    $Length = (Get-Item -LiteralPath $FullPath).Length
    if ($Length -le 10) {
        throw "Arquivo criado com tamanho invalido: $RelativePath"
    }
    Write-Host "[OK] $RelativePath ($Length bytes)" -ForegroundColor Green
}

if ($GitAvailable -and (Test-Path -LiteralPath (Project-Path ".git"))) {
    git add scripts/hit_music_r7/tap_visual.gd
    git add scripts/hit_music_r7/playfield_renderer.gd
    git add scripts/hit_music_r7/selector.gd
    git add scripts/change_scenes.gd
    git commit -m "Upgrade R7 with pro effects and modern rounded selector"
}

Write-Host ""
Write-Host "========================================================" -ForegroundColor Green
Write-Host " R7 EFFECTS PRO APLICADO COM SUCESSO" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green
Write-Host "Backup local: $BackupRoot"
Write-Host "Branch: r7-effects-pro"
Write-Host ""
Write-Host "Abra o Godot, aguarde a importacao e rode com F5." -ForegroundColor Yellow
Write-Host "Nao apague o backup antes de testar Carmine e o seletor." -ForegroundColor Yellow
