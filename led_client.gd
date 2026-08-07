extends Node
## led_client.gd — HIT MUSIC R17
##
## Autoload global. ÚNICO caminho de saída do Godot:
## Godot -> arquivos .cmd -> BRIDGE_R17.ps1 -> COM5 -> Arduino.
##
## O Godot nunca abre COM5 diretamente.

const BASE_DIR := "user://hit_music_serial"
const SPOOL_DIR := BASE_DIR + "/spool"
const ALIVE_PATH := BASE_DIR + "/bridge_alive.txt"
const READY_PATH := BASE_DIR + "/bridge_ready.txt"
const STARTING_PATH := BASE_DIR + "/bridge_starting.txt"
const STOP_PATH := BASE_DIR + "/bridge_stop.txt"

const BRIDGE_SCRIPT_RES := "res://BRIDGE_R17.ps1"
const COM_PORT := "COM5"
const BAUD_RATE := 9600

const ALIVE_TIMEOUT_SEC := 2.5
const START_RETRY_MS := 4000
const CHECK_INTERVAL_MS := 500

var _seq: int = 0
var _last_check_ms: int = -999999
var _last_start_ms: int = -999999
var _bridge_pid: int = -1
var _warned_missing_bridge: bool = false


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SPOOL_DIR))

	# Um fechamento anterior pode ter deixado o arquivo de parada por alguns ms.
	# Ao iniciar uma nova execução, garantimos estado limpo.
	var stop_abs := ProjectSettings.globalize_path(STOP_PATH)
	if FileAccess.file_exists(stop_abs):
		DirAccess.remove_absolute(stop_abs)

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
			push_error("HIT MUSIC: BRIDGE_R17.ps1 não encontrado na raiz do projeto: " + bridge_path)
		return

	# Marca "starting" ANTES do create_process. Isso também impede o opening.gd
	# legado de iniciar a bridge antiga durante esta pequena janela de startup.
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
		"-SpoolPath", ProjectSettings.globalize_path(SPOOL_DIR),
	])

	_bridge_pid = OS.create_process("powershell.exe", args, false)
	if _bridge_pid <= 0:
		push_error("HIT MUSIC: não foi possível iniciar BRIDGE_R17.ps1.")
	else:
		print("HIT MUSIC: bridge R14 solicitada. PID=", _bridge_pid)


func send(command: String) -> bool:
	var cmd := command.strip_edges()
	if cmd.is_empty():
		return false

	ensure_bridge()

	var spool_abs := ProjectSettings.globalize_path(SPOOL_DIR)
	DirAccess.make_dir_recursive_absolute(spool_abs)

	_seq = (_seq + 1) % 1000000
	var name := "cmd_%020d_%06d_%06d.cmd" % [
		Time.get_ticks_usec(),
		OS.get_process_id(),
		_seq
	]
	var final_path := spool_abs.path_join(name)

	return _write_text_atomic(final_path, cmd + "\n")


# Alias para código antigo que já chama enviar().
func enviar(command: String) -> bool:
	return send(command)


func clear() -> bool:
	return send("CLEAR")


func apagar_guias() -> bool:
	return send("MULTI 000000000000000000000000000000000000000000000000")


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
	# Solicita desligamento LIMPO da bridge.
	# A própria bridge envia CLEAR diretamente ao Arduino antes de fechar a COM,
	# então os LEDs apagam mesmo que o spool ainda tenha algum comando pendente.
	if OS.get_name() != "Windows":
		return

	var stop_abs := ProjectSettings.globalize_path(STOP_PATH)
	var f := FileAccess.open(stop_abs, FileAccess.WRITE)
	if f != null:
		f.store_string("STOP\n")
		f.flush()
		f.close()


func _exit_tree() -> void:
	# Autoload só sai da árvore quando o aplicativo realmente está encerrando.
	shutdown()


func _write_text_atomic(final_path: String, content: String) -> bool:
	var tmp := final_path + ".tmp_%d_%d" % [
		OS.get_process_id(),
		Time.get_ticks_usec()
	]

	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("HIT MUSIC: não foi possível criar " + tmp)
		return false

	f.store_string(content)
	f.flush()
	f.close()

	if FileAccess.file_exists(final_path):
		DirAccess.remove_absolute(final_path)

	var err := DirAccess.rename_absolute(tmp, final_path)
	if err != OK:
		if FileAccess.file_exists(tmp):
			DirAccess.remove_absolute(tmp)
		push_error("HIT MUSIC: falha ao publicar comando serial. Erro=" + str(err))
		return false

	return true
