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
