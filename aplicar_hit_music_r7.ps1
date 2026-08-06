param(
    [switch]$Push
)

$ErrorActionPreference = "Stop"
$Version = "R7_MAIMAI_STYLE_20260806"
$ProjectRoot = (Get-Location).Path

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

    $Utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $Utf8)
}

function Add-GitIgnoreLine {
    param([Parameter(Mandatory = $true)][string]$Line)

    $GitIgnore = Project-Path ".gitignore"
    if (-not (Test-Path -LiteralPath $GitIgnore)) {
        Write-Utf8NoBom $GitIgnore ""
    }

    $Current = Get-Content -Raw -LiteralPath $GitIgnore
    if ($Current -notmatch [Regex]::Escape($Line)) {
        Add-Content -LiteralPath $GitIgnore -Value $Line -Encoding ASCII
    }
}

function Test-RequiredFile {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $FullPath = Project-Path $RelativePath
    if (-not (Test-Path -LiteralPath $FullPath)) {
        throw "Required file not found: $RelativePath"
    }
}

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " HIT MUSIC R7 - MAIMAI STYLE MODULAR REFACTOR" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "Version: $Version" -ForegroundColor DarkGray
Write-Host "Project: $ProjectRoot"
Write-Host ""

Test-RequiredFile "project.godot"
Test-RequiredFile "scenes\opening.tscn"
Test-RequiredFile "scenes\change_scenes.tscn"
Test-RequiredFile "entities\tazo.tscn"

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupRoot = Project-Path "_backup_hit_music_r7_$Stamp"
New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null

$BackupItems = @(
    "project.godot",
    "scripts\opening.gd",
    "scripts\change_scenes.gd",
    "scripts\carmine.gd",
    "scripts\dragon_ball.gd",
    "scripts\demon.gd",
    "scripts\fairy.gd",
    "scripts\naruto.gd",
    "scripts\rick_morty.gd",
    "scripts\soul.gd",
    "scenes\opening.tscn",
    "scenes\change_scenes.tscn",
    "scenes\carmine.tscn",
    "scenes\dragon_ball.tscn",
    "scenes\demon.tscn",
    "scenes\fairy.tscn",
    "scenes\naruto.tscn",
    "scenes\rick_morty.tscn",
    "scenes\soul.tscn",
    "entities\tazo.tscn"
)

foreach ($Item in $BackupItems) {
    $Source = Project-Path $Item
    if (Test-Path -LiteralPath $Source) {
        $Destination = Join-Path $BackupRoot $Item
        $DestinationParent = Split-Path -Parent $Destination
        New-Item -ItemType Directory -Path $DestinationParent -Force | Out-Null
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
    }
}

Add-GitIgnoreLine "_backup_hit_music_r7_*/"

$GitAvailable = $null -ne (Get-Command git -ErrorAction SilentlyContinue)
if ($GitAvailable -and (Test-Path -LiteralPath (Project-Path ".git"))) {
    $Dirty = git status --porcelain
    if ($Dirty) {
        git add -A
        git commit -m "Checkpoint before Hit Music R7 refactor"
    }

    $BackupBranch = "backup/pre-r7-$Stamp"
    git branch $BackupBranch HEAD

    $TargetBranch = "r7-maimai-style"
    $BranchExists = git branch --list $TargetBranch
    if ($BranchExists) {
        git switch $TargetBranch
    }
    else {
        git switch -c $TargetBranch
    }

    Write-Host "Git backup branch: $BackupBranch" -ForegroundColor DarkGray
    Write-Host "Working branch: $TargetBranch" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "Writing modular R7 files..." -ForegroundColor Yellow

Write-Utf8NoBom (Project-Path "scripts\hit_music_r7\catalog.gd") @'
extends RefCounted

const CATALOG_PATH: String = "res://data/hit_music_songs.json"

static func all_songs() -> Array:
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if file == null:
		push_error("Hit Music catalog not found: " + CATALOG_PATH)
		return []

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("Hit Music catalog root must be a Dictionary.")
		return []

	var raw_songs: Variant = (parsed as Dictionary).get("songs", [])
	if not raw_songs is Array:
		push_error("Hit Music catalog field 'songs' must be an Array.")
		return []

	var result: Array = []
	for raw_song in raw_songs:
		if not raw_song is Dictionary:
			continue
		var song: Dictionary = (raw_song as Dictionary).duplicate(true)
		_prepare_colors(song)
		result.append(song)
	return result


static func get_song(song_id: String) -> Dictionary:
	for song in all_songs():
		if str(song.get("id", "")) == song_id:
			return song
	return {}


static func get_difficulty(song: Dictionary, difficulty_name: String) -> Dictionary:
	var key: String = "hard" if difficulty_name.to_lower() == "hard" else "easy"
	var value: Variant = song.get(key, {})
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}


static func _prepare_colors(song: Dictionary) -> void:
	var colors_value: Variant = song.get("colors", {})
	if not colors_value is Dictionary:
		song["colors"] = {
			"primary": Color(0.05, 0.92, 1.0, 1.0),
			"secondary": Color.WHITE,
			"accent": Color(1.0, 0.84, 0.05, 1.0),
			"dark": Color(0.01, 0.02, 0.05, 1.0),
		}
		return

	var raw_colors: Dictionary = colors_value as Dictionary
	var prepared: Dictionary = {}
	prepared["primary"] = _color_from_value(raw_colors.get("primary", "#10E6F2"))
	prepared["secondary"] = _color_from_value(raw_colors.get("secondary", "#FFFFFF"))
	prepared["accent"] = _color_from_value(raw_colors.get("accent", "#FFE11A"))
	prepared["dark"] = _color_from_value(raw_colors.get("dark", "#020611"))
	song["colors"] = prepared


static func _color_from_value(value: Variant) -> Color:
	if value is Color:
		return value
	return Color.from_string(str(value), Color.WHITE)
'@

Write-Utf8NoBom (Project-Path "scripts\hit_music_r7\chart_factory.gd") @'
extends RefCounted

static func build(song: Dictionary, difficulty_name: String, duration: float) -> Array:
	var profile_value: Variant = song.get(
		"hard" if difficulty_name.to_lower() == "hard" else "easy",
		{}
	)
	if not profile_value is Dictionary:
		return []

	var profile: Dictionary = profile_value as Dictionary
	var events: Array = []
	var bpm: float = maxf(float(song.get("bpm", 120.0)), 1.0)
	var beat: float = 60.0 / bpm
	var step_beats: float = maxf(float(profile.get("step_beats", 1.0)), 0.25)
	var step: float = beat * step_beats
	var start_time: float = maxf(float(song.get("chart_start", 4.0)), 3.2)
	var end_time: float = maxf(start_time + step, duration - 2.2)
	var seed_value: int = int(song.get("seed", 1001))
	if difficulty_name.to_lower() == "hard":
		seed_value += 100000

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var lane_pattern: Array = _array_value(
		song.get(
			"lane_pattern_hard" if difficulty_name.to_lower() == "hard" else "lane_pattern_easy",
			[0, 2, 4, 6, 1, 3, 5, 7]
		)
	)
	if lane_pattern.is_empty():
		lane_pattern = [0, 2, 4, 6, 1, 3, 5, 7]

	var slide_patterns: Array = _array_value(
		song.get(
			"slides_hard" if difficulty_name.to_lower() == "hard" else "slides_easy",
			[
				{"path": [0, 4], "shape": "cross"},
				{"path": [2, 6], "shape": "straight"},
			]
		)
	)

	var slide_every: int = maxi(int(profile.get("slide_every", 10)), 0)
	var hold_every: int = maxi(int(profile.get("hold_every", 14)), 0)
	var double_every: int = maxi(int(profile.get("double_every", 0)), 0)
	var slide_beats: float = maxf(float(profile.get("slide_beats", 3.0)), 1.0)
	var hold_beats: float = maxf(float(profile.get("hold_beats", 3.0)), 1.0)
	var jitter: float = clampf(float(profile.get("jitter", 0.0)), 0.0, 0.20)
	var index: int = 0
	var time_value: float = start_time

	while time_value < end_time:
		var base_lane: int = int(lane_pattern[index % lane_pattern.size()]) % 8
		var event_time: float = time_value
		if jitter > 0.0:
			event_time += rng.randf_range(-step * jitter, step * jitter)
			event_time = maxf(event_time, start_time)

		var made_special: bool = false

		if (
			slide_every > 0
			and index > 0
			and index % slide_every == 0
			and not slide_patterns.is_empty()
		):
			var pattern_value: Variant = slide_patterns[int(index / slide_every) % slide_patterns.size()]
			if pattern_value is Dictionary:
				var pattern: Dictionary = (pattern_value as Dictionary).duplicate(true)
				var path: Array = _array_value(pattern.get("path", [base_lane, (base_lane + 4) % 8]))
				if path.size() >= 2:
					events.append({
						"type": "slide",
						"time": event_time,
						"end_time": minf(event_time + beat * slide_beats, end_time + 1.0),
						"path": path,
						"shape": str(pattern.get("shape", "straight")),
						"curve": float(pattern.get("curve", 0.55)),
						"color_index": index % 3,
					})
					made_special = true

		if (
			not made_special
			and hold_every > 0
			and index > 0
			and index % hold_every == 0
		):
			events.append({
				"type": "hold",
				"time": event_time,
				"end_time": minf(event_time + beat * hold_beats, end_time + 1.0),
				"lane": base_lane,
				"color_index": index % 3,
			})
			made_special = true

		if not made_special:
			events.append({
				"type": "tap",
				"time": event_time,
				"lane": base_lane,
				"color_index": index % 3,
			})

			if double_every > 0 and index > 0 and index % double_every == 0:
				var second_lane: int = (base_lane + int(profile.get("double_distance", 4))) % 8
				events.append({
					"type": "tap",
					"time": event_time,
					"lane": second_lane,
					"color_index": (index + 1) % 3,
				})

		index += 1
		time_value += step

	events.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.get("time", 0.0)) < float(b.get("time", 0.0))
	)
	return events


static func _array_value(value: Variant) -> Array:
	if value is Array:
		return (value as Array).duplicate(true)
	return []
'@

Write-Utf8NoBom (Project-Path "scripts\hit_music_r7\path_builder.gd") @'
extends RefCounted

static func build(
	event: Dictionary,
	center: Vector2,
	radius: float,
	lane_positions: PackedVector2Array
) -> PackedVector2Array:
	var lanes_value: Variant = event.get("path", [])
	if not lanes_value is Array:
		return PackedVector2Array()

	var lanes: Array = lanes_value as Array
	if lanes.size() < 2:
		return PackedVector2Array()

	var start_lane: int = clampi(int(lanes[0]), 0, lane_positions.size() - 1)
	var end_lane: int = clampi(int(lanes[lanes.size() - 1]), 0, lane_positions.size() - 1)
	var start: Vector2 = lane_positions[start_lane]
	var finish: Vector2 = lane_positions[end_lane]
	var shape: String = str(event.get("shape", "straight")).to_lower()
	var curve: float = clampf(float(event.get("curve", 0.55)), -1.0, 1.0)

	match shape:
		"cross":
			return _sample_polyline(PackedVector2Array([start, center, finish]), 18)
		"v":
			var middle_direction: Vector2 = ((start + finish) * 0.5 - center).normalized()
			if middle_direction.length_squared() < 0.01:
				middle_direction = Vector2(0.0, -1.0)
			var middle: Vector2 = center + middle_direction * radius * 0.24
			return _sample_polyline(PackedVector2Array([start, middle, finish]), 18)
		"arc_cw":
			return _sample_quadratic(
				start,
				_arc_control(start, finish, center, radius, absf(curve)),
				finish,
				42
			)
		"arc_ccw":
			return _sample_quadratic(
				start,
				_arc_control(start, finish, center, radius, -absf(curve)),
				finish,
				42
			)
		"hook":
			var direction: Vector2 = (finish - start).normalized()
			var perpendicular := Vector2(-direction.y, direction.x)
			var control_a: Vector2 = start.lerp(center, 0.60) + perpendicular * radius * curve * 0.35
			var control_b: Vector2 = finish.lerp(center, 0.42) - perpendicular * radius * curve * 0.20
			return _sample_cubic(start, control_a, control_b, finish, 48)
		"zigzag":
			var anchors := PackedVector2Array()
			for lane_value in lanes:
				var lane_index: int = clampi(int(lane_value), 0, lane_positions.size() - 1)
				anchors.append(lane_positions[lane_index])
			return _sample_polyline(anchors, 14)
		_:
			if lanes.size() > 2:
				var anchors := PackedVector2Array()
				for lane_value in lanes:
					var lane_index: int = clampi(int(lane_value), 0, lane_positions.size() - 1)
					anchors.append(lane_positions[lane_index])
				return _sample_polyline(anchors, 14)
			return _sample_polyline(PackedVector2Array([start, finish]), 42)


static func point_at(points: PackedVector2Array, progress: float) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	if points.size() == 1:
		return points[0]

	var lengths: Array[float] = []
	var total: float = 0.0
	for index in range(points.size() - 1):
		var length_value: float = points[index].distance_to(points[index + 1])
		lengths.append(length_value)
		total += length_value

	if total <= 0.001:
		return points[0]

	var target_distance: float = total * clampf(progress, 0.0, 1.0)
	var accumulated: float = 0.0
	for index in range(lengths.size()):
		var length_value: float = lengths[index]
		if target_distance <= accumulated + length_value:
			var local: float = (target_distance - accumulated) / maxf(length_value, 0.001)
			return points[index].lerp(points[index + 1], local)
		accumulated += length_value
	return points[points.size() - 1]


static func tangent_at(points: PackedVector2Array, progress: float) -> Vector2:
	if points.size() < 2:
		return Vector2.RIGHT
	var before: Vector2 = point_at(points, maxf(progress - 0.008, 0.0))
	var after: Vector2 = point_at(points, minf(progress + 0.008, 1.0))
	var tangent: Vector2 = after - before
	return tangent.normalized() if tangent.length_squared() > 0.001 else Vector2.RIGHT


static func nearest_progress(
	points: PackedVector2Array,
	position_value: Vector2,
	minimum_progress: float = 0.0
) -> Dictionary:
	if points.is_empty():
		return {"progress": 0.0, "distance": INF}

	var start_index: int = clampi(
		int(floor(clampf(minimum_progress, 0.0, 1.0) * float(points.size() - 1))) - 2,
		0,
		points.size() - 1
	)
	var best_index: int = start_index
	var best_distance: float = INF

	for index in range(start_index, points.size()):
		var distance_value: float = points[index].distance_to(position_value)
		if distance_value < best_distance:
			best_distance = distance_value
			best_index = index

	return {
		"progress": float(best_index) / float(maxi(points.size() - 1, 1)),
		"distance": best_distance,
	}


static func _arc_control(
	start: Vector2,
	finish: Vector2,
	center: Vector2,
	radius: float,
	curve: float
) -> Vector2:
	var midpoint: Vector2 = (start + finish) * 0.5
	var chord: Vector2 = finish - start
	var perpendicular := Vector2(-chord.y, chord.x).normalized()
	if perpendicular.dot(midpoint - center) < 0.0:
		perpendicular = -perpendicular
	return midpoint + perpendicular * radius * curve * 0.60


static func _sample_quadratic(
	a: Vector2,
	b: Vector2,
	c: Vector2,
	steps: int
) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(steps + 1):
		var t: float = float(index) / float(steps)
		var p: Vector2 = (
			a * pow(1.0 - t, 2.0)
			+ b * (2.0 * (1.0 - t) * t)
			+ c * (t * t)
		)
		points.append(p)
	return points


static func _sample_cubic(
	a: Vector2,
	b: Vector2,
	c: Vector2,
	d: Vector2,
	steps: int
) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(steps + 1):
		var t: float = float(index) / float(steps)
		var one_minus: float = 1.0 - t
		var p: Vector2 = (
			a * pow(one_minus, 3.0)
			+ b * (3.0 * pow(one_minus, 2.0) * t)
			+ c * (3.0 * one_minus * t * t)
			+ d * pow(t, 3.0)
		)
		points.append(p)
	return points


static func _sample_polyline(
	anchors: PackedVector2Array,
	steps_per_segment: int
) -> PackedVector2Array:
	var result := PackedVector2Array()
	if anchors.is_empty():
		return result
	if anchors.size() == 1:
		result.append(anchors[0])
		return result

	for segment in range(anchors.size() - 1):
		for index in range(steps_per_segment):
			var t: float = float(index) / float(steps_per_segment)
			result.append(anchors[segment].lerp(anchors[segment + 1], t))
	result.append(anchors[anchors.size() - 1])
	return result
'@

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

func _ready() -> void:
	var instance: Node = TAZO_SCENE.instantiate()
	if not instance is Node2D:
		push_error("res://entities/tazo.tscn must have a Node2D root.")
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
	z_index = 30

	if _sprite != null:
		_sprite.frame = frame_index


func update_visual(song_time: float) -> void:
	var duration: float = maxf(hit_time - spawn_time, 0.001)
	var progress: float = clampf((song_time - spawn_time) / duration, 0.0, 1.0)
	var eased: float = 1.0 - pow(1.0 - progress, 4.0)
	position = origin.lerp(target, eased)

	var source_diameter: float = 160.0
	var scale_value: float = desired_diameter / source_diameter
	scale_value *= lerpf(0.66, 1.0, eased)
	scale = Vector2.ONE * scale_value

	var pulse: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) / 85.0)
	modulate = Color(1.0, 1.0, 1.0, 0.92 + pulse * 0.08)


func _find_sprite(node: Node) -> AnimatedSprite2D:
	if node is AnimatedSprite2D:
		return node as AnimatedSprite2D
	for child in node.get_children():
		var result: AnimatedSprite2D = _find_sprite(child)
		if result != null:
			return result
	return null
'@

Write-Utf8NoBom (Project-Path "scripts\hit_music_r7\led_client.gd") @'
extends RefCounted

static func clear_all() -> void:
	send_raw("CLEAR")


static func set_lane(lane: int, color: Color, duration_ms: int = 0) -> void:
	var r: int = int(round(clampf(color.r, 0.0, 1.0) * 255.0))
	var g: int = int(round(clampf(color.g, 0.0, 1.0) * 255.0))
	var b: int = int(round(clampf(color.b, 0.0, 1.0) * 255.0))
	if duration_ms > 0:
		send_raw("LED %d %d %d %d %d" % [lane, r, g, b, duration_ms])
	else:
		send_raw("LED %d %d %d %d" % [lane, r, g, b])


static func clear_lane(lane: int) -> void:
	send_raw("LED %d 0 0 0" % lane)


static func menu_state(index: int, color: Color) -> void:
	var r: int = int(round(clampf(color.r, 0.0, 1.0) * 255.0))
	var g: int = int(round(clampf(color.g, 0.0, 1.0) * 255.0))
	var b: int = int(round(clampf(color.b, 0.0, 1.0) * 255.0))
	send_raw("MENU %d %d %d %d" % [index, r, g, b])


static func send_raw(command: String) -> void:
	var clean: String = command.strip_edges()
	if clean.is_empty():
		return

	var base_dir: String = ProjectSettings.globalize_path("user://hit_music_serial")
	var spool_dir: String = base_dir.path_join("spool")
	DirAccess.make_dir_recursive_absolute(spool_dir)

	var name: String = "cmd_%020d_%d.cmd" % [
		Time.get_ticks_usec(),
		OS.get_process_id(),
	]
	var final_path: String = spool_dir.path_join(name)
	var temporary_path: String = final_path + ".tmp"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return

	file.store_string(clean + "\n")
	file.flush()
	file.close()

	if FileAccess.file_exists(final_path):
		DirAccess.remove_absolute(final_path)
	var error: Error = DirAccess.rename_absolute(temporary_path, final_path)
	if error != OK and FileAccess.file_exists(temporary_path):
		DirAccess.remove_absolute(temporary_path)
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
	effects.append({
		"kind": kind,
		"position": position_value,
		"color": color,
		"start": float(Time.get_ticks_msec()) / 1000.0,
		"duration": 0.34 if kind == "tap" else 0.46,
	})
	queue_redraw()


func _process(_delta: float) -> void:
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	for index in range(effects.size() - 1, -1, -1):
		var effect: Dictionary = effects[index]
		if now - float(effect.get("start", now)) >= float(effect.get("duration", 0.4)):
			effects.remove_at(index)
	if not effects.is_empty() or game_state == "playing":
		queue_redraw()


func _draw() -> void:
	if radius <= 0.0:
		return

	_draw_theme_geometry()
	_draw_video_frame()
	_draw_ring()

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


func _draw_theme_geometry() -> void:
	var pattern: String = str(song.get("pattern", "diamonds")).to_lower()
	var intensity: float = clampf(float(difficulty.get("background_intensity", 0.16)), 0.03, 0.35)
	var time_value: float = float(Time.get_ticks_msec()) / 1000.0
	var rotation: float = time_value * float(difficulty.get("background_speed", 0.18))
	var primary: Color = _primary()
	var secondary: Color = _secondary()

	match pattern:
		"hex":
			for ring in range(2, 6):
				var ring_radius: float = radius * (0.13 + float(ring) * 0.12)
				for index in range(6):
					var angle: float = rotation + TAU * float(index) / 6.0
					var position_value: Vector2 = center + Vector2(cos(angle), sin(angle)) * ring_radius
					_draw_regular_polygon(
						position_value,
						radius * (0.038 + float(ring) * 0.002),
						6,
						rotation * 0.42,
						Color(primary.r, primary.g, primary.b, intensity * 0.42)
					)
		"radial":
			for index in range(24):
				var angle: float = rotation + TAU * float(index) / 24.0
				var direction := Vector2(cos(angle), sin(angle))
				var alpha: float = intensity * (0.12 + 0.12 * absf(sin(float(index) * 0.7 + time_value)))
				draw_line(
					center + direction * radius * 0.17,
					center + direction * radius * 0.76,
					Color(primary.r, primary.g, primary.b, alpha),
					maxf(1.0, radius * 0.0018),
					true
				)
			for ring in range(2, 6):
				draw_arc(
					center,
					radius * (0.16 + float(ring) * 0.12),
					0.0,
					TAU,
					96,
					Color(secondary.r, secondary.g, secondary.b, intensity * 0.15),
					maxf(1.0, radius * 0.0015),
					true
				)
		"grid":
			var spacing: float = radius * 0.12
			for index in range(-5, 6):
				var offset: float = float(index) * spacing
				draw_line(
					center + Vector2(offset, -radius * 0.62),
					center + Vector2(offset, radius * 0.62),
					Color(primary.r, primary.g, primary.b, intensity * 0.12),
					maxf(1.0, radius * 0.0015),
					true
				)
				draw_line(
					center + Vector2(-radius * 0.62, offset),
					center + Vector2(radius * 0.62, offset),
					Color(secondary.r, secondary.g, secondary.b, intensity * 0.10),
					maxf(1.0, radius * 0.0015),
					true
				)
		_:
			for ring in range(2, 6):
				var ring_radius: float = radius * (0.14 + float(ring) * 0.12)
				for index in range(8):
					var angle: float = rotation + TAU * float(index) / 8.0
					var position_value: Vector2 = center + Vector2(cos(angle), sin(angle)) * ring_radius
					_draw_diamond(
						position_value,
						radius * (0.026 + float(ring) * 0.003),
						Color(primary.r, primary.g, primary.b, intensity * 0.38)
					)


func _draw_video_frame() -> void:
	var rect: Rect2 = Rect2(
		center - Vector2(radius * 0.75, radius * 0.29),
		Vector2(radius * 1.50, radius * 0.58)
	)
	var primary: Color = _primary()
	var secondary: Color = _secondary()
	draw_rect(
		rect.grow(radius * 0.012),
		Color(0.0, 0.0, 0.0, 0.58),
		false,
		maxf(4.0, radius * 0.012),
		true
	)
	draw_rect(
		rect,
		Color(primary.r, primary.g, primary.b, 0.22),
		false,
		maxf(2.0, radius * 0.004),
		true
	)
	draw_line(
		rect.position,
		rect.position + Vector2(rect.size.x, 0.0),
		Color(secondary.r, secondary.g, secondary.b, 0.34),
		maxf(1.0, radius * 0.002),
		true
	)


func _draw_ring() -> void:
	var ring_radius: float = radius * 0.905
	var width: float = maxf(3.0, radius * 0.0065)
	var marker_radius: float = maxf(6.0, radius * 0.021)

	draw_arc(
		center,
		ring_radius,
		0.0,
		TAU,
		240,
		Color(1.0, 1.0, 1.0, 0.10),
		width * 3.2,
		true
	)
	draw_arc(
		center,
		ring_radius,
		0.0,
		TAU,
		240,
		Color.WHITE,
		width,
		true
	)

	for position_value in lane_positions:
		draw_circle(
			position_value,
			marker_radius * 1.70,
			Color(1.0, 1.0, 1.0, 0.085),
			true
		)
		draw_circle(position_value, marker_radius, Color.WHITE, true)


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
	var length: float = radius * (0.42 if song_time < hit_time else maxf(0.065, 0.42 * remaining))
	var tail: Vector2 = head - direction * length
	var width: float = radius * 0.050 * float(difficulty.get("hold_width", 1.0))
	var color: Color = _accent()
	var holding: bool = bool(event.get("_holding", false))
	if holding:
		color = color.lerp(Color.WHITE, 0.18)

	_draw_capsule(tail, head, width, color, holding)


func _draw_capsule(
	tail: Vector2,
	head: Vector2,
	half_width: float,
	color: Color,
	active: bool
) -> void:
	var glow: float = 0.22 if active else 0.13
	draw_line(
		tail,
		head,
		Color(color.r, color.g, color.b, glow),
		half_width * 3.9,
		true
	)
	draw_circle(tail, half_width * 1.95, Color(color.r, color.g, color.b, glow), true)
	draw_circle(head, half_width * 1.95, Color(color.r, color.g, color.b, glow), true)

	draw_line(tail, head, color, half_width * 2.0, true)
	draw_circle(tail, half_width, color, true)
	draw_circle(head, half_width, color, true)

	var inner_width: float = half_width * 1.18
	draw_line(tail, head, _dark(), inner_width, true)
	draw_circle(tail, inner_width * 0.5, _dark(), true)
	draw_circle(head, inner_width * 0.5, _dark(), true)

	draw_arc(
		head,
		half_width * 0.72,
		0.0,
		TAU,
		36,
		Color.WHITE,
		maxf(2.0, half_width * 0.13),
		true
	)
	draw_circle(head, half_width * 0.14, Color.WHITE, true)


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
	var visual_progress: float = clampf(float(event.get("_visual_progress", 0.0)), 0.0, 1.0)
	var active: bool = bool(event.get("_active", false))
	var arrows_from: float = visual_progress if active else 0.0
	_draw_chevrons(points, arrows_from, color)

	var star_position: Vector2
	var tangent: Vector2
	if song_time < hit_time:
		var arrival: float = clampf(
			(song_time - (hit_time - approach)) / maxf(approach, 0.001),
			0.0,
			1.0
		)
		var eased: float = 1.0 - pow(1.0 - arrival, 4.0)
		star_position = center.lerp(points[0], eased)
		tangent = (points[0] - center).normalized()
	else:
		star_position = PATH_BUILDER.point_at(points, visual_progress)
		tangent = PATH_BUILDER.tangent_at(points, visual_progress)

	_draw_star(
		star_position,
		tangent.angle(),
		radius * 0.070 * float(difficulty.get("star_scale", 1.0)),
		color
	)


func _draw_chevrons(
	points: PackedVector2Array,
	start_progress: float,
	color: Color
) -> void:
	var spacing: float = radius * 0.056
	var estimated_length: float = 0.0
	for index in range(points.size() - 1):
		estimated_length += points[index].distance_to(points[index + 1])
	var count: int = maxi(4, int(ceil(estimated_length / maxf(spacing, 1.0))))
	var start_index: int = clampi(int(floor(start_progress * float(count))), 0, count - 1)

	for index in range(start_index, count):
		var progress: float = (float(index) + 0.50) / float(count)
		var position_value: Vector2 = PATH_BUILDER.point_at(points, progress)
		var tangent: Vector2 = PATH_BUILDER.tangent_at(points, progress)
		_draw_chevron(position_value, tangent, radius * 0.037, color)


func _draw_chevron(
	position_value: Vector2,
	direction: Vector2,
	size: float,
	color: Color
) -> void:
	var tangent: Vector2 = direction.normalized()
	var perpendicular := Vector2(-tangent.y, tangent.x)
	var length: float = size * 1.80
	var width: float = size
	var tip: Vector2 = position_value + tangent * length * 0.55
	var back: Vector2 = position_value - tangent * length * 0.45
	var notch: Vector2 = position_value - tangent * length * 0.02

	var polygon := PackedVector2Array([
		back + perpendicular * width,
		notch + perpendicular * width * 0.46,
		tip,
		notch - perpendicular * width * 0.46,
		back - perpendicular * width,
		back - tangent * length * 0.12,
		position_value,
		back - tangent * length * 0.12,
	])

	var shadow := PackedVector2Array()
	var shadow_offset := Vector2(radius * 0.007, radius * 0.008)
	for point in polygon:
		shadow.append(point + shadow_offset)

	draw_colored_polygon(shadow, Color(0.0, 0.0, 0.0, 0.88))
	draw_colored_polygon(polygon, color)
	draw_polyline(
		PackedVector2Array([
			back + perpendicular * width,
			notch + perpendicular * width * 0.46,
			tip,
		]),
		Color(0.86, 1.0, 1.0, 0.92),
		maxf(1.5, size * 0.10),
		true
	)


func _draw_star(
	position_value: Vector2,
	rotation_value: float,
	size: float,
	color: Color
) -> void:
	var outer: PackedVector2Array = _star_points(size, size * 0.46, rotation_value, position_value)
	var inner: PackedVector2Array = _star_points(size * 0.56, size * 0.24, rotation_value, position_value)
	outer.append(outer[0])
	inner.append(inner[0])

	draw_polyline(outer, Color(0.0, 0.0, 0.0, 0.80), maxf(10.0, size * 0.28), true)
	draw_polyline(outer, Color.WHITE, maxf(5.0, size * 0.14), true)
	draw_polyline(inner, color, maxf(4.0, size * 0.12), true)
	draw_circle(position_value, size * 0.10, Color.WHITE, true)


func _draw_effects() -> void:
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	for effect_value in effects:
		if not effect_value is Dictionary:
			continue
		var effect: Dictionary = effect_value as Dictionary
		var duration: float = maxf(float(effect.get("duration", 0.4)), 0.001)
		var progress: float = clampf(
			(now - float(effect.get("start", now))) / duration,
			0.0,
			1.0
		)
		var life: float = 1.0 - progress
		var position_value: Vector2 = effect.get("position", center)
		var color: Color = effect.get("color", Color.WHITE)
		var kind: String = str(effect.get("kind", "tap"))

		if kind == "slide":
			for layer in range(3):
				var size: float = radius * (0.085 + float(layer) * 0.020) * (0.28 + progress * 1.05)
				var points: PackedVector2Array = _star_points(
					size,
					size * 0.44,
					progress * (0.8 if layer % 2 == 0 else -0.7),
					position_value
				)
				points.append(points[0])
				draw_polyline(
					points,
					Color(color.r, color.g, color.b, life * (0.90 - float(layer) * 0.18)),
					maxf(2.0, radius * 0.007),
					true
				)
		elif kind == "hold":
			draw_arc(
				position_value,
				radius * (0.035 + progress * 0.11),
				0.0,
				TAU,
				52,
				Color(color.r, color.g, color.b, life),
				maxf(3.0, radius * 0.010),
				true
			)
			draw_circle(position_value, radius * 0.018 * life, Color.WHITE, true)
		elif kind == "miss":
			var size: float = radius * (0.035 + progress * 0.08)
			draw_line(
				position_value - Vector2(size, size),
				position_value + Vector2(size, size),
				Color(1.0, 0.12, 0.16, life),
				maxf(3.0, radius * 0.010),
				true
			)
			draw_line(
				position_value + Vector2(size, -size),
				position_value + Vector2(-size, size),
				Color(1.0, 0.12, 0.16, life),
				maxf(3.0, radius * 0.010),
				true
			)
		else:
			for layer in range(3):
				var size: float = radius * (0.040 + float(layer) * 0.020) * (0.22 + progress * 1.10)
				var alpha: float = life * (0.96 - float(layer) * 0.20)
				var layer_color: Color = Color.WHITE.lerp(
					color,
					0.30 + float(layer) * 0.28
				)
				layer_color.a = alpha
				_draw_diamond(position_value, size, layer_color)


func _draw_pointer(position_value: Vector2) -> void:
	var color: Color = _primary()
	var pulse: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) / 75.0)
	draw_circle(
		position_value,
		radius * (0.040 + pulse * 0.006),
		Color(color.r, color.g, color.b, 0.10),
		true
	)
	draw_arc(
		position_value,
		radius * (0.030 + pulse * 0.004),
		0.0,
		TAU,
		32,
		Color.WHITE,
		maxf(2.0, radius * 0.004),
		true
	)


func _draw_diamond(position_value: Vector2, size: float, color: Color) -> void:
	var points := PackedVector2Array([
		position_value + Vector2(0.0, -size),
		position_value + Vector2(size, 0.0),
		position_value + Vector2(0.0, size),
		position_value + Vector2(-size, 0.0),
		position_value + Vector2(0.0, -size),
	])
	draw_polyline(points, color, maxf(1.0, radius * 0.0035), true)


func _draw_regular_polygon(
	position_value: Vector2,
	size: float,
	sides: int,
	rotation_value: float,
	color: Color
) -> void:
	var points := PackedVector2Array()
	for index in range(sides + 1):
		var angle: float = rotation_value + TAU * float(index) / float(sides)
		points.append(position_value + Vector2(cos(angle), sin(angle)) * size)
	draw_polyline(points, color, maxf(1.0, radius * 0.002), true)


func _star_points(
	outer_radius: float,
	inner_radius: float,
	rotation_value: float,
	position_value: Vector2
) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(10):
		var angle: float = -PI * 0.5 + PI * float(index) / 5.0 + rotation_value
		var current_radius: float = outer_radius if index % 2 == 0 else inner_radius
		points.append(position_value + Vector2(cos(angle), sin(angle)) * current_radius)
	return points
'@

Write-Utf8NoBom (Project-Path "scripts\hit_music_r7\stage.gd") @'
extends Node2D

const CATALOG: Script = preload("res://scripts/hit_music_r7/catalog.gd")
const CHART_FACTORY: Script = preload("res://scripts/hit_music_r7/chart_factory.gd")
const PATH_BUILDER: Script = preload("res://scripts/hit_music_r7/path_builder.gd")
const TAP_VISUAL_SCRIPT: Script = preload("res://scripts/hit_music_r7/tap_visual.gd")
const RENDERER_SCRIPT: Script = preload("res://scripts/hit_music_r7/playfield_renderer.gd")
const LED_CLIENT: Script = preload("res://scripts/hit_music_r7/led_client.gd")

enum GameState {
	PRESENTATION,
	COUNTDOWN,
	PLAYING,
	RESULT,
}

const NUM_LANES: int = 8
const INPUT_ACTIONS: Array[String] = [
	"input_a",
	"input_b",
	"input_c",
	"input_d",
	"input_e",
	"input_f",
	"input_g",
	"input_h",
]

const TOP_MARGIN_RATIO: float = 0.022
const TOP_HEIGHT_RATIO: float = 0.205
const TOP_GAP_RATIO: float = 0.024
const SIDE_MARGIN_RATIO: float = 0.015
const BOTTOM_MARGIN_RATIO: float = 0.012
const CIRCLE_SCALE: float = 0.985
const PRESENTATION_SECONDS: float = 2.70
const COUNTDOWN_SECONDS: float = 3.0
const RESULT_SECONDS: float = 12.0
const RECORD_PATH: String = "user://hit_music_records.json"

var _song: Dictionary = {}
var _difficulty_name: String = "easy"
var _difficulty: Dictionary = {}
var _events: Array = []
var _state: int = GameState.PRESENTATION
var _state_time: float = 0.0
var _song_time: float = 0.0
var _song_duration: float = 90.0
var _failed: bool = false

var _center: Vector2 = Vector2.ZERO
var _radius: float = 100.0
var _lane_positions: PackedVector2Array = PackedVector2Array()
var _video_rect: Rect2 = Rect2()

var _music_player: AudioStreamPlayer
var _video_player: VideoStreamPlayer
var _cover: TextureRect
var _renderer

var _hud_layer: CanvasLayer
var _top_panel: Panel
var _label_title: Label
var _label_difficulty: Label
var _label_score: Label
var _label_combo: Label
var _label_performance: Label
var _label_time: Label
var _progress_bar: ProgressBar
var _countdown_label: Label
var _result_panel: Panel
var _result_title: Label
var _result_score: Label
var _result_details: Label

var _score_quality_sum: float = 0.0
var _judgement_count: int = 0
var _hits: int = 0
var _misses: int = 0
var _combo: int = 0
var _max_combo: int = 0
var _performance: float = 100.0

var _touch_positions: Dictionary = {}
var _mouse_down: bool = false
var _mouse_position: Vector2 = Vector2.ZERO
var _pointer_active: bool = false
var _pointer_position: Vector2 = Vector2.ZERO


func _song_id() -> String:
	return "carmine"


func _ready() -> void:
	Engine.max_fps = 60
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	_song = CATALOG.get_song(_song_id())
	if _song.is_empty():
		push_error("Song not found in catalog: " + _song_id())
		return

	if get_tree().has_meta("hit_music_difficulty"):
		_difficulty_name = str(get_tree().get_meta("hit_music_difficulty")).to_lower()
	if _difficulty_name != "hard":
		_difficulty_name = "easy"

	_difficulty = CATALOG.get_difficulty(_song, _difficulty_name)
	if _difficulty.is_empty():
		push_error("Difficulty not found for song: " + _song_id())
		return

	_calculate_geometry()
	_build_scene()
	_load_assets()
	_prepare_chart()
	_update_hud()
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	LED_CLIENT.clear_all()


func _process(delta: float) -> void:
	_state_time += delta
	_process_physical_inputs()

	match _state:
		GameState.PRESENTATION:
			if _state_time >= PRESENTATION_SECONDS:
				_start_countdown()
		GameState.COUNTDOWN:
			_update_song_time()
			var count_value: int = maxi(1, int(ceil(COUNTDOWN_SECONDS - _state_time)))
			_countdown_label.text = str(count_value)
			if _state_time >= COUNTDOWN_SECONDS:
				_start_playing()
		GameState.PLAYING:
			_update_song_time()
			_spawn_due_events()
			_update_tap_visuals()
			_update_notes_and_misses()
			_update_hud()
			if _song_time >= _song_duration - 0.02:
				_finish_game(false)
		GameState.RESULT:
			if _state_time >= RESULT_SECONDS:
				_go_to_selector()

	_renderer.set_runtime(
		_events,
		_song_time,
		_state_name(),
		_pointer_position,
		_pointer_active
	)
	queue_redraw()


func _draw() -> void:
	var screen: Vector2 = get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, screen), Color.BLACK, true)
	draw_circle(_center, _radius * 1.012, Color(0.0, 0.0, 0.0, 0.96), true)
	draw_circle(_center, _radius * 0.995, _dark_color(), true)

	var glow_color: Color = _primary_color()
	draw_arc(
		_center,
		_radius * 1.002,
		0.0,
		TAU,
		240,
		Color(glow_color.r, glow_color.g, glow_color.b, 0.12),
		maxf(4.0, _radius * 0.014),
		true
	)


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
	_center = Vector2(
		screen.x * 0.5,
		screen.y - bottom_margin - _radius
	)

	_lane_positions = PackedVector2Array()
	for lane in range(NUM_LANES):
		var angle: float = -PI * 0.5 + TAU * float(lane) / float(NUM_LANES)
		_lane_positions.append(
			_center + Vector2(cos(angle), sin(angle)) * _radius * 0.905
		)

	_video_rect = Rect2(
		_center - Vector2(_radius * 0.75, _radius * 0.29),
		Vector2(_radius * 1.50, _radius * 0.58)
	)


func _build_scene() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	_music_player.bus = "Master"
	add_child(_music_player)

	_video_player = VideoStreamPlayer.new()
	_video_player.name = "VideoBackground"
	_video_player.position = _video_rect.position
	_video_player.size = _video_rect.size
	_video_player.expand = true
	_video_player.loop = true
	_video_player.volume_db = -80.0
	_video_player.z_index = 2
	add_child(_video_player)

	_cover = TextureRect.new()
	_cover.name = "PresentationCover"
	_cover.position = _center - Vector2(_radius * 0.72, _radius * 0.58)
	_cover.size = Vector2(_radius * 1.44, _radius * 1.16)
	_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover.z_index = 3
	add_child(_cover)

	_renderer = RENDERER_SCRIPT.new()
	_renderer.name = "PlayfieldRenderer"
	_renderer.z_index = 10
	add_child(_renderer)
	_renderer.configure(_center, _radius, _lane_positions, _song, _difficulty)

	_build_hud()


func _build_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 40
	add_child(_hud_layer)

	var screen: Vector2 = get_viewport_rect().size
	var margin: float = screen.x * TOP_MARGIN_RATIO
	var height: float = screen.y * TOP_HEIGHT_RATIO

	_top_panel = Panel.new()
	_top_panel.position = Vector2(margin, margin)
	_top_panel.size = Vector2(screen.x - margin * 2.0, height)
	_top_panel.add_theme_stylebox_override("panel", _top_panel_style())
	_hud_layer.add_child(_top_panel)

	var font: Font = _load_font()
	var inner_margin: float = _top_panel.size.x * 0.025
	var title_width: float = _top_panel.size.x * 0.52
	var right_x: float = _top_panel.size.x * 0.60

	_label_title = _make_label(
		str(_song.get("title", "HIT MUSIC")),
		int(height * 0.24),
		HORIZONTAL_ALIGNMENT_LEFT,
		font
	)
	_label_title.position = Vector2(inner_margin, height * 0.10)
	_label_title.size = Vector2(title_width, height * 0.34)
	_top_panel.add_child(_label_title)

	_label_difficulty = _make_label(
		"DIFICIL" if _difficulty_name == "hard" else "FACIL",
		int(height * 0.15),
		HORIZONTAL_ALIGNMENT_LEFT,
		font
	)
	_label_difficulty.position = Vector2(inner_margin, height * 0.47)
	_label_difficulty.size = Vector2(title_width, height * 0.22)
	_label_difficulty.add_theme_color_override("font_color", _accent_color())
	_top_panel.add_child(_label_difficulty)

	_label_time = _make_label("0:00", int(height * 0.14), HORIZONTAL_ALIGNMENT_LEFT, font)
	_label_time.position = Vector2(inner_margin, height * 0.70)
	_label_time.size = Vector2(title_width * 0.42, height * 0.18)
	_top_panel.add_child(_label_time)

	_label_score = _make_label("100.00%", int(height * 0.29), HORIZONTAL_ALIGNMENT_RIGHT, font)
	_label_score.position = Vector2(right_x, height * 0.06)
	_label_score.size = Vector2(_top_panel.size.x - right_x - inner_margin, height * 0.38)
	_label_score.add_theme_color_override("font_color", _secondary_color())
	_top_panel.add_child(_label_score)

	_label_combo = _make_label("COMBO 0", int(height * 0.14), HORIZONTAL_ALIGNMENT_RIGHT, font)
	_label_combo.position = Vector2(right_x, height * 0.46)
	_label_combo.size = Vector2(_top_panel.size.x - right_x - inner_margin, height * 0.18)
	_top_panel.add_child(_label_combo)

	_label_performance = _make_label("LIFE 100%", int(height * 0.13), HORIZONTAL_ALIGNMENT_RIGHT, font)
	_label_performance.position = Vector2(right_x, height * 0.67)
	_label_performance.size = Vector2(_top_panel.size.x - right_x - inner_margin, height * 0.18)
	_label_performance.add_theme_color_override("font_color", _primary_color())
	_top_panel.add_child(_label_performance)

	_progress_bar = ProgressBar.new()
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 1.0
	_progress_bar.value = 0.0
	_progress_bar.show_percentage = false
	_progress_bar.position = Vector2(inner_margin, height * 0.90)
	_progress_bar.size = Vector2(_top_panel.size.x - inner_margin * 2.0, maxf(7.0, height * 0.035))
	_progress_bar.add_theme_stylebox_override("background", _progress_background_style())
	_progress_bar.add_theme_stylebox_override("fill", _progress_fill_style())
	_top_panel.add_child(_progress_bar)

	_countdown_label = _make_label("", int(_radius * 0.32), HORIZONTAL_ALIGNMENT_CENTER, font)
	_countdown_label.position = _center - Vector2(_radius * 0.45, _radius * 0.25)
	_countdown_label.size = Vector2(_radius * 0.90, _radius * 0.50)
	_countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown_label.add_theme_color_override("font_color", Color.WHITE)
	_countdown_label.add_theme_constant_override("outline_size", 10)
	_countdown_label.visible = false
	_hud_layer.add_child(_countdown_label)

	_result_panel = Panel.new()
	_result_panel.position = _center - Vector2(_radius * 0.56, _radius * 0.40)
	_result_panel.size = Vector2(_radius * 1.12, _radius * 0.80)
	_result_panel.visible = false
	_result_panel.add_theme_stylebox_override("panel", _result_panel_style())
	_hud_layer.add_child(_result_panel)

	_result_title = _make_label("TRACK CLEAR", int(_radius * 0.085), HORIZONTAL_ALIGNMENT_CENTER, font)
	_result_title.position = Vector2(_radius * 0.05, _radius * 0.05)
	_result_title.size = Vector2(_result_panel.size.x - _radius * 0.10, _radius * 0.14)
	_result_panel.add_child(_result_title)

	_result_score = _make_label("100.00%", int(_radius * 0.12), HORIZONTAL_ALIGNMENT_CENTER, font)
	_result_score.position = Vector2(_radius * 0.05, _radius * 0.22)
	_result_score.size = Vector2(_result_panel.size.x - _radius * 0.10, _radius * 0.18)
	_result_score.add_theme_color_override("font_color", _accent_color())
	_result_panel.add_child(_result_score)

	_result_details = _make_label("", int(_radius * 0.038), HORIZONTAL_ALIGNMENT_CENTER, font)
	_result_details.position = Vector2(_radius * 0.06, _radius * 0.45)
	_result_details.size = Vector2(_result_panel.size.x - _radius * 0.12, _radius * 0.25)
	_result_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_panel.add_child(_result_details)


func _load_assets() -> void:
	var audio_path: String = str(_song.get("audio", ""))
	if ResourceLoader.exists(audio_path):
		var audio_resource: Resource = load(audio_path)
		if audio_resource is AudioStream:
			_music_player.stream = audio_resource as AudioStream
			_song_duration = maxf((_music_player.stream as AudioStream).get_length(), 10.0)
	else:
		push_error("Audio not found: " + audio_path)

	var video_path: String = str(_song.get("video", ""))
	if ResourceLoader.exists(video_path):
		var video_resource: Resource = load(video_path)
		if video_resource is VideoStream:
			_video_player.stream = video_resource as VideoStream

	var cover_path: String = str(_song.get("cover", ""))
	if ResourceLoader.exists(cover_path):
		var cover_resource: Resource = load(cover_path)
		if cover_resource is Texture2D:
			_cover.texture = cover_resource as Texture2D
	else:
		_cover.visible = false


func _prepare_chart() -> void:
	_events = CHART_FACTORY.build(_song, _difficulty_name, _song_duration)
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


func _start_countdown() -> void:
	_state = GameState.COUNTDOWN
	_state_time = 0.0
	_cover.visible = false
	_video_player.visible = true
	if _video_player.stream != null:
		_video_player.play()
	if _music_player.stream != null:
		_music_player.play()
	_countdown_label.visible = true
	_countdown_label.text = "3"


func _start_playing() -> void:
	_state = GameState.PLAYING
	_state_time = 0.0
	_countdown_label.visible = false


func _update_song_time() -> void:
	if _music_player == null or not _music_player.playing:
		return
	var value: float = _music_player.get_playback_position()
	value += AudioServer.get_time_since_last_mix()
	value -= AudioServer.get_output_latency()
	_song_time = clampf(value, 0.0, _song_duration)


func _spawn_due_events() -> void:
	var approach: float = float(_difficulty.get("approach", 1.0))
	for event_value in _events:
		if not event_value is Dictionary:
			continue
		var event: Dictionary = event_value as Dictionary
		if bool(event.get("_spawned", false)):
			continue
		var hit_time: float = float(event.get("time", 0.0))
		if _song_time < hit_time - approach:
			continue

		event["_spawned"] = true
		var type_name: String = str(event.get("type", "tap"))
		if type_name == "tap":
			_spawn_tap_visual(event, approach)
		elif type_name == "hold":
			var lane: int = int(event.get("lane", 0))
			LED_CLIENT.set_lane(lane, _accent_color())
		elif type_name == "slide":
			pass


func _spawn_tap_visual(event: Dictionary, approach: float) -> void:
	var lane: int = clampi(int(event.get("lane", 0)), 0, NUM_LANES - 1)
	var visual = TAP_VISUAL_SCRIPT.new()
	add_child(visual)
	visual.configure(
		_center,
		_lane_positions[lane],
		float(event.get("time", 0.0)) - approach,
		float(event.get("time", 0.0)),
		_radius * 0.145 * float(_difficulty.get("tap_scale", 1.0)),
		int(event.get("color_index", lane % 3))
	)
	event["_node"] = visual
	LED_CLIENT.set_lane(lane, _tap_color(int(event.get("color_index", 0))))


func _update_tap_visuals() -> void:
	for event_value in _events:
		if not event_value is Dictionary:
			continue
		var event: Dictionary = event_value as Dictionary
		if str(event.get("type", "")) != "tap":
			continue
		if bool(event.get("_resolved", false)):
			continue
		var node_value: Variant = event.get("_node", null)
		if node_value is Node2D and is_instance_valid(node_value):
			node_value.update_visual(_song_time)


func _update_notes_and_misses() -> void:
	var hit_window: float = float(_difficulty.get("hit_window", 0.20))
	for event_value in _events:
		if not event_value is Dictionary:
			continue
		var event: Dictionary = event_value as Dictionary
		if bool(event.get("_resolved", false)):
			continue

		var type_name: String = str(event.get("type", "tap"))
		var hit_time: float = float(event.get("time", 0.0))
		var end_time: float = float(event.get("end_time", hit_time))

		if type_name == "tap":
			if _song_time > hit_time + hit_window:
				_resolve_miss(event)
		elif type_name == "hold":
			if bool(event.get("_holding", false)):
				if _song_time >= end_time:
					_resolve_hit(event, "hold", 1.0)
			elif _song_time > hit_time + hit_window:
				_resolve_miss(event)
		elif type_name == "slide":
			if not bool(event.get("_active", false)) and _song_time > hit_time + hit_window:
				_resolve_miss(event)
			elif _song_time > end_time + 0.28:
				_resolve_miss(event)


func _process_physical_inputs() -> void:
	if _state == GameState.RESULT:
		if _action_pressed("input_start") or _action_pressed("ui_accept"):
			get_tree().reload_current_scene()
		elif _action_pressed("input_b") or _action_pressed("ui_cancel"):
			_go_to_selector()
		return

	if _state != GameState.PLAYING:
		return

	for lane in range(INPUT_ACTIONS.size()):
		var action: String = INPUT_ACTIONS[lane]
		if not InputMap.has_action(action):
			continue
		if Input.is_action_just_pressed(action):
			_handle_lane_press(lane, "lane_%d" % lane)
		if Input.is_action_just_released(action):
			_handle_lane_release(lane, "lane_%d" % lane)


func _input(event: InputEvent) -> void:
	if _state == GameState.RESULT:
		if event is InputEventScreenTouch and event.pressed:
			get_tree().reload_current_scene()
		elif event is InputEventMouseButton and event.pressed:
			get_tree().reload_current_scene()
		return

	if _state != GameState.PLAYING:
		return

	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		_pointer_position = touch.position
		_pointer_active = touch.pressed
		if touch.pressed:
			_touch_positions[touch.index] = touch.position
			_handle_pointer_press("touch_%d" % touch.index, touch.position)
		else:
			_touch_positions.erase(touch.index)
			_handle_pointer_release("touch_%d" % touch.index, touch.position)
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		_touch_positions[drag.index] = drag.position
		_pointer_position = drag.position
		_pointer_active = true
		_handle_pointer_move("touch_%d" % drag.index, drag.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_button: InputEventMouseButton = event
		_mouse_down = mouse_button.pressed
		_mouse_position = mouse_button.position
		_pointer_position = mouse_button.position
		_pointer_active = mouse_button.pressed
		if mouse_button.pressed:
			_handle_pointer_press("mouse", mouse_button.position)
		else:
			_handle_pointer_release("mouse", mouse_button.position)
	elif event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event
		_mouse_position = motion.position
		_pointer_position = motion.position
		_pointer_active = _mouse_down
		if _mouse_down:
			_handle_pointer_move("mouse", motion.position)


func _handle_pointer_press(source: String, position_value: Vector2) -> void:
	var lane: int = _nearest_lane(position_value)
	if lane < 0:
		return
	_handle_lane_press(lane, source)


func _handle_pointer_move(source: String, position_value: Vector2) -> void:
	for event_value in _events:
		if not event_value is Dictionary:
			continue
		var event: Dictionary = event_value as Dictionary
		if bool(event.get("_resolved", false)):
			continue
		if str(event.get("type", "")) != "slide":
			continue
		if not bool(event.get("_active", false)):
			continue
		if str(event.get("_source", "")) != source:
			continue

		var points_value: Variant = event.get("_path_points", PackedVector2Array())
		if not points_value is PackedVector2Array:
			continue
		var points: PackedVector2Array = points_value as PackedVector2Array
		var current_progress: float = float(event.get("_visual_progress", 0.0))
		var nearest: Dictionary = PATH_BUILDER.nearest_progress(
			points,
			position_value,
			current_progress
		)
		var distance_value: float = float(nearest.get("distance", INF))
		if distance_value <= _radius * 0.115:
			var next_progress: float = maxf(
				current_progress,
				float(nearest.get("progress", current_progress))
			)
			event["_visual_progress"] = next_progress
			if next_progress >= 0.965:
				var end_position: Vector2 = PATH_BUILDER.point_at(points, 1.0)
				_renderer.add_effect("slide", end_position, _primary_color())
				_resolve_hit(event, "slide", 1.0)


func _handle_pointer_release(source: String, _position_value: Vector2) -> void:
	for event_value in _events:
		if not event_value is Dictionary:
			continue
		var event: Dictionary = event_value as Dictionary
		if bool(event.get("_resolved", false)):
			continue
		if str(event.get("_source", "")) != source:
			continue

		var type_name: String = str(event.get("type", ""))
		if type_name == "hold" and bool(event.get("_holding", false)):
			var end_time: float = float(event.get("end_time", 0.0))
			if _song_time >= end_time - 0.12:
				_resolve_hit(event, "hold", 1.0)
			else:
				_resolve_miss(event)
		elif type_name == "slide" and bool(event.get("_active", false)):
			if float(event.get("_visual_progress", 0.0)) < 0.90:
				_resolve_miss(event)


func _handle_lane_press(lane: int, source: String) -> void:
	if _try_tap(lane):
		return
	if _try_hold(lane, source):
		return
	_try_slide(lane, source)


func _handle_lane_release(_lane: int, source: String) -> void:
	for event_value in _events:
		if not event_value is Dictionary:
			continue
		var event: Dictionary = event_value as Dictionary
		if bool(event.get("_resolved", false)):
			continue
		if str(event.get("type", "")) != "hold":
			continue
		if str(event.get("_source", "")) != source:
			continue
		var end_time: float = float(event.get("end_time", 0.0))
		if _song_time >= end_time - 0.12:
			_resolve_hit(event, "hold", 1.0)
		else:
			_resolve_miss(event)


func _try_tap(lane: int) -> bool:
	var hit_window: float = float(_difficulty.get("hit_window", 0.20))
	var perfect_window: float = float(_difficulty.get("perfect_window", 0.075))
	var best: Dictionary = {}
	var best_difference: float = INF

	for event_value in _events:
		if not event_value is Dictionary:
			continue
		var event: Dictionary = event_value as Dictionary
		if bool(event.get("_resolved", false)):
			continue
		if str(event.get("type", "")) != "tap":
			continue
		if int(event.get("lane", -1)) != lane:
			continue

		var difference: float = absf(_song_time - float(event.get("time", 0.0)))
		if difference <= hit_window and difference < best_difference:
			best = event
			best_difference = difference

	if best.is_empty():
		return false

	var quality: float = 1.0 if best_difference <= perfect_window else 0.72
	_resolve_hit(best, "tap", quality)
	return true


func _try_hold(lane: int, source: String) -> bool:
	var hit_window: float = float(_difficulty.get("hit_window", 0.20))
	var best: Dictionary = {}
	var best_difference: float = INF

	for event_value in _events:
		if not event_value is Dictionary:
			continue
		var event: Dictionary = event_value as Dictionary
		if bool(event.get("_resolved", false)):
			continue
		if str(event.get("type", "")) != "hold":
			continue
		if int(event.get("lane", -1)) != lane:
			continue

		var difference: float = absf(_song_time - float(event.get("time", 0.0)))
		if difference <= hit_window and difference < best_difference:
			best = event
			best_difference = difference

	if best.is_empty():
		return false

	best["_holding"] = true
	best["_source"] = source
	return true


func _try_slide(lane: int, source: String) -> bool:
	var hit_window: float = float(_difficulty.get("hit_window", 0.20))
	var best: Dictionary = {}
	var best_difference: float = INF

	for event_value in _events:
		if not event_value is Dictionary:
			continue
		var event: Dictionary = event_value as Dictionary
		if bool(event.get("_resolved", false)):
			continue
		if str(event.get("type", "")) != "slide":
			continue
		if bool(event.get("_active", false)):
			continue

		var path_value: Variant = event.get("path", [])
		if not path_value is Array or (path_value as Array).is_empty():
			continue
		if int((path_value as Array)[0]) != lane:
			continue

		var difference: float = absf(_song_time - float(event.get("time", 0.0)))
		if difference <= hit_window and difference < best_difference:
			best = event
			best_difference = difference

	if best.is_empty():
		return false

	best["_active"] = true
	best["_source"] = source
	best["_visual_progress"] = 0.0
	return true


func _resolve_hit(event: Dictionary, kind: String, quality: float) -> void:
	if bool(event.get("_resolved", false)):
		return
	event["_resolved"] = true
	event["_active"] = false
	event["_holding"] = false

	var position_value: Vector2 = _event_end_position(event)
	var effect_kind: String = "tap"
	if kind == "slide":
		effect_kind = "slide"
	elif kind == "hold":
		effect_kind = "hold"
	_renderer.add_effect(effect_kind, position_value, _event_color(event))

	_remove_tap_node(event)
	_clear_event_led(event)

	_score_quality_sum += quality
	_judgement_count += 1
	_hits += 1
	_combo += 1
	_max_combo = maxi(_max_combo, _combo)
	_performance = minf(100.0, _performance + (1.15 if quality >= 0.99 else 0.55))


func _resolve_miss(event: Dictionary) -> void:
	if bool(event.get("_resolved", false)):
		return
	event["_resolved"] = true
	event["_active"] = false
	event["_holding"] = false

	var position_value: Vector2 = _event_end_position(event)
	_renderer.add_effect("miss", position_value, Color(1.0, 0.12, 0.16, 1.0))
	_remove_tap_node(event)
	_clear_event_led(event)

	_judgement_count += 1
	_misses += 1
	_combo = 0
	_performance = maxf(0.0, _performance - 6.0)
	if _performance <= 70.0:
		_finish_game(true)


func _remove_tap_node(event: Dictionary) -> void:
	var node_value: Variant = event.get("_node", null)
	if node_value is Node and is_instance_valid(node_value):
		(node_value as Node).queue_free()
	event.erase("_node")


func _clear_event_led(event: Dictionary) -> void:
	var type_name: String = str(event.get("type", ""))
	if type_name == "tap" or type_name == "hold":
		LED_CLIENT.clear_lane(int(event.get("lane", 0)))


func _event_end_position(event: Dictionary) -> Vector2:
	var type_name: String = str(event.get("type", "tap"))
	if type_name == "slide":
		var points_value: Variant = event.get("_path_points", PackedVector2Array())
		if points_value is PackedVector2Array and not (points_value as PackedVector2Array).is_empty():
			return (points_value as PackedVector2Array)[(points_value as PackedVector2Array).size() - 1]
	var lane: int = clampi(int(event.get("lane", 0)), 0, NUM_LANES - 1)
	return _lane_positions[lane]


func _event_color(event: Dictionary) -> Color:
	var type_name: String = str(event.get("type", "tap"))
	if type_name == "hold":
		return _accent_color()
	if type_name == "slide":
		return _primary_color()
	return _tap_color(int(event.get("color_index", 0)))


func _finish_game(failed: bool) -> void:
	if _state == GameState.RESULT:
		return
	_state = GameState.RESULT
	_state_time = 0.0
	_failed = failed
	_music_player.stop()
	_video_player.stop()
	_countdown_label.visible = false
	_result_panel.visible = true

	var score: float = _score_percent()
	_result_title.text = "TRACK FAILED" if failed else "TRACK CLEAR"
	_result_score.text = "%.2f%%" % score
	_result_details.text = (
		"HITS %d   MISSES %d\nMAX COMBO %d\nSTART: REPLAY   B: MENU"
		% [_hits, _misses, _max_combo]
	)
	_save_record(score)
	LED_CLIENT.clear_all()


func _update_hud() -> void:
	if _label_score == null:
		return

	var score: float = _score_percent()
	_label_score.text = "%.2f%%" % score
	_label_combo.text = "COMBO %d" % _combo
	_label_performance.text = "LIFE %d%%" % int(round(_performance))
	_label_performance.add_theme_color_override(
		"font_color",
		_primary_color() if _performance > 78.0 else Color(1.0, 0.15, 0.18, 1.0)
	)

	var current_seconds: int = int(round(_song_time))
	var total_seconds: int = int(round(_song_duration))
	_label_time.text = "%d:%02d / %d:%02d" % [
		int(current_seconds / 60),
		current_seconds % 60,
		int(total_seconds / 60),
		total_seconds % 60,
	]
	_progress_bar.value = clampf(_song_time / maxf(_song_duration, 0.001), 0.0, 1.0)


func _score_percent() -> float:
	if _judgement_count <= 0:
		return 100.0
	return 100.0 * _score_quality_sum / float(_judgement_count)


func _save_record(score: float) -> void:
	var data: Dictionary = {}
	if FileAccess.file_exists(RECORD_PATH):
		var read_file := FileAccess.open(RECORD_PATH, FileAccess.READ)
		if read_file != null:
			var parsed: Variant = JSON.parse_string(read_file.get_as_text())
			if parsed is Dictionary:
				data = parsed as Dictionary

	var song_id: String = str(_song.get("id", _song_id()))
	var current_value: Variant = data.get(song_id, {})
	var song_record: Dictionary = {}
	if current_value is Dictionary:
		song_record = current_value as Dictionary
	var key: String = "dificil" if _difficulty_name == "hard" else "facil"
	song_record[key] = maxf(float(song_record.get(key, 0.0)), score)
	data[song_id] = song_record

	var write_file := FileAccess.open(RECORD_PATH, FileAccess.WRITE)
	if write_file != null:
		write_file.store_string(JSON.stringify(data, "\t"))


func _go_to_selector() -> void:
	LED_CLIENT.clear_all()
	get_tree().change_scene_to_file("res://scenes/change_scenes.tscn")


func _on_viewport_size_changed() -> void:
	_calculate_geometry()
	if _video_player != null:
		_video_player.position = _video_rect.position
		_video_player.size = _video_rect.size
	if _cover != null:
		_cover.position = _center - Vector2(_radius * 0.72, _radius * 0.58)
		_cover.size = Vector2(_radius * 1.44, _radius * 1.16)
	if _renderer != null:
		_renderer.configure(_center, _radius, _lane_positions, _song, _difficulty)
	queue_redraw()


func _nearest_lane(position_value: Vector2) -> int:
	var best_lane: int = -1
	var best_distance: float = INF
	for lane in range(_lane_positions.size()):
		var distance_value: float = _lane_positions[lane].distance_to(position_value)
		if distance_value < best_distance:
			best_distance = distance_value
			best_lane = lane
	return best_lane if best_distance <= _radius * 0.14 else -1


func _state_name() -> String:
	match _state:
		GameState.COUNTDOWN:
			return "countdown"
		GameState.PLAYING:
			return "playing"
		GameState.RESULT:
			return "result"
		_:
			return "presentation"


func _action_pressed(action: String) -> bool:
	return InputMap.has_action(action) and Input.is_action_just_pressed(action)


func _primary_color() -> Color:
	var value: Variant = _song.get("colors", {})
	if value is Dictionary:
		return (value as Dictionary).get("primary", Color(0.05, 0.92, 1.0, 1.0))
	return Color(0.05, 0.92, 1.0, 1.0)


func _secondary_color() -> Color:
	var value: Variant = _song.get("colors", {})
	if value is Dictionary:
		return (value as Dictionary).get("secondary", Color.WHITE)
	return Color.WHITE


func _accent_color() -> Color:
	var value: Variant = _song.get("colors", {})
	if value is Dictionary:
		return (value as Dictionary).get("accent", Color(1.0, 0.84, 0.05, 1.0))
	return Color(1.0, 0.84, 0.05, 1.0)


func _dark_color() -> Color:
	var value: Variant = _song.get("colors", {})
	if value is Dictionary:
		return (value as Dictionary).get("dark", Color(0.01, 0.02, 0.05, 1.0))
	return Color(0.01, 0.02, 0.05, 1.0)


func _tap_color(index: int) -> Color:
	match index % 3:
		0:
			return _accent_color()
		1:
			return _primary_color()
		_:
			return Color(1.0, 0.18, 0.55, 1.0)


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
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.95))
	label.add_theme_constant_override("outline_size", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _top_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.005, 0.010, 0.024, 0.96)
	style.border_color = Color(
		_primary_color().r,
		_primary_color().g,
		_primary_color().b,
		0.72
	)
	style.set_border_width_all(3)
	style.set_corner_radius_all(18)
	style.shadow_color = Color(
		_primary_color().r,
		_primary_color().g,
		_primary_color().b,
		0.18
	)
	style.shadow_size = 12
	return style


func _progress_background_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 1.0, 1.0, 0.10)
	style.set_corner_radius_all(8)
	return style


func _progress_fill_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = _primary_color()
	style.set_corner_radius_all(8)
	style.shadow_color = Color(
		_primary_color().r,
		_primary_color().g,
		_primary_color().b,
		0.36
	)
	style.shadow_size = 6
	return style


func _result_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.006, 0.010, 0.022, 0.96)
	style.border_color = _primary_color()
	style.set_border_width_all(4)
	style.set_corner_radius_all(22)
	style.shadow_color = Color(
		_primary_color().r,
		_primary_color().g,
		_primary_color().b,
		0.28
	)
	style.shadow_size = 16
	return style
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
'@

Write-Utf8NoBom (Project-Path "data\hit_music_songs.json") @'
{
  "songs": [
    {
      "id": "carmine",
      "title": "CARMINE - ONE PIECE",
      "scene": "res://scenes/carmine.tscn",
      "audio": "res://songs/carmine.mp3",
      "video": "res://medias/carmine.ogv",
      "cover": "res://images/carmine.jpg",
      "bpm": 174.0,
      "chart_start": 4.2,
      "seed": 1101,
      "pattern": "diamonds",
      "colors": {
        "primary": "#F40730",
        "secondary": "#FFFFFF",
        "accent": "#FFD21A",
        "dark": "#090208"
      },
      "lane_pattern_easy": [
        0,
        2,
        4,
        6,
        1,
        3,
        5,
        7,
        2,
        6,
        0,
        4
      ],
      "lane_pattern_hard": [
        0,
        4,
        1,
        5,
        2,
        6,
        3,
        7,
        0,
        3,
        6,
        1,
        4,
        7,
        2,
        5
      ],
      "slides_easy": [
        {
          "path": [
            7,
            3
          ],
          "shape": "straight"
        },
        {
          "path": [
            1,
            5
          ],
          "shape": "arc_cw",
          "curve": 0.52
        },
        {
          "path": [
            0,
            4
          ],
          "shape": "cross"
        }
      ],
      "slides_hard": [
        {
          "path": [
            7,
            2,
            5
          ],
          "shape": "zigzag"
        },
        {
          "path": [
            1,
            6
          ],
          "shape": "cross"
        },
        {
          "path": [
            0,
            3
          ],
          "shape": "arc_ccw",
          "curve": 0.72
        },
        {
          "path": [
            4,
            7,
            2
          ],
          "shape": "zigzag"
        }
      ],
      "easy": {
        "approach": 1.12,
        "hit_window": 0.24,
        "perfect_window": 0.09,
        "step_beats": 2.0,
        "slide_every": 9,
        "hold_every": 13,
        "double_every": 0,
        "slide_beats": 4.0,
        "hold_beats": 4.0,
        "tap_scale": 1.08,
        "star_scale": 1.08,
        "hold_width": 1.1,
        "background_intensity": 0.13,
        "background_speed": 0.13,
        "jitter": 0.02
      },
      "hard": {
        "approach": 0.86,
        "hit_window": 0.16,
        "perfect_window": 0.065,
        "step_beats": 1.0,
        "slide_every": 7,
        "hold_every": 11,
        "double_every": 6,
        "double_distance": 4,
        "slide_beats": 3.0,
        "hold_beats": 3.0,
        "tap_scale": 0.98,
        "star_scale": 1.0,
        "hold_width": 0.96,
        "background_intensity": 0.22,
        "background_speed": 0.28,
        "jitter": 0.03
      }
    },
    {
      "id": "dragon_ball",
      "title": "DRAGON BALL",
      "scene": "res://scenes/dragon_ball.tscn",
      "audio": "res://songs/dragon-ball.mp3",
      "video": "res://medias/dragon-ball.ogv",
      "cover": "res://images/dragon-ball.jpeg",
      "bpm": 140.0,
      "chart_start": 4.0,
      "seed": 2202,
      "pattern": "radial",
      "colors": {
        "primary": "#FF6A00",
        "secondary": "#26A7FF",
        "accent": "#FFE21A",
        "dark": "#05080F"
      },
      "lane_pattern_easy": [
        0,
        4,
        2,
        6,
        1,
        5,
        3,
        7,
        0,
        2,
        4,
        6
      ],
      "lane_pattern_hard": [
        0,
        4,
        7,
        3,
        1,
        5,
        2,
        6,
        0,
        5,
        1,
        6,
        2,
        7,
        3,
        4
      ],
      "slides_easy": [
        {
          "path": [
            0,
            4
          ],
          "shape": "cross"
        },
        {
          "path": [
            2,
            6
          ],
          "shape": "arc_cw",
          "curve": 0.6
        },
        {
          "path": [
            7,
            3
          ],
          "shape": "straight"
        }
      ],
      "slides_hard": [
        {
          "path": [
            0,
            5
          ],
          "shape": "hook",
          "curve": 0.8
        },
        {
          "path": [
            7,
            2,
            5
          ],
          "shape": "zigzag"
        },
        {
          "path": [
            1,
            6
          ],
          "shape": "cross"
        },
        {
          "path": [
            3,
            0
          ],
          "shape": "arc_ccw",
          "curve": 0.8
        }
      ],
      "easy": {
        "approach": 1.15,
        "hit_window": 0.24,
        "perfect_window": 0.09,
        "step_beats": 2.0,
        "slide_every": 8,
        "hold_every": 14,
        "double_every": 0,
        "slide_beats": 4.0,
        "hold_beats": 4.0,
        "tap_scale": 1.1,
        "star_scale": 1.1,
        "hold_width": 1.08,
        "background_intensity": 0.15,
        "background_speed": 0.24,
        "jitter": 0.01
      },
      "hard": {
        "approach": 0.82,
        "hit_window": 0.16,
        "perfect_window": 0.06,
        "step_beats": 0.75,
        "slide_every": 7,
        "hold_every": 12,
        "double_every": 5,
        "double_distance": 4,
        "slide_beats": 3.0,
        "hold_beats": 3.0,
        "tap_scale": 0.96,
        "star_scale": 1.02,
        "hold_width": 0.94,
        "background_intensity": 0.24,
        "background_speed": 0.42,
        "jitter": 0.02
      }
    },
    {
      "id": "demon",
      "title": "DEMON",
      "scene": "res://scenes/demon.tscn",
      "audio": "res://songs/demon.mp3",
      "video": "res://medias/demon.ogv",
      "cover": "res://images/demon.jpg",
      "bpm": 135.0,
      "chart_start": 4.0,
      "seed": 3303,
      "pattern": "hex",
      "colors": {
        "primary": "#16E0B8",
        "secondary": "#FF3A64",
        "accent": "#F2FF4B",
        "dark": "#020908"
      },
      "lane_pattern_easy": [
        0,
        1,
        3,
        4,
        6,
        7,
        5,
        2,
        0,
        3,
        6,
        1
      ],
      "lane_pattern_hard": [
        0,
        3,
        1,
        6,
        2,
        7,
        4,
        1,
        5,
        0,
        6,
        3,
        7,
        2,
        4,
        5
      ],
      "slides_easy": [
        {
          "path": [
            0,
            4
          ],
          "shape": "v"
        },
        {
          "path": [
            2,
            7
          ],
          "shape": "arc_ccw",
          "curve": 0.62
        },
        {
          "path": [
            6,
            1
          ],
          "shape": "straight"
        }
      ],
      "slides_hard": [
        {
          "path": [
            0,
            3,
            6
          ],
          "shape": "zigzag"
        },
        {
          "path": [
            2,
            7
          ],
          "shape": "hook",
          "curve": -0.75
        },
        {
          "path": [
            5,
            1
          ],
          "shape": "cross"
        },
        {
          "path": [
            7,
            4,
            0
          ],
          "shape": "zigzag"
        }
      ],
      "easy": {
        "approach": 1.16,
        "hit_window": 0.25,
        "perfect_window": 0.095,
        "step_beats": 2.0,
        "slide_every": 10,
        "hold_every": 12,
        "double_every": 0,
        "slide_beats": 4.0,
        "hold_beats": 4.0,
        "tap_scale": 1.08,
        "star_scale": 1.08,
        "hold_width": 1.12,
        "background_intensity": 0.12,
        "background_speed": 0.12,
        "jitter": 0.02
      },
      "hard": {
        "approach": 0.87,
        "hit_window": 0.17,
        "perfect_window": 0.068,
        "step_beats": 1.0,
        "slide_every": 6,
        "hold_every": 10,
        "double_every": 7,
        "double_distance": 3,
        "slide_beats": 3.0,
        "hold_beats": 3.5,
        "tap_scale": 0.97,
        "star_scale": 1.0,
        "hold_width": 0.96,
        "background_intensity": 0.22,
        "background_speed": 0.24,
        "jitter": 0.03
      }
    },
    {
      "id": "fairy",
      "title": "FAIRY",
      "scene": "res://scenes/fairy.tscn",
      "audio": "res://songs/fairy.mp3",
      "video": "res://medias/fairy.ogv",
      "cover": "res://images/fairy.jpg",
      "bpm": 160.0,
      "chart_start": 4.0,
      "seed": 4404,
      "pattern": "grid",
      "colors": {
        "primary": "#FF4CD8",
        "secondary": "#58F3FF",
        "accent": "#FFE56B",
        "dark": "#07030D"
      },
      "lane_pattern_easy": [
        0,
        2,
        3,
        5,
        6,
        4,
        1,
        7,
        0,
        3,
        6,
        2
      ],
      "lane_pattern_hard": [
        0,
        2,
        5,
        7,
        3,
        1,
        6,
        4,
        0,
        5,
        2,
        7,
        4,
        1,
        3,
        6
      ],
      "slides_easy": [
        {
          "path": [
            7,
            3
          ],
          "shape": "arc_cw",
          "curve": 0.55
        },
        {
          "path": [
            0,
            4
          ],
          "shape": "straight"
        },
        {
          "path": [
            2,
            6
          ],
          "shape": "v"
        }
      ],
      "slides_hard": [
        {
          "path": [
            7,
            1,
            4
          ],
          "shape": "zigzag"
        },
        {
          "path": [
            0,
            5
          ],
          "shape": "hook",
          "curve": 0.7
        },
        {
          "path": [
            2,
            6
          ],
          "shape": "cross"
        },
        {
          "path": [
            4,
            0
          ],
          "shape": "arc_ccw",
          "curve": 0.82
        }
      ],
      "easy": {
        "approach": 1.1,
        "hit_window": 0.24,
        "perfect_window": 0.09,
        "step_beats": 2.0,
        "slide_every": 9,
        "hold_every": 15,
        "double_every": 0,
        "slide_beats": 4.0,
        "hold_beats": 4.0,
        "tap_scale": 1.08,
        "star_scale": 1.1,
        "hold_width": 1.08,
        "background_intensity": 0.14,
        "background_speed": 0.16,
        "jitter": 0.01
      },
      "hard": {
        "approach": 0.83,
        "hit_window": 0.16,
        "perfect_window": 0.062,
        "step_beats": 0.75,
        "slide_every": 6,
        "hold_every": 11,
        "double_every": 5,
        "double_distance": 3,
        "slide_beats": 3.0,
        "hold_beats": 3.0,
        "tap_scale": 0.96,
        "star_scale": 1.02,
        "hold_width": 0.94,
        "background_intensity": 0.25,
        "background_speed": 0.32,
        "jitter": 0.02
      }
    },
    {
      "id": "naruto",
      "title": "NARUTO",
      "scene": "res://scenes/naruto.tscn",
      "audio": "res://songs/naruto.mp3",
      "video": "res://medias/naruto.ogv",
      "cover": "res://images/naruto.jpg",
      "bpm": 164.0,
      "chart_start": 4.0,
      "seed": 5505,
      "pattern": "radial",
      "colors": {
        "primary": "#FF7A00",
        "secondary": "#2D9CFF",
        "accent": "#FFF040",
        "dark": "#070604"
      },
      "lane_pattern_easy": [
        0,
        3,
        6,
        1,
        4,
        7,
        2,
        5,
        0,
        4,
        1,
        5
      ],
      "lane_pattern_hard": [
        0,
        3,
        6,
        1,
        5,
        2,
        7,
        4,
        0,
        6,
        2,
        5,
        1,
        7,
        3,
        4
      ],
      "slides_easy": [
        {
          "path": [
            0,
            4
          ],
          "shape": "cross"
        },
        {
          "path": [
            7,
            2
          ],
          "shape": "arc_ccw",
          "curve": 0.6
        },
        {
          "path": [
            3,
            6
          ],
          "shape": "straight"
        }
      ],
      "slides_hard": [
        {
          "path": [
            0,
            3,
            6
          ],
          "shape": "zigzag"
        },
        {
          "path": [
            7,
            2
          ],
          "shape": "hook",
          "curve": -0.78
        },
        {
          "path": [
            1,
            5
          ],
          "shape": "cross"
        },
        {
          "path": [
            4,
            0
          ],
          "shape": "arc_cw",
          "curve": 0.88
        }
      ],
      "easy": {
        "approach": 1.12,
        "hit_window": 0.24,
        "perfect_window": 0.09,
        "step_beats": 2.0,
        "slide_every": 10,
        "hold_every": 13,
        "double_every": 0,
        "slide_beats": 4.0,
        "hold_beats": 4.0,
        "tap_scale": 1.08,
        "star_scale": 1.08,
        "hold_width": 1.1,
        "background_intensity": 0.14,
        "background_speed": 0.2,
        "jitter": 0.015
      },
      "hard": {
        "approach": 0.84,
        "hit_window": 0.16,
        "perfect_window": 0.064,
        "step_beats": 0.75,
        "slide_every": 7,
        "hold_every": 10,
        "double_every": 6,
        "double_distance": 4,
        "slide_beats": 3.0,
        "hold_beats": 3.0,
        "tap_scale": 0.97,
        "star_scale": 1.02,
        "hold_width": 0.95,
        "background_intensity": 0.24,
        "background_speed": 0.38,
        "jitter": 0.02
      }
    },
    {
      "id": "rick_morty",
      "title": "RICK AND MORTY",
      "scene": "res://scenes/rick_morty.tscn",
      "audio": "res://songs/rick_morty.mp3",
      "video": "res://medias/rick_morty.ogv",
      "cover": "res://images/rick_morty.jpg",
      "bpm": 128.0,
      "chart_start": 4.0,
      "seed": 6606,
      "pattern": "hex",
      "colors": {
        "primary": "#4CFF55",
        "secondary": "#47E9FF",
        "accent": "#E7FF4C",
        "dark": "#020B05"
      },
      "lane_pattern_easy": [
        0,
        4,
        1,
        5,
        2,
        6,
        3,
        7,
        0,
        2,
        4,
        6
      ],
      "lane_pattern_hard": [
        0,
        5,
        2,
        7,
        4,
        1,
        6,
        3,
        0,
        6,
        1,
        7,
        2,
        4,
        5,
        3
      ],
      "slides_easy": [
        {
          "path": [
            0,
            4
          ],
          "shape": "hook",
          "curve": 0.62
        },
        {
          "path": [
            2,
            6
          ],
          "shape": "arc_cw",
          "curve": 0.7
        },
        {
          "path": [
            7,
            3
          ],
          "shape": "cross"
        }
      ],
      "slides_hard": [
        {
          "path": [
            0,
            5
          ],
          "shape": "hook",
          "curve": 0.92
        },
        {
          "path": [
            7,
            2,
            5
          ],
          "shape": "zigzag"
        },
        {
          "path": [
            1,
            6
          ],
          "shape": "arc_ccw",
          "curve": 0.88
        },
        {
          "path": [
            4,
            0
          ],
          "shape": "cross"
        }
      ],
      "easy": {
        "approach": 1.18,
        "hit_window": 0.25,
        "perfect_window": 0.095,
        "step_beats": 2.0,
        "slide_every": 8,
        "hold_every": 14,
        "double_every": 0,
        "slide_beats": 4.0,
        "hold_beats": 4.0,
        "tap_scale": 1.1,
        "star_scale": 1.1,
        "hold_width": 1.1,
        "background_intensity": 0.15,
        "background_speed": 0.18,
        "jitter": 0.02
      },
      "hard": {
        "approach": 0.88,
        "hit_window": 0.17,
        "perfect_window": 0.068,
        "step_beats": 1.0,
        "slide_every": 6,
        "hold_every": 11,
        "double_every": 5,
        "double_distance": 4,
        "slide_beats": 3.0,
        "hold_beats": 3.0,
        "tap_scale": 0.98,
        "star_scale": 1.04,
        "hold_width": 0.96,
        "background_intensity": 0.27,
        "background_speed": 0.34,
        "jitter": 0.04
      }
    },
    {
      "id": "soul",
      "title": "SOUL",
      "scene": "res://scenes/soul.tscn",
      "audio": "res://songs/soul.mp3",
      "video": "res://medias/soul.ogv",
      "cover": "res://images/soul.jpg",
      "bpm": 152.0,
      "chart_start": 4.0,
      "seed": 7707,
      "pattern": "diamonds",
      "colors": {
        "primary": "#FF263F",
        "secondary": "#FFFFFF",
        "accent": "#FFE300",
        "dark": "#080204"
      },
      "lane_pattern_easy": [
        0,
        2,
        5,
        7,
        4,
        1,
        3,
        6,
        0,
        4,
        2,
        6
      ],
      "lane_pattern_hard": [
        0,
        4,
        2,
        6,
        1,
        5,
        3,
        7,
        0,
        5,
        2,
        7,
        4,
        1,
        6,
        3
      ],
      "slides_easy": [
        {
          "path": [
            0,
            4
          ],
          "shape": "straight"
        },
        {
          "path": [
            2,
            6
          ],
          "shape": "v"
        },
        {
          "path": [
            7,
            3
          ],
          "shape": "arc_ccw",
          "curve": 0.62
        }
      ],
      "slides_hard": [
        {
          "path": [
            0,
            4
          ],
          "shape": "cross"
        },
        {
          "path": [
            7,
            2,
            5
          ],
          "shape": "zigzag"
        },
        {
          "path": [
            1,
            6
          ],
          "shape": "hook",
          "curve": 0.8
        },
        {
          "path": [
            3,
            0
          ],
          "shape": "arc_cw",
          "curve": 0.78
        }
      ],
      "easy": {
        "approach": 1.14,
        "hit_window": 0.24,
        "perfect_window": 0.09,
        "step_beats": 2.0,
        "slide_every": 9,
        "hold_every": 12,
        "double_every": 0,
        "slide_beats": 4.0,
        "hold_beats": 4.0,
        "tap_scale": 1.08,
        "star_scale": 1.08,
        "hold_width": 1.1,
        "background_intensity": 0.13,
        "background_speed": 0.14,
        "jitter": 0.015
      },
      "hard": {
        "approach": 0.84,
        "hit_window": 0.16,
        "perfect_window": 0.063,
        "step_beats": 0.75,
        "slide_every": 6,
        "hold_every": 9,
        "double_every": 5,
        "double_distance": 4,
        "slide_beats": 3.0,
        "hold_beats": 3.0,
        "tap_scale": 0.96,
        "star_scale": 1.0,
        "hold_width": 0.95,
        "background_intensity": 0.23,
        "background_speed": 0.3,
        "jitter": 0.02
      }
    }
  ]
}
'@

Write-Utf8NoBom (Project-Path "tools\adicionar_musica_r7.ps1") @'
param(
    [Parameter(Mandatory = $true)][string]$Id,
    [Parameter(Mandatory = $true)][string]$Title,
    [Parameter(Mandatory = $true)][string]$Audio,
    [Parameter(Mandatory = $true)][string]$Video,
    [Parameter(Mandatory = $true)][string]$Cover,
    [double]$Bpm = 140.0,
    [string]$Primary = "#16E6F2",
    [string]$Secondary = "#FFFFFF",
    [string]$Accent = "#FFE11A",
    [string]$Pattern = "diamonds"
)

$ErrorActionPreference = "Stop"
$Root = (Get-Location).Path
$CatalogPath = Join-Path $Root "data\hit_music_songs.json"
if (-not (Test-Path $CatalogPath)) {
    throw "Run aplicar_hit_music_r7.ps1 first."
}

function Write-Utf8NoBom {
    param([string]$Path, [string]$Content)
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8)
}

$idClean = $Id.ToLower().Replace(" ", "_").Replace("-", "_")
$scenePath = "res://scenes/$idClean.tscn"
$scriptPath = "res://scripts/$idClean.gd"

$data = Get-Content -Raw -LiteralPath $CatalogPath | ConvertFrom-Json
if ($data.songs.id -contains $idClean) {
    throw "Song id already exists: $idClean"
}

$newSong = [ordered]@{
    id = $idClean
    title = $Title
    scene = $scenePath
    audio = $Audio
    video = $Video
    cover = $Cover
    bpm = $Bpm
    chart_start = 4.0
    seed = [Math]::Abs($idClean.GetHashCode())
    pattern = $Pattern
    colors = [ordered]@{
        primary = $Primary
        secondary = $Secondary
        accent = $Accent
        dark = "#050812"
    }
    lane_pattern_easy = @(0,2,4,6,1,3,5,7)
    lane_pattern_hard = @(0,4,1,5,2,6,3,7,0,3,6,1,4,7,2,5)
    slides_easy = @(
        [ordered]@{path=@(0,4);shape="straight"},
        [ordered]@{path=@(2,6);shape="arc_cw";curve=0.60}
    )
    slides_hard = @(
        [ordered]@{path=@(0,4);shape="cross"},
        [ordered]@{path=@(7,2,5);shape="zigzag"},
        [ordered]@{path=@(1,6);shape="hook";curve=0.75}
    )
    easy = [ordered]@{
        approach=1.12; hit_window=0.24; perfect_window=0.09; step_beats=2.0
        slide_every=9; hold_every=13; double_every=0; slide_beats=4.0
        hold_beats=4.0; tap_scale=1.08; star_scale=1.08; hold_width=1.10
        background_intensity=0.14; background_speed=0.16; jitter=0.01
    }
    hard = [ordered]@{
        approach=0.85; hit_window=0.16; perfect_window=0.065; step_beats=1.0
        slide_every=6; hold_every=10; double_every=5; double_distance=4
        slide_beats=3.0; hold_beats=3.0; tap_scale=0.97; star_scale=1.02
        hold_width=0.95; background_intensity=0.24; background_speed=0.32
        jitter=0.02
    }
}

$data.songs += [pscustomobject]$newSong
$json = $data | ConvertTo-Json -Depth 20
Write-Utf8NoBom $CatalogPath $json

$wrapper = @"
extends "res://scripts/hit_music_r7/stage.gd"

func _song_id() -> String:
    return "$idClean"
"@
Write-Utf8NoBom (Join-Path $Root "scripts\$idClean.gd") $wrapper

$scene = @"
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="$scriptPath" id="1"]

[node name="$Title" type="Node2D"]
script = ExtResource("1")
"@
Write-Utf8NoBom (Join-Path $Root "scenes\$idClean.tscn") $scene

git add "data/hit_music_songs.json" "scripts/$idClean.gd" "scenes/$idClean.tscn"
git commit -m "Add Hit Music song pack $idClean"

Write-Host "Song added: $idClean" -ForegroundColor Green
Write-Host "Scene: $scenePath"
'@

Write-Utf8NoBom (Project-Path "README_HIT_MUSIC_R7.md") @'
# Hit Music R7

This refactor keeps the original cabinet flow:

1. `scenes/opening.tscn`
2. `scenes/change_scenes.tscn`
3. One scene per song
4. Result screen
5. Return to selector

## Main layout

- Rectangular HUD at the top.
- Large circular playfield at the bottom.
- Continuous white outer ring.
- Eight fixed white lane markers.
- No stationary tazo at the target.
- The tazo entity is used only by moving TAP notes.
- HOLD notes are thick yellow hollow capsules.
- SLIDE notes use large cyan chevrons and a large outlined star.
- TAP hits use layered diamonds.
- Song video is shown in the central horizontal rectangle.
- Each song has its own colors, pattern, BPM, lane sequence, easy chart and hard chart.

## Controls

Selector:

- `input_a`: next song.
- `input_b`: switch easy/hard.
- `input_start`: play.

Gameplay:

- `input_a` through `input_h`: TAP and HOLD lanes.
- Touch/mouse: TAP, HOLD and SLIDE.
- Result: START replays, B returns to selector.

## Song catalog

All packs are configured in:

`res://data/hit_music_songs.json`

Existing packs linked by the migration:

- Carmine
- Dragon Ball
- Demon
- Fairy
- Naruto
- Rick and Morty
- Soul

Each pack defines:

- scene
- audio
- video
- cover
- BPM
- theme colors
- background pattern
- easy timing/profile
- hard timing/profile
- lane patterns
- slide path patterns

## Adding another song

Run from the project root:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\adicionar_musica_r7.ps1 `
  -Id "new_song" `
  -Title "NEW SONG" `
  -Audio "res://songs/new_song.mp3" `
  -Video "res://medias/new_song.ogv" `
  -Cover "res://images/new_song.jpg" `
  -Bpm 150
```

This creates the scene, wrapper script and catalog entry.

## Important synchronization note

The charts are deterministic and BPM-based. Easy and hard are genuinely different, but exact note-to-drum synchronization still depends on the BPM and `chart_start` values in the JSON catalog. Adjust those values per song after testing on the cabinet.
'@

Write-Utf8NoBom (Project-Path "scripts\change_scenes.gd") @'
extends "res://scripts/hit_music_r7/selector.gd"
'@

Write-Utf8NoBom (Project-Path "scripts\carmine.gd") @'
extends "res://scripts/hit_music_r7/stage.gd"

func _song_id() -> String:
	return "carmine"
'@

Write-Utf8NoBom (Project-Path "scripts\dragon_ball.gd") @'
extends "res://scripts/hit_music_r7/stage.gd"

func _song_id() -> String:
	return "dragon_ball"
'@

Write-Utf8NoBom (Project-Path "scripts\demon.gd") @'
extends "res://scripts/hit_music_r7/stage.gd"

func _song_id() -> String:
	return "demon"
'@

Write-Utf8NoBom (Project-Path "scripts\fairy.gd") @'
extends "res://scripts/hit_music_r7/stage.gd"

func _song_id() -> String:
	return "fairy"
'@

Write-Utf8NoBom (Project-Path "scripts\naruto.gd") @'
extends "res://scripts/hit_music_r7/stage.gd"

func _song_id() -> String:
	return "naruto"
'@

Write-Utf8NoBom (Project-Path "scripts\rick_morty.gd") @'
extends "res://scripts/hit_music_r7/stage.gd"

func _song_id() -> String:
	return "rick_morty"
'@

Write-Utf8NoBom (Project-Path "scripts\soul.gd") @'
extends "res://scripts/hit_music_r7/stage.gd"

func _song_id() -> String:
	return "soul"
'@

Write-Host ""
Write-Host "Validating linked assets..." -ForegroundColor Yellow

$Catalog = Get-Content -Raw -LiteralPath (Project-Path "data\hit_music_songs.json") | ConvertFrom-Json
$Missing = @()

foreach ($Song in $Catalog.songs) {
    foreach ($Field in @("scene", "audio", "video", "cover")) {
        $ResourcePath = [string]$Song.$Field
        if ([string]::IsNullOrWhiteSpace($ResourcePath)) {
            $Missing += "$($Song.id): empty $Field"
            continue
        }

        $Relative = $ResourcePath.Replace("res://", "").Replace("/", [IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath (Project-Path $Relative))) {
            $Missing += "$($Song.id): $Field -> $ResourcePath"
        }
    }
}

if ($Missing.Count -gt 0) {
    Write-Host "Missing assets were found:" -ForegroundColor Red
    foreach ($Item in $Missing) {
        Write-Host " - $Item" -ForegroundColor Red
    }
    throw "Fix the missing asset paths before opening the new gameplay."
}

$GodotCommand = Get-Command godot -ErrorAction SilentlyContinue
if ($null -eq $GodotCommand) {
    $GodotCommand = Get-Command godot4 -ErrorAction SilentlyContinue
}

if ($null -ne $GodotCommand) {
    Write-Host "Running Godot headless import check..." -ForegroundColor Yellow
    & $GodotCommand.Source --headless --path $ProjectRoot --editor --quit
    if ($LASTEXITCODE -ne 0) {
        throw "Godot headless validation failed with exit code $LASTEXITCODE"
    }
}
else {
    Write-Warning "Godot was not found in PATH. Open the project in Godot and wait for import."
}

if ($GitAvailable -and (Test-Path -LiteralPath (Project-Path ".git"))) {
    git add -A

    $Changes = git status --porcelain
    if ($Changes) {
        git commit -m "Refactor Hit Music to modular R7 arcade style"
    }

    if ($Push) {
        git push -u origin r7-maimai-style
    }
}

Write-Host ""
Write-Host "======================================================" -ForegroundColor Green
Write-Host " HIT MUSIC R7 CREATED SUCCESSFULLY" -ForegroundColor Green
Write-Host "======================================================" -ForegroundColor Green
Write-Host "Opening was preserved: res://scenes/opening.tscn"
Write-Host "Selector: res://scenes/change_scenes.tscn"
Write-Host "Gameplay packs: Carmine, Dragon Ball, Demon, Fairy, Naruto, Rick and Morty, Soul"
Write-Host "Backup folder: $BackupRoot"
Write-Host ""
Write-Host "Open Godot, wait for imports, then run the project with F5." -ForegroundColor Yellow
Write-Host "To push later: git push -u origin r7-maimai-style" -ForegroundColor Cyan
