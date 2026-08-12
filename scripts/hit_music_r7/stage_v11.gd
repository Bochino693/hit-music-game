extends "res://scripts/hit_music_r7/stage_v10.gd"

const GUIDE_PRELIGHT_SEC: float = 0.95
const GUIDE_LATE_CUTOFF_SEC: float = 0.14

var _lane_led_cache_active: Array = []
var _lane_led_cache_colors: Array = []


func _ready() -> void:
	Engine.max_fps = 144
	super._ready()

	_lane_led_cache_active.resize(8)
	_lane_led_cache_colors.resize(8)
	for lane in range(8):
		_lane_led_cache_active[lane] = false
		_lane_led_cache_colors[lane] = Color.BLACK

	_apply_scene_led_theme()


func _process(delta: float) -> void:
	super._process(delta)

	_update_gameplay_lane_leds(delta)


func _start_countdown() -> void:
	_apply_scene_led_theme()
	super._start_countdown()


func _start_playing() -> void:
	_apply_scene_led_theme()
	super._start_playing()


func _finish_song() -> void:
	_clear_gameplay_lane_leds()


func _exit_tree() -> void:
	_clear_gameplay_lane_leds()


func _apply_scene_led_theme() -> void:
	LED_CLIENT.scene_state(
		_primary_color(),
		_accent_color()
	)


func _update_gameplay_lane_leds(_delta: float) -> void:
	var state_name: String = _state_name()
	if state_name != "countdown" and state_name != "playing":
		_clear_gameplay_lane_leds()
		return

	if _events.is_empty():
		return

	var now: float = 0.0 if state_name == "countdown" else _song_time
	var desired_active: Array = []
	var desired_colors: Array = []
	var best_dt: Array = []

	desired_active.resize(8)
	desired_colors.resize(8)
	best_dt.resize(8)

	for lane in range(8):
		desired_active[lane] = false
		desired_colors[lane] = Color.BLACK
		best_dt[lane] = 99999.0

	for event_value in _events:
		if not (event_value is Dictionary):
			continue

		var event: Dictionary = event_value as Dictionary
		var type_name: String = str(event.get("type", "tap"))
		if type_name != "tap" and type_name != "hold":
			continue

		var lane: int = int(event.get("lane", -1))
		if lane < 0 or lane > 7:
			continue

		var start_time: float = _event_start_time(event)
		var end_time: float = _event_end_time(event, start_time)

		if type_name == "hold" and now >= start_time and now <= end_time:
			desired_active[lane] = true
			desired_colors[lane] = _event_color(event)
			best_dt[lane] = -1.0
			continue

		var dt: float = start_time - now
		if dt < -GUIDE_LATE_CUTOFF_SEC:
			continue
		if dt > GUIDE_PRELIGHT_SEC:
			continue
		if dt < float(best_dt[lane]):
			desired_active[lane] = true
			desired_colors[lane] = _event_color(event)
			best_dt[lane] = dt

	for lane2 in range(8):
		var should_enable: bool = bool(desired_active[lane2])
		var last_enable: bool = bool(_lane_led_cache_active[lane2])

		if should_enable:
			var desired_color: Color = desired_colors[lane2]
			var last_color: Color = _lane_led_cache_colors[lane2]

			if not last_enable or last_color != desired_color:
				LED_CLIENT.set_lane(lane2, desired_color)

			_lane_led_cache_active[lane2] = true
			_lane_led_cache_colors[lane2] = desired_color
		else:
			if last_enable:
				LED_CLIENT.clear_lane(lane2)

			_lane_led_cache_active[lane2] = false
			_lane_led_cache_colors[lane2] = Color.BLACK


func _clear_gameplay_lane_leds() -> void:
	for lane in range(8):
		if (
			_lane_led_cache_active.size() > lane
			and bool(_lane_led_cache_active[lane])
		):
			LED_CLIENT.clear_lane(lane)

	if _lane_led_cache_active.is_empty():
		return

	for lane2 in range(8):
		_lane_led_cache_active[lane2] = false
		_lane_led_cache_colors[lane2] = Color.BLACK


func _event_start_time(event: Dictionary) -> float:
	if event.has("time"):
		return float(event.get("time", 0.0))
	if event.has("start"):
		return float(event.get("start", 0.0))
	if event.has("start_time"):
		return float(event.get("start_time", 0.0))
	return 0.0


func _event_end_time(
	event: Dictionary,
	start_time: float
) -> float:
	if event.has("end_time"):
		return float(event.get("end_time", start_time))
	if event.has("end"):
		return float(event.get("end", start_time))
	if event.has("duration"):
		return start_time + float(event.get("duration", 0.0))
	return start_time
