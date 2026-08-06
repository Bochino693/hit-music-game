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
