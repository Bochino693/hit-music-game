extends "res://scripts/hit_music_r7/selector_v10.gd"

const LED_CLIENT_V11: Script = preload(
	"res://scripts/hit_music_r7/led_client.gd"
)

var _drag_total: float = 0.0
var _menu_led_timer_v11: Timer


func _ready() -> void:
	Engine.max_fps = 144
	super._ready()

	_menu_led_timer_v11 = Timer.new()
	_menu_led_timer_v11.wait_time = 0.30
	_menu_led_timer_v11.one_shot = false
	_menu_led_timer_v11.timeout.connect(
		_refresh_menu_leds_v11
	)
	add_child(_menu_led_timer_v11)
	_menu_led_timer_v11.start()
	_refresh_menu_leds_v11()


func _refresh_menu_leds_v11() -> void:
	_refresh_selector_leds()


func _input(event: InputEvent) -> void:
	if _transitioning:
		return

	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed:
			_touch_dragging = true
			_touch_start = touch.position
			_touch_last = touch.position
			_touch_velocity = 0.0
			_drag_total = 0.0
		else:
			_touch_dragging = false
			if absf(_drag_total) > _radius * 0.08:
				_change_selection(
					1 if _drag_total < 0.0 else -1
				)
			else:
				_handle_touch(touch.position)

	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		if _touch_dragging:
			var movement: float = drag.position.y - _touch_last.y
			_drag_total += movement
			_touch_velocity = movement
			_touch_last = drag.position

	elif (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
	):
		var mouse: InputEventMouseButton = event
		if mouse.pressed:
			_touch_dragging = true
			_touch_start = mouse.position
			_touch_last = mouse.position
			_touch_velocity = 0.0
			_drag_total = 0.0
		else:
			_touch_dragging = false
			if absf(_drag_total) > _radius * 0.08:
				_change_selection(
					1 if _drag_total < 0.0 else -1
				)
			else:
				_handle_touch(mouse.position)

	elif event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event
		if _touch_dragging:
			var move_y: float = motion.position.y - _touch_last.y
			_drag_total += move_y
			_touch_velocity = move_y
			_touch_last = motion.position

	elif event is InputEventMouseButton:
		var wheel: InputEventMouseButton = event
		if wheel.pressed:
			if wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_change_selection(1)
			elif wheel.button_index == MOUSE_BUTTON_WHEEL_UP:
				_change_selection(-1)
