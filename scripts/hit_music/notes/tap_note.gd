class_name HitMusicTapNote
extends HitMusicNoteBase

const TAZO_SCENE: PackedScene = preload("res://entities/tazo.tscn")

var visual_tazo: Node2D
var scale_multiplier: float = 1.0

func _ready() -> void:
	var instance: Node = TAZO_SCENE.instantiate()
	if not instance is Node2D:
		push_error("A raiz de res://entities/tazo.tscn precisa ser Node2D.")
		instance.queue_free()
		return

	visual_tazo = instance as Node2D
	visual_tazo.position = Vector2.ZERO
	visual_tazo.rotation = 0.0
	add_child(visual_tazo)

func configure(
	data: Dictionary,
	new_origin: Vector2,
	new_target: Vector2,
	difficulty: HitMusicDifficultyConfig
) -> void:
	super.configure(data, new_origin, new_target, difficulty)
	scale_multiplier = difficulty.escala_tap

func update_note(song_time: float) -> void:
	if resolved:
		return

	var start_time: float = hit_time - approach_time
	var progress: float = clampf(
		(song_time - start_time) / maxf(approach_time, 0.001),
		0.0,
		1.0
	)
	var eased: float = 1.0 - pow(1.0 - progress, 4.0)
	position = origin.lerp(target, eased)

	var visual_scale: float = lerpf(0.72, 1.0, eased) * scale_multiplier
	scale = Vector2.ONE * visual_scale

	if song_time > hit_time + 0.35:
		miss()