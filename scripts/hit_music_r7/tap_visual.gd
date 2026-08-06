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