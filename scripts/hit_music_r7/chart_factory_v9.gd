extends RefCounted
## Gerador de fases. Trabalha em COMPASSOS, nao em "um evento a cada N".
##
## Toda nota cai exatamente numa subdivisao da batida derivada do BPM da
## musica (ver rhythm_profile.gd), entao a jogada soa junto com a
## bateria em vez de escorregar por cima dela.
##
## A musica e dividida em FRASES de 4 compassos e cada frase recebe um
## arquetipo sorteado (corrida de taps, quebra com hold, virada com
## arrasto, par de maos, misto). E isso que mistura as jogadas: antes o
## tipo saia de "indice % slide_every", o que produzia sempre o mesmo
## desenho na mesma ordem. Agora a mesma musica tem frases com cara
## diferente e as duas dificuldades desenham fases distintas — o facil
## anda em batidas inteiras e cai nos tempos fortes, o dificil anda em
## colcheias e usa contratempo.

const TAP_PALETTE: Script = preload("res://scripts/hit_music_r7/tap_palette.gd")
const RHYTHM: Script = preload("res://scripts/hit_music_r7/rhythm_profile.gd")

const NUM_LANES: int = 8
const BEATS_PER_BAR: float = 4.0

## Arquetipos de frase. O peso muda entre facil e dificil, entao a
## mesma musica nao entrega a mesma sequencia nas duas fases.
const PHRASE_RUN: int = 0
const PHRASE_HOLD_BREAK: int = 1
const PHRASE_SLIDE_TURN: int = 2
const PHRASE_DOUBLE_HIT: int = 3
const PHRASE_MIXED: int = 4


static func build(song: Dictionary, difficulty_name: String, duration: float) -> Array:
	var hard: bool = difficulty_name.to_lower() == "hard"
	var profile: Dictionary = RHYTHM.build(song, difficulty_name)

	var beat: float = maxf(float(profile.get("beat", 0.5)), 0.05)
	var bar: float = beat * BEATS_PER_BAR
	var grid_beats: float = maxf(float(profile.get("grid_beats", 1.0)), 0.25)
	var bars_per_phrase: int = maxi(int(profile.get("bars_per_phrase", 4)), 1)

	var start_time: float = maxf(float(song.get("chart_start", 4.0)), 3.2)
	var end_time: float = maxf(start_time + bar, duration - 2.2)

	var lane_pattern: Array = RHYTHM.lane_pattern(song, difficulty_name)
	if lane_pattern.is_empty():
		lane_pattern = [0, 2, 4, 6, 1, 3, 5, 7]
	var slide_patterns: Array = RHYTHM.slide_patterns(song, difficulty_name)

	# Semente separada por dificuldade: o sorteio de frases do dificil
	# nunca repete o do facil, mesmo com a mesma musica.
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(int(song.get("seed", 1001))) * 7919 + (104729 if hard else 15485863)

	var slide_beats: float = maxf(float(profile.get("slide_beats", 3.0)), 1.0)
	var hold_beats: float = maxf(float(profile.get("hold_beats", 3.0)), 1.0)
	var double_distance: int = clampi(int(profile.get("double_distance", 4)), 1, 7)

	# Densidade herdada do JSON (slide_every/hold_every continuam
	# valendo como ajuste do operador): vira a chance de uma frase
	# receber aquele tipo de jogada.
	var slots_per_bar: float = BEATS_PER_BAR / grid_beats
	var slots_per_phrase: float = slots_per_bar * float(bars_per_phrase)
	var slide_weight: float = _density_weight(profile, "slide_every", slots_per_phrase, 1.30)
	var hold_weight: float = _density_weight(profile, "hold_every", slots_per_phrase, 1.10)
	var double_weight: float = 0.0
	if hard:
		double_weight = _density_weight(profile, "double_every", slots_per_phrase, 1.20)
	var previous_archetype: int = -1

	var events: Array = []
	var note_index: int = 0
	var slide_index: int = 0
	var phrase_index: int = 0

	# A posicao na grade e contada em SLOTS INTEIROS, nao somando
	# segundos. Somar beat*grid_beats centenas de vezes acumula erro de
	# ponto flutuante, e ai "isto e uma batida forte?" comeca a falhar
	# no meio da musica — a nota sairia do compasso justamente onde o
	# jogador mais sente. Com indice inteiro, cada instante e calculado
	# de uma vez a partir do inicio da frase e a grade nunca escorrega.
	var slots_per_bar_int: int = maxi(int(round(BEATS_PER_BAR / grid_beats)), 1)
	var slots_in_phrase: int = slots_per_bar_int * bars_per_phrase

	while true:
		var phrase_start: float = start_time + bar * float(bars_per_phrase * phrase_index)
		if phrase_start >= end_time:
			break

		var archetype: int = _pick_archetype(
			rng,
			hard,
			phrase_index,
			previous_archetype,
			slide_weight,
			hold_weight,
			double_weight
		)
		previous_archetype = archetype

		# Slot reservado para a jogada especial: ultimo compasso da
		# frase, na batida 1 ou 3 — e onde a musica costuma abrir espaco
		# para um gesto longo.
		var special_slot: int = (
			slots_in_phrase
			- slots_per_bar_int
			+ (0 if rng.randf() < 0.6 else int(round(2.0 / grid_beats)))
		)
		var special_done: bool = false

		var slot: int = 0
		while slot < slots_in_phrase:
			var beats_in_phrase: float = float(slot) * grid_beats
			var slot_time: float = phrase_start + beat * beats_in_phrase
			if slot_time >= end_time:
				break

			var beat_in_bar: float = fposmod(beats_in_phrase, BEATS_PER_BAR)

			if not _slot_is_active(rng, hard, archetype, beat_in_bar):
				slot += 1
				continue

			var base_lane: int = posmod(
				int(lane_pattern[note_index % lane_pattern.size()]),
				NUM_LANES
			)

			# A jogada especial da frase entra na primeira posicao valida
			# depois do instante reservado.
			var wants_special: bool = not special_done and slot >= special_slot

			if wants_special and _archetype_uses_slide(archetype) and not slide_patterns.is_empty():
				var pattern_value: Variant = slide_patterns[slide_index % slide_patterns.size()]
				if pattern_value is Dictionary:
					var pattern: Dictionary = (pattern_value as Dictionary).duplicate(true)
					var path: Array = _array_value(pattern.get("path", []))
					if path.size() >= 2:
						events.append({
							"type": "slide",
							"time": slot_time,
							"end_time": minf(slot_time + beat * slide_beats, end_time + beat),
							"path": path,
							"shape": str(pattern.get("shape", "straight")),
							"curve": float(pattern.get("curve", 0.55)),
							"color_index": note_index % 3,
							"arrow_style": TAP_PALETTE.arrow_style_for(slide_index),
							"star_style": TAP_PALETTE.star_style_for(slide_index * 3 + 1),
							"phrase": phrase_index,
						})
						slide_index += 1
						note_index += 1
						special_done = true
						# O arrasto ocupa varias batidas: pula os slots
						# dele para nao empilhar tap por cima do gesto.
						slot += maxi(int(ceil(slide_beats / grid_beats)), 1)
						continue

			if wants_special and _archetype_uses_hold(archetype):
				events.append({
					"type": "hold",
					"time": slot_time,
					"end_time": minf(slot_time + beat * hold_beats, end_time + beat),
					"lane": base_lane,
					"color_index": note_index % 3,
					"phrase": phrase_index,
				})
				note_index += 1
				special_done = true
				slot += maxi(int(ceil(hold_beats / grid_beats)), 1)
				continue

			events.append({
				"type": "tap",
				"time": slot_time,
				"lane": base_lane,
				"color_index": note_index % 3,
				"phrase": phrase_index,
			})

			# Par de maos: so no dificil, e so na batida forte, para
			# continuar tocavel com as duas maos.
			if (
				archetype == PHRASE_DOUBLE_HIT
				and _on_subdivision(beat_in_bar, 2.0)
				and rng.randf() < 0.72
			):
				events.append({
					"type": "tap",
					"time": slot_time,
					"lane": posmod(base_lane + double_distance, NUM_LANES),
					"color_index": (note_index + 1) % 3,
					"phrase": phrase_index,
					"two_hand_pair": true,
				})

			note_index += 1
			slot += 1

		phrase_index += 1

	events.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var time_a: float = float(a.get("time", 0.0))
			var time_b: float = float(b.get("time", 0.0))
			if is_equal_approx(time_a, time_b):
				return int(a.get("lane", 0)) < int(b.get("lane", 0))
			return time_a < time_b
	)

	return events


## Converte "uma jogada a cada N notas" (ajuste antigo do JSON) no PESO
## daquele tipo de frase no sorteio. Peso, e nao probabilidade direta:
## assim o ajuste do operador continua valendo sem que um valor baixo
## faca um unico arquetipo dominar a musica inteira.
static func _density_weight(
	profile: Dictionary,
	key: String,
	slots_per_phrase: float,
	fallback: float
) -> float:
	var every: int = int(profile.get(key, 0))
	if every <= 0:
		return fallback
	return clampf(slots_per_phrase / float(every), 0.35, 1.60)


## Sorteio ponderado dos cinco arquetipos. Repetir o arquetipo anterior
## paga uma penalidade forte, entao a musica alterna entre corrida,
## quebra, virada e par de maos em vez de encadear tres frases iguais.
static func _pick_archetype(
	rng: RandomNumberGenerator,
	hard: bool,
	phrase_index: int,
	previous: int,
	slide_weight: float,
	hold_weight: float,
	double_weight: float
) -> int:
	# A primeira frase e sempre corrida limpa: o jogador entra na musica
	# sem levar um gesto longo de cara.
	if phrase_index == 0:
		return PHRASE_RUN

	var weights: Array[float] = [
		1.40,
		hold_weight,
		slide_weight,
		double_weight,
		0.55 if hard else 0.38,
	]

	if previous >= 0 and previous < weights.size():
		weights[previous] *= 0.28

	var total: float = 0.0
	for weight in weights:
		total += weight
	if total <= 0.0:
		return PHRASE_RUN

	var roll: float = rng.randf() * total
	var accumulated: float = 0.0
	for index in range(weights.size()):
		accumulated += weights[index]
		if roll <= accumulated:
			return index
	return PHRASE_RUN


static func _archetype_uses_slide(archetype: int) -> bool:
	return archetype == PHRASE_SLIDE_TURN or archetype == PHRASE_MIXED


static func _archetype_uses_hold(archetype: int) -> bool:
	return archetype == PHRASE_HOLD_BREAK or archetype == PHRASE_MIXED


## Decide se a posicao da grade vira nota. E aqui que as duas fases se
## separam de verdade: o facil so aceita tempo forte (1 e 3, com 2 e 4
## em frase corrida), o dificil aceita as quatro batidas e ainda abre
## contratempo em colcheia.
static func _slot_is_active(
	rng: RandomNumberGenerator,
	hard: bool,
	archetype: int,
	beat_in_bar: float
) -> bool:
	var on_beat: bool = _on_subdivision(beat_in_bar, 1.0)
	var strong: bool = _on_subdivision(beat_in_bar, 2.0)

	if not hard:
		if not on_beat:
			return false
		if strong:
			return true
		# Batidas 2 e 4 entram nas frases corridas e, de vez em quando,
		# nas outras — e o que da respiro entre um gesto e outro.
		if archetype == PHRASE_RUN:
			return true
		return rng.randf() < 0.45

	if on_beat:
		return true
	# Contratempo (colcheia): denso na corrida, esparso quando a frase
	# ja tem um gesto longo para executar.
	if archetype == PHRASE_RUN:
		return rng.randf() < 0.62
	if archetype == PHRASE_DOUBLE_HIT:
		return rng.randf() < 0.30
	return rng.randf() < 0.42


## "Este instante cai numa subdivisao de tamanho step?" Testa os dois
## lados do resto: fposmod(3.9999, 1.0) devolve 0.9999, que tambem e
## uma batida cheia — comparar so com zero deixaria passar como
## contratempo uma nota que esta exatamente na batida.
static func _on_subdivision(beat_in_bar: float, step: float) -> bool:
	var remainder: float = fposmod(beat_in_bar, step)
	return remainder < 0.0005 or remainder > step - 0.0005


static func _array_value(value: Variant) -> Array:
	if value is Array:
		return (value as Array).duplicate(true)
	return []
