extends "res://scripts/hit_music_r7/stage_v11.gd"

const FINAL_LED_CLIENT: Script = preload(
	"res://scripts/hit_music_r7/led_client.gd"
)

const LED_PRELIGHT_SECONDS: float = 1.18
const LED_LATE_SECONDS: float = 0.18
const LED_HEARTBEAT_SECONDS: float = 0.10
const SCENE_HEARTBEAT_SECONDS: float = 0.28

var _final_led_timer: float = 0.0
var _final_scene_timer: float = 0.0
var _final_lane_active: Array[bool] = [
	false, false, false, false,
	false, false, false, false,
]
var _final_lane_color: Array[Color] = [
	Color.BLACK, Color.BLACK, Color.BLACK, Color.BLACK,
	Color.BLACK, Color.BLACK, Color.BLACK, Color.BLACK,
]


func _ready() -> void:
	Engine.max_fps = 160
	super._ready()

	# O renderer final ja possui o fundo geometrico completo.
	# O overlay antigo e removido para nao deixar arcos cortados.
	if _theme_overlay_v11 != null:
		_theme_overlay_v11.queue_free()
		_theme_overlay_v11 = null

	_final_led_timer = 0.0
	_final_scene_timer = 0.0
	_send_scene_state_final()


func _process(delta: float) -> void:
	super._process(delta)

	var state_name: String = _state_name()

	# Renova a cena durante o jogo sem cancelar a contagem regressiva.
	if (
		state_name == "presentation"
		or state_name == "pre_game"
		or (
			state_name == "playing"
			and _song_time >= 0.70
		)
	):
		_final_scene_timer -= delta
		if _final_scene_timer <= 0.0:
			_send_scene_state_final()
			_final_scene_timer = SCENE_HEARTBEAT_SECONDS
	else:
		_final_scene_timer = 0.0

	if state_name == "playing":
		_final_led_timer -= delta
		if _final_led_timer <= 0.0:
			_update_lane_leds_final()
			_final_led_timer = LED_HEARTBEAT_SECONDS
	else:
		_final_led_timer = 0.0
		_clear_lane_leds_final()


func _handle_lane_press(
	lane: int,
	_source: String
) -> void:
	var safe_lane: int = clampi(lane, 0, 7)
	var input_color: Color = _nearest_lane_color_final(safe_lane)

	# Resposta imediata do input fisico/touch.
	# lane 0=D2, lane 1=D3 ... lane 7=D9.
	FINAL_LED_CLIENT.set_lane(safe_lane, input_color)
	FINAL_LED_CLIENT.pulse_lane(safe_lane)

	super._handle_lane_press(lane, _source)


func _update_lane_leds_final() -> void:
	if _events.is_empty():
		_clear_lane_leds_final()
		return

	var desired_active: Array[bool] = [
		false, false, false, false,
		false, false, false, false,
	]
	var desired_color: Array[Color] = [
		Color.BLACK, Color.BLACK, Color.BLACK, Color.BLACK,
		Color.BLACK, Color.BLACK, Color.BLACK, Color.BLACK,
	]
	var nearest_time: Array[float] = [
		99999.0, 99999.0, 99999.0, 99999.0,
		99999.0, 99999.0, 99999.0, 99999.0,
	]

	for event_value in _events:
		if not (event_value is Dictionary):
			continue

		var event: Dictionary = event_value as Dictionary
		if bool(event.get("_resolved", false)):
			continue

		var type_name: String = str(
			event.get("type", "tap")
		)
		if type_name != "tap" and type_name != "hold":
			continue

		var lane: int = int(event.get("lane", -1))
		if lane < 0 or lane > 7:
			continue

		var start_time: float = _event_start_time(event)
		var end_time: float = _event_end_time(
			event,
			start_time
		)

		if (
			type_name == "hold"
			and _song_time >= start_time
			and _song_time <= end_time
		):
			desired_active[lane] = true
			desired_color[lane] = _event_color(event)
			nearest_time[lane] = -1.0
			continue

		var time_until_hit: float = start_time - _song_time
		if time_until_hit < -LED_LATE_SECONDS:
			continue
		if time_until_hit > LED_PRELIGHT_SECONDS:
			continue

		if time_until_hit < nearest_time[lane]:
			desired_active[lane] = true
			desired_color[lane] = _event_color(event)
			nearest_time[lane] = time_until_hit

	for lane_index in range(8):
		if desired_active[lane_index]:
			# Heartbeat: reenvia mesmo quando a lane ja estava acesa.
			# Isso elimina apagamentos ou comandos perdidos.
			FINAL_LED_CLIENT.set_lane(
				lane_index,
				desired_color[lane_index]
			)
			_final_lane_active[lane_index] = true
			_final_lane_color[lane_index] = desired_color[lane_index]
		elif _final_lane_active[lane_index]:
			FINAL_LED_CLIENT.clear_lane(lane_index)
			_final_lane_active[lane_index] = false
			_final_lane_color[lane_index] = Color.BLACK


func _clear_lane_leds_final() -> void:
	for lane_index in range(8):
		if _final_lane_active[lane_index]:
			FINAL_LED_CLIENT.clear_lane(lane_index)

		_final_lane_active[lane_index] = false
		_final_lane_color[lane_index] = Color.BLACK


func _nearest_lane_color_final(lane: int) -> Color:
	var selected_color: Color = _primary_color()
	var best_distance: float = 99999.0

	for event_value in _events:
		if not (event_value is Dictionary):
			continue

		var event: Dictionary = event_value as Dictionary
		if bool(event.get("_resolved", false)):
			continue
		if int(event.get("lane", -1)) != lane:
			continue

		var type_name: String = str(
			event.get("type", "tap")
		)
		if type_name != "tap" and type_name != "hold":
			continue

		var distance: float = absf(
			_event_start_time(event) - _song_time
		)
		if distance < best_distance:
			best_distance = distance
			selected_color = _event_color(event)

	return selected_color


func _send_scene_state_final() -> void:
	FINAL_LED_CLIENT.scene_state(
		_primary_color(),
		_accent_color()
	)
