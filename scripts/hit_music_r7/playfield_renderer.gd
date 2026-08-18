extends Node2D

# HIT MUSIC R12 - LEITURA LIMPA, HOLD ARCADE E AMBIENTE REFINADO

const PATH_BUILDER: Script = preload("res://scripts/hit_music_r7/path_builder.gd")
const TAP_PALETTE: Script = preload("res://scripts/hit_music_r7/tap_palette.gd")

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
var _hit_color: Color = Color.WHITE
var _hit_color_energy: float = 0.0
## Versao suavizada de _hit_color_energy. O valor bruto salta de 0 para
## 1 no mesmo quadro do acerto e, como o cenario inteiro e tingido por
## ele, essa troca instantanea aparecia como um "pisca" — bem visivel
## no fim do hold, que e quando o jogador esta parado olhando a nota.
## Aqui a subida leva ~0.1s e a descida acompanha o decaimento.
var _hit_color_smooth: float = 0.0

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
## O ceu de cada musica REFORCA o universo dela em vez de brigar com
## ele: riscos para as laminas do carmine, coroa para a aura do dragon
## ball, bandas para as ondas do demon, orbitas para a lua do soul, e
## assim por diante. Antes carmine usava supernova (raios saindo do
## centro), que puxava a leitura de volta para o desenho concentrico.
const COSMIC_STYLE_BY_SONG: Dictionary = {
	"carmine": "meteor",
	"dragon_ball": "solar_crown",
	"demon": "aurora",
	"fairy": "constellation",
	"naruto": "spiral_galaxy",
	"rick_morty": "wormhole",
	"soul": "planetary",
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

## ─── DESEMPENHO ───────────────────────────────────────────────────
## O cenario (ceu, universo, poeira) mudava 60x por segundo junto com
## as notas, mas ele nao PRECISA: uma estrela que leva 4 minutos para
## atravessar a tela nao ganha nada em ser redesenhada a cada 16ms.
## Agora ele mora numa camada propria, que se redesenha nesta taxa.
## As notas, o anel e os efeitos continuam a 60 fps na camada de cima.
##
## 24 e o padrao. Suba para 30 se a mesa aguentar; desca para 15 se
## ainda estiver pesado (o cenario fica levemente mais "duro", nada
## que se note durante a partida).
const BACKGROUND_REDRAW_HZ: float = 24.0

## Toda primitiva sai por aqui em vez de sair direto por `self`. E o
## que permite que as MESMAS funcoes de desenho pintem ora na camada
## de fundo, ora nesta — sem duplicar codigo.
var _target: CanvasItem = null
var _bg_layer: BackgroundLayer
var _background_clock: float = 0.0

## Halo pre-renderizado. Antes cada halo era uma pilha de 3-4 circulos
## preenchidos concentricos; com 20 particulas de poeira mais as
## nebulosas e os estouros, dava mais de cem circulos preenchidos por
## quadro so de brilho. Agora e um quadrado texturizado por halo — e
## o degrade fica de verdade contínuo, sem as faixas dos circulos.
var _glow_texture: Texture2D

## As cores do tema saem de Color.from_hsv() dentro de vivid_theme().
## Elas dependem so de `song`, que muda uma vez por partida — nao ha
## por que recalcular a cada chamada dentro dos lacos de desenho.
var _cached_primary: Color = Color(0.0, 0.86, 1.0, 1.0)
var _cached_secondary: Color = Color.WHITE
var _cached_accent: Color = Color(1.0, 0.72, 0.0, 1.0)
var _cached_dark: Color = Color(0.01, 0.02, 0.05, 1.0)


## Camada de fundo. Nao guarda estado: so devolve o desenho para o
## renderer, que pinta nela. `show_behind_parent` a mantem atras das
## notas mesmo compartilhando o z_index do pai.
class BackgroundLayer:
	extends Node2D

	var renderer: Node2D

	func _draw() -> void:
		if renderer != null and is_instance_valid(renderer):
			# call() em vez da chamada direta: `renderer` e tipado como
			# Node2D e o verificador estatico do Godot recusaria um
			# metodo que Node2D nao declara.
			renderer.call("paint_background", self)


func _ready() -> void:
	_target = self
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

	_glow_texture = _build_glow_texture()
	_rebuild_color_cache()

	_bg_layer = BackgroundLayer.new()
	_bg_layer.name = "BackgroundLayer"
	_bg_layer.renderer = self
	_bg_layer.show_behind_parent = true
	add_child(_bg_layer)

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
	_rebuild_color_cache()
	_request_background_redraw()
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


func add_effect(
	kind: String,
	position_value: Vector2,
	color: Color,
	arrow_style: int = 0,
	star_style: int = 0
) -> void:
	# O erro continua afetando combo e performance, mas nao cobre a proxima nota.
	if kind == "miss":
		return
	var duration: float = 0.68
	if kind == "slide":
		# A explosao conserva a estrela de 4/5/6/8 pontas, mas e curta. O
		# sprite do percurso ja foi removido pelo stage no quadro do acerto.
		duration = 0.46
	elif kind == "hold":
		duration = 0.88

	effects.append({
		"kind": kind,
		"position": position_value,
		"color": color,
		"start": float(Time.get_ticks_msec()) / 1000.0,
		"duration": duration,
		"rotation": fmod(position_value.x * 0.017 + position_value.y * 0.013, TAU),
		# O estouro reaproveita a mesma seta/estrela que a nota mostrava,
		# entao o efeito continua sendo "aquele objeto explodindo".
		"arrow_style": arrow_style,
		"star_style": star_style,
	})
	queue_redraw()


func register_hit(quality: float, combo: int, color: Color = Color.WHITE) -> void:
	# Um unico impulso alimenta fundo, bolinhas e anel. Sem nodes temporarios.
	var carmine_boost: float = 1.22 if str(song.get("id", "")) == "carmine" else 1.0
	_hit_energy = minf(1.0, _hit_energy + (0.30 + quality * 0.30) * carmine_boost)
	_combo_energy = clampf(float(combo) / 40.0, 0.0, 1.0)
	_hit_color = color
	# Mantem a identidade da cor durante todo o efeito visual. A energia
	# mecanica decai rapido; esta memoria cromatica dura o burst completo.
	_hit_color_energy = 1.0
	queue_redraw()


## Acende a lane mais proxima de position_value com a cor real do
## tazo/evento. intensity controla
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
	_hit_color_energy = move_toward(_hit_color_energy, 0.0, delta * 1.10)
	# Sobe rapido mas nao instantaneo (~0.1s ate o topo) e desce junto
	# com o valor bruto: e o que tira o pisca do fundo no acerto.
	_hit_color_smooth = move_toward(_hit_color_smooth, _hit_color_energy, delta * 9.0)

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

	# O cenario tem relogio proprio: ele nao acompanha os 60 fps das
	# notas. E daqui que vem a maior parte do ganho de desempenho.
	_background_clock += delta
	if _background_clock >= 1.0 / maxf(BACKGROUND_REDRAW_HZ, 1.0):
		_background_clock = 0.0
		_request_background_redraw()

	var pulses_active: bool = not _ring_pulses.is_empty()
	if not effects.is_empty() or lane_flash_active or pulses_active or game_state == "playing" or game_state == "selector":
		queue_redraw()


## Camada de CIMA, a 60 fps: anel, energia das lanes, notas e efeitos.
## Tudo que reage ao dedo do jogador no mesmo quadro esta aqui.
func _draw() -> void:
	if radius <= 0.0:
		return

	_target = self
	_draw_ring()
	_draw_ring_pulses()
	_draw_lane_energy()

	if game_state == "playing" or game_state == "countdown":
		for event_value in events:
			if not event_value is Dictionary:
				continue
			var event: Dictionary = event_value as Dictionary
			# Porta barata antes do str(): a lista tem a fase INTEIRA,
			# entao a maioria dos eventos ainda nem nasceu. Sem esta
			# linha o laco convertia centenas de tipos em String por
			# quadro so para descartar tudo em seguida.
			if not bool(event.get("_spawned", false)):
				continue
			var type_name: String = str(event.get("type", "tap"))

			if bool(event.get("_resolved", false)):
				# Resolvido significa encerrado visualmente neste mesmo quadro.
				# O burst de acerto e desenhado separadamente em _draw_effects().
				continue

			if type_name == "hold":
				_draw_hold(event)
			elif type_name == "slide":
				_draw_slide(event)

	_draw_effects()

	if pointer_active and game_state == "playing":
		_draw_pointer(pointer_position)


## Camada de BAIXO, na taxa de BACKGROUND_REDRAW_HZ. Chamada pela
## BackgroundLayer, que passa a si mesma como superficie de desenho.
func paint_background(canvas: CanvasItem) -> void:
	if radius <= 0.0:
		return

	_target = canvas
	# Uma unica camada desenha o cenario. Antes eram tres empilhadas (a
	# mandala geral, os aneis tecnicos e o overlay tematico), todas com o
	# mesmo desenho concentrico — por isso toda tela parecia a do carmine
	# com coisas por cima.
	_draw_circle_base()
	_draw_cosmic_sky()
	_draw_universe()
	_draw_ambient_particles()
	_target = self


func _request_background_redraw() -> void:
	if _bg_layer != null and is_instance_valid(_bg_layer):
		_bg_layer.queue_redraw()


## Halo radial de 128px, gerado uma vez. O branco puro deixa a cor
## final por conta do `modulate` de cada chamada.
func _build_glow_texture() -> Texture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.32, 0.68, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.52),
		Color(1.0, 1.0, 1.0, 0.14),
		Color(1.0, 1.0, 1.0, 0.0),
	])

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 128
	texture.height = 128
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture


func _rebuild_color_cache() -> void:
	_cached_primary = TAP_PALETTE.vivid_theme(
		_colors().get("primary", TAP_PALETTE.TAP_CYAN)
	)
	_cached_secondary = TAP_PALETTE.vivid_theme(
		_colors().get("secondary", Color.WHITE)
	)
	_cached_accent = TAP_PALETTE.vivid_theme(
		_colors().get("accent", TAP_PALETTE.TAP_YELLOW)
	)
	_cached_dark = _colors().get("dark", Color(0.01, 0.02, 0.05, 1.0))


func _colors() -> Dictionary:
	var value: Variant = song.get("colors", {})
	if value is Dictionary:
		return value as Dictionary
	return {}


func _primary() -> Color:
	return _cached_primary


func _secondary() -> Color:
	return _cached_secondary


func _accent() -> Color:
	return _cached_accent


func _dark() -> Color:
	return _cached_dark


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
	_target.draw_circle(
		center,
		radius * 0.995,
		Color(0.002, 0.004, 0.012, base_alpha),
		true
	)
	_target.draw_circle(
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
				_target.draw_line(from, to, Color(primary.r, primary.g, primary.b, 0.18), maxf(1.0, radius * 0.0018), false)

		"spiral_galaxy":
			for arm in range(3):
				var previous: Vector2 = center
				for step in range(1, 13):
					var progress: float = float(step) / 12.0
					var angle: float = time_value * 0.045 + TAU * float(arm) / 3.0 + progress * TAU * 1.38
					var position_value: Vector2 = center + Vector2(cos(angle), sin(angle)) * radius * progress * 0.78
					var arm_color: Color = primary.lerp(accent, progress)
					_target.draw_line(previous, position_value, Color(arm_color.r, arm_color.g, arm_color.b, 0.13), maxf(1.0, radius * 0.0022), false)
					_target.draw_circle(position_value, maxf(1.0, radius * 0.0035), Color(arm_color.r, arm_color.g, arm_color.b, 0.42), true)
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
				_target.draw_polyline(points, Color(band_color.r, band_color.g, band_color.b, 0.14 + float(band) * 0.025), maxf(2.0, radius * 0.004), false)

		"meteor":
			var meteor_direction := Vector2(-0.88, 0.48).normalized()
			for index in range(0, _cosmic_stars.size(), 4):
				var head: Vector2 = _cosmic_star_position(_cosmic_stars[index], time_value, 1.8)
				var length: float = radius * (0.035 + float(index % 5) * 0.012)
				_target.draw_line(head - meteor_direction * length, head, Color(accent.r, accent.g, accent.b, 0.34), maxf(1.0, radius * 0.0024), false)

		"planetary":
			for orbit_index in range(1, 5):
				var orbit_radius: float = radius * (0.16 + float(orbit_index) * 0.13)
				_target.draw_arc(center, orbit_radius, 0.0, TAU, 40, Color(primary.r, primary.g, primary.b, 0.08 + float(orbit_index) * 0.012), maxf(1.0, radius * 0.0017), false)
				var planet_angle: float = time_value * (0.035 / float(orbit_index)) + float(orbit_index) * 1.31
				var planet_position: Vector2 = center + Vector2(cos(planet_angle), sin(planet_angle)) * orbit_radius
				_target.draw_circle(planet_position, radius * (0.008 + float(orbit_index) * 0.002), primary.lerp(accent, float(orbit_index) / 5.0), true)

		"supernova":
			for ray in range(20):
				var angle: float = TAU * float(ray) / 20.0 + time_value * 0.018
				var ray_length: float = radius * (0.20 + 0.10 * (0.5 + 0.5 * sin(time_value * 0.8 + float(ray))))
				var direction := Vector2(cos(angle), sin(angle))
				_target.draw_line(center + direction * radius * 0.07, center + direction * ray_length, Color(primary.r, primary.g, primary.b, 0.14), maxf(1.0, radius * 0.002), false)
			_draw_soft_glow(center, radius * 0.18, accent, 0.16 + reaction * 0.10, 3)

		"wormhole":
			for ring_index in range(1, 11):
				var progress: float = float(ring_index) / 10.0
				var wobble: float = sin(time_value * 0.35 + float(ring_index) * 0.71) * radius * 0.018
				var ring_center: Vector2 = center + Vector2(wobble, -wobble * 0.55)
				var ring_color: Color = primary.lerp(secondary, progress)
				_target.draw_arc(ring_center, radius * progress * 0.72, 0.0, TAU, 40, Color(ring_color.r, ring_color.g, ring_color.b, 0.05 + progress * 0.07), maxf(1.0, radius * 0.002), false)

		"solar_crown":
			var crown_radius: float = radius * (0.22 + _beat_pulse() * 0.012)
			_draw_soft_glow(center, crown_radius * 1.25, primary, 0.14 + reaction * 0.06, 3)
			for ray in range(16):
				var angle: float = TAU * float(ray) / 16.0 - time_value * 0.025
				var direction := Vector2(cos(angle), sin(angle))
				_target.draw_line(center + direction * crown_radius, center + direction * crown_radius * 1.34, Color(accent.r, accent.g, accent.b, 0.20), maxf(1.0, radius * 0.0023), false)
			_target.draw_arc(center, crown_radius, 0.0, TAU, 44, Color(accent.r, accent.g, accent.b, 0.28), maxf(2.0, radius * 0.004), false)

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
		_target.draw_circle(position_value, maxf(1.0, star_size), Color(star_color.r, star_color.g, star_color.b, 0.30 + twinkle * 0.62), true)
		if twinkle > 0.82 and star.z > 0.45:
			_target.draw_line(position_value - Vector2(star_size * 2.2, 0.0), position_value + Vector2(star_size * 2.2, 0.0), Color(1.0, 1.0, 1.0, 0.18), maxf(1.0, star_size * 0.28), false)
			_target.draw_line(position_value - Vector2(0.0, star_size * 2.2), position_value + Vector2(0.0, star_size * 2.2), Color(1.0, 1.0, 1.0, 0.18), maxf(1.0, star_size * 0.28), false)


## Cada musica tem o SEU universo. Antes todas as telas desenhavam a
## mesma mandala concentrica (a do carmine) e as diferencas eram apenas
## a forma miuda de cada cristal — por cima ainda vinha um overlay que
## repetia a mesma mandala. Agora cada cenario tem uma ESTRUTURA
## propria: lamina, aura, onda, enxame, espiral, grade e favo nao se
## parecem nem de longe, e nenhuma camada e empilhada sobre a outra.
const UNIVERSE_STYLES: Array[String] = [
	"blade_shards",
	"ki_aura",
	"breath_waves",
	"rune_swarm",
	"spiral_seal",
	"portal_lab",
	"moon_hive",
	"prism_field",
]
const UNIVERSE_BY_SONG: Dictionary = {
	"carmine": "blade_shards",
	"dragon_ball": "ki_aura",
	"demon": "breath_waves",
	"fairy": "rune_swarm",
	"naruto": "spiral_seal",
	"rick_morty": "portal_lab",
	"soul": "moon_hive",
}
## Nenhum desenho de cenario passa deste raio: tudo fica dentro do
## disco, sem vazar para o fundo preto nem encostar na linha do anel.
const UNIVERSE_INNER_RATIO: float = 0.86


func _universe_style() -> String:
	var explicit_style: String = str(song.get("universe_style", ""))
	if explicit_style in UNIVERSE_STYLES:
		return explicit_style
	var song_id: String = str(song.get("id", ""))
	if UNIVERSE_BY_SONG.has(song_id):
		return str(UNIVERSE_BY_SONG[song_id])
	# Musica nova sem universo definido nao herda o do carmine: cai num
	# campo neutro proprio, escolhido pela semente.
	var seed_value: int = absi(int(song.get("seed", 0)))
	return UNIVERSE_STYLES[seed_value % UNIVERSE_STYLES.size()]


func _universe_radius() -> float:
	return radius * UNIVERSE_INNER_RATIO


## Meia-corda do disco na distancia informada do centro. Usada pelos
## cenarios de linha reta (lamina, onda, grade) para terminarem
## exatamente na borda do circulo, sem corte quadrado.
func _chord_half(distance_value: float) -> float:
	var limit: float = _universe_radius()
	return sqrt(maxf(limit * limit - distance_value * distance_value, 0.0))


func _draw_universe() -> void:
	# background_intensity da dificuldade vem baixo (0.13 no facil, 0.22
	# no dificil) porque servia a uma mandala de linhas finas repetida em
	# quatro camadas. Cada universo agora tem uma estrutura unica e
	# precisa de corpo para ser reconhecido, entao esse valor e reescalado
	# aqui — continua respondendo a dificuldade, mas com presenca real.
	var base_intensity: float = clampf(
		float(difficulty.get("background_intensity", 0.18)),
		0.06,
		0.30
	)
	var intensity: float = clampf(base_intensity * 1.90 + 0.06, 0.14, 0.52)
	var time_value: float = _idle_time()
	var speed: float = float(difficulty.get("background_speed", 0.22))
	var rotation: float = time_value * speed
	var beat: float = _beat_pulse()
	var reaction: float = _hit_energy + _combo_energy * 0.32

	# Enquanto o burst do acerto esta vivo, o cenario inteiro assume a
	# cor do tazo acertado e volta suavemente para a paleta da musica.
	var hit_mix: float = clampf(_hit_color_smooth * 4.0, 0.0, 1.0)
	var primary: Color = _primary().lerp(_hit_color, hit_mix)
	var secondary: Color = _secondary().lerp(_hit_color, hit_mix)
	var accent: Color = _accent().lerp(_hit_color, hit_mix)

	match _universe_style():
		"ki_aura":
			_draw_universe_ki_aura(time_value, intensity, beat, reaction, primary, accent)
		"breath_waves":
			_draw_universe_breath_waves(time_value, intensity, beat, reaction, primary, secondary, accent)
		"rune_swarm":
			_draw_universe_rune_swarm(time_value, intensity, beat, reaction, primary, secondary, accent)
		"spiral_seal":
			_draw_universe_spiral_seal(time_value, rotation, intensity, beat, reaction, primary, accent)
		"portal_lab":
			_draw_universe_portal_lab(time_value, rotation, intensity, beat, reaction, primary, secondary, accent)
		"moon_hive":
			_draw_universe_moon_hive(time_value, rotation, intensity, beat, reaction, primary, secondary, accent)
		"prism_field":
			_draw_universe_prism_field(time_value, rotation, intensity, beat, reaction, primary, secondary, accent)
		_:
			_draw_universe_blade_shards(time_value, intensity, beat, reaction, primary, accent)

	_draw_hit_bloom()


## Clarao central na cor do tazo acertado. E a unica camada comum a
## todos os universos, porque nao e decoracao: e a resposta do acerto.
func _draw_hit_bloom() -> void:
	if _hit_color_smooth <= 0.015:
		return
	_draw_soft_glow(
		center,
		radius * (0.26 + _hit_color_smooth * 0.20),
		_hit_color,
		_hit_color_smooth * 0.26,
		3
	)


## CARMINE — laminas. Cortes diagonais atravessam o disco e deixam
## estilhacos para tras. Sem nenhum anel concentrico: a leitura e de
## golpe, nao de mandala.
func _draw_universe_blade_shards(
	time_value: float,
	intensity: float,
	beat: float,
	reaction: float,
	primary: Color,
	accent: Color
) -> void:
	for slash in range(5):
		var angle: float = -PI * 0.30 + float(slash) * 0.38
		angle += sin(time_value * 0.14 + float(slash) * 1.3) * 0.05
		var direction := Vector2(cos(angle), sin(angle))
		var normal := Vector2(-direction.y, direction.x)

		var phase: float = fposmod(time_value * 0.055 + float(slash) * 0.21, 1.0)
		var offset: float = (phase - 0.5) * _universe_radius() * 1.72
		var span: float = _chord_half(absf(offset))
		if span <= 1.0:
			continue

		var middle: Vector2 = center + normal * offset
		var thickness: float = radius * (0.016 + 0.009 * float(slash % 3))
		thickness *= 1.0 + reaction * 0.85 + beat * 0.25

		var blade_color: Color = primary.lerp(accent, float(slash % 3) * 0.34)
		var fade: float = sin(PI * phase)
		blade_color.a = intensity * (0.46 + beat * 0.16 + reaction * 0.34) * fade

		_target.draw_colored_polygon(
			PackedVector2Array([
				middle - direction * span,
				middle + normal * thickness,
				middle + direction * span,
				middle - normal * thickness,
			]),
			blade_color
		)

		# Fio de luz no meio da lamina e estilhacos saltando do corte.
		_target.draw_line(
			middle - direction * span * 0.86,
			middle + direction * span * 0.86,
			Color(1.0, 1.0, 1.0, intensity * 0.28 * fade),
			maxf(1.0, radius * 0.0016),
			false
		)

		for shard in range(3):
			var along: float = -0.52 + float(shard) * 0.52
			var side: float = 1.0 if shard % 2 == 0 else -1.0
			var shard_position: Vector2 = (
				middle
				+ direction * span * along
				+ normal * radius * (0.030 + 0.012 * float(shard)) * side
			)
			if shard_position.distance_to(center) > _universe_radius():
				continue
			_draw_regular_polygon(
				shard_position,
				radius * (0.026 + 0.009 * float(shard)),
				3,
				angle + PI * 0.5 + time_value * 0.55 * side,
				Color(accent.r, accent.g, accent.b, intensity * (0.62 + reaction * 0.35) * fade),
				maxf(2.0, radius * 0.0034)
			)


## DRAGON BALL — aura de ki. Linguas de energia tremulam a partir do
## nucleo e ondas de choque sobem em direcao a borda.
func _draw_universe_ki_aura(
	time_value: float,
	intensity: float,
	beat: float,
	reaction: float,
	primary: Color,
	accent: Color
) -> void:
	var core: float = radius * (0.085 + beat * 0.012 + reaction * 0.02)
	_draw_soft_glow(
		center,
		radius * (0.22 + reaction * 0.12),
		accent,
		intensity * (0.50 + beat * 0.20),
		3
	)

	for tongue in range(16):
		var base_angle: float = TAU * float(tongue) / 16.0
		var flicker: float = 0.5 + 0.5 * sin(
			time_value * (3.4 + float(tongue % 5) * 0.31) + float(tongue) * 1.7
		)
		var length: float = radius * (0.26 + 0.30 * flicker + reaction * 0.10)
		var points := PackedVector2Array()
		for step in range(6):
			var t: float = float(step) / 5.0
			var sway: float = sin(time_value * 4.2 + float(tongue) * 2.1 + t * 6.0)
			var angle: float = base_angle + sway * 0.075 * (1.0 - t * 0.55)
			points.append(
				center
				+ Vector2(cos(angle), sin(angle)) * minf(core + (length - core) * t, _universe_radius())
			)
		var tongue_color: Color = primary.lerp(accent, flicker * 0.60)
		_target.draw_polyline(
			points,
			Color(tongue_color.r, tongue_color.g, tongue_color.b, intensity * (0.30 + flicker * 0.42)),
			maxf(1.5, radius * (0.0022 + flicker * 0.0016)),
			false
		)

	for shock in range(3):
		var progress: float = fposmod(time_value * 0.32 + float(shock) / 3.0, 1.0)
		var shock_radius: float = radius * (0.14 + progress * 0.66)
		_target.draw_arc(
			center,
			shock_radius,
			0.0,
			TAU,
			32,
			Color(accent.r, accent.g, accent.b, intensity * (1.0 - progress) * 0.46),
			maxf(1.5, radius * 0.0030 * (1.0 - progress * 0.5)),
			false
		)

	_target.draw_circle(center, core, Color(accent.r, accent.g, accent.b, intensity * 0.85), true)
	_target.draw_circle(center, core * 0.52, Color(1.0, 1.0, 1.0, intensity * 0.70), true)


## DEMON — respiracao. Faixas horizontais varrem o disco de baixo para
## cima, com escamas ao longo da crista. Leitura totalmente linear, sem
## simetria radial.
func _draw_universe_breath_waves(
	time_value: float,
	intensity: float,
	beat: float,
	reaction: float,
	primary: Color,
	secondary: Color,
	accent: Color
) -> void:
	for band in range(6):
		var slot: float = fposmod(float(band) / 6.0 - time_value * 0.045, 1.0)
		var y: float = (slot - 0.5) * 2.0 * _universe_radius()
		var half_width: float = _chord_half(absf(y))
		if half_width <= 1.0:
			continue

		var band_color: Color = primary.lerp(secondary, float(band) / 5.0)
		var alpha: float = intensity * (0.54 + beat * 0.16 + reaction * 0.28)
		alpha *= sin(PI * clampf(slot, 0.0, 1.0))

		var crest := PackedVector2Array()
		for step in range(21):
			var t: float = float(step) / 20.0
			var x: float = -half_width + 2.0 * half_width * t
			var wave: float = sin(t * 6.8 + time_value * 1.15 + float(band) * 0.85)
			crest.append(center + Vector2(x, y + wave * radius * 0.028))
		_target.draw_polyline(
			crest,
			Color(band_color.r, band_color.g, band_color.b, alpha),
			maxf(2.0, radius * 0.0040),
			false
		)

		# Escamas: meio-arcos apoiados na crista, como agua quebrando.
		for scale_index in range(5):
			var t2: float = 0.12 + float(scale_index) * 0.19
			var x2: float = -half_width + 2.0 * half_width * t2
			var wave2: float = sin(t2 * 6.8 + time_value * 1.15 + float(band) * 0.85)
			var scale_position: Vector2 = center + Vector2(x2, y + wave2 * radius * 0.028)
			_target.draw_arc(
				scale_position,
				radius * 0.026,
				PI,
				TAU,
				12,
				Color(accent.r, accent.g, accent.b, alpha * 0.72),
				maxf(1.5, radius * 0.0024),
				false
			)


## FAIRY — enxame de runas. Glifos flutuam em orbitas irregulares com
## poeira magica ao redor. Nada e concentrico nem alinhado.
func _draw_universe_rune_swarm(
	time_value: float,
	intensity: float,
	beat: float,
	reaction: float,
	primary: Color,
	secondary: Color,
	accent: Color
) -> void:
	for rune in range(10):
		var seed_value: float = float(rune) * 12.9898
		var base_angle: float = fposmod(absf(sin(seed_value) * 43758.5453), TAU)
		var orbit: float = radius * (0.18 + fposmod(absf(cos(seed_value * 0.73)) * 9.7, 0.50))
		var direction_sign: float = -1.0 if rune % 2 == 0 else 1.0
		var breath: float = sin(time_value * (0.55 + float(rune % 3) * 0.18) + seed_value)
		var angle: float = base_angle + time_value * 0.055 * direction_sign + breath * 0.10
		var rune_position: Vector2 = (
			center + Vector2(cos(angle), sin(angle)) * (orbit + breath * radius * 0.030)
		)
		var glow: float = 0.5 + 0.5 * sin(time_value * 1.7 + seed_value)
		var rune_color: Color = primary.lerp(secondary, float(rune % 3) * 0.32)
		var alpha: float = intensity * (0.52 + glow * 0.40 + reaction * 0.28)

		_draw_soft_glow(rune_position, radius * 0.070, rune_color, alpha * 0.60, 3)

		var sparkle := _star_points(
			radius * (0.044 + glow * 0.008),
			radius * 0.012,
			angle + time_value * 0.35 * direction_sign,
			rune_position,
			4
		)
		sparkle.append(sparkle[0])
		_target.draw_polyline(
			sparkle,
			Color(rune_color.r, rune_color.g, rune_color.b, alpha),
			maxf(2.0, radius * 0.0038),
			false
		)
		_target.draw_arc(
			rune_position,
			radius * (0.058 + beat * 0.005),
			angle,
			angle + PI * 1.45,
			20,
			Color(accent.r, accent.g, accent.b, alpha * 0.66),
			maxf(1.5, radius * 0.0026),
			false
		)

	for mote in range(20):
		var mote_seed: float = float(mote) * 7.517 + 3.19
		var mote_angle: float = fposmod(absf(sin(mote_seed) * 21311.71), TAU)
		var mote_orbit: float = radius * (0.12 + fposmod(absf(cos(mote_seed * 1.31)) * 5.3, 0.66))
		var rise: float = fposmod(time_value * 0.10 + float(mote) * 0.07, 1.0)
		var mote_position: Vector2 = (
			center
			+ Vector2(cos(mote_angle + rise * 0.55), sin(mote_angle + rise * 0.55))
			* minf(mote_orbit + rise * radius * 0.10, _universe_radius())
		)
		var twinkle: float = 0.5 + 0.5 * sin(time_value * 2.6 + mote_seed)
		_target.draw_circle(
			mote_position,
			maxf(1.0, radius * (0.0018 + twinkle * 0.0016)),
			Color(accent.r, accent.g, accent.b, intensity * (0.30 + twinkle * 0.55) * (1.0 - rise)),
			true
		)


## NARUTO — selo em espiral. Uma unica espiral longa domina a tela,
## fechada por um anel de marcas. Nada de mandala de cristais.
func _draw_universe_spiral_seal(
	time_value: float,
	rotation: float,
	intensity: float,
	beat: float,
	reaction: float,
	primary: Color,
	accent: Color
) -> void:
	# O numero de voltas respira devagar: o redemoinho aperta e afrouxa
	# em vez de girar sempre igual.
	var turns: float = 3.15 + sin(time_value * 0.22) * 0.18
	var spiral := PackedVector2Array()
	for step in range(89):
		var t: float = float(step) / 88.0
		var angle: float = rotation * 0.85 + t * TAU * turns
		var spiral_radius: float = radius * 0.055 + t * _universe_radius() * 0.76
		spiral.append(center + Vector2(cos(angle), sin(angle)) * spiral_radius)

	_target.draw_polyline(
		spiral,
		Color(primary.r, primary.g, primary.b, intensity * (0.42 + reaction * 0.34)),
		maxf(2.0, radius * 0.0052 * (1.0 + beat * 0.20)),
		false
	)

	# Segunda espiral, oposta e mais fina, dando profundidade ao redemoinho.
	var counter := PackedVector2Array()
	for step2 in range(67):
		var t2: float = float(step2) / 66.0
		var angle2: float = -rotation * 0.55 - t2 * TAU * (turns * 0.70) + PI
		var counter_radius: float = radius * 0.10 + t2 * _universe_radius() * 0.62
		counter.append(center + Vector2(cos(angle2), sin(angle2)) * counter_radius)
	_target.draw_polyline(
		counter,
		Color(accent.r, accent.g, accent.b, intensity * 0.30),
		maxf(1.0, radius * 0.0026),
		false
	)

	var seal_radius: float = _universe_radius() * 0.92
	_target.draw_arc(
		center,
		seal_radius,
		0.0,
		TAU,
		44,
		Color(accent.r, accent.g, accent.b, intensity * (0.34 + beat * 0.10)),
		maxf(1.5, radius * 0.0032),
		false
	)
	for tick in range(24):
		var tick_angle: float = -rotation * 0.32 + TAU * float(tick) / 24.0
		var tick_direction := Vector2(cos(tick_angle), sin(tick_angle))
		var tick_length: float = radius * (0.040 if tick % 3 == 0 else 0.020)
		_target.draw_line(
			center + tick_direction * seal_radius,
			center + tick_direction * (seal_radius - tick_length),
			Color(primary.r, primary.g, primary.b, intensity * (0.46 if tick % 3 == 0 else 0.24)),
			maxf(1.5, radius * 0.0026),
			false
		)


## RICK AND MORTY — laboratorio. Grade cartesiana em fuga e um portal
## eliptico com redemoinho. Leitura retilinea, o oposto de radial.
func _draw_universe_portal_lab(
	time_value: float,
	rotation: float,
	intensity: float,
	beat: float,
	reaction: float,
	primary: Color,
	secondary: Color,
	accent: Color
) -> void:
	var spacing: float = _universe_radius() * 0.208
	var drift: float = fposmod(time_value * radius * 0.020, spacing)

	for column in range(-5, 6):
		var x: float = float(column) * spacing + drift - spacing * 0.5
		var column_half: float = _chord_half(absf(x))
		if column_half <= 1.0:
			continue
		_target.draw_line(
			center + Vector2(x, -column_half),
			center + Vector2(x, column_half),
			Color(primary.r, primary.g, primary.b, intensity * (0.20 + beat * 0.06)),
			maxf(1.0, radius * 0.0018),
			false
		)

	for row in range(-5, 6):
		var y: float = float(row) * spacing - drift + spacing * 0.5
		var row_half: float = _chord_half(absf(y))
		if row_half <= 1.0:
			continue
		_target.draw_line(
			center + Vector2(-row_half, y),
			center + Vector2(row_half, y),
			Color(secondary.r, secondary.g, secondary.b, intensity * 0.14),
			maxf(1.0, radius * 0.0016),
			false
		)

	# Portal: elipse com redemoinho interno e borda mais viva.
	var portal_size := Vector2(_universe_radius() * 0.46, _universe_radius() * 0.34)
	_draw_soft_glow(center, portal_size.y * 1.25, accent, intensity * (0.42 + reaction * 0.26), 3)

	for layer in range(3):
		var ellipse := PackedVector2Array()
		var scale_value: float = 1.0 - float(layer) * 0.24
		for step in range(41):
			var angle: float = TAU * float(step) / 40.0
			ellipse.append(
				center
				+ Vector2(
					cos(angle) * portal_size.x * scale_value,
					sin(angle) * portal_size.y * scale_value
				)
			)
		_target.draw_polyline(
			ellipse,
			Color(accent.r, accent.g, accent.b, intensity * (0.50 - float(layer) * 0.12)),
			maxf(1.5, radius * (0.0034 - float(layer) * 0.0008)),
			false
		)

	var swirl := PackedVector2Array()
	for step2 in range(49):
		var t: float = float(step2) / 48.0
		var angle2: float = rotation * 1.35 + t * TAU * 1.85
		swirl.append(
			center
			+ Vector2(
				cos(angle2) * portal_size.x * (1.0 - t) * 0.90,
				sin(angle2) * portal_size.y * (1.0 - t) * 0.90
			)
		)
	_target.draw_polyline(
		swirl,
		Color(primary.r, primary.g, primary.b, intensity * 0.55),
		maxf(1.5, radius * 0.0030),
		false
	)


## SOUL — favo e lua. Placas hexagonais preenchem o disco e uma lua
## crescente atravessa o campo. Grade compacta, sem centro dominante.
func _draw_universe_moon_hive(
	time_value: float,
	rotation: float,
	intensity: float,
	beat: float,
	reaction: float,
	primary: Color,
	secondary: Color,
	accent: Color
) -> void:
	var cell: float = _universe_radius() * 0.185
	var breathe: float = 0.90 + 0.08 * sin(time_value * 1.25) + beat * 0.05

	for column in range(-4, 5):
		for row in range(-4, 5):
			var offset_y: float = cell * 0.866 if posmod(column, 2) == 1 else 0.0
			var cell_position: Vector2 = center + Vector2(
				float(column) * cell * 1.50,
				float(row) * cell * 1.732 + offset_y
			)
			var distance_value: float = cell_position.distance_to(center)
			if distance_value > _universe_radius() - cell * 0.55:
				continue

			var depth: float = 1.0 - clampf(distance_value / maxf(_universe_radius(), 1.0), 0.0, 1.0)
			var wobble: float = sin(time_value * 1.05 + float(column) * 0.8 + float(row) * 0.6)
			var plate_color: Color = primary.lerp(secondary, 0.30 + wobble * 0.20)
			_draw_regular_polygon(
				cell_position,
				cell * 0.52 * breathe,
				6,
				PI / 6.0 + rotation * 0.05,
				Color(
					plate_color.r,
					plate_color.g,
					plate_color.b,
					intensity * (0.28 + depth * 0.42 + reaction * 0.24)
				),
				maxf(1.5, radius * 0.0028)
			)

	# Lua crescente: dois arcos deslocados formando a foice.
	var moon_center: Vector2 = center + Vector2(
		-_universe_radius() * 0.24,
		-_universe_radius() * 0.20
	)
	var moon_radius: float = _universe_radius() * 0.30
	var swing: float = sin(time_value * 0.28) * 0.16
	_target.draw_arc(
		moon_center,
		moon_radius,
		-PI * 0.62 + swing,
		PI * 0.62 + swing,
		28,
		Color(accent.r, accent.g, accent.b, intensity * (0.62 + beat * 0.14)),
		maxf(2.0, radius * 0.0048),
		false
	)
	_target.draw_arc(
		moon_center + Vector2(moon_radius * 0.42, 0.0),
		moon_radius * 0.92,
		-PI * 0.52 + swing,
		PI * 0.52 + swing,
		26,
		Color(accent.r, accent.g, accent.b, intensity * 0.40),
		maxf(1.5, radius * 0.0034),
		false
	)


## Universo neutro para musicas futuras que ainda nao tenham cenario
## proprio. Prismas em deriva, sem a mandala concentrica antiga.
func _draw_universe_prism_field(
	time_value: float,
	rotation: float,
	intensity: float,
	beat: float,
	reaction: float,
	primary: Color,
	secondary: Color,
	accent: Color
) -> void:
	for prism in range(16):
		var seed_value: float = float(prism) * 9.371
		var lane_angle: float = TAU * float(prism) / 16.0 + rotation * 0.22
		var travel: float = fposmod(time_value * 0.075 + float(prism) * 0.0625, 1.0)
		var prism_radius: float = _universe_radius() * (0.14 + travel * 0.74)
		var prism_position: Vector2 = (
			center + Vector2(cos(lane_angle), sin(lane_angle)) * prism_radius
		)
		var fade: float = sin(PI * travel)
		var prism_color: Color = primary.lerp(
			secondary if prism % 2 == 0 else accent,
			0.35 + 0.30 * sin(time_value * 0.6 + seed_value)
		)
		var size: float = radius * (0.018 + travel * 0.020)

		_draw_rotated_diamond(
			prism_position,
			size,
			lane_angle + time_value * 0.45,
			Color(
				prism_color.r,
				prism_color.g,
				prism_color.b,
				intensity * (0.30 + reaction * 0.30 + beat * 0.10) * fade
			),
			maxf(1.5, radius * 0.0028)
		)
		_target.draw_line(
			prism_position - Vector2(cos(lane_angle), sin(lane_angle)) * size * 2.2,
			prism_position,
			Color(prism_color.r, prism_color.g, prism_color.b, intensity * 0.20 * fade),
			maxf(1.0, radius * 0.0018),
			false
		)


## Poeira ambiente com movimento proprio de cada universo: orbital,
## ascendente, lateral ou em queda. Assim nem a camada de particulas
## fica igual entre duas telas.
## POEIRA ESPACIAL
##
## Antes eram 18 bolinhas em orbita fixa: cada uma girava para sempre no
## mesmo raio, com o mesmo tamanho e o mesmo brilho. Lia como "bolinhas
## dando volta", nao como espaco.
##
## Agora cada particula tem CICLO DE VIDA e PROFUNDIDADE. Ela nasce
## perto do centro, acelera para fora, cresce e clareia conforme se
## aproxima, e desvanece na borda — a leitura e a de estar atravessando
## um campo de estrelas. Tres camadas de paralaxe se movem em
## velocidades diferentes (as do fundo quase paradas, as da frente
## rapidas e riscadas), que e o que da a sensacao de volume.
##
## Cada universo escolhe o quanto a poeira espirala e o quanto ela
## corre, entao a mesma tecnica entrega leituras diferentes: a aura do
## dragon ball cospe faisca, a espiral do naruto arrasta tudo em
## redemoinho, o favo do soul quase nao se mexe.
const DUST_COUNT: int = 20
const COMET_COUNT: int = 2


## Ruido deterministico 0..1. Sem RandomNumberGenerator por quadro: a
## mesma particula fica sempre igual entre um quadro e o proximo.
func _hash01(value: float) -> float:
	return fposmod(absf(sin(value) * 43758.5453), 1.0)


## x = quanto a poeira espirala, y = velocidade do ciclo de vida.
func _dust_settings() -> Vector2:
	match _universe_style():
		"ki_aura":
			return Vector2(0.30, 0.34)
		"spiral_seal":
			return Vector2(1.35, 0.17)
		"portal_lab":
			return Vector2(0.62, 0.26)
		"breath_waves":
			return Vector2(0.14, 0.13)
		"moon_hive":
			return Vector2(0.08, 0.11)
		"rune_swarm":
			return Vector2(0.80, 0.15)
		"blade_shards":
			return Vector2(0.22, 0.29)
		_:
			return Vector2(0.42, 0.20)


func _draw_ambient_particles() -> void:
	var time_value: float = _idle_time()
	var beat: float = _beat_pulse()
	var settings: Vector2 = _dust_settings()
	var swirl: float = settings.x
	var speed: float = settings.y
	var limit: float = _universe_radius()
	var palette: Array[Color] = [_primary(), _secondary(), _accent()]

	for index in range(DUST_COUNT):
		var seed_value: float = float(index) * 12.9898 + 4.13
		var phase: float = _hash01(seed_value * 1.7)
		var depth: float = 0.24 + _hash01(seed_value * 3.1) * 0.76
		var direction_sign: float = -1.0 if index % 2 == 0 else 1.0

		# Camada de tras vive mais devagar; a da frente atravessa rapido.
		var life_speed: float = speed * (0.42 + depth * 1.05)
		var life: float = fposmod(time_value * life_speed + phase, 1.0)

		# O avanco e acelerado (expoente > 1): perto do centro a
		# particula quase nao anda e, chegando na borda, dispara. E esse
		# ganho de velocidade que o olho le como profundidade.
		var travel: float = pow(life, 1.30)
		var previous_travel: float = pow(maxf(life - 0.035, 0.0), 1.30)

		var base_angle: float = _hash01(seed_value * 2.3) * TAU
		var angle: float = base_angle + travel * swirl * direction_sign
		var previous_angle: float = base_angle + previous_travel * swirl * direction_sign

		var distance_value: float = limit * (0.05 + travel * 0.95)
		var previous_distance: float = limit * (0.05 + previous_travel * 0.95)
		if distance_value > limit:
			continue

		var position_value: Vector2 = center + Vector2(cos(angle), sin(angle)) * distance_value
		var trail_position: Vector2 = (
			center + Vector2(cos(previous_angle), sin(previous_angle)) * previous_distance
		)

		# Nasce e morre suave: nada aparece ou some de estalo.
		var fade: float = sin(PI * clampf(life, 0.0, 1.0))
		var twinkle: float = 0.5 + 0.5 * sin(time_value * (1.3 + depth * 2.4) + seed_value)
		var size: float = radius * (0.0013 + depth * 0.0030) * (0.55 + travel * 0.85)
		size += radius * beat * 0.0007 * depth

		# Longe = mais frio e apagado, perto = na cor do cenario e vivo.
		var particle_color: Color = palette[index % palette.size()].lerp(
			Color(0.72, 0.80, 1.0, 1.0),
			1.0 - depth
		)
		var alpha: float = fade * (0.20 + depth * 0.66)

		_target.draw_line(
			trail_position,
			position_value,
			Color(particle_color.r, particle_color.g, particle_color.b, alpha * 0.45),
			maxf(1.0, size * 0.80),
			false
		)

		# Halo so nas particulas da frente: nas do fundo ele nao apareceria
		# e custaria tres circulos preenchidos por quadro a toa.
		if depth > 0.62:
			_draw_soft_glow(
				position_value,
				size * 3.4,
				particle_color,
				alpha * (0.30 + twinkle * 0.28),
				2
			)

		_target.draw_circle(
			position_value,
			maxf(1.0, size),
			Color(particle_color.r, particle_color.g, particle_color.b, alpha * (0.55 + twinkle * 0.45)),
			true
		)
		if depth > 0.50:
			_target.draw_circle(
				position_value,
				maxf(1.0, size * 0.42),
				Color(1.0, 1.0, 1.0, alpha * (0.40 + twinkle * 0.50)),
				true
			)

	_draw_comets(time_value, limit)


## Duas riscas longas atravessando o campo de tempos em tempos. Sao o
## detalhe que tira a leitura de "campo uniforme" e faz a tela parecer
## viva sem custar quase nada (duas linhas por quadro).
func _draw_comets(time_value: float, limit: float) -> void:
	var accent: Color = _accent()
	for index in range(COMET_COUNT):
		var seed_value: float = float(index) * 31.7 + 9.1
		var cycle: float = fposmod(time_value * 0.085 + _hash01(seed_value), 1.0)
		# Fica invisivel a maior parte do ciclo: o cometa e evento, nao
		# elemento permanente.
		if cycle > 0.32:
			continue

		var progress: float = cycle / 0.32
		var entry_angle: float = _hash01(seed_value * 2.9) * TAU
		var sweep: float = 0.9 + _hash01(seed_value * 5.3) * 0.7
		var direction_sign: float = -1.0 if index % 2 == 0 else 1.0

		var start_point: Vector2 = center + Vector2(cos(entry_angle), sin(entry_angle)) * limit
		var exit_angle: float = entry_angle + PI * sweep * direction_sign
		var end_point: Vector2 = center + Vector2(cos(exit_angle), sin(exit_angle)) * limit

		var head: Vector2 = start_point.lerp(end_point, progress)
		var tail: Vector2 = start_point.lerp(end_point, maxf(progress - 0.14, 0.0))
		var fade: float = sin(PI * progress)

		_target.draw_line(
			tail,
			head,
			Color(accent.r, accent.g, accent.b, fade * 0.30),
			maxf(1.0, radius * 0.0030),
			false
		)
		_target.draw_line(
			tail.lerp(head, 0.55),
			head,
			Color(1.0, 1.0, 1.0, fade * 0.62),
			maxf(1.0, radius * 0.0018),
			false
		)
		_target.draw_circle(head, maxf(1.0, radius * 0.0030), Color(1.0, 1.0, 1.0, fade * 0.85), true)

func _draw_ring() -> void:
	var ring_radius: float = radius * 0.905
	var width: float = maxf(4.0, radius * 0.0072)
	# Alvo branco onde o tazo se encaixa: levemente ampliado para
	# dar mais presenca e deixar claro o ponto de acerto.
	var marker_radius: float = maxf(10.0, radius * 0.0330)
	var pulse: float = _beat_pulse()
	var primary: Color = _primary()
	var reaction: float = _hit_energy + _combo_energy * 0.26

	_target.draw_arc(
		center,
		ring_radius + radius * 0.004,
		0.0,
		TAU,
		56,
		Color(primary.r, primary.g, primary.b, 0.10 + pulse * 0.05 + reaction * 0.12),
		width * (3.4 + reaction * 1.6),
		true
	)
	_target.draw_arc(
		center,
		ring_radius,
		0.0,
		TAU,
		56,
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
		_target.draw_circle(
			position_value,
			marker_radius * (1.75 + lane_pulse * 0.55 + flash * 0.90),
			Color(glow_color.r, glow_color.g, glow_color.b, 0.08 + lane_pulse * 0.18 + flash_mix * 0.52),
			true
		)

		var core_color: Color = Color.WHITE.lerp(flash_color, minf(flash * 1.4, 1.0))
		var core_size: float = marker_radius * (1.0 + lane_pulse * 0.16 + flash * 0.32)

		# Miolo escuro + anel branco grosso: leitura de "alvo", bem
		# mais definida que um disco branco chapado.
		_target.draw_circle(position_value, core_size, Color(0.010, 0.016, 0.030, 0.92), true)
		_target.draw_arc(
			position_value,
			core_size * 0.80,
			0.0,
			TAU,
			22,
			core_color,
			maxf(2.0, core_size * 0.34),
			true
		)
		_target.draw_circle(position_value, core_size * 0.26, core_color, true)

		if flash > 0.02:
			# Arco de energia correndo pela linha, saindo do ponto
			# onde o tazo se encaixou — a assinatura visual do acerto
			# fica na propria linha, nao so num flash central.
			var arc_span: float = deg_to_rad(9.0 + flash * 30.0)
			var base_angle: float = (position_value - center).angle()
			_target.draw_arc(
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

			_target.draw_arc(
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
				lerpf(1.0, color.r, 0.82),
				lerpf(1.0, color.g, 0.82),
				lerpf(1.0, color.b, 0.82),
				fade
			)
			_target.draw_arc(
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
		# Tap e hold usam a mesma regra de cor: a do proprio objeto.
		var color: Color = TAP_PALETTE.color_for_index(int(event.get("color_index", 0)))
		var size: float = radius * (0.028 + progress * 0.032)
		_target.draw_arc(
			position_value,
			size,
			-PI * 0.5,
			-PI * 0.5 + TAU * progress,
			32,
			Color(color.r, color.g, color.b, 0.22 + progress * 0.62),
			maxf(2.0, radius * 0.006),
			true
		)


## HOLD — fita fina de energia.
##
## A versao anterior era uma barra grossa com cinco linhas empilhadas,
## chevrons e trilhos tracejados: pesada de ler e sem movimento proprio.
## Agora e um feixe fino com nucleo brilhante, um preenchimento que
## DRENA conforme o tempo passa (o quanto falta da nota fica obvio pelo
## proprio comprimento aceso) e pulsos curtos correndo em direcao ao
## alvo. A cauda desvanece em vez de terminar num disco.
##
## Nos ultimos instantes a fita ja comeca a recolher para dentro do
## alvo (_hold_release_ratio), entao quando o estouro entra ele nasce
## exatamente de onde a fita terminou — nao existe mais o salto de
## "barra cheia some / explosao aparece" que dava sensacao de travada.
const HOLD_RELEASE_SECONDS: float = 0.16


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

	var length: float = radius * 0.52
	if song_time >= hit_time:
		length = radius * maxf(0.06, 0.52 * (1.0 - hold_progress))

	# Recolhimento final: nos ultimos milissegundos a fita encolhe para
	# dentro do alvo, entregando a cena ao estouro sem corte seco.
	var release: float = _hold_release_ratio(end_time)
	length *= 1.0 - release

	var tail: Vector2 = head - direction * length
	var width: float = radius * 0.030 * float(difficulty.get("hold_width", 1.0))
	var holding: bool = bool(event.get("_holding", false))
	# A fita usa a cor do proprio hold (mesmo color_index dos taps), nao
	# mais um amarelo unico para todos.
	var color: Color = TAP_PALETTE.color_for_index(int(event.get("color_index", 0)))

	_draw_hold_ribbon(
		tail,
		head,
		width,
		color,
		holding,
		hold_progress,
		1.0 - release
	)


## 0 enquanto falta tempo, subindo ate 1 no instante em que a nota
## termina. E o que costura a fita ao estouro.
func _hold_release_ratio(end_time: float) -> float:
	var remaining: float = end_time - song_time
	if remaining >= HOLD_RELEASE_SECONDS:
		return 0.0
	return clampf(1.0 - remaining / HOLD_RELEASE_SECONDS, 0.0, 1.0)


func _draw_hold_ribbon(
	tail: Vector2,
	head: Vector2,
	half_width: float,
	color: Color,
	active: bool,
	progress: float,
	fade: float
) -> void:
	if fade <= 0.02:
		return

	var length: float = tail.distance_to(head)
	if length <= 0.5:
		return

	var direction: Vector2 = (head - tail) / length
	var normal := Vector2(-direction.y, direction.x)
	var pulse: float = 0.5 + 0.5 * sin(_idle_time() * (7.5 if active else 3.2))
	var highlight: Color = TAP_PALETTE.highlight(color)

	# Halo largo e suave em vez de contorno grosso: da presenca sem
	# engordar a forma.
	_target.draw_line(
		tail,
		head,
		Color(color.r, color.g, color.b, (0.16 if active else 0.09) * fade),
		half_width * (3.4 + pulse * 0.4),
		true
	)
	# Corpo fino.
	_target.draw_line(
		tail,
		head,
		Color(color.r, color.g, color.b, (0.62 if active else 0.40) * fade),
		half_width * 1.55,
		true
	)
	# Nucleo claro, bem estreito — e o que da a leitura "nitida".
	_target.draw_line(
		tail,
		head,
		Color(highlight.r, highlight.g, highlight.b, (0.95 if active else 0.62) * fade),
		maxf(1.5, half_width * 0.52),
		true
	)

	# Pulsos curtos correndo para o alvo. Substituem os chevrons e os
	# trilhos tracejados: metade dos tracos, muito mais movimento.
	var pulse_count: int = 3 if active else 2
	var phase: float = fmod(_idle_time() * (1.35 if active else 0.55), 1.0)
	for index in range(pulse_count):
		var travel: float = fmod(phase + float(index) / float(pulse_count), 1.0)
		var span: float = minf(length * 0.20, radius * 0.05)
		var pulse_head: Vector2 = tail.lerp(head, travel)
		var pulse_tail: Vector2 = pulse_head - direction * span
		var alpha: float = sin(PI * travel) * (0.85 if active else 0.40) * fade
		_target.draw_line(
			pulse_tail,
			pulse_head,
			Color(1.0, 1.0, 1.0, alpha),
			maxf(1.5, half_width * 0.44),
			true
		)

	# Cauda que desvanece: tres tracos curtos com alpha caindo, no lugar
	# do disco solido que fechava a fita antes.
	for index in range(3):
		var t: float = float(index) / 3.0
		var from: Vector2 = tail + direction * length * t * 0.10
		var to: Vector2 = tail + direction * length * (t + 0.33) * 0.10
		_target.draw_line(
			from,
			to,
			Color(color.r, color.g, color.b, (0.10 + t * 0.22) * fade),
			half_width * (1.0 + t * 0.4),
			true
		)

	_draw_hold_target(head, half_width, color, highlight, active, progress, fade, pulse)


## Alvo do hold: anel fino com arco de progresso. Sem miolo escuro
## chapado — o preenchimento e um brilho, entao o alvo nao vira um
## botao opaco em cima do cenario.
func _draw_hold_target(
	head: Vector2,
	half_width: float,
	color: Color,
	highlight: Color,
	active: bool,
	progress: float,
	fade: float,
	pulse: float
) -> void:
	var size: float = half_width * (1.75 + pulse * (0.12 if active else 0.04))

	_draw_soft_glow(head, size * 1.7, color, (0.30 if active else 0.16) * fade, 3)
	_target.draw_arc(
		head,
		size,
		0.0,
		TAU,
		40,
		Color(color.r, color.g, color.b, 0.42 * fade),
		maxf(1.5, half_width * 0.30),
		true
	)

	var shown: float = progress if progress > 0.0 else 1.0
	if shown > 0.001:
		_target.draw_arc(
			head,
			size,
			-PI * 0.5,
			-PI * 0.5 + TAU * shown,
			44,
			Color(highlight.r, highlight.g, highlight.b, (0.98 if active else 0.70) * fade),
			maxf(2.0, half_width * 0.40),
			true
		)

	_target.draw_circle(
		head,
		size * 0.26,
		Color(highlight.r, highlight.g, highlight.b, (0.95 if active else 0.55) * fade),
		true
	)

## O arrasto ainda tem imagem a mostrar? Vale enquanto o progresso
## desenhado nao alcancou o logico.
func _slide_still_running(event: Dictionary) -> bool:
	var target: float = clampf(float(event.get("_visual_progress", 0.0)), 0.0, 1.0)
	var drawn: float = clampf(float(event.get("_draw_progress", 0.0)), 0.0, 1.0)
	return drawn < target - 0.005


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

	# A trilha, as setas e a estrela saem na cor do proprio tazo que
	# gerou o arrasto (o realce e a mesma cor, so mais clara). Antes
	# tudo era ciano fixo, entao um arrasto vermelho aparecia azul.
	var color: Color = TAP_PALETTE.color_for_index(int(event.get("color_index", 0)))
	var accent: Color = TAP_PALETTE.highlight(color)
	var arrow_style: int = int(event.get("arrow_style", 0))
	var star_style: int = int(event.get("star_style", 0))
	# PROGRESSO LOGICO x PROGRESSO DESENHADO.
	#
	# _visual_progress e o valor da mecanica: ele salta (o avanco por
	# botao pula direto para o proximo ponto do caminho, e o ponteiro
	# pode varrer varios passos num quadro so). Desenhar esse valor cru
	# fazia a estrela teleportar — o movimento "acontecia do nada".
	#
	# _draw_progress persegue o valor logico com velocidade limitada,
	# entao a estrela SEMPRE percorre o trajeto: mesmo quando a mecanica
	# ja considerou a nota adiantada, o olho ve o gesto acontecendo.
	var target_progress: float = clampf(float(event.get("_visual_progress", 0.0)), 0.0, 1.0)
	var drawn_progress: float = clampf(float(event.get("_draw_progress", 0.0)), 0.0, 1.0)
	var active: bool = bool(event.get("_active", false))
	var arrows_from: float = drawn_progress if active else 0.0

	# Entrada por fade: a trilha e as setas nascem transparentes durante a
	# aproximacao e ganham corpo conforme a nota chega. Antes elas
	# apareciam inteiras de um quadro para o outro.
	var appear: float = 1.0
	if song_time < hit_time:
		appear = clampf(
			(song_time - (hit_time - approach)) / maxf(approach * 0.55, 0.001),
			0.0,
			1.0
		)
		appear = appear * appear * (3.0 - 2.0 * appear)

	# Depois de resolvido so a estrela termina o percurso: a trilha e as
	# setas ja cumpriram o papel e sairiam competindo com o estouro.
	var resolved: bool = bool(event.get("_resolved", false))
	if not resolved:
		_draw_slide_rail(points, color, appear)
		_draw_chevrons(points, lengths, arrows_from, color, accent, arrow_style, appear)

	var star_position: Vector2
	var tangent: Vector2
	var star_progress: float = drawn_progress

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
		star_position = PATH_BUILDER.point_at_cached(points, lengths, drawn_progress)
		tangent = PATH_BUILDER.tangent_at_cached(points, lengths, drawn_progress)

	if active:
		# O rastro cresce com a distancia que a estrela ainda tem para
		# recuperar: quanto mais ela esta "correndo", mais longo o
		# borrao, que e o que da leitura de velocidade.
		var chase: float = clampf(target_progress - drawn_progress, 0.0, 1.0)
		var ghost_step: float = 0.030 + chase * 0.075
		for ghost_index in range(1, 4):
			var ghost_progress: float = maxf(0.0, star_progress - float(ghost_index) * ghost_step)
			var ghost_position: Vector2 = PATH_BUILDER.point_at_cached(points, lengths, ghost_progress)
			var ghost_tangent: Vector2 = PATH_BUILDER.tangent_at_cached(points, lengths, ghost_progress)
			_draw_star(
				ghost_position,
				ghost_tangent.angle(),
				radius * (0.080 - float(ghost_index) * 0.008),
				Color(color.r, color.g, color.b, 0.14),
				Color(accent.r, accent.g, accent.b, 0.08),
				star_style
			)

	_draw_star(
		star_position,
		tangent.angle(),
		radius * 0.105 * float(difficulty.get("star_scale", 1.0)),
		color,
		accent,
		star_style
	)


func _draw_slide_rail(
	points: PackedVector2Array,
	color: Color,
	appear: float = 1.0
) -> void:
	if appear <= 0.02:
		return
	for index in range(points.size() - 1):
		_target.draw_line(
			points[index],
			points[index + 1],
			Color(0.0, 0.0, 0.0, 0.76 * appear),
			maxf(8.0, radius * 0.026),
			true
		)
		_target.draw_line(
			points[index],
			points[index + 1],
			Color(color.r, color.g, color.b, 0.16 * appear),
			maxf(3.0, radius * 0.008),
			true
		)


func _draw_chevrons(
	points: PackedVector2Array,
	lengths: Dictionary,
	start_progress: float,
	color: Color,
	accent: Color,
	style: int = 0,
	appear: float = 1.0
) -> void:
	if appear <= 0.02:
		return
	var size: float = radius * 0.058
	# O espacamento nasce do TAMANHO REAL da seta escolhida, com folga
	# de 35%. Antes era um valor fixo (0.052 * raio) menor que a propria
	# seta, entao elas se sobrepunham e o caminho virava uma mancha —
	# pior ainda no dardo, que e a silhueta mais comprida.
	var spacing: float = _arrow_footprint(style) * size * 1.55
	var estimated_length: float = float(lengths.get("total", 0.0))
	if estimated_length <= 0.0:
		for index in range(points.size() - 1):
			estimated_length += points[index].distance_to(points[index + 1])

	var count: int = maxi(3, int(floor(estimated_length / maxf(spacing, 1.0))))
	var start_index: int = clampi(int(floor(start_progress * float(count))), 0, count - 1)

	for index in range(start_index, count):
		var progress: float = (float(index) + 0.50) / float(count)
		var position_value: Vector2 = PATH_BUILDER.point_at_cached(points, lengths, progress)
		var tangent: Vector2 = PATH_BUILDER.tangent_at_cached(points, lengths, progress)
		var mix_value: float = 0.10 + 0.18 * float(index % 3)
		var arrow_color: Color = color.lerp(accent, mix_value)
		# As setas entram em cascata, da primeira para a ultima, em vez de
		# a trilha inteira surgir de uma vez.
		var stagger: float = clampf(
			appear * float(count) - float(index - start_index) * 0.55,
			0.0,
			1.0
		)
		if stagger <= 0.02:
			break
		arrow_color.a = stagger
		_draw_chevron(position_value, tangent, size, arrow_color, style)


## Comprimento que cada silhueta ocupa ao longo do caminho, em
## multiplos do tamanho base. Usado para espacar as setas sem palpite.
func _arrow_footprint(style: int) -> float:
	match posmod(style, TAP_PALETTE.ARROW_STYLE_COUNT):
		1:
			return 2.95
		2:
			return 2.00
		3:
			return 2.30
		_:
			return 2.10


## Quatro desenhos de seta. A cor sempre chega pronta de quem chamou
## (cor do tazo); aqui so muda a SILHUETA, para que dois arrastos
## seguidos nao pareçam a mesma nota repetida.
func _draw_chevron(
	position_value: Vector2,
	direction: Vector2,
	size: float,
	color: Color,
	style: int = 0
) -> void:
	var tangent: Vector2 = direction.normalized()
	var perpendicular := Vector2(-tangent.y, tangent.x)

	match posmod(style, TAP_PALETTE.ARROW_STYLE_COUNT):
		1:
			_draw_arrow_dart(position_value, tangent, perpendicular, size, color)
		2:
			_draw_arrow_double(position_value, tangent, perpendicular, size, color)
		3:
			_draw_arrow_feather(position_value, tangent, perpendicular, size, color)
		_:
			_draw_arrow_chevron(position_value, tangent, perpendicular, size, color)


## Estilo 0 — chevron cheio, a seta classica do jogo.
func _draw_arrow_chevron(
	position_value: Vector2,
	tangent: Vector2,
	perpendicular: Vector2,
	size: float,
	color: Color
) -> void:
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

	_fill_arrow_polygon(polygon, color, size)

	var highlight := PackedVector2Array([
		rear + perpendicular * half_height * 0.58,
		inner + perpendicular * half_height * 0.22,
		tip - tangent * length * 0.10,
	])
	_target.draw_polyline(
		highlight,
		TAP_PALETTE.highlight(color),
		maxf(2.0, size * 0.075),
		true
	)


## Estilo 1 — dardo: ponta longa e fina, com corte reto na traseira.
func _draw_arrow_dart(
	position_value: Vector2,
	tangent: Vector2,
	perpendicular: Vector2,
	size: float,
	color: Color
) -> void:
	var length: float = size * 2.95
	var half_height: float = size * 0.54

	var tip: Vector2 = position_value + tangent * length * 0.66
	var rear: Vector2 = position_value - tangent * length * 0.40

	var polygon := PackedVector2Array([
		tip,
		rear + perpendicular * half_height,
		rear + perpendicular * half_height * 0.30 - tangent * size * 0.30,
		rear - perpendicular * half_height * 0.30 - tangent * size * 0.30,
		rear - perpendicular * half_height,
	])

	_fill_arrow_polygon(polygon, color, size)

	_target.draw_line(
		rear + tangent * size * 0.10,
		tip - tangent * size * 0.30,
		TAP_PALETTE.highlight(color),
		maxf(2.0, size * 0.085),
		true
	)


## Estilo 2 — chevron duplo vazado: duas pontas em "V" seguidas.
func _draw_arrow_double(
	position_value: Vector2,
	tangent: Vector2,
	perpendicular: Vector2,
	size: float,
	color: Color
) -> void:
	var half_height: float = size * 0.86
	var highlight_color: Color = TAP_PALETTE.highlight(color)

	for wing in range(2):
		var offset: Vector2 = tangent * size * (0.62 - float(wing) * 0.86)
		var tip: Vector2 = position_value + offset + tangent * size * 0.52
		var left: Vector2 = position_value + offset - tangent * size * 0.42 + perpendicular * half_height
		var right: Vector2 = position_value + offset - tangent * size * 0.42 - perpendicular * half_height
		var stroke := PackedVector2Array([left, tip, right])

		_target.draw_polyline(
			stroke,
			Color(0.0, 0.0, 0.0, 0.92),
			maxf(6.0, size * 0.46),
			true
		)
		_target.draw_polyline(
			stroke,
			Color(color.r, color.g, color.b, color.a),
			maxf(3.5, size * 0.30),
			true
		)
		if wing == 0:
			_target.draw_polyline(
				stroke,
				Color(highlight_color.r, highlight_color.g, highlight_color.b, 0.85),
				maxf(1.5, size * 0.10),
				true
			)


## Estilo 3 — flecha com empena: haste central e duas asas curtas.
func _draw_arrow_feather(
	position_value: Vector2,
	tangent: Vector2,
	perpendicular: Vector2,
	size: float,
	color: Color
) -> void:
	var length: float = size * 2.30
	var half_height: float = size * 0.92

	var tip: Vector2 = position_value + tangent * length * 0.60
	var neck: Vector2 = position_value - tangent * length * 0.02
	var rear: Vector2 = position_value - tangent * length * 0.52

	var head := PackedVector2Array([
		tip,
		neck + perpendicular * half_height,
		neck + perpendicular * half_height * 0.30,
		neck - perpendicular * half_height * 0.30,
		neck - perpendicular * half_height,
	])
	_fill_arrow_polygon(head, color, size)

	_target.draw_line(
		rear,
		neck,
		Color(0.0, 0.0, 0.0, 0.92),
		maxf(5.0, size * 0.40),
		true
	)
	_target.draw_line(
		rear,
		neck,
		color,
		maxf(3.0, size * 0.24),
		true
	)

	var highlight_color: Color = TAP_PALETTE.highlight(color)
	for side in [-1.0, 1.0]:
		_target.draw_line(
			rear + perpendicular * half_height * 0.55 * side,
			rear + tangent * size * 0.58,
			Color(highlight_color.r, highlight_color.g, highlight_color.b, 0.90),
			maxf(1.5, size * 0.11),
			true
		)


## Preenchimento comum das setas solidas: sombra deslocada, corpo na
## cor do tazo e contorno escuro derivado da mesma cor.
func _fill_arrow_polygon(
	polygon: PackedVector2Array,
	color: Color,
	size: float
) -> void:
	var shadow_offset := Vector2(radius * 0.009, radius * 0.010)
	var shadow := PackedVector2Array()
	for point in polygon:
		shadow.append(point + shadow_offset)

	_target.draw_colored_polygon(shadow, Color(0.0, 0.0, 0.0, 0.96))
	_target.draw_colored_polygon(polygon, color)

	var outline := polygon.duplicate()
	outline.append(outline[0])
	var outline_color: Color = TAP_PALETTE.shade(color)
	_target.draw_polyline(
		outline,
		Color(outline_color.r, outline_color.g, outline_color.b, 0.98),
		maxf(5.0, size * 0.19),
		true
	)



## Quatro desenhos de estrela para a cabeca do arrasto. Assim como nas
## setas, so a forma muda: a cor vem do tazo e o realce e a mesma cor
## clareada, nunca um matiz de outra familia.
func _draw_star(
	position_value: Vector2,
	rotation_value: float,
	size: float,
	color: Color,
	accent: Color,
	style: int = 0
) -> void:
	var pulse: float = 0.5 + 0.5 * sin(_idle_time() * 9.0)
	var resolved_style: int = posmod(style, TAP_PALETTE.STAR_STYLE_COUNT)

	# Numero de pontas e proporcao interna definem a personalidade de
	# cada variacao: 5 pontas classica, 6 pontas de cristal, 4 pontas
	# de brilho alongado e 8 pontas de explosao.
	var spikes: int = 5
	var inner_ratio: float = 0.44
	match resolved_style:
		1:
			spikes = 6
			inner_ratio = 0.54
		2:
			# 4 pontas: a versao anterior usava cintura 0.26, tao fina
			# que os tres aneis concentricos se cruzavam e o desenho
			# saia embolado — parecia um X torto com um risco atravessado
			# por cima. Cintura mais aberta mantem a silhueta de brilho
			# e deixa os aneis empilhados sem se tocarem.
			spikes = 4
			inner_ratio = 0.40
		3:
			spikes = 8
			inner_ratio = 0.60

	var outer: PackedVector2Array = _star_points(
		size * (1.0 + pulse * 0.045),
		size * inner_ratio,
		rotation_value,
		position_value,
		spikes
	)
	var middle: PackedVector2Array = _star_points(
		size * 0.73,
		size * inner_ratio * 0.70,
		rotation_value,
		position_value,
		spikes
	)
	var inner: PackedVector2Array = _star_points(
		size * 0.48,
		size * inner_ratio * 0.45,
		rotation_value,
		position_value,
		spikes
	)
	outer.append(outer[0])
	middle.append(middle[0])
	inner.append(inner[0])

	# Brilho por tras da estrela — da mais definicao/profundidade em
	# vez de so linhas finas sobre o fundo.
	_draw_soft_glow(position_value, size * 1.55, color, 0.34 + pulse * 0.12, 3)

	_target.draw_polyline(outer, Color(0.0, 0.0, 0.0, 0.90), maxf(12.0, size * 0.30), true)
	_target.draw_polyline(outer, Color.WHITE, maxf(7.0, size * 0.16), true)
	# Com apenas quatro pontas os aneis internos ficam grudados no
	# contorno; a de 4 pontas leva so um anel de reforco.
	if resolved_style != 2:
		_target.draw_polyline(middle, color, maxf(5.0, size * 0.13), true)
	_target.draw_polyline(inner, accent, maxf(3.5, size * 0.10), true)

	# Detalhe exclusivo de cada variacao, ainda na cor do objeto.
	match resolved_style:
		1:
			# Cristal: eixos internos ligando pontas opostas.
			for axis in range(3):
				var axis_angle: float = rotation_value + PI * float(axis) / 3.0
				var axis_dir := Vector2(cos(axis_angle), sin(axis_angle))
				_target.draw_line(
					position_value - axis_dir * size * 0.62,
					position_value + axis_dir * size * 0.62,
					Color(accent.r, accent.g, accent.b, 0.55),
					maxf(1.5, size * 0.055),
					true
				)
		2:
			# Brilho: dois raios curtos SOBRE as pontas da estrela, nao
			# um risco solto atravessando o desenho. Assim o detalhe
			# reforca a silhueta em vez de brigar com ela.
			for axis in range(2):
				var flare_angle: float = rotation_value - PI * 0.5 + PI * float(axis) * 0.5
				var flare_dir := Vector2(cos(flare_angle), sin(flare_angle))
				_target.draw_line(
					position_value - flare_dir * size * 1.18,
					position_value + flare_dir * size * 1.18,
					Color(accent.r, accent.g, accent.b, 0.34 + pulse * 0.16),
					maxf(1.5, size * 0.050),
					true
				)
		3:
			# Explosao: anel fino amarrando as oito pontas.
			_target.draw_arc(
				position_value,
				size * inner_ratio * 1.06,
				0.0,
				TAU,
				28,
				Color(accent.r, accent.g, accent.b, 0.50),
				maxf(1.5, size * 0.050),
				true
			)

	_target.draw_circle(position_value, size * 0.18, Color(0.002, 0.006, 0.016, 0.96), true)
	_target.draw_circle(position_value, size * 0.10, Color.WHITE, true)
	_target.draw_circle(position_value, size * 0.045, accent, true)


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
			_draw_slide_burst(
				position_value,
				color,
				progress,
				life,
				rotation_value,
				int(effect.get("arrow_style", 0)),
				int(effect.get("star_style", 0))
			)
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
	_target.draw_circle(
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
		# Mantem a identidade cromatica do tazo. O branco entra apenas como
		# brilho, sem lavar um burst vermelho ate ele parecer rosa/branco.
		var layer_color: Color = color.lerp(
			Color.WHITE,
			0.28 - float(layer) * 0.045
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
				color.r,
				color.g,
				color.b,
				life * (0.76 - float(polygon_layer) * 0.18)
			),
			maxf(3.0, radius * 0.0070)
		)

func _draw_slide_burst(
	position_value: Vector2,
	color: Color,
	progress: float,
	life: float,
	rotation_value: float,
	arrow_style: int = 0,
	star_style: int = 0
) -> void:
	_draw_soft_glow(
		position_value,
		radius * (0.13 + progress * 0.20),
		color,
		life * 0.50,
		3
	)

	var spikes: int = 5
	var inner_ratio: float = 0.43
	match posmod(star_style, TAP_PALETTE.STAR_STYLE_COUNT):
		1:
			spikes = 6
			inner_ratio = 0.54
		2:
			spikes = 4
			inner_ratio = 0.26
		3:
			spikes = 8
			inner_ratio = 0.60

	for layer in range(4):
		var size: float = radius * (0.105 + float(layer) * 0.030)
		size *= 0.30 + progress * 1.10
		var points: PackedVector2Array = _star_points(
			size,
			size * inner_ratio,
			rotation_value + progress * (1.4 if layer % 2 == 0 else -1.1),
			position_value,
			spikes
		)
		points.append(points[0])
		_target.draw_polyline(
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
			Color(color.r, color.g, color.b, life * 0.72),
			arrow_style
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

	# Rastro de entrega: no primeiro terco do estouro ainda existe um
	# feixe curto vindo do centro, no lugar exato onde a fita acabou de
	# se recolher. E o que emenda o hold no efeito — sem ele a fita
	# sumia num quadro e a explosao aparecia no seguinte, e o olho lia
	# isso como engasgo mesmo com o jogo rodando liso.
	if progress < 0.34:
		var handoff: float = 1.0 - progress / 0.34
		var direction_in: Vector2 = (position_value - center).normalized()
		if direction_in.length_squared() > 0.001:
			var beam_length: float = radius * 0.085 * handoff
			var highlight: Color = TAP_PALETTE.highlight(color)
			_target.draw_line(
				position_value - direction_in * beam_length,
				position_value,
				Color(color.r, color.g, color.b, handoff * 0.55),
				maxf(2.0, radius * 0.010),
				true
			)
			_target.draw_line(
				position_value - direction_in * beam_length,
				position_value,
				Color(highlight.r, highlight.g, highlight.b, handoff * 0.85),
				maxf(1.5, radius * 0.0034),
				true
			)

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

	_target.draw_circle(
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
	_target.draw_line(
		position_value - a,
		position_value + a,
		Color(1.0, 0.08, 0.13, life),
		maxf(4.0, radius * 0.012),
		true
	)
	_target.draw_line(
		position_value - b,
		position_value + b,
		Color(1.0, 0.08, 0.13, life),
		maxf(4.0, radius * 0.012),
		true
	)
	_target.draw_arc(
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

	_target.draw_circle(
		position_value,
		outer_radius * 1.28,
		Color(color.r, color.g, color.b, 0.09),
		true
	)
	_target.draw_arc(
		position_value,
		outer_radius,
		0.0,
		TAU,
		40,
		Color.WHITE,
		maxf(2.0, radius * 0.0045),
		true
	)
	_target.draw_arc(
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
		_target.draw_line(
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
	_layers: int = 4
) -> void:
	if radius_value <= 0.0 or alpha <= 0.0:
		return
	if _glow_texture == null:
		_glow_texture = _build_glow_texture()

	# O parametro de camadas ficou sem uso (a textura ja tem o degrade
	# inteiro) mas continua na assinatura para nao quebrar as ~18
	# chamadas espalhadas pelo arquivo.
	var diameter: float = radius_value * 2.0
	_target.draw_texture_rect(
		_glow_texture,
		Rect2(
			position_value - Vector2(radius_value, radius_value),
			Vector2(diameter, diameter)
		),
		false,
		Color(color.r, color.g, color.b, clampf(alpha * 0.92, 0.0, 1.0))
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
	_target.draw_polyline(points, color, width, true)


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
	_target.draw_polyline(points, color, width, true)


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
	_target.draw_polyline(points, color, width, true)


func _star_points(
	outer_radius: float,
	inner_radius: float,
	rotation_value: float,
	position_value: Vector2,
	spikes: int = 5
) -> PackedVector2Array:
	var point_count: int = maxi(spikes, 3) * 2
	var points := PackedVector2Array()
	for index in range(point_count):
		var angle: float = (
			rotation_value
			- PI * 0.5
			+ TAU * float(index) / float(point_count)
		)
		var point_radius: float = outer_radius if index % 2 == 0 else inner_radius
		points.append(position_value + Vector2(cos(angle), sin(angle)) * point_radius)
	return points
