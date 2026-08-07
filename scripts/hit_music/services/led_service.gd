class_name HitMusicLedService
extends Node

signal state_changed(colors: Array[Color])

const NUM_LANES: int = 8
var desired_colors: Array[Color] = []
var revision: int = 0

func _ready() -> void:
	desired_colors.resize(NUM_LANES)
	clear_all()

func set_lane_color(lane: int, color: Color) -> void:
	if lane < 0 or lane >= NUM_LANES:
		return
	desired_colors[lane] = color
	revision += 1
	state_changed.emit(desired_colors.duplicate())

func clear_lane(lane: int) -> void:
	set_lane_color(lane, Color.BLACK)

func clear_all() -> void:
	if desired_colors.size() != NUM_LANES:
		desired_colors.resize(NUM_LANES)
	for lane in range(NUM_LANES):
		desired_colors[lane] = Color.BLACK
	revision += 1
	state_changed.emit(desired_colors.duplicate())

func create_snapshot_command() -> String:
	var values: PackedStringArray = PackedStringArray()
	values.append("STATE")
	values.append(str(revision))
	for color in desired_colors:
		values.append(str(int(round(clampf(color.r, 0.0, 1.0) * 255.0))))
		values.append(str(int(round(clampf(color.g, 0.0, 1.0) * 255.0))))
		values.append(str(int(round(clampf(color.b, 0.0, 1.0) * 255.0))))
	return " ".join(values)
