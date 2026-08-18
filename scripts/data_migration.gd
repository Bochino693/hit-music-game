extends Node
## Migração de dados persistentes do HIT MUSIC.
##
## Este autoload precisa ser o PRIMEIRO do project.godot.
## Ele copia dados de versões antigas para o diretório persistente atual
## antes de ArcadeSettings, ArcadeCounters e o catálogo tentarem ler user://.

const MIGRATION_MARKER: String = "user://.hit_music_storage_v3"


func _init() -> void:
	_migrate_legacy_windows_data()


func _migrate_legacy_windows_data() -> void:
	if FileAccess.file_exists(MIGRATION_MARKER):
		return

	if OS.get_name() != "Windows":
		_write_marker()
		return

	var appdata: String = OS.get_environment("APPDATA")
	if appdata.is_empty():
		return

	var target: String = OS.get_user_data_dir().replace("\\", "/")
	var candidates: Array[String] = [
		appdata.path_join("Godot/app_userdata/Hit Music"),
		appdata.path_join("Godot/app_userdata/beta12"),
		appdata.path_join("Godot/app_userdata/beta-12"),
	]

	for candidate in candidates:
		var source: String = candidate.replace("\\", "/")

		if source.to_lower() == target.to_lower():
			continue
		if not DirAccess.dir_exists_absolute(source):
			continue
		if not _folder_has_any_file(source):
			continue

		_copy_tree_without_overwrite(source, target)

	_write_marker()


func _folder_has_any_file(folder: String) -> bool:
	if not DirAccess.get_files_at(folder).is_empty():
		return true

	for child_value in DirAccess.get_directories_at(folder):
		var child: String = str(child_value)
		if child == "." or child == "..":
			continue
		if _folder_has_any_file(folder.path_join(child)):
			return true

	return false


func _copy_tree_without_overwrite(source_dir: String, target_dir: String) -> void:
	if not DirAccess.dir_exists_absolute(target_dir):
		DirAccess.make_dir_recursive_absolute(target_dir)

	for file_value in DirAccess.get_files_at(source_dir):
		var file_name: String = str(file_value)
		var source_file: String = source_dir.path_join(file_name)
		var target_file: String = target_dir.path_join(file_name)

		# O destino sempre vence: nunca substituímos um save mais novo.
		if FileAccess.file_exists(target_file):
			continue

		_copy_file(source_file, target_file)

	for dir_value in DirAccess.get_directories_at(source_dir):
		var dir_name: String = str(dir_value)
		if dir_name == "." or dir_name == "..":
			continue

		_copy_tree_without_overwrite(
			source_dir.path_join(dir_name),
			target_dir.path_join(dir_name)
		)


func _copy_file(source: String, target: String) -> bool:
	var input := FileAccess.open(source, FileAccess.READ)
	if input == null:
		return false

	var output := FileAccess.open(target, FileAccess.WRITE)
	if output == null:
		input.close()
		return false

	const CHUNK_SIZE: int = 1024 * 1024

	while input.get_position() < input.get_length():
		var remaining: int = int(input.get_length() - input.get_position())
		var buffer: PackedByteArray = input.get_buffer(
			mini(remaining, CHUNK_SIZE)
		)
		if buffer.is_empty():
			break
		output.store_buffer(buffer)

	output.flush()
	output.close()
	input.close()
	return FileAccess.file_exists(target)


func _write_marker() -> void:
	var file := FileAccess.open(MIGRATION_MARKER, FileAccess.WRITE)
	if file == null:
		return
	file.store_string("storage_v3")
	file.close()
