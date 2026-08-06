class_name HitMusicSlideNote
extends HitMusicNoteBase

var path_points: PackedVector2Array = PackedVector2Array()
var slide_color: Color = Color(0.0, 0.95, 1.0, 1.0)
var star_scale: float = 1.0
var current_song_time: float = 0.0

func configure_slide(
	data: Dictionary,
	points: PackedVector2Array,
	difficulty: HitMusicDifficultyConfig,
	color: Color
) -> void:
	event_data = data
	path_points = points
	hit_time = float(data.get("time", 0.0))
	end_time = float(data.get("end_time", hit_time + 1.0))
	approach_time = difficulty.tempo_aproximacao
	star_scale = difficulty.escala_estrela
	slide_color = color
	state = NoteState.APPROACHING
	queue_redraw()

func update_note(song_time: float) -> void:
	if resolved:
		return
	current_song_time = song_time
	queue_redraw()
	if song_time > end_time + 0.35:
		miss()

func _draw() -> void:
	if path_points.size() < 2:
		return

	var width: float = 24.0
	for index in range(path_points.size() - 1):
		var a: Vector2 = path_points[index]
		var b: Vector2 = path_points[index + 1]
		var segment: Vector2 = b - a
		var length: float = segment.length()
		if length <= 0.001:
			continue

		var direction: Vector2 = segment / length
		var perpendicular := Vector2(-direction.y, direction.x)
		var count: int = maxi(4, int(length / 38.0))

		for i in range(count):
			var t: float = (float(i) + 0.5) / float(count)
			var center_point: Vector2 = a.lerp(b, t)
			_draw_chevron(center_point, direction, perpendicular, width)

	var duration: float = maxf(end_time - hit_time, 0.001)
	var progress: float = clampf(
		(current_song_time - hit_time) / duration,
		0.0,
		1.0
	)
	var star_position: Vector2 = _sample_polyline(progress)
	_draw_star(star_position, width * 1.45 * star_scale)

func _draw_chevron(
	center_point: Vector2,
	direction: Vector2,
	perpendicular: Vector2,
	width: float
) -> void:
	var length: float = width * 1.55
	var opening: float = width * 0.72
	var tip: Vector2 = center_point + direction * length * 0.50
	var base: Vector2 = center_point - direction * length * 0.42
	var top: Vector2 = base + perpendicular * opening
	var bottom: Vector2 = base - perpendicular * opening

	var shadow_offset := Vector2(4.0, 5.0)
	var shadow := PackedVector2Array([
		bottom + shadow_offset,
		tip + shadow_offset,
		top + shadow_offset,
	])
	var body := PackedVector2Array([bottom, tip, top])

	draw_polyline(shadow, Color(0.0, 0.0, 0.0, 0.92), maxf(8.0, width * 0.38), true)
	draw_polyline(body, Color(slide_color.r, slide_color.g, slide_color.b, 0.98), maxf(7.0, width * 0.30), true)
	draw_polyline(body, Color(0.72, 1.0, 1.0, 0.94), maxf(2.0, width * 0.075), true)

func _draw_star(pos: Vector2, radius: float) -> void:
	var exterior := _star_polygon(radius, radius * 0.46)
	var interior := _star_polygon(radius * 0.55, radius * 0.24)
	for i in range(exterior.size()):
		exterior[i] += pos
	for i in range(interior.size()):
		interior[i] += pos
	exterior.append(exterior[0])
	interior.append(interior[0])

	draw_polyline(exterior, Color(0.0, 0.0, 0.0, 0.75), maxf(10.0, radius * 0.22), true)
	draw_polyline(exterior, Color.WHITE, maxf(5.0, radius * 0.12), true)
	draw_polyline(interior, slide_color, maxf(4.0, radius * 0.10), true)

func _star_polygon(outer_radius: float, inner_radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(10):
		var angle: float = -PI * 0.5 + PI * float(i) / 5.0
		var radius: float = outer_radius if i % 2 == 0 else inner_radius
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points

func _sample_polyline(progress: float) -> Vector2:
	var lengths: Array[float] = []
	var total: float = 0.0
	for i in range(path_points.size() - 1):
		var length: float = path_points[i].distance_to(path_points[i + 1])
		lengths.append(length)
		total += length

	var target_distance: float = total * clampf(progress, 0.0, 1.0)
	var accumulated: float = 0.0
	for i in range(lengths.size()):
		var length: float = lengths[i]
		if target_distance <= accumulated + length:
			var local_progress: float = (target_distance - accumulated) / maxf(length, 0.001)
			return path_points[i].lerp(path_points[i + 1], local_progress)
		accumulated += length

	return path_points[path_points.size() - 1]