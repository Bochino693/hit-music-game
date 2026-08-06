class_name HitMusicInputRouter
extends Node

signal lane_pressed(lane: int)
signal lane_released(lane: int)
signal pointer_pressed(pointer_id: int, position_value: Vector2)
signal pointer_moved(pointer_id: int, position_value: Vector2)
signal pointer_released(pointer_id: int, position_value: Vector2)

const INPUTS: Array[String] = [
	"input_a",
	"input_b",
	"input_c",
	"input_d",
	"input_e",
	"input_f",
	"input_g",
	"input_h",
]

func _process(_delta: float) -> void:
	for lane in range(INPUTS.size()):
		var action: String = INPUTS[lane]
		if not InputMap.has_action(action):
			continue
		if Input.is_action_just_pressed(action):
			lane_pressed.emit(lane)
		if Input.is_action_just_released(action):
			lane_released.emit(lane)

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			pointer_pressed.emit(event.index, event.position)
		else:
			pointer_released.emit(event.index, event.position)
	elif event is InputEventScreenDrag:
		pointer_moved.emit(event.index, event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			pointer_pressed.emit(-1, event.position)
		else:
			pointer_released.emit(-1, event.position)
	elif event is InputEventMouseMotion:
		pointer_moved.emit(-1, event.position)