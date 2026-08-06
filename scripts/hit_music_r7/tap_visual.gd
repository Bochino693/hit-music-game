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