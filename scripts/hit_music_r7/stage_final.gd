extends "res://scripts/hit_music_r7/stage_v11.gd"
## STAGE FINAL R21
##
## A cadeia antiga continua fornecendo gameplay/UI, mas NÃO governa
## fisicamente a mesa durante PLAYING: LedClient bloqueia seus LED/PULSE/HIT.
##
## Este arquivo publica o ÚNICO quadro MULTI das 8 lanes.

const GAMEPLAY_TAP_PALETTE: Script = preload("res://scripts/hit_music_r7/tap_palette.gd")
const LED_PRELIGHT_SECONDS: float = 1.18
const LED_LATE_SECONDS: float = 0.18
## Cor de seguranca do hold. O normal e o LED usar _event_color(event),
## que segue a cor do proprio objeto; isto so entra se o evento chegar
## sem indice de cor.
const HOLD_COLOR: Color = GAMEPLAY_TAP_PALETTE.HOLD_YELLOW

var _r21_was_playing: bool = false


func _ready() -> void:
	super._ready()

	# stage.gd/stage_v9/stage_v10/stage_v11 tentam limitar o FPS em
	# cascata (60 -> 120 -> 144) dentro de _ready(), mas como cada
	# _ready() chama super._ready() ANTES de aplicar seu proprio valor,
	# quem "vence" e o mais base da cadeia (stage.gd = 60), nao o mais
	# derivado. Aplicar aqui, depois de todo o super._ready() ja ter
	# rodado, garante que o jogo realmente rode a 160 FPS: movimento
	# mais fluido e responsivo, sem o teto de 60 escondido.
	Engine.max_fps = 160

	var client := _led_client_r21()
	if client != null:
		if client.has_method("begin_stage"):
			client.call("begin_stage")
		_send_scene_state_r21(client)


func _process(delta: float) -> void:
	super._process(delta)

	var playing := _state_name() == "playing"

	if playing:
		_publish_game_frame_r21()
	elif _r21_was_playing:
		var client := _led_client_r21()
		if client != null and client.has_method("end_game"):
			client.call("end_game")

	_r21_was_playing = playing


func _start_playing() -> void:
	# Entra em GAME ANTES de chamar super.
	# Assim READY/SCENE/PULSE herdados já são bloqueados.
	var client := _led_client_r21()
	if client != null and client.has_method("begin_game"):
		client.call("begin_game")

	_r21_was_playing = true
	super._start_playing()

	_publish_game_frame_r21()


func _finish_game(failed: bool) -> void:
	super._finish_game(failed)
	# A cadeia de overlays evoluiu em varias versoes. Reafirma o modal
	# no ultimo nivel para que nenhuma camada herdada o deixe invisivel.
	call_deferred("_force_result_panel_visible")


func _exit_tree() -> void:
	var client := _led_client_r21()
	if client != null and client.has_method("end_game"):
		client.call("end_game")


# stage_v11 chama esta função em seu _process.
# Ela fica vazia de propósito: o estado físico é composto somente
# por _publish_game_frame_r21().
func _update_gameplay_lane_leds(_delta: float) -> void:
	pass


# stage_v11 também tenta aplicar SCENE em vários momentos.
# A cena temática é enviada somente uma vez no _ready().
func _apply_scene_led_theme() -> void:
	pass


func _publish_game_frame_r21() -> void:
	var frame := _quadro_das_lanes_r21()

	var client := _led_client_r21()
	if client != null and client.has_method("send_state"):
		client.call("send_state", frame)


## Monta o quadro MULTI das 8 lanes a partir dos eventos vivos. Separado
## do envio para poder ser conferido sem mesa ligada (ver
## tools/smoke_final.tscn): e aqui que se prova que arrasto nao acende.
func _quadro_das_lanes_r21() -> String:
	var colors: Array[Color] = []
	var best_distance: Array[float] = []
	var hold_active: Array[bool] = []

	for _lane in range(8):
		colors.append(Color.BLACK)
		best_distance.append(INF)
		hold_active.append(false)

	for event_value in _events:
		if not (event_value is Dictionary):
			continue

		var event: Dictionary = event_value as Dictionary

		if bool(event.get("_resolved", false)):
			continue

		var type_name := str(event.get("type", "tap")).to_lower()

		# ARRASTO NAO ACENDE LED NENHUM.
		#
		# Antes o botao da lane de partida (e depois o do proximo ponto do
		# caminho) acendia, porque o percurso podia ser feito apertando as
		# lanes em ordem. Isso convidava ao atalho que agora nao existe
		# mais: apertar A e depois B fechava a nota sem desenhar nada.
		#
		# O arrasto e um gesto da moldura touch — quem mostra o caminho e
		# a tela, com o traco, as setas e a estrela. A mesa fica apagada
		# de proposito: LED aceso ali seria um convite a apertar o botao,
		# que agora nao faz efeito.
		if type_name != "tap" and type_name != "hold":
			continue

		var lane := int(event.get("lane", -1))
		if lane < 0 or lane > 7:
			continue

		var start_time := _event_start_time(event)
		var end_time := _event_end_time(event, start_time)

		if type_name == "hold":
			# Hold: aceso desde a aproximação até o final.
			if (
				_song_time >= start_time - LED_PRELIGHT_SECONDS
				and _song_time <= end_time
			):
				# O botao acende na cor da fita daquele hold, nao num
				# amarelo fixo: a mesa passa a mostrar a mesma variacao
				# de cor que a tela.
				colors[lane] = _event_color(event)
				hold_active[lane] = true
				best_distance[lane] = 0.0
			continue

		# TAP: cor RGB do próprio tazo/evento.
		var dt := start_time - _song_time

		if dt > LED_PRELIGHT_SECONDS:
			continue
		if dt < -LED_LATE_SECONDS:
			continue
		if hold_active[lane]:
			continue

		var distance := absf(dt)
		if distance < best_distance[lane]:
			best_distance[lane] = distance
			colors[lane] = _event_color(event)

	return _multi_command_r21(colors)


func _multi_command_r21(colors: Array[Color]) -> String:
	var payload := ""

	for lane in range(8):
		var color := Color.BLACK
		if lane < colors.size():
			color = colors[lane]

		payload += "%02X%02X%02X" % [
			clampi(roundi(color.r * 255.0), 0, 255),
			clampi(roundi(color.g * 255.0), 0, 255),
			clampi(roundi(color.b * 255.0), 0, 255)
		]

	return "MULTI " + payload


func _send_scene_state_r21(client: Node) -> void:
	var primary := _primary_color()
	var accent := _accent_color()

	client.call(
		"send",
		"SCENE2 %d %d %d %d %d %d" % [
			roundi(primary.r * 255.0),
			roundi(primary.g * 255.0),
			roundi(primary.b * 255.0),
			roundi(accent.r * 255.0),
			roundi(accent.g * 255.0),
			roundi(accent.b * 255.0)
		]
	)


func _led_client_r21() -> Node:
	return get_node_or_null("/root/LedClient")
