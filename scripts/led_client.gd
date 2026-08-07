extends Node
## HIT MUSIC — LedClient R21
## ÚNICA autoridade de comunicação LED do projeto.
##
## Regras:
## - nenhuma cena abre COM diretamente;
## - nenhuma cena inicia PowerShell diretamente;
## - MENU/SCENE/ATTRACT/CLEAR usam um único slot persistente;
## - durante GAME, somente MULTI é aceito;
## - MULTI usa um único arquivo game_state.cmd: estado novo substitui o antigo;
## - PULSE/HIT/ERR/LED/READY/COUNT de versões herdadas são bloqueados no GAME.

const BASE_DIR := "user://hit_music_serial"
const SPOOL_DIR := BASE_DIR + "/spool"

const ALIVE_PATH := BASE_DIR + "/bridge_alive.txt"
const READY_PATH := BASE_DIR + "/bridge_ready.txt"
const STARTING_PATH := BASE_DIR + "/bridge_starting.txt"
const STOP_PATH := BASE_DIR + "/bridge_stop.txt"
const GAME_MODE_PATH := BASE_DIR + "/game_mode.flag"

const BRIDGE_SCRIPT_RES := "res://BRIDGE_R21.ps1"
const COM_PORT := "COM5"
const BAUD_RATE := 9600

const GAME_STATE_NAME := "game_state.cmd"
const UI_STATE_NAME := "ui_state.cmd"

const ALIVE_TIMEOUT_SEC := 2.5
const START_RETRY_MS := 4000
const CHECK_INTERVAL_MS := 500

enum LedMode {
	NORMAL,
	MENU,
	GAME,
}

var _mode: int = LedMode.NORMAL
var _seq: int = 0
var _last_check_ms: int = -999999
var _last_start_ms: int = -999999
var _bridge_pid: int = -1
var _warned_missing_bridge: bool = false

var _last_game_state: String = ""
var _last_ui_state: String = ""


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SPOOL_DIR))
	_remove_if_exists(ProjectSettings.globalize_path(STOP_PATH))
	_remove_if_exists(ProjectSettings.globalize_path(GAME_MODE_PATH))
	ensure_bridge()


func tick() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_check_ms < CHECK_INTERVAL_MS:
		return
	_last_check_ms = now

	if not bridge_alive():
		ensure_bridge()


func bridge_ready() -> bool:
	return FileAccess.file_exists(READY_PATH) and bridge_alive()


func bridge_alive() -> bool:
	var path := ProjectSettings.globalize_path(ALIVE_PATH)
	if not FileAccess.file_exists(path):
		return false

	var modified := FileAccess.get_modified_time(path)
	if modified <= 0:
		return false

	var age := Time.get_unix_time_from_system() - float(modified)
	return age >= -1.0 and age <= ALIVE_TIMEOUT_SEC


func ensure_bridge() -> void:
	if OS.get_name() != "Windows":
		return

	if bridge_alive():
		return

	var now := Time.get_ticks_msec()
	if now - _last_start_ms < START_RETRY_MS:
		return
	_last_start_ms = now

	var bridge_path := ProjectSettings.globalize_path(BRIDGE_SCRIPT_RES)
	if not FileAccess.file_exists(bridge_path):
		if not _warned_missing_bridge:
			_warned_missing_bridge = true
			push_error("HIT MUSIC: BRIDGE_R21.ps1 não encontrado: " + bridge_path)
		return

	_write_text_atomic(
		ProjectSettings.globalize_path(STARTING_PATH),
		str(Time.get_unix_time_from_system())
	)

	var args := PackedStringArray([
		"-NoLogo",
		"-NoProfile",
		"-NonInteractive",
		"-ExecutionPolicy", "Bypass",
		"-WindowStyle", "Hidden",
		"-File", bridge_path,
		"-ComPort", COM_PORT,
		"-BaudRate", str(BAUD_RATE),
		"-SpoolPath", ProjectSettings.globalize_path(SPOOL_DIR)
	])

	_bridge_pid = OS.create_process("powershell.exe", args, false)

	if _bridge_pid <= 0:
		push_error("HIT MUSIC: falha ao iniciar BRIDGE_R21.ps1.")
	else:
		print("HIT MUSIC: bridge R21 iniciada. PID=", _bridge_pid)


func begin_opening() -> void:
	_mode = LedMode.NORMAL
	_leave_game_mode()
	_clear_transient_queue()
	_last_ui_state = ""


func begin_menu() -> void:
	_mode = LedMode.MENU
	_leave_game_mode()
	_clear_transient_queue()
	_last_ui_state = ""


func begin_stage() -> void:
	_mode = LedMode.NORMAL
	_leave_game_mode()
	_clear_transient_queue()
	_last_ui_state = ""


func begin_game() -> void:
	ensure_bridge()

	# Primeiro marca GAME. A bridge para de consumir qualquer fila antiga.
	_mode = LedMode.GAME
	_write_text_atomic(
		ProjectSettings.globalize_path(GAME_MODE_PATH),
		"GAME\n"
	)

	# Depois elimina tudo que sobrou de MENU/COUNT/SCENE.
	_clear_all_spool_files()

	_last_game_state = ""
	_last_ui_state = ""

	# O primeiro frame da partida é sempre preto.
	send_state("MULTI 000000000000000000000000000000000000000000000000")


func end_game() -> void:
	if _mode == LedMode.GAME:
		_mode = LedMode.NORMAL

	_leave_game_mode()
	_last_game_state = ""

	# CLEAR também é estado persistente: se a abertura ou menu publicar
	# ATTRACT/MENU logo depois, o estado novo substitui este CLEAR.
	send("CLEAR")


func send(command: String) -> bool:
	var cmd := command.strip_edges()
	if cmd.is_empty():
		return false

	ensure_bridge()

	var op := cmd.get_slice(" ", 0).to_upper()

	# GAME: somente o quadro completo MULTI pode tocar no hardware.
	if _mode == LedMode.GAME:
		if op == "MULTI":
			return send_state(cmd)

		# Toda lógica herdada antiga é deliberadamente ignorada:
		# LED/PULSE/HIT/ERR/READY/SCENE/etc.
		return true

	# MENU: apenas estado persistente de MENU/CLEAR.
	# Feedback antigo HIT/PULSE é ignorado para manter D2/D3 fixos.
	if _mode == LedMode.MENU:
		if op == "MENU" or op == "CLEAR":
			return _send_ui_state(cmd)
		return true

	# Fora do GAME, estes comandos representam um estado persistente.
	if op in ["ATTRACT", "MENU", "SCENE", "SCENE2", "ALL", "CLEAR"]:
		return _send_ui_state(cmd)

	# Contagem/efeitos temporários podem continuar em fila fora da partida.
	return _enqueue_transient(cmd)


func enviar(command: String) -> bool:
	return send(command)


func send_state(command: String) -> bool:
	var cmd := command.strip_edges()
	if not cmd.begins_with("MULTI "):
		return false

	if cmd == _last_game_state:
		return true

	_last_game_state = cmd

	var state_path := ProjectSettings.globalize_path(SPOOL_DIR).path_join(GAME_STATE_NAME)
	return _write_text_atomic(state_path, cmd + "\n")


func clear() -> bool:
	return send("CLEAR")


func apagar_guias() -> bool:
	return send_state("MULTI 000000000000000000000000000000000000000000000000")


func menu(cor_a: Color, cor_b: Color, idx_a: int = 0, idx_b: int = 1) -> bool:
	return send(
		"MENU %d %d %d %d %d %d %d %d" % [
			roundi(cor_a.r * 255.0),
			roundi(cor_a.g * 255.0),
			roundi(cor_a.b * 255.0),
			roundi(cor_b.r * 255.0),
			roundi(cor_b.g * 255.0),
			roundi(cor_b.b * 255.0),
			idx_a,
			idx_b
		]
	)


func shutdown() -> void:
	if OS.get_name() != "Windows":
		return

	_mode = LedMode.NORMAL
	_leave_game_mode()

	var stop_abs := ProjectSettings.globalize_path(STOP_PATH)
	var file := FileAccess.open(stop_abs, FileAccess.WRITE)
	if file != null:
		file.store_string("STOP\n")
		file.flush()
		file.close()


func _exit_tree() -> void:
	shutdown()


func _send_ui_state(cmd: String) -> bool:
	if cmd == _last_ui_state:
		return true

	_last_ui_state = cmd

	var path := ProjectSettings.globalize_path(SPOOL_DIR).path_join(UI_STATE_NAME)
	return _write_text_atomic(path, cmd + "\n")


func _enqueue_transient(cmd: String) -> bool:
	var spool_abs := ProjectSettings.globalize_path(SPOOL_DIR)
	DirAccess.make_dir_recursive_absolute(spool_abs)

	_seq = (_seq + 1) % 1000000
	var name := "cmd_%020d_%06d_%06d.cmd" % [
		Time.get_ticks_usec(),
		OS.get_process_id(),
		_seq
	]

	return _write_text_atomic(spool_abs.path_join(name), cmd + "\n")


func _leave_game_mode() -> void:
	_remove_if_exists(ProjectSettings.globalize_path(GAME_MODE_PATH))
	_remove_if_exists(
		ProjectSettings.globalize_path(SPOOL_DIR).path_join(GAME_STATE_NAME)
	)


func _clear_transient_queue() -> void:
	var spool_abs := ProjectSettings.globalize_path(SPOOL_DIR)
	var dir := DirAccess.open(spool_abs)
	if dir == null:
		return

	for name in dir.get_files():
		if name.begins_with("cmd_") and name.ends_with(".cmd"):
			dir.remove(name)


func _clear_all_spool_files() -> void:
	var spool_abs := ProjectSettings.globalize_path(SPOOL_DIR)
	DirAccess.make_dir_recursive_absolute(spool_abs)

	var dir := DirAccess.open(spool_abs)
	if dir == null:
		return

	for name in dir.get_files():
		if (
			name.ends_with(".cmd")
			or name.ends_with(".processing")
			or name.contains(".tmp_")
			or name.ends_with(".tmp")
		):
			dir.remove(name)


func _remove_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _write_text_atomic(final_path: String, content: String) -> bool:
	var tmp := final_path + ".tmp_%d_%d" % [
		OS.get_process_id(),
		Time.get_ticks_usec()
	]

	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_error("HIT MUSIC: não foi possível criar " + tmp)
		return false

	file.store_string(content)
	file.flush()
	file.close()

	for _attempt in range(5):
		if FileAccess.file_exists(final_path):
			DirAccess.remove_absolute(final_path)

		var err := DirAccess.rename_absolute(tmp, final_path)
		if err == OK:
			return true

		OS.delay_msec(1)

	if FileAccess.file_exists(tmp):
		DirAccess.remove_absolute(tmp)

	push_error("HIT MUSIC: falha ao publicar estado LED atômico.")
	return false
