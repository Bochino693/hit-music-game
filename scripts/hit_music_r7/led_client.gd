extends RefCounted
## Adaptador de compatibilidade R21.
## NÃO escreve arquivos e NÃO abre serial.
## Toda chamada antiga é encaminhada ao Autoload /root/LedClient.

const MENU_NEXT_COLOR: Color = Color(0.0, 0.72, 1.0, 1.0)
const MENU_SELECT_COLOR: Color = Color(1.0, 0.82, 0.08, 1.0)

## Mapeamento fisico dos botoes de navegacao dos menus. Fonte unica:
## seletor de musicas, tela de dificuldade e os LEDs leem daqui, entao
## trocar um botao de lugar e uma linha so. DESCER passou do input_d
## (lane 3) para o input_e (lane 4).
const NAV_NEXT_ACTION: String = "input_a"
const NAV_SELECT_ACTION: String = "input_b"
const NAV_DOWN_ACTION: String = "input_e"
const NAV_NEXT_LANE: int = 0
const NAV_SELECT_LANE: int = 1
const NAV_DOWN_LANE: int = 4


static func _client() -> Node:
	var main_loop := Engine.get_main_loop()
	if main_loop is SceneTree:
		return (main_loop as SceneTree).root.get_node_or_null("LedClient")
	return null


static func send_raw(command: String) -> void:
	var client := _client()
	if client == null:
		return
	if client.has_method("send"):
		client.call("send", command)


static func clear_all() -> void:
	send_raw("CLEAR")


static func set_lane(lane: int, color: Color) -> void:
	var rgb := _rgb(color)
	send_raw(
		"LED %d %d %d %d" % [
			clampi(lane, 0, 7),
			rgb.x,
			rgb.y,
			rgb.z
		]
	)


static func clear_lane(lane: int) -> void:
	send_raw("LED %d 0 0 0" % clampi(lane, 0, 7))


static func hit_lane(lane: int, color: Color, duration_ms: int = 240) -> void:
	var rgb := _rgb(color)
	send_raw(
		"HIT %d %d %d %d %d" % [
			clampi(lane, 0, 7),
			rgb.x,
			rgb.y,
			rgb.z,
			clampi(duration_ms, 90, 1400)
		]
	)


static func error_lane(lane: int) -> void:
	send_raw("ERR %d" % clampi(lane, 0, 7))


static func pulse_lane(lane: int) -> void:
	send_raw("PULSE %d" % clampi(lane, 0, 7))


static func menu_state(_index: int = 0, color: Color = MENU_NEXT_COLOR) -> void:
	menu_state_colors(color, MENU_SELECT_COLOR)


## Menu com tres botoes acesos (A = proximo, B = selecionar, C =
## anterior). Exige firmware R25+; em firmware antigo o Arduino
## ignora os tokens extras e acende so A e B, entao degrada bem.
static func menu_state_three(
	next_color: Color = MENU_NEXT_COLOR,
	select_color: Color = MENU_SELECT_COLOR,
	previous_color: Color = MENU_NEXT_COLOR,
	idx_next: int = 0,
	idx_select: int = 1,
	idx_previous: int = 3
) -> void:
	var next_rgb := _rgb(next_color)
	var select_rgb := _rgb(select_color)
	var previous_rgb := _rgb(previous_color)

	send_raw(
		"MENU %d %d %d %d %d %d %d %d %d %d %d %d" % [
			next_rgb.x,
			next_rgb.y,
			next_rgb.z,
			select_rgb.x,
			select_rgb.y,
			select_rgb.z,
			clampi(idx_next, 0, 7),
			clampi(idx_select, 0, 7),
			clampi(idx_previous, 0, 7),
			previous_rgb.x,
			previous_rgb.y,
			previous_rgb.z
		]
	)


static func menu_state_colors(next_color: Color, select_color: Color) -> void:
	var next_rgb := _rgb(next_color)
	var select_rgb := _rgb(select_color)

	send_raw(
		"MENU %d %d %d %d %d %d" % [
			next_rgb.x,
			next_rgb.y,
			next_rgb.z,
			select_rgb.x,
			select_rgb.y,
			select_rgb.z
		]
	)


static func menu_next_feedback() -> void:
	hit_lane(0, MENU_NEXT_COLOR, 180)


static func menu_select_feedback() -> void:
	hit_lane(1, MENU_SELECT_COLOR, 210)


static func scene_state(primary: Color, secondary: Color) -> void:
	var first_rgb := _rgb(primary)
	var second_rgb := _rgb(secondary)

	send_raw(
		"SCENE2 %d %d %d %d %d %d" % [
			first_rgb.x,
			first_rgb.y,
			first_rgb.z,
			second_rgb.x,
			second_rgb.y,
			second_rgb.z
		]
	)


static func countdown_start() -> void:
	send_raw("BLINKALL")


static func countdown_value(value: int) -> void:
	send_raw("COUNT %d" % clampi(value, 0, 9))


static func ready() -> void:
	send_raw("READY")


static func _rgb(color: Color) -> Vector3i:
	return Vector3i(
		int(round(clampf(color.r, 0.0, 1.0) * 255.0)),
		int(round(clampf(color.g, 0.0, 1.0) * 255.0)),
		int(round(clampf(color.b, 0.0, 1.0) * 255.0))
	)
