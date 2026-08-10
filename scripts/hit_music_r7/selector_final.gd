extends "res://scripts/hit_music_r7/selector_v11.gd"
## SELECTOR FINAL R21
##
## Dois LEDs fixos durante a seleção:
## D2 = próxima/navegação
## D3 = selecionar
##
## Não existe heartbeat de MENU. Só publica quando entra ou muda seleção.

var _r21_menu_signature: String = ""


func _ready() -> void:
	Engine.max_fps = 160
	super._ready()

	# selector_v11 cria um heartbeat antigo. Desliga definitivamente.
	var old_timer_value: Variant = get("_menu_led_timer_v11")
	if old_timer_value is Timer:
		var old_timer := old_timer_value as Timer
		old_timer.stop()
		old_timer.queue_free()

	var client := get_node_or_null("/root/LedClient")
	if client != null and client.has_method("begin_menu"):
		client.call("begin_menu")

	_refresh_menu_leds_r21()


func _change_selection(direction: int) -> void:
	super._change_selection(direction)
	_refresh_menu_leds_r21()


func _refresh_menu_leds_r21() -> void:
	var songs_value: Variant = get("_songs")
	if not (songs_value is Array):
		return

	var songs: Array = songs_value as Array
	if songs.is_empty():
		return

	var index_value := clampi(int(get("_index")), 0, songs.size() - 1)
	var song_value: Variant = songs[index_value]

	if not (song_value is Dictionary):
		return

	var song: Dictionary = song_value as Dictionary
	var colors_value: Variant = song.get("colors", {})

	var primary := Color(0.0, 0.72, 1.0, 1.0)
	var accent := Color(1.0, 0.82, 0.08, 1.0)

	if colors_value is Dictionary:
		var colors: Dictionary = colors_value as Dictionary
		primary = _color_from_value_r21(
			colors.get("primary", primary),
			primary
		)
		accent = _color_from_value_r21(
			colors.get("accent", accent),
			primary.lerp(Color.WHITE, 0.46)
		)

	var signature := "%d|%s|%s" % [
		index_value,
		str(primary),
		str(accent)
	]

	if signature == _r21_menu_signature:
		return

	_r21_menu_signature = signature

	# Tres botoes acesos nesta tela: A (proximo, lane 0), B
	# (selecionar, lane 1) e D (anterior, lane 3). Vai num unico
	# comando MENU estendido (firmware R25+): mandar "LED <idx>" por
	# cima do MENU nao funciona, porque o handler de LED do firmware
	# zera efeito_global e apagaria justamente A e B.
	var client := get_node_or_null("/root/LedClient")
	if client == null:
		return
	if client.has_method("menu3"):
		client.call("menu3", primary, accent, primary, 0, 1, DOWN_LANE_INDEX)
	elif client.has_method("menu"):
		client.call("menu", primary, accent, 0, 1)


func _color_from_value_r21(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value as Color

	if value is String:
		return Color.from_string(str(value), fallback)

	return fallback
