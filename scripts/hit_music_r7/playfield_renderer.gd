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