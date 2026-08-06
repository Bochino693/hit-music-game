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