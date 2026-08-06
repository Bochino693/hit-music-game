class_name HitMusicDiamondHitEffect
extends Node2D

var color: Color = Color.WHITE
var life: float = 0.0
var duration: float = 0.32
var base_size: float = 80.0

func configure(effect_color: Color, size: float) -> void:
	color = effect_color
	base_size = size
	queue_redraw()

func _process(delta: float) -> void:
	life += delta
	if life >= duration:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var t: float = clampf(life / duration, 0.0, 1.0)
	var scale_value: float = lerpf(0.12, 1.12, 1.0 - pow(1.0 - t, 4.0))
	var alpha: float = 1.0 - t
	for layer in range(3):
		var size: float = base_size * scale_value * (1.0 - float(layer) * 0.18)
		var points := PackedVector2Array([
			Vector2(0, -size),
			Vector2(size, 0),
			Vector2(0, size),
			Vector2(-size, 0),
			Vector2(0, -size),
		])
		var layer_color: Color = Color.WHITE.lerp(color, 0.30 + float(layer) * 0.25)
		draw_polyline(
			points,
			Color(layer_color.r, layer_color.g, layer_color.b, alpha * (0.98 - float(layer) * 0.12)),
			maxf(3.0, base_size * (0.055 - float(layer) * 0.010)),
			true
		)