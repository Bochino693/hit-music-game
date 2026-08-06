class_name HitMusicLaneRingRenderer
extends Node2D

const NUM_LANES: int = 8

var center: Vector2 = Vector2.ZERO
var radius: float = 100.0
var lane_positions: PackedVector2Array = PackedVector2Array()

func configure(layout: Dictionary) -> void:
	center = layout.get("center", Vector2.ZERO)
	radius = float(layout.get("radius", 100.0))
	lane_positions = layout.get("lane_positions", PackedVector2Array())
	queue_redraw()

func _draw() -> void:
	var ring_radius: float = radius * 0.905
	var ring_width: float = maxf(3.0, radius * 0.0065)
	var marker_radius: float = maxf(6.0, radius * 0.022)

	# Halo discreto, sem particulas e sem segmentos.
	draw_arc(
		center,
		ring_radius,
		0.0,
		TAU,
		192,
		Color(1.0, 1.0, 1.0, 0.10),
		ring_width * 3.2,
		true
	)

	# Linha continua que separa o preto do circulo.
	draw_arc(
		center,
		ring_radius,
		0.0,
		TAU,
		192,
		Color.WHITE,
		ring_width,
		true
	)

	# Oito bolinhas fixas. Nunca sao tazos ou notas.
	for lane in range(mini(NUM_LANES, lane_positions.size())):
		var pos: Vector2 = lane_positions[lane]
		draw_circle(pos, marker_radius * 1.65, Color(1.0, 1.0, 1.0, 0.09), true)
		draw_circle(pos, marker_radius, Color.WHITE, true)