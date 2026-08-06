class_name HitMusicBackgroundThemeRenderer
extends Node2D

var center: Vector2 = Vector2.ZERO
var radius: float = 100.0
var primary_color: Color = Color.WHITE
var secondary_color: Color = Color.WHITE
var pattern_primary: String = "LOSANGOS"
var pattern_secondary: String = "HEXAGONOS"
var intensity: float = 0.18
var speed: float = 0.5
var song_time: float = 0.0

func configure(
	layout: Dictionary,
	song: HitMusicSongConfig,
	difficulty: HitMusicDifficultyConfig
) -> void:
	center = layout.get("center", Vector2.ZERO)
	radius = float(layout.get("radius", 100.0))
	primary_color = song.cor_primaria
	secondary_color = song.cor_secundaria
	pattern_primary = song.padrao_fundo_principal
	pattern_secondary = song.padrao_fundo_secundario
	intensity = difficulty.intensidade_fundo
	speed = difficulty.velocidade_fundo
	queue_redraw()

func set_song_time(value: float) -> void:
	song_time = value
	queue_redraw()

func _draw() -> void:
	_draw_base()
	var section: int = int(floor(song_time / 16.0)) % 2
	var pattern: String = pattern_primary if section == 0 else pattern_secondary
	match pattern:
		"LOSANGOS":
			_draw_diamonds()
		"HEXAGONOS", "COLMEIA":
			_draw_hexagons()
		"QUADRADOS":
			_draw_squares()
		"RADIAL":
			_draw_radial()
		"LINHAS TECNICAS":
			_draw_technical_lines()

func _draw_base() -> void:
	draw_circle(center, radius * 0.995, Color(0.005, 0.008, 0.018, 1.0), true)

func _draw_diamonds() -> void:
	var rotation: float = song_time * speed * 0.08
	for ring in range(2, 6):
		var r: float = radius * (0.16 + float(ring) * 0.12)
		for i in range(8):
			var angle: float = rotation + TAU * float(i) / 8.0
			var pos: Vector2 = center + Vector2(cos(angle), sin(angle)) * r
			var size: float = radius * (0.034 + float(ring) * 0.002)
			var points := PackedVector2Array([
				pos + Vector2(0, -size),
				pos + Vector2(size, 0),
				pos + Vector2(0, size),
				pos + Vector2(-size, 0),
				pos + Vector2(0, -size),
			])
			draw_polyline(
				points,
				Color(primary_color.r, primary_color.g, primary_color.b, intensity * 0.42),
				maxf(1.0, radius * 0.002),
				true
			)

func _draw_hexagons() -> void:
	var rotation: float = -song_time * speed * 0.05
	for ring in range(2, 5):
		var r: float = radius * (0.18 + float(ring) * 0.14)
		for i in range(6):
			var angle: float = rotation + TAU * float(i) / 6.0
			var pos: Vector2 = center + Vector2(cos(angle), sin(angle)) * r
			var points := PackedVector2Array()
			var size: float = radius * 0.055
			for p in range(7):
				var a: float = TAU * float(p) / 6.0
				points.append(pos + Vector2(cos(a), sin(a)) * size)
			draw_polyline(
				points,
				Color(secondary_color.r, secondary_color.g, secondary_color.b, intensity * 0.38),
				maxf(1.0, radius * 0.002),
				true
			)

func _draw_squares() -> void:
	var rotation: float = song_time * speed * 0.06
	for i in range(12):
		var angle: float = rotation + TAU * float(i) / 12.0
		var pos: Vector2 = center + Vector2(cos(angle), sin(angle)) * radius * 0.54
		var size: float = radius * 0.045
		var rect := Rect2(pos - Vector2.ONE * size, Vector2.ONE * size * 2.0)
		draw_rect(
			rect,
			Color(primary_color.r, primary_color.g, primary_color.b, intensity * 0.30),
			false,
			maxf(1.0, radius * 0.002)
		)

func _draw_radial() -> void:
	var rotation: float = song_time * speed * 0.12
	for i in range(24):
		var angle: float = rotation + TAU * float(i) / 24.0
		var direction := Vector2(cos(angle), sin(angle))
		draw_line(
			center + direction * radius * 0.18,
			center + direction * radius * 0.72,
			Color(primary_color.r, primary_color.g, primary_color.b, intensity * 0.18),
			maxf(1.0, radius * 0.0015),
			true
		)

func _draw_technical_lines() -> void:
	for i in range(8):
		var angle: float = -PI * 0.5 + TAU * float(i) / 8.0
		var direction := Vector2(cos(angle), sin(angle))
		draw_dashed_line(
			center + direction * radius * 0.12,
			center + direction * radius * 0.75,
			Color(secondary_color.r, secondary_color.g, secondary_color.b, intensity * 0.28),
			maxf(1.0, radius * 0.002),
			radius * 0.015,
			true
		)