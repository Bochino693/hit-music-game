class_name HitMusicHoldNote
extends HitMusicNoteBase

var color: Color = Color(1.0, 0.84, 0.05, 1.0)
var width_multiplier: float = 1.0
var current_song_time: float = 0.0
var pressed: bool = false

func configure(
	data: Dictionary,
	new_origin: Vector2,
	new_target: Vector2,
	difficulty: HitMusicDifficultyConfig
) -> void:
	super.configure(data, new_origin, new_target, difficulty)
	width_multiplier = difficulty.largura_hold
	queue_redraw()

func set_pressed(value: bool) -> void:
	pressed = value
	queue_redraw()

func update_note(song_time: float) -> void:
	if resolved:
		return

	current_song_time = song_time
	var start_time: float = hit_time - approach_time
	var arrival: float = clampf(
		(song_time - start_time) / maxf(approach_time, 0.001),
		0.0,
		1.0
	)
	position = origin.lerp(target, 1.0 - pow(1.0 - arrival, 4.0))
	queue_redraw()

	if song_time > end_time + 0.25:
		miss()

func _draw() -> void:
	var direction: Vector2 = (target - origin).normalized()
	var local_direction: Vector2 = direction
	var lateral := Vector2(-local_direction.y, local_direction.x)

	var duration: float = maxf(end_time - hit_time, 0.001)
	var progress: float = (
		clampf((current_song_time - hit_time) / duration, 0.0, 1.0)
		if current_song_time >= hit_time
		else 0.0
	)
	var remaining: float = 1.0 - progress
	var length: float = maxf(28.0, target.distance_to(origin) * 0.48 * remaining)
	var width: float = maxf(18.0, target.distance_to(origin) * 0.060 * width_multiplier)
	var back: Vector2 = -local_direction * length
	var front: Vector2 = Vector2.ZERO

	var a0: Vector2 = back + lateral * width
	var a1: Vector2 = front + lateral * width
	var b0: Vector2 = back - lateral * width
	var b1: Vector2 = front - lateral * width

	var active_color: Color = color.lerp(Color.WHITE, 0.12 if pressed else 0.0)
	var glow_alpha: float = 0.24 if pressed else 0.13

	draw_line(a0, a1, Color(color.r, color.g, color.b, glow_alpha), width * 0.90, true)
	draw_line(b0, b1, Color(color.r, color.g, color.b, glow_alpha), width * 0.90, true)

	draw_line(a0, a1, active_color, maxf(4.0, width * 0.22), true)
	draw_line(b0, b1, active_color, maxf(4.0, width * 0.22), true)

	draw_arc(
		front,
		width,
		-local_direction.angle() - PI * 0.5,
		-local_direction.angle() + PI * 0.5,
		32,
		Color.WHITE,
		maxf(4.0, width * 0.22),
		true
	)
	draw_arc(
		back,
		width,
		local_direction.angle() - PI * 0.5,
		local_direction.angle() + PI * 0.5,
		32,
		active_color,
		maxf(4.0, width * 0.22),
		true
	)

	draw_circle(front, width * 0.35, Color(0.015, 0.020, 0.035, 0.96), true)
	draw_arc(front, width * 0.35, 0.0, TAU, 28, active_color, maxf(2.0, width * 0.10), true)