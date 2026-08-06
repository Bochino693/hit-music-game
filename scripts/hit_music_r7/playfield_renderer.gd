extends Node2D

# HIT MUSIC R11 FINAL - GEOMETRIA, BRILHO E HOLD CRISTALINO

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
	var duration: float = 0.68
	if kind == "slide":
		duration = 0.78
	elif kind == "hold":
		duration = 0.88
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
	var base_alpha: float = 0.50 if game_state == "selector" else 1.0
	draw_circle(
		center,
		radius * 0.995,
		Color(0.002, 0.004, 0.012, base_alpha),
		true
	)
	draw_circle(
		center,
		radius * (0.86 + pulse * 0.012),
		Color(_primary().r, _primary().g, _primary().b, 0.022 + pulse * 0.018),
		true
	)


func _draw_theme_geometry() -> void:
	var configured_pattern: String = str(
		song.get("pattern", "diamonds")
	).to_lower()
	var intensity: float = clampf(
		float(difficulty.get("background_intensity", 0.18)),
		0.08,
		0.42
	)
	var time_value: float = _idle_time()
	var speed: float = float(
		difficulty.get("background_speed", 0.22)
	)
	var rotation: float = time_value * speed
	var beat: float = _beat_pulse()
	var primary: Color = _primary()
	var secondary: Color = _secondary()
	var accent: Color = _accent()

	# Fundo totalmente geometrico: sem arcos cortados.
	# Cada camada forma uma mandala completa de cristais.
	for layer in range(1, 7):
		var layer_radius: float = radius * (
			0.10 + float(layer) * 0.115
		)
		var count: int = 8 + layer * 2
		var direction_sign: float = (
			1.0 if layer % 2 == 0 else -1.0
		)
		var layer_rotation: float = (
			rotation * direction_sign * (0.35 + float(layer) * 0.04)
		)

		for index in range(count):
			var angle: float = (
				layer_rotation
				+ TAU * float(index) / float(count)
			)
			var direction: Vector2 = Vector2(
				cos(angle),
				sin(angle)
			)
			var position_value: Vector2 = (
				center + direction * layer_radius
			)
			var size: float = radius * (
				0.024 + float(layer) * 0.0032
			)
			var mix_value: float = float(
				(index + layer) % 4
			) / 4.0
			var color: Color = primary.lerp(
				accent,
				mix_value * 0.55
			)
			color.a = (
				intensity * (0.34 + float(layer) * 0.035)
				+ beat * 0.035
			)

			match configured_pattern:
				"hex":
					_draw_regular_polygon(
						position_value,
						size,
						6,
						angle + rotation * 0.16,
						color,
						maxf(1.5, radius * 0.0028)
					)
				"radial":
					_draw_regular_polygon(
						position_value,
						size,
						8,
						angle,
						color,
						maxf(1.5, radius * 0.0028)
					)
				"grid":
					_draw_rotated_diamond(
						position_value,
						size * 1.10,
						angle + PI * 0.25,
						color,
						maxf(1.5, radius * 0.0028)
					)
				_:
					_draw_rotated_diamond(
						position_value,
						size * 1.18,
						angle + PI * 0.25,
						color,
						maxf(1.5, radius * 0.0030)
					)

			if layer >= 3 and index % 2 == 0:
				var inner_position: Vector2 = (
					center + direction * (layer_radius - radius * 0.070)
				)
				draw_line(
					inner_position,
					position_value,
					Color(
						color.r,
						color.g,
						color.b,
						intensity * 0.16
					),
					maxf(1.0, radius * 0.0018),
					true
				)

	# Flor central geometrica, inteira e brilhante.
	for petal in range(8):
		var petal_angle: float = (
			-rotation * 0.55
			+ TAU * float(petal) / 8.0
		)
		var petal_position: Vector2 = (
			center
			+ Vector2(cos(petal_angle), sin(petal_angle))
			* radius * 0.105
		)
		_draw_rotated_diamond(
			petal_position,
			radius * (0.050 + beat * 0.006),
			petal_angle + PI * 0.25,
			Color(primary.r, primary.g, primary.b, 0.30),
			maxf(2.0, radius * 0.0040)
		)

	_draw_regular_polygon(
		center,
		radius * (0.095 + beat * 0.008),
		8,
		rotation * 0.28,
		Color(secondary.r, secondary.g, secondary.b, 0.28),
		maxf(2.0, radius * 0.0042)
	)
	_draw_regular_polygon(
		center,
		radius * (0.062 + beat * 0.006),
		6,
		-rotation * 0.45,
		Color(accent.r, accent.g, accent.b, 0.42),
		maxf(2.0, radius * 0.0045)
	)

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


func _draw_inner_technical_rings() -> void:
	var time_value: float = _idle_time()
	var primary: Color = _primary()
	var accent: Color = _accent()

	# Substitui os antigos segmentos redondos por molduras poligonais.
	for layer in range(3):
		var sides: int = 8 if layer != 1 else 12
		var layer_size: float = radius * (
			0.34 + float(layer) * 0.13
		)
		var rotation_value: float = time_value * (
			0.055 + float(layer) * 0.025
		)
		var color: Color = primary if layer % 2 == 0 else accent
		_draw_regular_polygon(
			center,
			layer_size,
			sides,
			rotation_value * (1.0 if layer % 2 == 0 else -1.0),
			Color(color.r, color.g, color.b, 0.11),
			maxf(1.0, radius * 0.0023)
		)

		for node_index in range(sides):
			var angle: float = (
				rotation_value
				+ TAU * float(node_index) / float(sides)
			)
			var node_position: Vector2 = (
				center
				+ Vector2(cos(angle), sin(angle)) * layer_size
			)
			_draw_rotated_diamond(
				node_position,
				radius * 0.014,
				angle + PI * 0.25,
				Color(color.r, color.g, color.b, 0.18),
				maxf(1.0, radius * 0.0020)
			)

func _draw_ring() -> void:
	var ring_radius: float = radius * 0.905
	var width: float = maxf(4.0, radius * 0.0072)
	var marker_radius: float = maxf(6.0, radius * 0.0195)
	var pulse: float = _beat_pulse()
	var primary: Color = _primary()

	draw_arc(
		center,
		ring_radius + radius * 0.004,
		0.0,
		TAU,
		320,
		Color(primary.r, primary.g, primary.b, 0.10 + pulse * 0.05),
		width * 3.4,
		true
	)
	draw_arc(
		center,
		ring_radius,
		0.0,
		TAU,
		320,
		Color.WHITE,
		width,
		true
	)

	for position_value in lane_positions:
		draw_circle(
			position_value,
			marker_radius * 1.75,
			Color(1.0, 1.0, 1.0, 0.08),
			true
		)
		draw_circle(position_value, marker_radius, Color.WHITE, true)



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
	var length: float = radius * (0.52 if song_time < hit_time else maxf(0.085, 0.52 * remaining))
	var tail: Vector2 = head - direction * length
	var width: float = radius * 0.092 * float(difficulty.get("hold_width", 1.0))
	var color: Color = Color(1.0, 0.83, 0.08, 1.0)
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
	# HOLD CRISTALINO: trilho geometrico em vez de tubo arredondado.
	var direction: Vector2 = (head - tail).normalized()
	var normal: Vector2 = Vector2(-direction.y, direction.x)
	var length: float = tail.distance_to(head)
	var angle: float = direction.angle()
	var glow_alpha: float = 0.42 if active else 0.24
	var core_alpha: float = 0.96 if active else 0.78

	# Aura larga e dois trilhos luminosos.
	draw_line(
		tail,
		head,
		Color(color.r, color.g, color.b, glow_alpha * 0.34),
		half_width * 5.2,
		true
	)
	draw_line(
		tail + normal * half_width * 0.62,
		head + normal * half_width * 0.62,
		Color.WHITE,
		maxf(2.0, half_width * 0.23),
		true
	)
	draw_line(
		tail - normal * half_width * 0.62,
		head - normal * half_width * 0.62,
		Color(color.r, color.g, color.b, core_alpha),
		maxf(2.0, half_width * 0.28),
		true
	)

	var cell_spacing: float = maxf(half_width * 1.35, 1.0)
	var cell_count: int = maxi(4, int(length / cell_spacing))
	var phase: float = fmod(
		_idle_time() * (2.2 if active else 1.15),
		1.0
	)

	for index in range(cell_count + 1):
		var cell_t: float = clampf(
			(float(index) + phase) / float(cell_count),
			0.0,
			1.0
		)
		var cell_position: Vector2 = tail.lerp(head, cell_t)
		var cell_color: Color = color.lerp(
			Color.WHITE,
			0.28 if index % 2 == 0 else 0.08
		)
		cell_color.a = 0.82 if active else 0.54
		var sides: int = 6 if index % 2 == 0 else 4
		_draw_regular_polygon(
			cell_position,
			half_width * (0.72 if sides == 6 else 0.60),
			sides,
			angle + float(index) * 0.34,
			cell_color,
			maxf(2.0, half_width * 0.16)
		)

	# Parte ja completada vira um feixe branco vivo.
	if progress > 0.0:
		var completed_start: Vector2 = head.lerp(tail, progress)
		draw_line(
			completed_start,
			head,
			Color(1.0, 1.0, 1.0, 0.62),
			half_width * 0.34,
			true
		)

	var pulse: float = 0.5 + 0.5 * sin(_idle_time() * 9.0)
	var head_size: float = half_width * (1.42 + pulse * 0.16)

	# Cabeca do hold: portal octogonal com flor de losangos.
	_draw_regular_polygon(
		head,
		head_size * 1.38,
		8,
		_idle_time() * 0.85,
		Color(color.r, color.g, color.b, 0.48),
		maxf(3.0, half_width * 0.24)
	)
	_draw_regular_polygon(
		head,
		head_size,
		6,
		-_idle_time() * 1.10,
		Color.WHITE,
		maxf(3.0, half_width * 0.22)
	)

	for petal in range(4):
		var petal_angle: float = (
			PI * 0.25
			+ TAU * float(petal) / 4.0
			+ _idle_time() * 0.40
		)
		var petal_position: Vector2 = (
			head
			+ Vector2(cos(petal_angle), sin(petal_angle))
			* head_size * 0.72
		)
		_draw_rotated_diamond(
			petal_position,
			head_size * 0.48,
			petal_angle,
			Color(color.r, color.g, color.b, 0.92),
			maxf(2.0, half_width * 0.15)
		)

	_draw_rotated_diamond(
		tail,
		half_width * 1.08,
		angle + PI * 0.25,
		Color(color.r, color.g, color.b, 0.82),
		maxf(2.0, half_width * 0.18)
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

	var color: Color = Color(0.04, 0.93, 1.0, 1.0)
	var accent: Color = Color(0.82, 1.0, 1.0, 1.0)
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
		radius * 0.105 * float(difficulty.get("star_scale", 1.0)),
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
	var spacing: float = radius * 0.052
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
		_draw_chevron(position_value, tangent, radius * 0.058, arrow_color)


func _draw_chevron(
	position_value: Vector2,
	direction: Vector2,
	size: float,
	color: Color
) -> void:
	var tangent: Vector2 = direction.normalized()
	var perpendicular := Vector2(-tangent.y, tangent.x)
	var length: float = size * 2.10
	var half_height: float = size * 0.88

	var tip: Vector2 = position_value + tangent * length * 0.62
	var rear: Vector2 = position_value - tangent * length * 0.48
	var inner: Vector2 = position_value - tangent * length * 0.02

	var polygon := PackedVector2Array([
		rear + perpendicular * half_height,
		inner + perpendicular * half_height * 0.42,
		tip,
		inner - perpendicular * half_height * 0.42,
		rear - perpendicular * half_height,
		position_value - tangent * length * 0.20,
	])

	var shadow_offset := Vector2(radius * 0.009, radius * 0.010)
	var shadow := PackedVector2Array()
	for point in polygon:
		shadow.append(point + shadow_offset)

	draw_colored_polygon(shadow, Color(0.0, 0.0, 0.0, 0.96))
	draw_colored_polygon(polygon, color)

	var outline := polygon.duplicate()
	outline.append(outline[0])
	draw_polyline(
		outline,
		Color(0.01, 0.04, 0.07, 0.98),
		maxf(5.0, size * 0.19),
		true
	)

	var highlight := PackedVector2Array([
		rear + perpendicular * half_height * 0.58,
		inner + perpendicular * half_height * 0.22,
		tip - tangent * length * 0.10,
	])
	draw_polyline(
		highlight,
		Color(0.90, 1.0, 1.0, 0.98),
		maxf(2.0, size * 0.075),
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
	# Explosao de TAP maior, mais luminosa e com prisma em camadas.
	var flash_radius: float = radius * (
		0.055 + progress * 0.190
	)
	draw_circle(
		position_value,
		flash_radius,
		Color(1.0, 1.0, 1.0, life * 0.22),
		true
	)

	for layer in range(5):
		var size: float = radius * (
			0.082 + float(layer) * 0.031
		)
		size *= 0.34 + progress * 1.34
		var alpha: float = life * (
			1.0 - float(layer) * 0.135
		)
		var layer_color: Color = Color.WHITE.lerp(
			color,
			0.14 + float(layer) * 0.19
		)
		layer_color.a = alpha
		_draw_rotated_diamond(
			position_value,
			size,
			rotation_value + float(layer) * PI * 0.20,
			layer_color,
			maxf(4.0, radius * (0.014 - float(layer) * 0.0015))
		)

	for index in range(12):
		var angle: float = (
			rotation_value
			+ TAU * float(index) / 12.0
		)
		var direction: Vector2 = Vector2(
			cos(angle),
			sin(angle)
		)
		var shard_center: Vector2 = (
			position_value
			+ direction * radius * (0.075 + progress * 0.235)
		)
		var shard_size: float = radius * (
			0.022 + progress * 0.032
		)
		_draw_rotated_diamond(
			shard_center,
			shard_size,
			angle,
			Color(color.r, color.g, color.b, life * 0.88),
			maxf(2.5, radius * 0.0060)
		)

	for polygon_layer in range(2):
		_draw_regular_polygon(
			position_value,
			radius * (
				0.080
				+ float(polygon_layer) * 0.065
				+ progress * 0.185
			),
			8 if polygon_layer == 0 else 6,
			rotation_value * (
				1.0 if polygon_layer == 0 else -1.0
			),
			Color(
				1.0,
				1.0,
				1.0,
				life * (0.64 - float(polygon_layer) * 0.18)
			),
			maxf(3.0, radius * 0.0070)
		)

func _draw_slide_burst(
	position_value: Vector2,
	color: Color,
	progress: float,
	life: float,
	rotation_value: float
) -> void:
	for layer in range(4):
		var size: float = radius * (0.105 + float(layer) * 0.030)
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
		var p: Vector2 = position_value + direction * radius * (0.075 + progress * 0.19)
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
	# Final do HOLD: portal cristalino, sem simples aneis redondos.
	var rotation_value: float = (
		float(Time.get_ticks_msec()) / 1000.0 * 1.8
	)

	for layer in range(5):
		var size: float = radius * (
			0.075
			+ float(layer) * 0.044
			+ progress * 0.185
		)
		var sides: int = 8 if layer % 2 == 0 else 6
		var direction_sign: float = (
			1.0 if layer % 2 == 0 else -1.0
		)
		_draw_regular_polygon(
			position_value,
			size,
			sides,
			rotation_value * direction_sign + float(layer) * 0.24,
			Color(
				color.r,
				color.g,
				color.b,
				life * (0.98 - float(layer) * 0.15)
			),
			maxf(3.0, radius * (0.013 - float(layer) * 0.0013))
		)

	for index in range(8):
		var angle: float = (
			rotation_value * 0.55
			+ TAU * float(index) / 8.0
		)
		var direction: Vector2 = Vector2(
			cos(angle),
			sin(angle)
		)
		var crystal_position: Vector2 = (
			position_value
			+ direction * radius * (0.090 + progress * 0.245)
		)
		_draw_rotated_diamond(
			crystal_position,
			radius * (0.034 + progress * 0.028),
			angle + PI * 0.25,
			Color(color.r, color.g, color.b, life * 0.90),
			maxf(2.5, radius * 0.0065)
		)

	draw_circle(
		position_value,
		radius * (0.038 + progress * 0.045),
		Color(1.0, 1.0, 1.0, life * 0.74),
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