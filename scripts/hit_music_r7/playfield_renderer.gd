extends Node2D

# HIT MUSIC R12 - LEITURA LIMPA, HOLD ARCADE E AMBIENTE REFINADO

const PATH_BUILDER: Script = preload("res://scripts/hit_music_r7/path_builder.gd")

var center: Vector2 = Vector2.ZERO
var radius: float = 100.0
var lane_positions: PackedVector2Array = PackedVector2Array()
var song: Dictionary = {}
var difficulty: Dictionary = {}
var events: Array = []
var song_time: float = 0.0
var game_state: String = "presentation"
var pointer_position: Vector2 = Vector2.ZERO
var pointer_active: bool = false
var effects: Array = []
var _hit_energy: float = 0.0
var _combo_energy: float = 0.0

# Nove ceus reutilizaveis. Os sete cenarios atuais recebem estilos
# exclusivos; os outros dois ficam prontos para novas musicas.
const COSMIC_STYLES: Array[String] = [
	"deep_space",
	"constellation",
	"spiral_galaxy",
	"aurora",
	"meteor",
	"planetary",
	"supernova",
	"wormhole",
	"solar_crown",
]
const COSMIC_STYLE_BY_SONG: Dictionary = {
	"carmine": "supernova",
	"dragon_ball": "solar_crown",
	"demon": "aurora",
	"fairy": "constellation",
	"naruto": "spiral_galaxy",
	"rick_morty": "wormhole",
	"soul": "meteor",
}
var _cosmic_stars: Array[Vector4] = []

# Feedback colorido por lane na linha de encaixe (o "ring"). Antes a
# linha e as bolinhas de cada lane eram sempre brancas, sem relacao
# com o que foi acertado. Agora cada lane guarda uma energia de flash
# que "acende" na cor do julgamento (perfect/good/hold/slide/miss) e
# decai suavemente — um efeito diferente para cada tipo de acerto.
var _lane_flash_colors: Array = []
var _lane_flash_energy: Array = []
var _lane_flash_decay: Array = []

# Pulso de energia que contagia a borda inteira a partir do ponto de
# acerto: nasce no angulo do hit e viaja pros dois lados do anel ate
# se encontrar do lado oposto, em vez de ficar so localizado na lane.
var _ring_pulses: Array = []
const RING_PULSE_DURATION: float = 0.85

var _video_style: StyleBoxFlat
var _video_inner_style: StyleBoxFlat


func _ready() -> void:
	_video_style = StyleBoxFlat.new()
	_video_style.bg_color = Color(0.002, 0.004, 0.012, 0.78)
	_video_style.border_color = Color(1.0, 1.0, 1.0, 0.22)
	_video_style.set_border_width_all(3)
	_video_style.set_corner_radius_all(24)
	_video_style.shadow_color = Color(0.0, 0.0, 0.0, 0.70)
	_video_style.shadow_size = 14

	_video_inner_style = StyleBoxFlat.new()
	_video_inner_style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	_video_inner_style.border_color = Color(1.0, 1.0, 1.0, 0.15)
	_video_inner_style.set_border_width_all(1)
	_video_inner_style.set_corner_radius_all(19)

	_lane_flash_colors.clear()
	_lane_flash_energy.clear()
	_lane_flash_decay.clear()
	for _lane in range(8):
		_lane_flash_colors.append(Color.WHITE)
		_lane_flash_energy.append(0.0)
		_lane_flash_decay.append(3.2)


func configure(
	new_center: Vector2,
	new_radius: float,
	new_lanes: PackedVector2Array,
	new_song: Dictionary,
	new_difficulty: Dictionary
) -> void:
	center = new_center
	radius = new_radius
	lane_positions = new_lanes
	song = new_song
	difficulty = new_difficulty
	_rebuild_cosmic_cache()
	queue_redraw()


func set_runtime(
	new_events: Array,
	new_song_time: float,
	new_state: String,
	new_pointer_position: Vector2,
	new_pointer_active: bool
) -> void:
	events = new_events
	song_time = new_song_time
	game_state = new_state
	pointer_position = new_pointer_position
	pointer_active = new_pointer_active
	queue_redraw()


func add_effect(kind: String, position_value: Vector2, color: Color) -> void:
	# O erro continua afetando combo e performance, mas nao cobre a proxima nota.
	if kind == "miss":
		return
	var duration: float = 0.68
	if kind == "slide":
		duration = 0.78
	elif kind == "hold":
		duration = 0.88

	effects.append({
		"kind": kind,
		"position": position_value,
		"color": color,
		"start": float(Time.get_ticks_msec()) / 1000.0,
		"duration": duration,
		"rotation": fmod(position_value.x * 0.017 + position_value.y * 0.013, TAU),
	})
	queue_redraw()


func register_hit(quality: float, combo: int) -> void:
	# Um unico impulso alimenta fundo, bolinhas e anel. Sem nodes temporarios.
	var carmine_boost: float = 1.22 if str(song.get("id", "")) == "carmine" else 1.0
	_hit_energy = minf(1.0, _hit_energy + (0.30 + quality * 0.30) * carmine_boost)
	_combo_energy = clampf(float(combo) / 40.0, 0.0, 1.0)
	queue_redraw()


## Acende a lane mais proxima de position_value com a cor do
## julgamento (PERFECT, GOOD, HOLD, SLIDE ou MISS). intensity controla
## o quao forte o flash comeca e decay_speed controla quao rapido ele
## apaga — assim cada tipo de acerto tem uma assinatura visual propria
## na propria linha de encaixe, nao so no burst central.
func flash_ring_at(
	position_value: Vector2,
	color: Color,
	intensity: float = 1.0,
	decay_speed: float = 3.2
) -> void:
	var lane: int = _nearest_lane_index(position_value)
	if lane < 0 or lane >= _lane_flash_energy.size():
		return
	_lane_flash_colors[lane] = color
	_lane_flash_energy[lane] = clampf(float(_lane_flash_energy[lane]) + intensity, 0.0, 1.6)
	_lane_flash_decay[lane] = decay_speed

	_ring_pulses.append({
		"angle": (lane_positions[lane] - center).angle(),
		"color": color,
		"start": float(Time.get_ticks_msec()) / 1000.0,
		"duration": RING_PULSE_DURATION * (0.55 + minf(intensity, 1.4) * 0.5),
	})
	if _ring_pulses.size() > 10:
		_ring_pulses.remove_at(0)

	queue_redraw()


func _nearest_lane_index(position_value: Vector2) -> int:
	var best_lane: int = -1
	var best_distance: float = INF
	for lane in range(lane_positions.size()):
		var distance_value: float = lane_positions[lane].distance_to(position_value)
		if distance_value < best_distance:
			best_distance = distance_value
			best_lane = lane
	return best_lane


func _process(delta: float) -> void:
	_hit_energy = move_toward(_hit_energy, 0.0, delta * 2.65)
	_combo_energy = move_toward(_combo_energy, 0.0, delta * 0.16)

	var lane_flash_active: bool = false
	for lane in range(_lane_flash_energy.size()):
		var energy: float = float(_lane_flash_energy[lane])
		if energy > 0.0:
			_lane_flash_energy[lane] = move_toward(energy, 0.0, delta * float(_lane_flash_decay[lane]))
			lane_flash_active = true

	var now: float = float(Time.get_ticks_msec()) / 1000.0
	for index in range(effects.size() - 1, -1, -1):
		var effect: Dictionary = effects[index]
		if now - float(effect.get("start", now)) >= float(effect.get("duration", 0.5)):
			effects.remove_at(index)

	for index in range(_ring_pulses.size() - 1, -1, -1):
		var pulse: Dictionary = _ring_pulses[index]
		if now - float(pulse.get("start", now)) >= float(pulse.get("duration", RING_PULSE_DURATION)):
			_ring_pulses.remove_at(index)

	var pulses_active: bool = not _ring_pulses.is_empty()
	if not effects.is_empty() or lane_flash_active or pulses_active or game_state == "playing" or game_state == "selector":
		queue_redraw()


func _draw() -> void:
	if radius <= 0.0:
		return

	_draw_circle_base()
	_draw_cosmic_sky()
	_draw_theme_geometry()
	_draw_ambient_particles()
	_draw_inner_technical_rings()
	_draw_ring()
	_draw_ring_pulses()
	_draw_lane_energy()

	if game_state == "playing" or game_state == "countdown":
		for event_value in events:
			if not event_value is Dictionary:
				continue
			var event: Dictionary = event_value as Dictionary
			if bool(event.get("_resolved", false)):
				continue

			var type_name: String = str(event.get("type", "tap"))
			if type_name == "hold":
				_draw_hold(event)
			elif type_name == "slide":
				_draw_slide(event)

	_draw_effects()

	if pointer_active and game_state == "playing":
		_draw_pointer(pointer_position)


func _colors() -> Dictionary:
	var value: Variant = song.get("colors", {})
	if value is Dictionary:
		return value as Dictionary
	return {}


func _primary() -> Color:
	return _colors().get("primary", Color(0.05, 0.92, 1.0, 1.0))


func _secondary() -> Color:
	return _colors().get("secondary", Color.WHITE)


func _accent() -> Color:
	return _colors().get("accent", Color(1.0, 0.84, 0.05, 1.0))


func _dark() -> Color:
	return _colors().get("dark", Color(0.01, 0.02, 0.05, 1.0))


func _idle_time() -> float:
	if game_state == "selector" or game_state == "presentation":
		return float(Time.get_ticks_msec()) / 1000.0
	return song_time


func _beat_pulse() -> float:
	var bpm: float = maxf(float(song.get("bpm", 120.0)), 1.0)
	var beat_position: float = fmod(maxf(_idle_time(), 0.0) * bpm / 60.0, 1.0)
	return pow(maxf(0.0, 1.0 - beat_position * 5.5), 2.0)


func _draw_circle_base() -> void:
	var pulse: float = _beat_pulse()
	var base_alpha: float = 0.50 if game_state == "selector" else 1.0
	draw_circle(
		center,
		radius * 0.995,
		Color(0.002, 0.004, 0.012, base_alpha),
		true
	)
	draw_circle(
		center,
		radius * (0.86 + pulse * 0.012),
		Color(_primary().r, _primary().g, _primary().b, 0.022 + pulse * 0.018),
		true
	)


func _rebuild_cosmic_cache() -> void:
	_cosmic_stars.clear()
	var song_seed: float = float(song.get("seed", 1001))
	for index in range(36):
		var seed: float = song_seed * 0.017 + float(index) * 12.9898
		var angle: float = fmod(absf(sin(seed) * 43758.5453), TAU)
		var radial: float = 0.10 + sqrt(fmod(absf(cos(seed * 0.731)) * 97.17, 0.82)) * 0.82
		var depth: float = 0.25 + float(index % 4) * 0.22
		var phase: float = fmod(absf(sin(seed * 1.91) * 173.31), TAU)
		_cosmic_stars.append(Vector4(angle, minf(radial, 0.94), depth, phase))


func _cosmic_style() -> String:
	var explicit_style: String = str(song.get("cosmic_style", ""))
	if explicit_style in COSMIC_STYLES:
		return explicit_style
	var song_id: String = str(song.get("id", ""))
	if COSMIC_STYLE_BY_SONG.has(song_id):
		return str(COSMIC_STYLE_BY_SONG[song_id])
	var seed: int = absi(int(song.get("seed", 0)))
	return COSMIC_STYLES[seed % COSMIC_STYLES.size()]


func _cosmic_star_position(star: Vector4, time_value: float, speed_scale: float = 1.0) -> Vector2:
	var direction_sign: float = -1.0 if int(star.w * 10.0) % 2 == 0 else 1.0
	var angle: float = star.x + time_value * (0.004 + star.z * 0.006) * direction_sign * speed_scale
	return center + Vector2(cos(angle), sin(angle)) * radius * star.y


func _draw_cosmic_sky() -> void:
	if _cosmic_stars.is_empty():
		_rebuild_cosmic_cache()

	var time_value: float = _idle_time()
	var primary: Color = _primary()
	var secondary: Color = _secondary()
	var accent: Color = _accent()
	var reaction: float = clampf(_hit_energy + _combo_energy * 0.28, 0.0, 1.0)
	var style: String = _cosmic_style()

	# Nebulosas largas, sempre contidas no ceu circular.
	var nebula_shift: Vector2 = Vector2(cos(time_value * 0.025), sin(time_value * 0.021)) * radius * 0.08
	_draw_soft_glow(center + nebula_shift + Vector2(-radius * 0.28, radius * 0.10), radius * 0.42, primary, 0.055 + reaction * 0.025, 3)
	_draw_soft_glow(center - nebula_shift + Vector2(radius * 0.24, -radius * 0.16), radius * 0.34, secondary, 0.040 + reaction * 0.020, 3)

	match style:
		"constellation":
			var links: Array[Vector2i] = [
				Vector2i(1, 5), Vector2i(5, 9), Vector2i(9, 14),
				Vector2i(14, 18), Vector2i(18, 23), Vector2i(9, 27),
				Vector2i(27, 31), Vector2i(5, 33),
			]
			for link in links:
				var from: Vector2 = _cosmic_star_position(_cosmic_stars[link.x], time_value)
				var to: Vector2 = _cosmic_star_position(_cosmic_stars[link.y], time_value)
				draw_line(from, to, Color(primary.r, primary.g, primary.b, 0.18), maxf(1.0, radius * 0.0018), true)

		"spiral_galaxy":
			for arm in range(3):
				var previous: Vector2 = center
				for step in range(1, 13):
					var progress: float = float(step) / 12.0
					var angle: float = time_value * 0.045 + TAU * float(arm) / 3.0 + progress * TAU * 1.38
					var position_value: Vector2 = center + Vector2(cos(angle), sin(angle)) * radius * progress * 0.78
					var arm_color: Color = primary.lerp(accent, progress)
					draw_line(previous, position_value, Color(arm_color.r, arm_color.g, arm_color.b, 0.13), maxf(1.0, radius * 0.0022), true)
					draw_circle(position_value, maxf(1.0, radius * 0.0035), Color(arm_color.r, arm_color.g, arm_color.b, 0.42), true)
					previous = position_value

		"aurora":
			for band in range(4):
				var points := PackedVector2Array()
				for step in range(25):
					var x_ratio: float = -0.78 + 1.56 * float(step) / 24.0
					var wave: float = sin(x_ratio * 5.2 + time_value * (0.18 + float(band) * 0.025) + float(band))
					var y_ratio: float = -0.28 + float(band) * 0.16 + wave * 0.075
					points.append(center + Vector2(x_ratio, y_ratio) * radius)
				var band_color: Color = primary.lerp(secondary, float(band) / 3.0)
				draw_polyline(points, Color(band_color.r, band_color.g, band_color.b, 0.14 + float(band) * 0.025), maxf(2.0, radius * 0.004), true)

		"meteor":
			var meteor_direction := Vector2(-0.88, 0.48).normalized()
			for index in range(0, _cosmic_stars.size(), 4):
				var head: Vector2 = _cosmic_star_position(_cosmic_stars[index], time_value, 1.8)
				var length: float = radius * (0.035 + float(index % 5) * 0.012)
				draw_line(head - meteor_direction * length, head, Color(accent.r, accent.g, accent.b, 0.34), maxf(1.0, radius * 0.0024), true)

		"planetary":
			for orbit_index in range(1, 5):
				var orbit_radius: float = radius * (0.16 + float(orbit_index) * 0.13)
				draw_arc(center, orbit_radius, 0.0, TAU, 96, Color(primary.r, primary.g, primary.b, 0.08 + float(orbit_index) * 0.012), maxf(1.0, radius * 0.0017), true)
				var planet_angle: float = time_value * (0.035 / float(orbit_index)) + float(orbit_index) * 1.31
				var planet_position: Vector2 = center + Vector2(cos(planet_angle), sin(planet_angle)) * orbit_radius
				draw_circle(planet_position, radius * (0.008 + float(orbit_index) * 0.002), primary.lerp(accent, float(orbit_index) / 5.0), true)

		"supernova":
			for ray in range(20):
				var angle: float = TAU * float(ray) / 20.0 + time_value * 0.018
				var ray_length: float = radius * (0.20 + 0.10 * (0.5 + 0.5 * sin(time_value * 0.8 + float(ray))))
				var direction := Vector2(cos(angle), sin(angle))
				draw_line(center + direction * radius * 0.07, center + direction * ray_length, Color(primary.r, primary.g, primary.b, 0.14), maxf(1.0, radius * 0.002), true)
			_draw_soft_glow(center, radius * 0.18, accent, 0.16 + reaction * 0.10, 3)

		"wormhole":
			for ring_index in range(1, 11):
				var progress: float = float(ring_index) / 10.0
				var wobble: float = sin(time_value * 0.35 + float(ring_index) * 0.71) * radius * 0.018
				var ring_center: Vector2 = center + Vector2(wobble, -wobble * 0.55)
				var ring_color: Color = primary.lerp(secondary, progress)
				draw_arc(ring_center, radius * progress * 0.72, 0.0, TAU, 100, Color(ring_color.r, ring_color.g, ring_color.b, 0.05 + progress * 0.07), maxf(1.0, radius * 0.002), true)

		"solar_crown":
			var crown_radius: float = radius * (0.22 + _beat_pulse() * 0.012)
			_draw_soft_glow(center, crown_radius * 1.25, primary, 0.14 + reaction * 0.06, 3)
			for ray in range(16):
				var angle: float = TAU * float(ray) / 16.0 - time_value * 0.025
				var direction := Vector2(cos(angle), sin(angle))
				draw_line(center + direction * crown_radius, center + direction * crown_radius * 1.34, Color(accent.r, accent.g, accent.b, 0.20), maxf(1.0, radius * 0.0023), true)
			draw_arc(center, crown_radius, 0.0, TAU, 120, Color(accent.r, accent.g, accent.b, 0.28), maxf(2.0, radius * 0.004), true)

		_:
			# Deep space: o movimento fica somente na deriva estelar e nas
			# nebulosas, oferecendo uma tela mais calma para futuras musicas.
			pass

	# Campo estelar compartilhado: estrelas com tres profundidades,
	# brilho leve e deriva deterministica (zero RandomNumberGenerator por frame).
	for star in _cosmic_stars:
		var position_value: Vector2 = _cosmic_star_position(star, time_value)
		var twinkle: float = 0.5 + 0.5 * sin(time_value * (0.75 + star.z * 0.9) + star.w)
		var star_color: Color = primary.lerp(Color.WHITE, 0.45 + star.z * 0.25)
		var star_size: float = radius * (0.0018 + star.z * 0.0021 + twinkle * 0.0012)
		draw_circle(position_value, maxf(1.0, star_size), Color(star_color.r, star_color.g, star_color.b, 0.30 + twinkle * 0.62), true)
		if twinkle > 0.82 and star.z > 0.45:
			draw_line(position_value - Vector2(star_size * 2.2, 0.0), position_value + Vector2(star_size * 2.2, 0.0), Color(1.0, 1.0, 1.0, 0.18), maxf(1.0, star_size * 0.28), true)
			draw_line(position_value - Vector2(0.0, star_size * 2.2), position_value + Vector2(0.0, star_size * 2.2), Color(1.0, 1.0, 1.0, 0.18), maxf(1.0, star_size * 0.28), true)
func _draw_theme_geometry() -> void:
	var configured_pattern: String = str(
		song.get("pattern", "diamonds")
	).to_lower()
	var intensity: float = clampf(
		float(difficulty.get("background_intensity", 0.18)),
		0.06,
		0.30
	)
	var time_value: float = _idle_time()
	var speed: float = float(
		difficulty.get("background_speed", 0.22)
	)
	var rotation: float = time_value * speed
	var beat: float = _beat_pulse()
	var reaction: float = _hit_energy + _combo_energy * 0.32
	var primary: Color = _primary()
	var secondary: Color = _secondary()
	var accent: Color = _accent()

	# Fundo totalmente geometrico: sem arcos cortados.
	# Cada camada forma uma mandala completa de cristais.
	for layer in range(1, 5):
		var layer_radius: float = radius * (
			0.10 + float(layer) * 0.115
		)
		layer_radius += sin(time_value * 3.2 + float(layer)) * radius * 0.010 * reaction
		var count: int = 6 + layer * 2
		var direction_sign: float = (
			1.0 if layer % 2 == 0 else -1.0
		)
		var layer_rotation: float = (
			rotation * direction_sign * (0.35 + float(layer) * 0.04 + reaction * 0.20)
		)

		for index in range(count):
			var angle: float = (
				layer_rotation
				+ TAU * float(index) / float(count)
			)
			var direction: Vector2 = Vector2(
				cos(angle),
				sin(angle)
			)
			var position_value: Vector2 = (
				center + direction * layer_radius
			)
			var size: float = radius * (
				0.024 + float(layer) * 0.0032
			)
			var mix_value: float = float(
				(index + layer) % 4
			) / 4.0
			# Deriva lenta de matiz entre primary/secondary/accent —
			# em vez de cor fixa por indice, da uma leitura mais viva
			# e "espectral" (aurora), nao uma grade tecnica estatica.
			var drift_mix: float = 0.5 + 0.5 * sin(
				time_value * 0.55 + float(layer) * 1.7 + float(index) * 0.42
			)
			var color: Color = primary.lerp(
				secondary,
				drift_mix * 0.30
			).lerp(
				accent,
				mix_value * 0.55
			)
			color.a = intensity * (0.20 + float(layer) * 0.024) + beat * 0.018 + reaction * 0.055

			# Brilho suave por tras do elemento. So em um a cada dois
			# elementos: visualmente o halo se funde com o do vizinho
			# de qualquer forma, e isso corta pela metade a quantidade
			# de circulos preenchidos por frame (parte mais cara do
			# fundo, que roda em TODO frame de gameplay).
			if (index + layer) % 2 == 0:
				_draw_soft_glow(
					position_value,
					size * 2.9,
					color,
					(intensity * 0.7 + reaction * 0.34) * (0.5 + beat * 0.3),
					2
				)

			# 8 fundos distintos, um por musica: cada shape/leitura muda
			# bastante a personalidade da tela sem precisar de arte nova.
			match configured_pattern:
				"hex":
					_draw_regular_polygon(
						position_value,
						size,
						6,
						angle + rotation * 0.16,
						color,
						maxf(1.5, radius * 0.0028)
					)
				"radial":
					_draw_regular_polygon(
						position_value,
						size,
						8,
						angle,
						color,
						maxf(1.5, radius * 0.0028)
					)
				"grid":
					_draw_rotated_diamond(
						position_value,
						size * 1.10,
						angle + PI * 0.25,
						color,
						maxf(1.5, radius * 0.0028)
					)
				"spiral":
					# Lamina fina em rotacao acentuada — leitura de
					# redemoinho/espiral (Naruto/Uzumaki).
					_draw_regular_polygon(
						position_value,
						size * 0.95,
						3,
						angle + rotation * 0.85,
						color,
						maxf(1.5, radius * 0.0026)
					)
				"waves":
					# Traco tangencial ao circulo — le como crista de onda.
					var tangent_dir := Vector2(-direction.y, direction.x)
					draw_line(
						position_value - tangent_dir * size * 0.95,
						position_value + tangent_dir * size * 0.95,
						color,
						maxf(2.0, radius * 0.0032),
						true
					)
				"orbits":
					# Aneis finos no lugar de formas solidas — leitura de
					# orbitas/particulas magneticas.
					draw_arc(
						position_value,
						size * 0.62,
						0.0,
						TAU,
						14,
						color,
						maxf(1.5, radius * 0.0026),
						true
					)
				"shards":
					# Estilhacos triangulares alongados — leitura cristalina.
					_draw_regular_polygon(
						position_value,
						size * 1.30,
						3,
						angle + PI * 0.5,
						color,
						maxf(1.5, radius * 0.0030)
					)
				_:
					_draw_rotated_diamond(
						position_value,
						size * 1.18,
						angle + PI * 0.25,
						color,
						maxf(1.5, radius * 0.0030)
					)

			if layer >= 3 and index % 2 == 0:
				var inner_position: Vector2 = (
					center + direction * (layer_radius - radius * 0.070)
				)
				draw_line(
					inner_position,
					position_value,
					Color(
						color.r,
						color.g,
						color.b,
						intensity * 0.16
					),
					maxf(1.0, radius * 0.0018),
					true
				)

	# Flor central geometrica, inteira e brilhante.
	for petal in range(8):
		var petal_angle: float = (
			-rotation * 0.55
			+ TAU * float(petal) / 8.0
		)
		var petal_position: Vector2 = (
			center
			+ Vector2(cos(petal_angle), sin(petal_angle))
			* radius * 0.105
		)
		_draw_soft_glow(
			petal_position,
			radius * (0.070 + beat * 0.010),
			primary,
			0.14 + reaction * 0.10,
			2
		)
		_draw_rotated_diamond(
			petal_position,
			radius * (0.050 + beat * 0.006),
			petal_angle + PI * 0.25,
			Color(primary.r, primary.g, primary.b, 0.16),
			maxf(2.0, radius * 0.0040)
		)

	_draw_soft_glow(center, radius * 0.135, secondary, 0.10 + reaction * 0.10, 2)
	_draw_regular_polygon(
		center,
		radius * (0.095 + beat * 0.008),
		8,
		rotation * 0.28,
		Color(secondary.r, secondary.g, secondary.b, 0.16),
		maxf(2.0, radius * 0.0042)
	)
	_draw_regular_polygon(
		center,
		radius * (0.062 + beat * 0.006),
		6,
		-rotation * 0.45,
		Color(accent.r, accent.g, accent.b, 0.24),
		maxf(2.0, radius * 0.0045)
	)


func _draw_ambient_particles() -> void:
	# Particulas deterministicas em tres profundidades. Cada uma usa
	# gradiente em camadas (em vez de dois circulos chapados) e um
	# rastro curto na direcao do movimento — le como poeira de energia
	# em vez de bolinhas soltas. A orbita minima fica mais afastada do
	# centro pra nao amontoar tudo no meio do tabuleiro.
	var time_value: float = _idle_time()
	var beat: float = _beat_pulse()
	var palette: Array[Color] = [_primary(), _secondary(), _accent()]
	for index in range(18):
		var seed: float = float(index) * 12.9898
		var depth: float = 0.35 + float(index % 3) * 0.27
		var base_angle: float = fmod(absf(sin(seed) * 43758.5453), TAU)
		var orbit: float = radius * (0.24 + fmod(absf(cos(seed * 0.73)) * 9.7, 0.62))
		var direction_sign: float = -1.0 if index % 2 == 0 else 1.0
		var angular_speed: float = (0.018 + depth * 0.022) * direction_sign
		var angle: float = base_angle + time_value * angular_speed
		var drift: float = sin(time_value * (0.32 + depth * 0.16) + seed) * radius * 0.012
		var particle_position: Vector2 = center + Vector2(cos(angle), sin(angle)) * (orbit + drift)
		var particle_color: Color = palette[index % palette.size()]
		var twinkle: float = 0.5 + 0.5 * sin(time_value * (1.2 + depth) + seed)
		var size: float = radius * (0.0026 + depth * 0.0026 + beat * 0.0010)

		# Rastro: amostra a posicao um instante atras no tempo, na
		# mesma orbita, e desenha uma linha fina que desvanece.
		var trail_angle: float = angle - angular_speed * 0.24
		var trail_position: Vector2 = center + Vector2(cos(trail_angle), sin(trail_angle)) * (orbit + drift)
		draw_line(
			trail_position,
			particle_position,
			Color(particle_color.r, particle_color.g, particle_color.b, 0.10 + twinkle * 0.12),
			maxf(1.0, size * 0.9),
			true
		)

		_draw_soft_glow(
			particle_position,
			size * 3.1,
			particle_color,
			0.055 + twinkle * 0.075,
			2
		)
		draw_circle(
			particle_position,
			size * 0.85,
			Color(particle_color.r, particle_color.g, particle_color.b, 0.35 + twinkle * 0.45),
			true
		)
		draw_circle(
			particle_position,
			size * 0.30,
			Color(1.0, 1.0, 1.0, 0.25 + twinkle * 0.35),
			true
		)

func _draw_diamond_field(
	rotation: float,
	intensity: float,
	primary: Color,
	secondary: Color,
	section: int
) -> void:
	for ring in range(2, 6):
		var count: int = 8 + section * 2
		var ring_radius: float = radius * (0.16 + float(ring) * 0.115)
		for index in range(count):
			var angle: float = rotation * (1.0 if ring % 2 == 0 else -0.65)
			angle += TAU * float(index) / float(count)
			var position_value: Vector2 = center + Vector2(cos(angle), sin(angle)) * ring_radius
			var size: float = radius * (0.026 + float(ring) * 0.0025)
			var color: Color = primary.lerp(secondary, float(index % 3) * 0.16)
			color.a = intensity * (0.27 + float(ring) * 0.025)
			_draw_diamond(position_value, size, color, maxf(1.0, radius * 0.0022))


func _draw_hex_field(
	rotation: float,
	intensity: float,
	primary: Color,
	accent: Color,
	section: int
) -> void:
	for ring in range(2, 6):
		var count: int = 6 + (section % 2) * 6
		var ring_radius: float = radius * (0.14 + float(ring) * 0.125)
		for index in range(count):
			var angle: float = rotation * (0.65 if ring % 2 == 0 else -0.44)
			angle += TAU * float(index) / float(count)
			var position_value: Vector2 = center + Vector2(cos(angle), sin(angle)) * ring_radius
			var color: Color = primary.lerp(accent, float(index % 4) * 0.08)
			color.a = intensity * 0.34
			_draw_regular_polygon(
				position_value,
				radius * (0.032 + float(ring) * 0.002),
				6,
				rotation * 0.30,
				color,
				maxf(1.0, radius * 0.002)
			)


func _draw_radial_field(
	rotation: float,
	intensity: float,
	primary: Color,
	secondary: Color,
	beat: float
) -> void:
	for index in range(32):
		var angle: float = rotation * 0.30 + TAU * float(index) / 32.0
		var direction := Vector2(cos(angle), sin(angle))
		var length_factor: float = 0.54 + 0.11 * absf(sin(float(index) * 0.72 + rotation))
		var color: Color = primary.lerp(secondary, float(index % 4) * 0.10)
		color.a = intensity * (0.12 + beat * 0.08)
		draw_line(
			center + direction * radius * 0.20,
			center + direction * radius * length_factor,
			color,
			maxf(1.0, radius * 0.0018),
			true
		)


func _draw_grid_field(
	rotation: float,
	intensity: float,
	primary: Color,
	accent: Color
) -> void:
	var spacing: float = radius * 0.115
	var offset: float = fmod(rotation * radius * 0.08, spacing)
	for index in range(-6, 7):
		var value: float = float(index) * spacing + offset
		draw_line(
			center + Vector2(value, -radius * 0.68),
			center + Vector2(value, radius * 0.68),
			Color(primary.r, primary.g, primary.b, intensity * 0.12),
			maxf(1.0, radius * 0.0015),
			true
		)
		draw_line(
			center + Vector2(-radius * 0.68, value),
			center + Vector2(radius * 0.68, value),
			Color(accent.r, accent.g, accent.b, intensity * 0.09),
			maxf(1.0, radius * 0.0015),
			true
		)


func _draw_orbit_nodes(rotation: float, intensity: float, color: Color) -> void:
	for index in range(12):
		var angle: float = -rotation * 0.48 + TAU * float(index) / 12.0
		var orbit_radius: float = radius * (0.28 + 0.028 * float(index % 4))
		var position_value: Vector2 = center + Vector2(cos(angle), sin(angle)) * orbit_radius
		draw_circle(
			position_value,
			maxf(1.5, radius * 0.004),
			Color(color.r, color.g, color.b, intensity * 0.30),
			true
		)


func _draw_inner_technical_rings() -> void:
	var time_value: float = _idle_time()
	var primary: Color = _primary()
	var accent: Color = _accent()
	var reaction: float = _hit_energy + _combo_energy * 0.34
	var carmine_factor: float = 1.30 if str(song.get("id", "")) == "carmine" else 1.0
	reaction *= carmine_factor

	# Substitui os antigos segmentos redondos por molduras poligonais.
	for layer in range(3):
		var sides: int = 8 if layer != 1 else 12
		var layer_size: float = radius * (
			0.34 + float(layer) * 0.13
		)
		layer_size += sin(time_value * 5.0 + float(layer) * 1.7) * radius * 0.012 * reaction
		var rotation_value: float = time_value * (
			0.055 + float(layer) * 0.025 + reaction * 0.12
		)
		var color: Color = primary if layer % 2 == 0 else accent
		_draw_regular_polygon(
			center,
			layer_size,
			sides,
			rotation_value * (1.0 if layer % 2 == 0 else -1.0),
			Color(color.r, color.g, color.b, 0.11),
			maxf(1.0, radius * 0.0023)
		)

		for node_index in range(sides):
			var angle: float = (
				rotation_value
				+ TAU * float(node_index) / float(sides)
				+ sin(time_value * 4.2 + float(node_index)) * reaction * 0.055
			)
			var node_position: Vector2 = (
				center
				+ Vector2(cos(angle), sin(angle)) * layer_size
			)
			_draw_rotated_diamond(
				node_position,
				radius * (0.014 + reaction * 0.004),
				angle + PI * 0.25,
				Color(color.r, color.g, color.b, 0.18 + reaction * 0.18),
				maxf(1.0, radius * 0.0020)
			)

func _draw_ring() -> void:
	var ring_radius: float = radius * 0.905
	var width: float = maxf(4.0, radius * 0.0072)
	# Alvo branco onde o tazo se encaixa: levemente ampliado para
	# dar mais presenca e deixar claro o ponto de acerto.
	var marker_radius: float = maxf(10.0, radius * 0.0330)
	var pulse: float = _beat_pulse()
	var primary: Color = _primary()
	var reaction: float = _hit_energy + _combo_energy * 0.26

	draw_arc(
		center,
		ring_radius + radius * 0.004,
		0.0,
		TAU,
		160,
		Color(primary.r, primary.g, primary.b, 0.10 + pulse * 0.05 + reaction * 0.12),
		width * (3.4 + reaction * 1.6),
		true
	)
	draw_arc(
		center,
		ring_radius,
		0.0,
		TAU,
		160,
		Color.WHITE,
		width,
		true
	)

	for lane_index in range(lane_positions.size()):
		var position_value: Vector2 = lane_positions[lane_index]
		var lane_pulse: float = reaction * (0.5 + 0.5 * sin(_idle_time() * 7.0 + float(lane_index)))

		var flash: float = 0.0
		var flash_color: Color = Color.WHITE
		if lane_index < _lane_flash_energy.size():
			flash = clampf(float(_lane_flash_energy[lane_index]), 0.0, 1.6)
			flash_color = _lane_flash_colors[lane_index]
		var flash_mix: float = minf(flash, 1.0)

		var glow_color: Color = primary.lerp(flash_color, flash_mix)
		draw_circle(
			position_value,
			marker_radius * (1.75 + lane_pulse * 0.55 + flash * 0.90),
			Color(glow_color.r, glow_color.g, glow_color.b, 0.08 + lane_pulse * 0.18 + flash_mix * 0.52),
			true
		)

		var core_color: Color = Color.WHITE.lerp(flash_color, minf(flash * 1.4, 1.0))
		var core_size: float = marker_radius * (1.0 + lane_pulse * 0.16 + flash * 0.32)

		# Miolo escuro + anel branco grosso: leitura de "alvo", bem
		# mais definida que um disco branco chapado.
		draw_circle(position_value, core_size, Color(0.010, 0.016, 0.030, 0.92), true)
		draw_arc(
			position_value,
			core_size * 0.80,
			0.0,
			TAU,
			22,
			core_color,
			maxf(2.0, core_size * 0.34),
			true
		)
		draw_circle(position_value, core_size * 0.26, core_color, true)

		if flash > 0.02:
			# Arco de energia correndo pela linha, saindo do ponto
			# onde o tazo se encaixou — a assinatura visual do acerto
			# fica na propria linha, nao so num flash central.
			var arc_span: float = deg_to_rad(9.0 + flash * 30.0)
			var base_angle: float = (position_value - center).angle()
			draw_arc(
				center,
				ring_radius,
				base_angle - arc_span,
				base_angle + arc_span,
				20,
				Color(flash_color.r, flash_color.g, flash_color.b, flash_mix * 0.85),
				width * (1.5 + flash * 2.1),
				true
			)


## Onda de energia que sai do ponto de acerto e contagia a borda
## inteira: viaja pros dois lados do anel (sentido horario e
## anti-horario) ate se encontrar do lado oposto, com uma cabeça
## brilhante e um rastro que desvanece atras dela.
func _draw_ring_pulses() -> void:
	if _ring_pulses.is_empty():
		return

	var ring_radius: float = radius * 0.905
	var width: float = maxf(4.0, radius * 0.0072)
	var now: float = float(Time.get_ticks_msec()) / 1000.0

	for pulse_value in _ring_pulses:
		var pulse: Dictionary = pulse_value
		var duration: float = maxf(float(pulse.get("duration", RING_PULSE_DURATION)), 0.001)
		var t: float = clampf((now - float(pulse.get("start", now))) / duration, 0.0, 1.0)
		if t >= 1.0:
			continue

		var color: Color = pulse.get("color", Color.WHITE)
		var base_angle: float = float(pulse.get("angle", 0.0))
		var eased: float = 1.0 - pow(1.0 - t, 2.2)
		var travel: float = eased * PI * 1.02
		var fade: float = pow(1.0 - t, 1.4)

		for direction_sign in [1.0, -1.0]:
			var head_angle: float = base_angle + travel * direction_sign
			var trail_span: float = minf(travel, PI * 0.34)
			var trail_from: float = head_angle - trail_span * direction_sign

			draw_arc(
				center,
				ring_radius,
				minf(trail_from, head_angle),
				maxf(trail_from, head_angle),
				28,
				Color(color.r, color.g, color.b, fade * 0.40),
				width * (2.4 + fade * 1.6),
				true
			)

			var head_span: float = 0.045
			var head_color: Color = Color(
				lerpf(1.0, color.r, 0.55),
				lerpf(1.0, color.g, 0.55),
				lerpf(1.0, color.b, 0.55),
				fade
			)
			draw_arc(
				center,
				ring_radius,
				head_angle - head_span,
				head_angle + head_span,
				10,
				head_color,
				width * (1.9 + fade * 1.1),
				true
			)


func _draw_lane_energy() -> void:
	if events.is_empty():
		return

	var approach: float = maxf(float(difficulty.get("approach", 1.0)), 0.001)
	for event_value in events:
		if not event_value is Dictionary:
			continue
		var event: Dictionary = event_value as Dictionary
		if bool(event.get("_resolved", false)):
			continue

		var type_name: String = str(event.get("type", "tap"))
		if type_name != "tap" and type_name != "hold":
			continue

		var lane: int = clampi(int(event.get("lane", 0)), 0, lane_positions.size() - 1)
		var hit_time: float = float(event.get("time", 0.0))
		var progress: float = clampf(
			(song_time - (hit_time - approach)) / approach,
			0.0,
			1.0
		)
		if progress <= 0.0 or progress >= 1.0:
			continue

		var position_value: Vector2 = lane_positions[lane]
		var color: Color = _accent() if type_name == "hold" else _primary()
		var size: float = radius * (0.028 + progress * 0.032)
		draw_arc(
			position_value,
			size,
			-PI * 0.5,
			-PI * 0.5 + TAU * progress,
			32,
			Color(color.r, color.g, color.b, 0.22 + progress * 0.62),
			maxf(2.0, radius * 0.006),
			true
		)


func _draw_hold(event: Dictionary) -> void:
	if not bool(event.get("_spawned", false)):
		return

	var hit_time: float = float(event.get("time", 0.0))
	var end_time: float = float(event.get("end_time", hit_time + 1.0))
	var approach: float = float(difficulty.get("approach", 1.0))
	if song_time < hit_time - approach or song_time > end_time + 0.25:
		return

	var lane: int = clampi(int(event.get("lane", 0)), 0, lane_positions.size() - 1)
	var target: Vector2 = lane_positions[lane]
	var direction: Vector2 = (target - center).normalized()
	var start_time: float = hit_time - approach
	var arrival: float = clampf((song_time - start_time) / maxf(approach, 0.001), 0.0, 1.0)
	var eased: float = 1.0 - pow(1.0 - arrival, 4.0)
	var head: Vector2 = center.lerp(target, eased)

	var hold_progress: float = 0.0
	if song_time >= hit_time:
		hold_progress = clampf(
			(song_time - hit_time) / maxf(end_time - hit_time, 0.001),
			0.0,
			1.0
		)
		head = target

	var remaining: float = 1.0 - hold_progress
	var length: float = radius * (0.52 if song_time < hit_time else maxf(0.085, 0.52 * remaining))
	var tail: Vector2 = head - direction * length
	# Hold fino: aproximadamente metade da espessura da R11/R12 inicial.
	var width: float = radius * 0.050 * float(difficulty.get("hold_width", 1.0))
	var color: Color = Color(1.0, 0.83, 0.08, 1.0)
	var holding: bool = bool(event.get("_holding", false))
	if holding:
		color = color.lerp(Color.WHITE, 0.16)

	_draw_capsule(tail, head, width, color, holding, hold_progress)


func _draw_capsule(
	tail: Vector2,
	head: Vector2,
	half_width: float,
	color: Color,
	active: bool,
	progress: float
) -> void:
	# Fita de hold inspirada na leitura de arcades circulares: uma forma unica,
	# larga e direcional. Brilho e movimento confirmam o estado pressionado.
	var direction: Vector2 = (head - tail).normalized()
	var normal: Vector2 = Vector2(-direction.y, direction.x)
	var length: float = tail.distance_to(head)
	var pulse: float = 0.5 + 0.5 * sin(_idle_time() * (10.0 if active else 4.0))
	var glow_alpha: float = 0.26 if active else 0.12

	draw_line(
		tail,
		head,
		Color(color.r, color.g, color.b, glow_alpha),
		half_width * (2.65 + pulse * 0.16),
		true
	)
	draw_line(
		tail,
		head,
		Color(0.006, 0.010, 0.022, 0.92),
		half_width * 1.82,
		true
	)
	draw_line(
		tail,
		head,
		Color(color.r, color.g, color.b, 0.78 if active else 0.54),
		half_width * 1.34,
		true
	)
	draw_line(
		tail + normal * half_width * 0.72,
		head + normal * half_width * 0.72,
		Color.WHITE,
		maxf(2.0, half_width * 0.13),
		true
	)
	draw_line(
		tail - normal * half_width * 0.72,
		head - normal * half_width * 0.72,
		Color(color.r, color.g, color.b, 0.92),
		maxf(2.0, half_width * 0.13),
		true
	)

	# Chevrons deslizantes no lugar de barras retas: alem de marcar o
	# ritmo, apontam pro alvo, deixando a direcao do hold obvia. Sao
	# poucos e desenhados como duas linhas (nao poligono), pra manter
	# barato mesmo com varios holds na tela.
	var marker_count: int = clampi(int(length / maxf(half_width * 3.1, 1.0)), 3, 7)
	var phase: float = fmod(_idle_time() * (1.7 if active else 0.75), 1.0)
	var wing: float = half_width * 0.46
	for index in range(marker_count):
		var marker_t: float = fmod((float(index) + phase) / float(marker_count), 1.0)
		var marker_position: Vector2 = tail.lerp(head, marker_t)
		var marker_alpha: float = (0.88 if active else 0.44) * smoothstep(0.0, 0.12, marker_t)
		var tip: Vector2 = marker_position + direction * wing * 0.85
		var marker_color := Color(1.0, 1.0, 1.0, marker_alpha)
		var marker_width: float = maxf(1.5, half_width * 0.11)
		draw_line(marker_position - normal * wing, tip, marker_color, marker_width, true)
		draw_line(marker_position + normal * wing, tip, marker_color, marker_width, true)

	# Trilhos laterais tracejados dao textura de "fita" ao hold.
	var rail_count: int = clampi(marker_count * 2, 6, 14)
	var rail_alpha: float = 0.30 if active else 0.16
	for index in range(rail_count):
		var rail_t: float = (float(index) + 0.5) / float(rail_count)
		var rail_center: Vector2 = tail.lerp(head, rail_t)
		var rail_half: Vector2 = direction * (length / float(rail_count)) * 0.26
		for side in [-1.0, 1.0]:
			var offset: Vector2 = normal * half_width * 1.02 * side
			draw_line(
				rail_center - rail_half + offset,
				rail_center + rail_half + offset,
				Color(color.r, color.g, color.b, rail_alpha),
				maxf(1.0, half_width * 0.07),
				true
			)

	# Alvo circular grande e estavel. O arco interno mostra o progresso.
	var head_size: float = half_width * (1.05 + pulse * (0.08 if active else 0.025))
	draw_circle(head, head_size * 1.30, Color(color.r, color.g, color.b, 0.15 + pulse * 0.06), true)
	draw_circle(head, head_size, Color(0.008, 0.012, 0.026, 0.98), true)
	draw_arc(head, head_size, 0.0, TAU, 48, Color.WHITE, maxf(3.0, half_width * 0.22), true)
	draw_arc(
		head,
		head_size * 0.70,
		-PI * 0.5,
		-PI * 0.5 + TAU * (progress if progress > 0.0 else 0.96),
		40,
		Color(color.r, color.g, color.b, 1.0),
		maxf(3.0, half_width * 0.26),
		true
	)
	draw_circle(head, head_size * 0.24, Color.WHITE if active else color, true)

	# Ticks radiais no alvo: dao acabamento de mostrador/medidor e
	# marcam visualmente o quanto ja foi segurado.
	for index in range(8):
		var tick_angle: float = -PI * 0.5 + TAU * float(index) / 8.0
		var tick_dir := Vector2(cos(tick_angle), sin(tick_angle))
		var filled: bool = (float(index) / 8.0) <= progress
		draw_line(
			head + tick_dir * head_size * 1.08,
			head + tick_dir * head_size * (1.30 if filled else 1.20),
			Color(
				color.r,
				color.g,
				color.b,
				(0.95 if filled else 0.30) * (1.0 if active else 0.75)
			),
			maxf(1.5, half_width * (0.13 if filled else 0.08)),
			true
		)

	# Cauda com anel, fechando a fita em vez de terminar num disco seco.
	draw_circle(tail, half_width * 0.86, Color(color.r, color.g, color.b, 0.92), true)
	draw_arc(
		tail,
		half_width * 1.18,
		0.0,
		TAU,
		20,
		Color(color.r, color.g, color.b, 0.34 + pulse * 0.10),
		maxf(1.5, half_width * 0.10),
		true
	)

func _draw_slide(event: Dictionary) -> void:
	if not bool(event.get("_spawned", false)):
		return

	var path_value: Variant = event.get("_path_points", PackedVector2Array())
	if not path_value is PackedVector2Array:
		return

	var points: PackedVector2Array = path_value as PackedVector2Array
	if points.size() < 2:
		return

	# Comprimento acumulado pre-calculado em _prepare_chart(): evita
	# recalcular a soma de distancias do trajeto inteiro a cada
	# chamada de point_at/tangent_at (estrela, fantasmas, cada seta) —
	# era o principal motivo do arrasto pesar quando havia varios
	# arrastos ativos na tela.
	var lengths_value: Variant = event.get("_path_lengths", {})
	var lengths: Dictionary = lengths_value if lengths_value is Dictionary else {}

	var hit_time: float = float(event.get("time", 0.0))
	var end_time: float = float(event.get("end_time", hit_time + 1.0))
	var approach: float = float(difficulty.get("approach", 1.0))
	if song_time < hit_time - approach or song_time > end_time + 0.35:
		return

	var color: Color = Color(0.04, 0.93, 1.0, 1.0)
	var accent: Color = Color(0.82, 1.0, 1.0, 1.0)
	var visual_progress: float = clampf(float(event.get("_visual_progress", 0.0)), 0.0, 1.0)
	var active: bool = bool(event.get("_active", false))
	var arrows_from: float = visual_progress if active else 0.0

	_draw_slide_rail(points, color)
	_draw_chevrons(points, lengths, arrows_from, color, accent)

	var star_position: Vector2
	var tangent: Vector2
	var star_progress: float = visual_progress

	if song_time < hit_time:
		var arrival: float = clampf(
			(song_time - (hit_time - approach)) / maxf(approach, 0.001),
			0.0,
			1.0
		)
		var eased: float = 1.0 - pow(1.0 - arrival, 4.0)
		star_position = center.lerp(points[0], eased)
		tangent = (points[0] - center).normalized()
		star_progress = 0.0
	else:
		star_position = PATH_BUILDER.point_at_cached(points, lengths, visual_progress)
		tangent = PATH_BUILDER.tangent_at_cached(points, lengths, visual_progress)

	if active:
		for ghost_index in range(1, 4):
			var ghost_progress: float = maxf(0.0, star_progress - float(ghost_index) * 0.035)
			var ghost_position: Vector2 = PATH_BUILDER.point_at_cached(points, lengths, ghost_progress)
			var ghost_tangent: Vector2 = PATH_BUILDER.tangent_at_cached(points, lengths, ghost_progress)
			_draw_star(
				ghost_position,
				ghost_tangent.angle(),
				radius * (0.080 - float(ghost_index) * 0.008),
				Color(color.r, color.g, color.b, 0.14),
				Color(accent.r, accent.g, accent.b, 0.08)
			)

	_draw_star(
		star_position,
		tangent.angle(),
		radius * 0.105 * float(difficulty.get("star_scale", 1.0)),
		color,
		accent
	)


func _draw_slide_rail(points: PackedVector2Array, color: Color) -> void:
	for index in range(points.size() - 1):
		draw_line(
			points[index],
			points[index + 1],
			Color(0.0, 0.0, 0.0, 0.76),
			maxf(8.0, radius * 0.026),
			true
		)
		draw_line(
			points[index],
			points[index + 1],
			Color(color.r, color.g, color.b, 0.16),
			maxf(3.0, radius * 0.008),
			true
		)


func _draw_chevrons(
	points: PackedVector2Array,
	lengths: Dictionary,
	start_progress: float,
	color: Color,
	accent: Color
) -> void:
	var spacing: float = radius * 0.052
	var estimated_length: float = float(lengths.get("total", 0.0))
	if estimated_length <= 0.0:
		for index in range(points.size() - 1):
			estimated_length += points[index].distance_to(points[index + 1])

	var count: int = maxi(5, int(ceil(estimated_length / maxf(spacing, 1.0))))
	var start_index: int = clampi(int(floor(start_progress * float(count))), 0, count - 1)

	for index in range(start_index, count):
		var progress: float = (float(index) + 0.50) / float(count)
		var position_value: Vector2 = PATH_BUILDER.point_at_cached(points, lengths, progress)
		var tangent: Vector2 = PATH_BUILDER.tangent_at_cached(points, lengths, progress)
		var mix_value: float = 0.10 + 0.18 * float(index % 3)
		var arrow_color: Color = color.lerp(accent, mix_value)
		_draw_chevron(position_value, tangent, radius * 0.058, arrow_color)


func _draw_chevron(
	position_value: Vector2,
	direction: Vector2,
	size: float,
	color: Color
) -> void:
	var tangent: Vector2 = direction.normalized()
	var perpendicular := Vector2(-tangent.y, tangent.x)
	var length: float = size * 2.10
	var half_height: float = size * 0.88

	var tip: Vector2 = position_value + tangent * length * 0.62
	var rear: Vector2 = position_value - tangent * length * 0.48
	var inner: Vector2 = position_value - tangent * length * 0.02

	var polygon := PackedVector2Array([
		rear + perpendicular * half_height,
		inner + perpendicular * half_height * 0.42,
		tip,
		inner - perpendicular * half_height * 0.42,
		rear - perpendicular * half_height,
		position_value - tangent * length * 0.20,
	])

	var shadow_offset := Vector2(radius * 0.009, radius * 0.010)
	var shadow := PackedVector2Array()
	for point in polygon:
		shadow.append(point + shadow_offset)

	draw_colored_polygon(shadow, Color(0.0, 0.0, 0.0, 0.96))
	draw_colored_polygon(polygon, color)

	var outline := polygon.duplicate()
	outline.append(outline[0])
	draw_polyline(
		outline,
		Color(0.01, 0.04, 0.07, 0.98),
		maxf(5.0, size * 0.19),
		true
	)

	var highlight := PackedVector2Array([
		rear + perpendicular * half_height * 0.58,
		inner + perpendicular * half_height * 0.22,
		tip - tangent * length * 0.10,
	])
	draw_polyline(
		highlight,
		Color(0.90, 1.0, 1.0, 0.98),
		maxf(2.0, size * 0.075),
		true
	)



func _draw_star(
	position_value: Vector2,
	rotation_value: float,
	size: float,
	color: Color,
	accent: Color
) -> void:
	var pulse: float = 0.5 + 0.5 * sin(_idle_time() * 9.0)
	var outer: PackedVector2Array = _star_points(
		size * (1.0 + pulse * 0.045),
		size * 0.44,
		rotation_value,
		position_value
	)
	var middle: PackedVector2Array = _star_points(
		size * 0.73,
		size * 0.31,
		rotation_value,
		position_value
	)
	var inner: PackedVector2Array = _star_points(
		size * 0.48,
		size * 0.20,
		rotation_value,
		position_value
	)
	outer.append(outer[0])
	middle.append(middle[0])
	inner.append(inner[0])

	# Brilho por tras da estrela — da mais definicao/profundidade em
	# vez de so linhas finas sobre o fundo.
	_draw_soft_glow(position_value, size * 1.55, color, 0.34 + pulse * 0.12, 3)

	draw_polyline(outer, Color(0.0, 0.0, 0.0, 0.90), maxf(12.0, size * 0.30), true)
	draw_polyline(outer, Color.WHITE, maxf(7.0, size * 0.16), true)
	draw_polyline(middle, color, maxf(5.0, size * 0.13), true)
	draw_polyline(inner, accent, maxf(3.5, size * 0.10), true)
	draw_circle(position_value, size * 0.18, Color(0.002, 0.006, 0.016, 0.96), true)
	draw_circle(position_value, size * 0.10, Color.WHITE, true)
	draw_circle(position_value, size * 0.045, accent, true)


func _draw_effects() -> void:
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	for effect_value in effects:
		if not effect_value is Dictionary:
			continue

		var effect: Dictionary = effect_value as Dictionary
		var duration: float = maxf(float(effect.get("duration", 0.5)), 0.001)
		var progress: float = clampf(
			(now - float(effect.get("start", now))) / duration,
			0.0,
			1.0
		)
		var life: float = 1.0 - progress
		var position_value: Vector2 = effect.get("position", center)
		var color: Color = effect.get("color", Color.WHITE)
		var kind: String = str(effect.get("kind", "tap"))
		var rotation_value: float = float(effect.get("rotation", 0.0))

		if kind == "slide":
			_draw_slide_burst(position_value, color, progress, life, rotation_value)
		elif kind == "hold":
			_draw_hold_burst(position_value, color, progress, life)
		elif kind == "miss":
			_draw_miss_burst(position_value, progress, life, rotation_value)
		else:
			_draw_tap_prism(position_value, color, progress, life, rotation_value)


func _draw_tap_prism(
	position_value: Vector2,
	color: Color,
	progress: float,
	life: float,
	rotation_value: float
) -> void:
	# Explosao de TAP maior, mais luminosa e com prisma em camadas.
	var flash_radius: float = radius * (
		0.055 + progress * 0.190
	)
	_draw_soft_glow(position_value, flash_radius * 1.9, color, life * 0.55, 4)
	draw_circle(
		position_value,
		flash_radius,
		Color(1.0, 1.0, 1.0, life * 0.30),
		true
	)

	for layer in range(5):
		var size: float = radius * (
			0.082 + float(layer) * 0.031
		)
		size *= 0.34 + progress * 1.34
		var alpha: float = life * (
			1.0 - float(layer) * 0.135
		)
		var layer_color: Color = Color.WHITE.lerp(
			color,
			0.14 + float(layer) * 0.19
		)
		layer_color.a = alpha
		_draw_rotated_diamond(
			position_value,
			size,
			rotation_value + float(layer) * PI * 0.20,
			layer_color,
			maxf(4.0, radius * (0.014 - float(layer) * 0.0015))
		)

	for index in range(12):
		var angle: float = (
			rotation_value
			+ TAU * float(index) / 12.0
		)
		var direction: Vector2 = Vector2(
			cos(angle),
			sin(angle)
		)
		var shard_center: Vector2 = (
			position_value
			+ direction * radius * (0.075 + progress * 0.235)
		)
		var shard_size: float = radius * (
			0.022 + progress * 0.032
		)
		_draw_rotated_diamond(
			shard_center,
			shard_size,
			angle,
			Color(color.r, color.g, color.b, life * 0.88),
			maxf(2.5, radius * 0.0060)
		)

	for polygon_layer in range(2):
		_draw_regular_polygon(
			position_value,
			radius * (
				0.080
				+ float(polygon_layer) * 0.065
				+ progress * 0.185
			),
			8 if polygon_layer == 0 else 6,
			rotation_value * (
				1.0 if polygon_layer == 0 else -1.0
			),
			Color(
				1.0,
				1.0,
				1.0,
				life * (0.64 - float(polygon_layer) * 0.18)
			),
			maxf(3.0, radius * 0.0070)
		)

func _draw_slide_burst(
	position_value: Vector2,
	color: Color,
	progress: float,
	life: float,
	rotation_value: float
) -> void:
	_draw_soft_glow(
		position_value,
		radius * (0.13 + progress * 0.20),
		color,
		life * 0.50,
		3
	)

	for layer in range(4):
		var size: float = radius * (0.105 + float(layer) * 0.030)
		size *= 0.30 + progress * 1.10
		var points: PackedVector2Array = _star_points(
			size,
			size * 0.43,
			rotation_value + progress * (1.4 if layer % 2 == 0 else -1.1),
			position_value
		)
		points.append(points[0])
		draw_polyline(
			points,
			Color(color.r, color.g, color.b, life * (0.96 - float(layer) * 0.16)),
			maxf(3.0, radius * (0.010 - float(layer) * 0.0012)),
			true
		)

	for index in range(6):
		var angle: float = rotation_value + TAU * float(index) / 6.0
		var direction := Vector2(cos(angle), sin(angle))
		var p: Vector2 = position_value + direction * radius * (0.075 + progress * 0.19)
		_draw_chevron(
			p,
			direction,
			radius * (0.018 + progress * 0.012),
			Color(color.r, color.g, color.b, life * 0.72)
		)


func _draw_hold_burst(
	position_value: Vector2,
	color: Color,
	progress: float,
	life: float
) -> void:
	# Final do HOLD: portal cristalino, sem simples aneis redondos.
	var rotation_value: float = (
		float(Time.get_ticks_msec()) / 1000.0 * 1.8
	)

	# Camadas reduzidas (eram 5 poligonos + 8 cristais + glow de 5
	# camadas): o burst de HOLD e o que mais pesava por acontecer bem
	# na transicao pro efeito de acerto, que era onde o travamento
	# ficava mais visivel. Menos camadas, mesma leitura de "portal".
	_draw_soft_glow(
		position_value,
		radius * (0.15 + progress * 0.22),
		color,
		life * 0.55,
		3
	)

	for layer in range(3):
		var size: float = radius * (
			0.075
			+ float(layer) * 0.044
			+ progress * 0.185
		)
		var sides: int = 8 if layer % 2 == 0 else 6
		var direction_sign: float = (
			1.0 if layer % 2 == 0 else -1.0
		)
		_draw_regular_polygon(
			position_value,
			size,
			sides,
			rotation_value * direction_sign + float(layer) * 0.24,
			Color(
				color.r,
				color.g,
				color.b,
				life * (0.98 - float(layer) * 0.15)
			),
			maxf(3.0, radius * (0.013 - float(layer) * 0.0013))
		)

	for index in range(6):
		var angle: float = (
			rotation_value * 0.55
			+ TAU * float(index) / 6.0
		)
		var direction: Vector2 = Vector2(
			cos(angle),
			sin(angle)
		)
		var crystal_position: Vector2 = (
			position_value
			+ direction * radius * (0.090 + progress * 0.245)
		)
		_draw_rotated_diamond(
			crystal_position,
			radius * (0.034 + progress * 0.028),
			angle + PI * 0.25,
			Color(color.r, color.g, color.b, life * 0.90),
			maxf(2.5, radius * 0.0065)
		)

	draw_circle(
		position_value,
		radius * (0.038 + progress * 0.045),
		Color(1.0, 1.0, 1.0, life * 0.74),
		true
	)

func _draw_miss_burst(
	position_value: Vector2,
	progress: float,
	life: float,
	rotation_value: float
) -> void:
	var size: float = radius * (0.040 + progress * 0.095)
	var a: Vector2 = Vector2(cos(rotation_value), sin(rotation_value)) * size
	var b: Vector2 = Vector2(-a.y, a.x)
	draw_line(
		position_value - a,
		position_value + a,
		Color(1.0, 0.08, 0.13, life),
		maxf(4.0, radius * 0.012),
		true
	)
	draw_line(
		position_value - b,
		position_value + b,
		Color(1.0, 0.08, 0.13, life),
		maxf(4.0, radius * 0.012),
		true
	)
	draw_arc(
		position_value,
		size * 1.18,
		0.0,
		TAU,
		40,
		Color(1.0, 0.12, 0.18, life * 0.42),
		maxf(2.0, radius * 0.005),
		true
	)


func _draw_pointer(position_value: Vector2) -> void:
	var color: Color = _primary()
	var pulse: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.025)
	var outer_radius: float = radius * (0.044 + pulse * 0.006)

	draw_circle(
		position_value,
		outer_radius * 1.28,
		Color(color.r, color.g, color.b, 0.09),
		true
	)
	draw_arc(
		position_value,
		outer_radius,
		0.0,
		TAU,
		40,
		Color.WHITE,
		maxf(2.0, radius * 0.0045),
		true
	)
	draw_arc(
		position_value,
		outer_radius * 0.70,
		-PI * 0.5,
		-PI * 0.5 + PI * 1.30,
		28,
		Color(color.r, color.g, color.b, 0.92),
		maxf(2.0, radius * 0.005),
		true
	)

	for index in range(4):
		var angle: float = PI * 0.25 + float(index) * PI * 0.5
		var direction := Vector2(cos(angle), sin(angle))
		var side := Vector2(-direction.y, direction.x)
		var corner: Vector2 = position_value + direction * outer_radius * 1.20
		draw_line(
			corner - side * outer_radius * 0.20,
			corner + side * outer_radius * 0.20,
			Color(color.r, color.g, color.b, 0.75),
			maxf(2.0, radius * 0.004),
			true
		)


## Gradiente radial "falso" reutilizavel: camadas de circulo com alpha
## decrescente. Usado para dar leitura "espectral"/energetica (glow
## suave) em vez de contorno solido e chapado — na mandala de fundo,
## nas particulas ambiente e nos bursts de acerto (tap/hold/slide).
func _draw_soft_glow(
	position_value: Vector2,
	radius_value: float,
	color: Color,
	alpha: float,
	layers: int = 4
) -> void:
	if radius_value <= 0.0 or alpha <= 0.0:
		return
	for layer in range(layers):
		var t: float = float(layer) / float(maxi(layers - 1, 1))
		var layer_radius: float = radius_value * (1.0 - t * 0.72)
		var layer_alpha: float = alpha * (0.16 + (1.0 - t) * 0.56)
		draw_circle(
			position_value,
			layer_radius,
			Color(color.r, color.g, color.b, layer_alpha),
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


func _draw_rotated_diamond(
	position_value: Vector2,
	size: float,
	rotation_value: float,
	color: Color,
	width: float
) -> void:
	var points := PackedVector2Array()
	for index in range(5):
		var angle: float = rotation_value - PI * 0.5 + float(index) * PI * 0.5
		points.append(position_value + Vector2(cos(angle), sin(angle)) * size)
	draw_polyline(points, color, width, true)


func _draw_regular_polygon(
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
		points.append(position_value + Vector2(cos(angle), sin(angle)) * size)
	draw_polyline(points, color, width, true)


func _star_points(
	outer_radius: float,
	inner_radius: float,
	rotation_value: float,
	position_value: Vector2
) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(10):
		var angle: float = rotation_value - PI * 0.5 + PI * float(index) / 5.0
		var point_radius: float = outer_radius if index % 2 == 0 else inner_radius
		points.append(position_value + Vector2(cos(angle), sin(angle)) * point_radius)
	return points
