extends RefCounted
## Ritmo de uma musica, derivado do BPM.
##
## Uma tela nova precisa informar so o essencial (id, titulo, audio,
## video, capa e bpm). Tudo que define COMO ela se joga — velocidade de
## aproximacao, janelas de acerto, densidade de notas, sequencia de
## lanes e desenhos de arrasto — nasce daqui a partir do BPM, e o JSON
## so precisa aparecer quando o operador quiser ajustar alguma coisa
## na mao. O que vier no JSON sempre vence o valor derivado.
##
## As duas dificuldades NAO compartilham desenho: o facil anda em
## semininimas/minimas e cai nas batidas fortes do compasso; o
## dificil anda em colcheias, usa contratempo e sincopa. Por isso as
## fases sao diferentes de verdade, e nao "a mesma fase com menos
## notas".

const BEATS_PER_BAR: int = 4
const NUM_LANES: int = 8

## Faixa de BPM tratada como valida. Fora dela o valor e dobrado ou
## partido pela metade ate cair dentro, senao uma musica de 78 BPM fica
## com notas raras demais e uma de 190 vira metralhadora.
const MIN_MUSICAL_BPM: float = 88.0
const MAX_MUSICAL_BPM: float = 178.0


## BPM efetivo para o desenho ritmico. Preserva a pulsacao da musica
## (dobrar/dividir mantem o mesmo compasso), so escolhe a oitava
## ritmica que rende uma leitura jogavel.
static func musical_bpm(raw_bpm: float) -> float:
	var value: float = maxf(raw_bpm, 1.0)
	var guard: int = 0
	while value < MIN_MUSICAL_BPM and guard < 6:
		value *= 2.0
		guard += 1
	guard = 0
	while value > MAX_MUSICAL_BPM and guard < 6:
		value *= 0.5
		guard += 1
	return value


## Perfil completo de uma dificuldade. Comeca derivado do BPM e recebe
## por cima o que a musica tiver definido no JSON.
static func build(song: Dictionary, difficulty_name: String) -> Dictionary:
	var hard: bool = difficulty_name.to_lower() == "hard"
	var raw_bpm: float = maxf(float(song.get("bpm", 120.0)), 1.0)
	var bpm: float = musical_bpm(raw_bpm)
	var beat: float = 60.0 / bpm

	# Musica rapida precisa de mais tempo de leitura por nota, senao o
	# tazo cruza o circulo antes do olho acompanhar. A aproximacao anda
	# em batidas, nao em segundos fixos: assim toda musica da o mesmo
	# "numero de batidas de aviso" antes da nota chegar.
	# Os limites sao separados por dificuldade de proposito: com um teto
	# unico, uma musica lenta batia no mesmo teto nas duas fases e o
	# dificil deixava de ser mais rapido que o facil.
	var approach: float = (
		clampf(beat * 2.6, 0.58, 1.20)
		if hard
		else clampf(beat * 3.4, 0.72, 1.58)
	)

	# As janelas tambem seguem a batida: em musica lenta a batida e
	# larga e a tolerancia pode ser maior sem ficar frouxa.
	var hit_window: float = clampf(beat * (0.30 if hard else 0.46), 0.11, 0.30)
	var perfect_window: float = clampf(hit_window * 0.40, 0.045, 0.12)

	var profile: Dictionary = {
		"bpm": bpm,
		"beat": beat,
		"approach": approach,
		"hit_window": hit_window,
		"perfect_window": perfect_window,
		# Grade de colocacao: o facil pisa de meia em meia batida no
		# maximo, o dificil chega a colcheia.
		"grid_beats": 0.5 if hard else 1.0,
		"bars_per_phrase": 4,
		"tap_scale": 0.98 if hard else 1.08,
		"star_scale": 1.0 if hard else 1.08,
		"hold_width": 0.88 if hard else 1.0,
		"background_intensity": 0.22 if hard else 0.13,
		"background_speed": 0.28 if hard else 0.13,
		"slide_beats": 3.0 if hard else 4.0,
		"hold_beats": 3.0 if hard else 4.0,
	}

	# O JSON manda: qualquer chave presente sobrescreve a derivada.
	var configured: Variant = song.get("hard" if hard else "easy", {})
	if configured is Dictionary:
		for key in (configured as Dictionary).keys():
			profile[str(key)] = (configured as Dictionary)[key]

	return profile


## Sequencia de lanes. Se a musica nao trouxer a sua, gera uma a partir
## da semente: passos coprimos de 8 fazem a mao circular pelo gabinete
## inteiro sem repetir vizinho, e o facil recebe um passo mais curto
## (movimento mais calmo) que o dificil.
static func lane_pattern(song: Dictionary, difficulty_name: String) -> Array:
	var hard: bool = difficulty_name.to_lower() == "hard"
	var configured: Variant = song.get(
		"lane_pattern_hard" if hard else "lane_pattern_easy",
		[]
	)
	if configured is Array and not (configured as Array).is_empty():
		return (configured as Array).duplicate(true)

	# Passo COPRIMO de 8 (3 ou 5): garante que a sequencia visite as oito
	# lanes antes de repetir, entao o gabinete inteiro e usado. Passo 2
	# ou 4 fecharia o ciclo em 4 lanes e metade dos botoes ficaria
	# parada a musica toda. O facil anda de 3 em 3 (salto medio) e o
	# dificil de 5 em 5 (salto largo, mao atravessa mais).
	var seed_value: int = absi(int(song.get("seed", 1001)))
	var step: int = 5 if hard else 3
	var start: int = seed_value % NUM_LANES
	var length: int = 16 if hard else 12
	var pattern: Array = []
	for index in range(length):
		pattern.append(posmod(start + index * step, NUM_LANES))
	return pattern


## Desenhos de arrasto. Sem configuracao, monta um conjunto proprio
## para a dificuldade: o facil so recebe tracos simples atravessando o
## circulo, o dificil ganha curvas e zigue-zague de tres pontos.
static func slide_patterns(song: Dictionary, difficulty_name: String) -> Array:
	var hard: bool = difficulty_name.to_lower() == "hard"
	var configured: Variant = song.get(
		"slides_hard" if hard else "slides_easy",
		[]
	)
	if configured is Array and not (configured as Array).is_empty():
		return (configured as Array).duplicate(true)

	var seed_value: int = absi(int(song.get("seed", 1001)))
	var base: int = seed_value % NUM_LANES
	if hard:
		return [
			{
				"path": [base, posmod(base + 3, NUM_LANES), posmod(base + 6, NUM_LANES)],
				"shape": "zigzag",
			},
			{"path": [posmod(base + 1, NUM_LANES), posmod(base + 6, NUM_LANES)], "shape": "cross"},
			{
				"path": [posmod(base + 5, NUM_LANES), posmod(base + 1, NUM_LANES)],
				"shape": "hook",
				"curve": 0.80,
			},
			{
				"path": [posmod(base + 2, NUM_LANES), posmod(base + 7, NUM_LANES)],
				"shape": "arc_ccw",
				"curve": 0.74,
			},
		]

	return [
		{"path": [base, posmod(base + 4, NUM_LANES)], "shape": "straight"},
		{
			"path": [posmod(base + 2, NUM_LANES), posmod(base + 6, NUM_LANES)],
			"shape": "arc_cw",
			"curve": 0.55,
		},
		{"path": [posmod(base + 7, NUM_LANES), posmod(base + 3, NUM_LANES)], "shape": "cross"},
	]
