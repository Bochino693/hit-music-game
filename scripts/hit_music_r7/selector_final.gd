extends "res://scripts/hit_music_r7/selector_v11.gd"

const FINAL_LED_CLIENT: Script = preload(
	"res://scripts/hit_music_r7/led_client.gd"
)

const MENU_HEARTBEAT_SECONDS: float = 0.16

var _final_menu_timer: Timer


func _ready() -> void:
	Engine.max_fps = 160
	super._ready()

	# Desliga qualquer timer antigo de cor fixa da R11.
	var old_timer_value: Variant = get("_menu_led_timer_v11")
	if old_timer_value is Timer:
		var old_timer: Timer = old_timer_value as Timer
		old_timer.stop()
		old_timer.queue_free()

	_final_menu_timer = Timer.new()
	_final_menu_timer.wait_time = MENU_HEARTBEAT_SECONDS
	_final_menu_timer.one_shot = false
	_final_menu_timer.timeout.connect(
		_refresh_menu_leds_final
	)
	add_child(_final_menu_timer)
	_final_menu_timer.start()
	_refresh_menu_leds_final()


func _refresh_menu_leds_final() -> void:
	var songs_value: Variant = get("_songs")
	if not (songs_value is Array):
		return

	var songs: Array = songs_value as Array
	if songs.is_empty():
		return

	var index_value: int = clampi(
		int(get("_index")),
		0,
		songs.size() - 1
	)
	var song_value: Variant = songs[index_value]
	if not (song_value is Dictionary):
		return

	var song: Dictionary = song_value as Dictionary
	var colors_value: Variant = song.get("colors", {})
	var primary: Color = Color(0.0, 0.72, 1.0, 1.0)
	var accent: Color = Color(1.0, 0.82, 0.08, 1.0)

	if colors_value is Dictionary:
		var colors: Dictionary = colors_value as Dictionary
		primary = _color_from_value_final(
			colors.get("primary", primary),
			primary
		)
		accent = _color_from_value_final(
			colors.get("accent", accent),
			primary.lerp(Color.WHITE, 0.46)
		)

	# D2=A e D3=B permanecem ligados durante toda a tela.
	# A cor muda automaticamente com o cenario selecionado.
	FINAL_LED_CLIENT.menu_state_colors(
		primary,
		accent
	)


func _color_from_value_final(
	value: Variant,
	fallback: Color
) -> Color:
	if value is Color:
		return value as Color
	if value is String:
		return Color.from_string(
			str(value),
			fallback
		)
	return fallback
