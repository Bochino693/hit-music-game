extends RefCounted
## Ritmo de uma musica, derivado do BPM.
##
## REVISAO R13 — jogabilidade da mesa fisica.
##
## O que mudou em relacao a versao anterior e POR QUE:
##
## 1. JANELAS DE ACERTO. O dificil usava beat*0.30 (0.13s a 140 BPM).
##    Essa mesma janela e a que o stage usa em _is_selectable para
##    decidir se um ARRASTO ainda pode ser INICIADO — ou seja, o
##    jogador tinha 130ms para encostar o dedo no ponto certo antes de
##    a nota morrer. Era isso que fazia o arrasto "durar pouco tempo
##    para acionar". Agora o dificil abre em beat*0.42 e o facil em
##    beat*0.58.
##
## 2. MOVIMENTO DE MAO. O padrao de lanes era gerado por passo coprimo
##    de 8 (3 no facil, 5 no dificil). Passo 5 num anel de 8 e o mesmo
##    que -3: cada nota jogava a mao 135 graus para o lado CONTRARIO ao
##    da nota anterior. Com o dificil colocando nota a cada colcheia
##    (~3.8 notas/s a 140 BPM), a mao teria que atravessar 135 graus em
##    260ms, nota apos nota — impossivel, nao dificil. Agora os padroes
##    sao listas de DESLOCAMENTO: o normal e andar 1 lane por nota
##    (botao vizinho), com saltos de 2 pontuais e um unico salto de 3
##    por ciclo no dificil. Os dois padroes continuam visitando as oito
##    lanes, entao nenhum tazo fica parado a musica inteira.
##
## 3. ARRASTOS SEM CONTRAMAO. O dificil trazia "hook" (curva 0.80, que
##    volta por tras do ponto de partida) e "arc_ccw" (arco pelo lado
##    longo). Os dois desenham um trajeto que vai no sentido oposto ao
##    da linha reta entre os dois tazos — o dedo tem que sair para um
##    lado para chegar no outro. Sairam. Todo arrasto agora avanca no
##    mesmo sentido de rotacao.
##
## 4. TEMPO PARA COMPLETAR O ARRASTO. slide_beats subiu (3 -> 4 no
##    dificil, 4 -> 5 no facil): o gesto de tres pontos do dificil nao
##    cabia em 1.3s de varredura mais os 0.28s de folga do stage.
##
## O JSON da musica continua mandando: qualquer chave presente em
## song["easy"] / song["hard"] sobrescreve o valor derivado aqui.

const BEATS_PER_BAR: int = 4
const NUM_LANES: int = 8

## Faixa de BPM tratada como valida. Fora dela o valor e dobrado ou
## partido pela metade ate cair dentro, senao uma musica de 78 BPM fica
## com notas raras demais e uma de 190 vira metralhadora.
const MIN_MUSICAL_BPM: float = 88.0
const MAX_MUSICAL_BPM: float = 178.0

## ─────────────────────────────────────────────────────────────────
## AJUSTE DE OPERADOR — mexa aqui se a mesa continuar pesada ou ficar
## facil demais depois do teste.
##
## HARD_GRID_BEATS: passo da grade do dificil.
##   0.5  = colcheia (padrao). Aceita contratempo, ~3.8 notas/s a 140.
##   0.75 = colcheia pontuada. Tira quase todo o contratempo.
##   1.0  = so batida cheia. Metade das notas; usa isto se o gabinete
##          estiver na rua com publico casual.
const HARD_GRID_BEATS: float = 0.5

## Multiplicador global das janelas. 1.0 = como esta abaixo. Suba para
## 1.15/1.25 se o toque da tela estiver com atraso de leitura; desca
## para 0.9 se quiser cobrar mais precisao.
const WINDOW_SCALE: float = 1.0
## ─────────────────────────────────────────────────────────────────

## Deslocamento de lane por nota. Positivo gira num sentido, negativo
## no outro. O que importa aqui e o TAMANHO do salto: 1 = botao ao
## lado, 2 = pula um, 3 = a mao precisa mesmo se deslocar. Trocas de
## sinal existem para a mao nao ficar so girando, mas nunca em duas
## notas seguidas de salto grande.
const LANE_STEPS_EASY: Array[int] = [
	1, 1, -1, 2, 1, -1, -1, 2, 1, 1, -2, 1, 1, -1, 2, -1,
]
const LANE_STEPS_HARD: Array[int] = [
	1, 1, 2, -1, 1, 1, -2, 1, 1, 3, -1, -1,
	1, 2, -1, 1, 1, -2, -1, 1, 2, 1, -1, 1,
]


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
	#
	# O piso do dificil subiu de 0.58 para 0.66: com 0.58 e a mesa
	# cheia de nota o tazo nascia praticamente em cima do anel.
	var approach: float = (
		clampf(beat * 2.8, 0.66, 1.24)
		if hard
		else clampf(beat * 3.4, 0.78, 1.58)
	)

	# As janelas seguem a batida (musica lenta tem batida larga e pode
	# tolerar mais sem ficar frouxa), mas com piso bem mais alto do que
	# antes. Esta janela nao serve so para pontuar o tap: e ela que
	# define por quanto tempo um ARRASTO aceita ser iniciado.
	var hit_window: float = clampf(
		beat * (0.42 if hard else 0.58) * WINDOW_SCALE,
		0.15 * WINDOW_SCALE,
		0.34 * WINDOW_SCALE
	)
	var perfect_window: float = clampf(hit_window * 0.38, 0.050, 0.13)

	var profile: Dictionary = {
		"bpm": bpm,
		"beat": beat,
		"approach": approach,
		"hit_window": hit_window,
		"perfect_window": perfect_window,
		# Grade de colocacao: o facil pisa de batida em batida, o
		# dificil desce ate a colcheia (ver HARD_GRID_BEATS).
		"grid_beats": HARD_GRID_BEATS if hard else 1.0,
		"bars_per_phrase": 4,
		"tap_scale": 1.02 if hard else 1.08,
		"star_scale": 1.04 if hard else 1.08,
		"hold_width": 0.92 if hard else 1.0,
		"background_intensity": 0.22 if hard else 0.13,
		"background_speed": 0.28 if hard else 0.13,
		# Tempo de vida do gesto longo. O stage marca erro em
		# end_time + 0.28s; com 3 batidas o zigue-zague de tres pontos
		# do dificil pedia uma varredura de mao impossivel.
		"slide_beats": 4.0 if hard else 5.0,
		"hold_beats": 3.5 if hard else 4.5,
		# Par de duas maos: lanes em lados opostos da mesa.
		"double_distance": 4,
	}

	# O JSON manda: qualquer chave presente sobrescreve a derivada.
	var configured: Variant = song.get("hard" if hard else "easy", {})
	if configured is Dictionary:
		for key in (configured as Dictionary).keys():
			profile[str(key)] = (configured as Dictionary)[key]

	return profile


## Sequencia de lanes.
##
## Antes: passo fixo coprimo de 8, o que garantia cobertura das oito
## lanes mas jogava a mao de um lado a outro da mesa a cada nota.
## Agora: soma de deslocamentos curtos. A cobertura das oito lanes
## continua garantida (as duas listas foram conferidas a partir de
## qualquer lane inicial), mas o percurso e continuo — o jogador anda
## pela mesa em vez de saltar por ela.
static func lane_pattern(song: Dictionary, difficulty_name: String) -> Array:
	var hard: bool = difficulty_name.to_lower() == "hard"
	var configured: Variant = song.get(
		"lane_pattern_hard" if hard else "lane_pattern_easy",
		[]
	)
	if configured is Array and not (configured as Array).is_empty():
		return (configured as Array).duplicate(true)

	var steps: Array[int] = LANE_STEPS_HARD if hard else LANE_STEPS_EASY
	var seed_value: int = absi(int(song.get("seed", 1001)))
	# A semente so escolhe ONDE o percurso comeca e para que lado ele
	# gira. O desenho do movimento e o mesmo, entao a mao aprende o
	# gesto e a musica muda a posicao — nao o contrario.
	var direction: int = 1 if seed_value % 2 == 0 else -1
	var lane: int = seed_value % NUM_LANES

	var pattern: Array = [lane]
	for index in range(steps.size() - 1):
		lane = posmod(lane + steps[index] * direction, NUM_LANES)
		pattern.append(lane)
	return pattern


## Desenhos de arrasto.
##
## Regra nova: todo trajeto avanca no MESMO sentido de rotacao da mesa
## e nunca volta por tras do ponto de partida. Sairam o "hook" (curva
## 0.80, que obriga o dedo a sair para um lado antes de ir para o
## outro) e o "arc_ccw" (arco pelo lado longo do circulo) — eram os
## dois gestos de contramao.
##
## O facil so recebe trajeto reto e um arco suave; o dificil recebe
## zigue-zague de tres pontos e travessia pelo centro, que sao gestos
## mais longos mas continuam legiveis num relance.
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
			# Tres pontos andando sempre para frente, 90 graus por perna.
			{
				"path": [base, posmod(base + 2, NUM_LANES), posmod(base + 4, NUM_LANES)],
				"shape": "zigzag",
			},
			# Travessia reta pelo centro: leitura instantanea.
			{
				"path": [posmod(base + 1, NUM_LANES), posmod(base + 5, NUM_LANES)],
				"shape": "cross",
			},
			# Arco curto acompanhando a borda, no mesmo sentido.
			{
				"path": [posmod(base + 3, NUM_LANES), posmod(base + 6, NUM_LANES)],
				"shape": "arc_cw",
				"curve": 0.42,
			},
			{
				"path": [posmod(base + 5, NUM_LANES), posmod(base + 7, NUM_LANES), posmod(base + 1, NUM_LANES)],
				"shape": "zigzag",
			},
		]

	return [
		{
			"path": [base, posmod(base + 4, NUM_LANES)],
			"shape": "straight",
		},
		{
			"path": [posmod(base + 2, NUM_LANES), posmod(base + 5, NUM_LANES)],
			"shape": "arc_cw",
			"curve": 0.38,
		},
		{
			"path": [posmod(base + 6, NUM_LANES), posmod(base + 2, NUM_LANES)],
			"shape": "straight",
		},
	]
