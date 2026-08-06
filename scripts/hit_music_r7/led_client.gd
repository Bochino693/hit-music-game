extends RefCounted

const MENU_NEXT_COLOR: Color = Color(0.0, 0.72, 1.0, 1.0)
const MENU_SELECT_COLOR: Color = Color(1.0, 0.82, 0.08, 1.0)

static var _command_sequence: int = 0


static func clear_all() -> void:
	send_raw("CLEAR")


static func set_lane(lane: int, color: Color) -> void:
	var rgb: Vector3i = _rgb(color)
	send_raw(
		"LED %d %d %d %d"
		% [clampi(lane, 0, 7), rgb.x, rgb.y, rgb.z]
	)


static func clear_lane(lane: int) -> void:
	send_raw("LED %d 0 0 0" % clampi(lane, 0, 7))


static func hit_lane(
	lane: int,
	color: Color,
	duration_ms: int = 240
) -> void:
	var rgb: Vector3i = _rgb(color)
	send_raw(
		"HIT %d %d %d %d %d"
		% [
			clampi(lane, 0, 7),
			rgb.x,
			rgb.y,
			rgb.z,
			clampi(duration_ms, 90, 1400),
		]
	)


static func error_lane(lane: int) -> void:
	send_raw("ERR %d" % clampi(lane, 0, 7))


static func pulse_lane(lane: int) -> void:
	send_raw("PULSE %d" % clampi(lane, 0, 7))


static func menu_state(
	_index: int = 0,
	color: Color = MENU_NEXT_COLOR
) -> void:
	menu_state_colors(
		color,
		MENU_SELECT_COLOR
	)


static func menu_state_colors(
	next_color: Color,
	select_color: Color
) -> void:
	var next_rgb: Vector3i = _rgb(next_color)
	var select_rgb: Vector3i = _rgb(select_color)
	send_raw(
		"MENU %d %d %d %d %d %d"
		% [
			next_rgb.x,
			next_rgb.y,
			next_rgb.z,
			select_rgb.x,
			select_rgb.y,
			select_rgb.z,
		]
	)


static func menu_next_feedback() -> void:
	hit_lane(0, MENU_NEXT_COLOR, 180)


static func menu_select_feedback() -> void:
	hit_lane(1, MENU_SELECT_COLOR, 210)


static func scene_state(
	primary: Color,
	secondary: Color
) -> void:
	var first_rgb: Vector3i = _rgb(primary)
	var second_rgb: Vector3i = _rgb(secondary)
	send_raw(
		"SCENE2 %d %d %d %d %d %d"
		% [
			first_rgb.x,
			first_rgb.y,
			first_rgb.z,
			second_rgb.x,
			second_rgb.y,
			second_rgb.z,
		]
	)


static func countdown_start() -> void:
	send_raw("BLINKALL")


static func countdown_value(value: int) -> void:
	send_raw("COUNT %d" % clampi(value, 0, 9))


static func ready() -> void:
	send_raw("READY")


static func send_raw(command: String) -> void:
	var clean_command: String = command.strip_edges()
	if clean_command.is_empty():
		return

	var base_dir: String = ProjectSettings.globalize_path(
		"user://hit_music_serial"
	)
	var spool_dir: String = base_dir.path_join("spool")
	DirAccess.make_dir_recursive_absolute(spool_dir)

	_command_sequence += 1
	var file_name: String = (
		"cmd_%020d_%06d_%d.cmd"
		% [
			Time.get_ticks_usec(),
			_command_sequence,
			OS.get_process_id(),
		]
	)
	var final_path: String = spool_dir.path_join(file_name)
	var temporary_path: String = final_path + ".tmp"
	var file: FileAccess = FileAccess.open(
		temporary_path,
		FileAccess.WRITE
	)
	if file == null:
		push_warning(
			"Falha ao escrever comando LED: "
			+ clean_command
		)
		return

	file.store_string(clean_command + "\n")
	file.flush()
	file.close()

	var rename_error: Error = DirAccess.rename_absolute(
		temporary_path,
		final_path
	)
	if rename_error != OK:
		if FileAccess.file_exists(temporary_path):
			DirAccess.remove_absolute(temporary_path)
		push_warning(
			"Falha ao publicar comando LED: "
			+ clean_command
		)


static func _rgb(color: Color) -> Vector3i:
	return Vector3i(
		int(round(clampf(color.r, 0.0, 1.0) * 255.0)),
		int(round(clampf(color.g, 0.0, 1.0) * 255.0)),
		int(round(clampf(color.b, 0.0, 1.0) * 255.0))
	)
