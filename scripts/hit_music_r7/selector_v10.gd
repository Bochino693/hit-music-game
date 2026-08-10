extends "res://scripts/hit_music_r7/selector_v9.gd"

var _touch_dragging: bool = false
var _touch_start: Vector2 = Vector2.ZERO
var _touch_last: Vector2 = Vector2.ZERO
var _touch_velocity: float = 0.0


# Lane fisica que acende como indicador do input D (desce/anterior).
# O comando MENU do firmware so acende 2 lanes por vez (idxA/idxB,
# ja usadas por A/B); D precisa de um LED %d avulso por cima.
const DOWN_LANE_INDEX: int = 3


func _ready() -> void:
	Engine.max_fps = 120
	super._ready()
	LED_CLIENT.menu_state(
		_index,
		_song_primary(_songs[_index] as Dictionary)
	)
	LED_CLIENT.set_lane(DOWN_LANE_INDEX, LED_CLIENT.MENU_NEXT_COLOR)


func _process(delta: float) -> void:
	super._process(delta)
	_touch_velocity = lerpf(
		_touch_velocity,
		0.0,
		1.0 - exp(-7.0 * delta)
	)


func _toggle_difficulty() -> void:
	LED_CLIENT.menu_select_feedback()
	_start_selected()


func _change_selection(direction: int) -> void:
	super._change_selection(direction)
	LED_CLIENT.menu_next_feedback()
	LED_CLIENT.menu_state(
		_index,
		_song_primary(_songs[_index] as Dictionary)
	)
	LED_CLIENT.set_lane(DOWN_LANE_INDEX, LED_CLIENT.MENU_NEXT_COLOR)


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
		else:
			var delta_y: float = (
				touch.position.y - _touch_start.y
			)
			_touch_dragging = false

			if absf(delta_y) > _radius * 0.08:
				_change_selection(
					1 if delta_y < 0.0 else -1
				)
			else:
				_handle_touch(touch.position)

	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		var movement: float = (
			drag.position.y - _touch_last.y
		)
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
		else:
			var delta_y: float = (
				mouse.position.y - _touch_start.y
			)
			_touch_dragging = false

			if absf(delta_y) > _radius * 0.08:
				_change_selection(
					1 if delta_y < 0.0 else -1
				)
			else:
				_handle_touch(mouse.position)

	elif event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event
		if _touch_dragging:
			_touch_velocity = (
				motion.position.y - _touch_last.y
			)
			_touch_last = motion.position

	elif event is InputEventMouseButton:
		var wheel: InputEventMouseButton = event
		if wheel.pressed:
			if wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_change_selection(1)
			elif wheel.button_index == MOUSE_BUTTON_WHEEL_UP:
				_change_selection(-1)
