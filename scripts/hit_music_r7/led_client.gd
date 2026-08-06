extends RefCounted

static func clear_all() -> void:
	send_raw("CLEAR")


static func set_lane(lane: int, color: Color, duration_ms: int = 0) -> void:
	var r: int = int(round(clampf(color.r, 0.0, 1.0) * 255.0))
	var g: int = int(round(clampf(color.g, 0.0, 1.0) * 255.0))
	var b: int = int(round(clampf(color.b, 0.0, 1.0) * 255.0))
	if duration_ms > 0:
		send_raw("LED %d %d %d %d %d" % [lane, r, g, b, duration_ms])
	else:
		send_raw("LED %d %d %d %d" % [lane, r, g, b])


static func clear_lane(lane: int) -> void:
	send_raw("LED %d 0 0 0" % lane)


static func menu_state(index: int, color: Color) -> void:
	var r: int = int(round(clampf(color.r, 0.0, 1.0) * 255.0))
	var g: int = int(round(clampf(color.g, 0.0, 1.0) * 255.0))
	var b: int = int(round(clampf(color.b, 0.0, 1.0) * 255.0))
	send_raw("MENU %d %d %d %d" % [index, r, g, b])


static func send_raw(command: String) -> void:
	var clean: String = command.strip_edges()
	if clean.is_empty():
		return

	var base_dir: String = ProjectSettings.globalize_path("user://hit_music_serial")
	var spool_dir: String = base_dir.path_join("spool")
	DirAccess.make_dir_recursive_absolute(spool_dir)

	var name: String = "cmd_%020d_%d.cmd" % [
		Time.get_ticks_usec(),
		OS.get_process_id(),
	]
	var final_path: String = spool_dir.path_join(name)
	var temporary_path: String = final_path + ".tmp"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return

	file.store_string(clean + "\n")
	file.flush()
	file.close()

	if FileAccess.file_exists(final_path):
		DirAccess.remove_absolute(final_path)
	var error: Error = DirAccess.rename_absolute(temporary_path, final_path)
	if error != OK and FileAccess.file_exists(temporary_path):
		DirAccess.remove_absolute(temporary_path)