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

	# So o brilho desenhado em _draw() usa blend aditivo (a sprite do
	# tazo continua normal): isso troca a leitura de "contorno solido
	# grosso" por um brilho de energia que se soma a luz do fundo,
	# igual ao efeito neon usado em arcades de ritmo modernos.
	var glow_material := CanvasItemMaterial.new()
	glow_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = glow_material

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
			var ghost_radius: float = 15.0 - float(index) * 2.1
			var alpha: float = (0.30 - float(index) * 0.045) * (0.35 + _progress * 0.65)
			_draw_energy_glow(ghost_position, ghost_radius, _visual_color, alpha)

	var ring_radius: float = 76.0 + pulse * 6.0

	# Nucleo em gradiente suave no lugar do preenchimento solido chapado.
	_draw_energy_glow(Vector2.ZERO, ring_radius * 0.68, _visual_color, 0.24 + pulse * 0.05)

	# Linha do anel mais fina e nitida — o brilho ja vem do gradiente acima,
	# entao o traco nao precisa ser grosso para ler como "energetico".
	draw_arc(
		Vector2.ZERO,
		ring_radius,
		0.0,
		TAU,
		56,
		Color(_visual_color.r, _visual_color.g, _visual_color.b, 0.55),
		2.2,
		true
	)
	draw_arc(
		Vector2.ZERO,
		ring_radius * 0.985,
		0.0,
		TAU,
		56,
		Color(1.0, 1.0, 1.0, 0.18 + pulse * 0.08),
		1.2,
		true
	)
	draw_arc(
		Vector2.ZERO,
		ring_radius * 0.84,
		-PI * 0.68,
		PI * 0.10,
		30,
		Color(1.0, 1.0, 1.0, 0.88),
		1.8,
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
			Color(_visual_color.r, _visual_color.g, _visual_color.b, 0.48),
			1.6,
			true
		)


## Gradiente radial "falso": camadas de circulo com alpha decrescente.
## Sem custo de shader/textura, mas le como um brilho de energia suave
## em vez do contorno solido e grosso que existia antes.
func _draw_energy_glow(
	position_value: Vector2,
	radius_value: float,
	color: Color,
	alpha: float
) -> void:
	if radius_value <= 0.0 or alpha <= 0.0:
		return
	const LAYERS: int = 4
	for layer in range(LAYERS):
		var t: float = float(layer) / float(LAYERS - 1)
		var layer_radius: float = radius_value * (1.0 - t * 0.74)
		var layer_alpha: float = alpha * (0.18 + (1.0 - t) * 0.58)
		draw_circle(
			position_value,
			layer_radius,
			Color(color.r, color.g, color.b, layer_alpha),
			true
		)


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