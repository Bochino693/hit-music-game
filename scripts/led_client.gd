extends Node
## HIT MUSIC — LED CLIENT CLEAN
##
## ÚNICA autoridade de LED do Godot.
##
## Editor:
##   res://BRIDGE_HIT_MUSIC.ps1 é um arquivo físico da raiz do projeto.
##
## Executável:
##   a bridge está dentro do PCK/EXE; o Godot copia os bytes para
##   user://hit_music_serial/BRIDGE_HIT_MUSIC.ps1 e executa essa cópia.
##
## Comunicação:
##   - porta serial = AUTO (a bridge encontra quem responde HITMUSIC_OK)
##   - baud = 9600
##   - UI usa ui_state.cmd persistente
##   - GAME usa game_state.cmd persistente
##   - somente MULTI governa LEDs durante a partida
##   - filas antigas não governam o GAME

const BASE_DIR := "user://hit_music_serial"
const SPOOL_DIR := BASE_DIR + "/spool"

const ALIVE_PATH := BASE_DIR + "/bridge_alive.txt"
const READY_PATH := BASE_DIR + "/bridge_ready.txt"
const STOP_PATH := BASE_DIR + "/bridge_stop.txt"
const GAME_MODE_PATH := BASE_DIR + "/game_mode.flag"

const BRIDGE_RES := "res://BRIDGE_HIT_MUSIC.ps1"
const BRIDGE_USER := BASE_DIR + "/BRIDGE_HIT_MUSIC.ps1"

const UI_STATE_NAME := "ui_state.cmd"
const GAME_STATE_NAME := "game_state.cmd"

const BAUD_RATE := 9600
const PORT_REQUEST := "AUTO"

const CHECK_INTERVAL_MS := 500
const START_RETRY_MS := 5000
const ALIVE_TIMEOUT_SEC := 2.0

enum LedMode {
	NORMAL,
	MENU,
	GAME,
}

var _mode: int = LedMode.NORMAL
var _bridge_path: String = ""
var _last_check_ms: int = -999999
var _last_start_ms: int = -999999
var _last_ui_state: String = ""
var _last_game_state: String = ""
var _seq: int = 0

## Fila de escrita assincrona. As chamadas de gameplay (hit/miss/troca de
## lane) nunca tocam disco na thread principal: elas so atualizam
## _pending e sinalizam a thread de escrita. Isso elimina o
## travamento perceptivel que acontecia sempre que um tazo trocava
## para o efeito de acerto (a escrita sincrona + retry com
## OS.delay_msec rodava direto no frame do jogo).
var _pending: Dictionary = {}
var _pending_mutex: Mutex = Mutex.new()
var _pending_semaphore: Semaphore = Semaphore.new()
var _writer_thread: Thread = null
var _writer_running: bool = true


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(SPOOL_DIR)
	)

	_remove_if_exists(
		ProjectSettings.globalize_path(STOP_PATH)
	)
	_remove_if_exists(
		ProjectSettings.globalize_path(GAME_MODE_PATH)
	)

	_bridge_path = _resolve_bridge_path()

	_writer_running = true
	_writer_thread = Thread.new()
	_writer_thread.start(Callable(self, "_writer_loop"))

	set_process(true)
	ensure_bridge()

	# A abertura deve acender mesmo que opening.gd não tenha lógica LED.
	begin_opening()
	send("ATTRACT")


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()

	if now - _last_check_ms < CHECK_INTERVAL_MS:
		return

	_last_check_ms = now
	ensure_bridge()


func bridge_ready() -> bool:
	return (
		FileAccess.file_exists(READY_PATH)
		and _alive_is_fresh()
	)


func bridge_alive() -> bool:
	return bridge_ready()


func ensure_bridge() -> void:
	if OS.get_name() != "Windows":
		return

	if bridge_ready():
		return

	var now := Time.get_ticks_msec()

	if now - _last_start_ms < START_RETRY_MS:
		return

	_last_start_ms = now

	if _bridge_path.is_empty():
		_bridge_path = _resolve_bridge_path()

	if (
		_bridge_path.is_empty()
		or not FileAccess.file_exists(_bridge_path)
	):
		push_error(
			"HIT MUSIC LED: bridge física não encontrada."
		)
		return

	var powershell := _powershell_path()

	var args := PackedStringArray([
		"-NoLogo",
		"-NoProfile",
		"-NonInteractive",
		"-ExecutionPolicy", "Bypass",
		"-WindowStyle", "Hidden",
		"-File", _bridge_path,
		"-ComPort", PORT_REQUEST,
		"-BaudRate", str(BAUD_RATE),
		"-SpoolPath",
		ProjectSettings.globalize_path(SPOOL_DIR),
	])

	var pid := OS.create_process(
		powershell,
		args,
		false
	)

	if pid <= 0:
		push_error(
			"HIT MUSIC LED: não foi possível iniciar a bridge."
		)
	else:
		print(
			"HIT MUSIC LED: bridge iniciada. PID=",
			pid
		)


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

	_mode = LedMode.GAME

	_write_atomic(
		ProjectSettings.globalize_path(GAME_MODE_PATH),
		"GAME\n"
	)

	_clear_transient_queue()
	_last_game_state = ""

	# Primeiro quadro da partida é sempre totalmente apagado.
	send_state(
		"MULTI 000000000000000000000000000000000000000000000000"
	)


func end_game() -> void:
	if _mode == LedMode.GAME:
		_mode = LedMode.NORMAL

	_leave_game_mode()
	_last_game_state = ""
	send("CLEAR")


func send(command: String) -> bool:
	var cmd := command.strip_edges()

	if cmd.is_empty():
		return false

	ensure_bridge()

	var op := cmd.get_slice(" ", 0).to_upper()

	if _mode == LedMode.GAME:
		if op == "MULTI":
			return send_state(cmd)

		# Bloqueia LED/HIT/PULSE/ERR/READY herdados durante GAME.
		return true

	if _mode == LedMode.MENU:
		if op == "MENU" or op == "CLEAR":
			return _write_ui_state(cmd)

		if op == "LED":
			# Guia estatica adicional além das 2 lanes do proprio
			# comando MENU (que so acende idxA/idxB, tudo mais fica
			# apagado) — usado quando uma tela de menu precisa de um
			# terceiro botao aceso (ex.: input D no seletor de musica).
			return _enqueue_transient(cmd)

		# Demais comandos (HIT/PULSE/OK/ERR) continuam sem flash fisico no menu.
		return true

	if op in [
		"ATTRACT",
		"MENU",
		"SCENE",
		"SCENE2",
		"ALL",
		"CLEAR",
	]:
		return _write_ui_state(cmd)

	# Apenas efeitos temporários fora do GAME entram em fila.
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

	var spool_abs := ProjectSettings.globalize_path(
		SPOOL_DIR
	)

	return _write_atomic(
		spool_abs.path_join(GAME_STATE_NAME),
		cmd + "\n"
	)


func clear() -> bool:
	return send("CLEAR")


func apagar_guias() -> bool:
	if _mode == LedMode.GAME:
		return send_state(
			"MULTI 000000000000000000000000000000000000000000000000"
		)

	return send("CLEAR")


func menu(
	cor_a: Color,
	cor_b: Color,
	idx_a: int = 0,
	idx_b: int = 1
) -> bool:
	return send(
		"MENU %d %d %d %d %d %d %d %d"
		% [
			roundi(clampf(cor_a.r, 0.0, 1.0) * 255.0),
			roundi(clampf(cor_a.g, 0.0, 1.0) * 255.0),
			roundi(clampf(cor_a.b, 0.0, 1.0) * 255.0),
			roundi(clampf(cor_b.r, 0.0, 1.0) * 255.0),
			roundi(clampf(cor_b.g, 0.0, 1.0) * 255.0),
			roundi(clampf(cor_b.b, 0.0, 1.0) * 255.0),
			clampi(idx_a, 0, 7),
			clampi(idx_b, 0, 7),
		]
	)


func shutdown() -> void:
	if OS.get_name() != "Windows":
		return

	_mode = LedMode.NORMAL
	_leave_game_mode()

	# Estado final visível caso a bridge ainda processe antes do STOP.
	_write_ui_state("CLEAR")

	var stop_abs := ProjectSettings.globalize_path(
		STOP_PATH
	)

	var file := FileAccess.open(
		stop_abs,
		FileAccess.WRITE
	)

	if file != null:
		file.store_string("STOP\n")
		file.flush()
		file.close()


func _exit_tree() -> void:
	shutdown()
	_stop_writer_thread()


func _stop_writer_thread() -> void:
	if _writer_thread == null:
		return
	_pending_mutex.lock()
	_writer_running = false
	_pending_mutex.unlock()
	_pending_semaphore.post()
	if _writer_thread.is_started():
		_writer_thread.wait_to_finish()
	_writer_thread = null


func _write_ui_state(cmd: String) -> bool:
	if cmd == _last_ui_state:
		return true

	_last_ui_state = cmd

	var spool_abs := ProjectSettings.globalize_path(
		SPOOL_DIR
	)

	return _write_atomic(
		spool_abs.path_join(UI_STATE_NAME),
		cmd + "\n"
	)


func _enqueue_transient(cmd: String) -> bool:
	var spool_abs := ProjectSettings.globalize_path(
		SPOOL_DIR
	)

	DirAccess.make_dir_recursive_absolute(
		spool_abs
	)

	_seq = (_seq + 1) % 1000000

	var name := (
		"cmd_%020d_%06d_%06d.cmd"
		% [
			Time.get_ticks_usec(),
			OS.get_process_id(),
			_seq,
		]
	)

	return _write_atomic(
		spool_abs.path_join(name),
		cmd + "\n"
	)


func _leave_game_mode() -> void:
	_remove_if_exists(
		ProjectSettings.globalize_path(
			GAME_MODE_PATH
		)
	)


func _clear_transient_queue() -> void:
	var spool_abs := ProjectSettings.globalize_path(
		SPOOL_DIR
	)

	var dir := DirAccess.open(
		spool_abs
	)

	if dir == null:
		return

	for name in dir.get_files():
		if (
			name.begins_with("cmd_")
			and name.ends_with(".cmd")
		):
			dir.remove(name)


func _resolve_bridge_path() -> String:
	if OS.has_feature("editor"):
		var editor_path := ProjectSettings.globalize_path(
			BRIDGE_RES
		)

		if FileAccess.file_exists(
			editor_path
		):
			return editor_path

		push_error(
			"HIT MUSIC LED: BRIDGE_HIT_MUSIC.ps1 não está "
			+ "na raiz do projeto."
		)
		return ""

	# No executável, a bridge pode estar dentro do PCK.
	var source := FileAccess.open(
		BRIDGE_RES,
		FileAccess.READ
	)

	if source == null:
		push_error(
			"HIT MUSIC LED: bridge não entrou no export."
		)
		return ""

	var size := source.get_length()

	if size <= 0:
		source.close()
		return ""

	var bytes := source.get_buffer(
		size
	)
	source.close()

	var target := FileAccess.open(
		BRIDGE_USER,
		FileAccess.WRITE
	)

	if target == null:
		push_error(
			"HIT MUSIC LED: falha ao extrair bridge para user://."
		)
		return ""

	target.store_buffer(
		bytes
	)
	target.flush()
	target.close()

	var physical := ProjectSettings.globalize_path(
		BRIDGE_USER
	)

	if not FileAccess.file_exists(
		physical
	):
		return ""

	return physical


func _powershell_path() -> String:
	var windir := OS.get_environment(
		"WINDIR"
	)

	if not windir.is_empty():
		var candidate := windir.path_join(
			"System32"
		)
		candidate = candidate.path_join(
			"WindowsPowerShell"
		)
		candidate = candidate.path_join(
			"v1.0"
		)
		candidate = candidate.path_join(
			"powershell.exe"
		)

		if FileAccess.file_exists(
			candidate
		):
			return candidate

	return "powershell.exe"


func _alive_is_fresh() -> bool:
	var path := ProjectSettings.globalize_path(
		ALIVE_PATH
	)

	if not FileAccess.file_exists(
		path
	):
		return false

	var modified := FileAccess.get_modified_time(
		path
	)

	if modified <= 0:
		return false

	var age := (
		Time.get_unix_time_from_system()
		- float(modified)
	)

	return (
		age >= -1.0
		and age <= ALIVE_TIMEOUT_SEC
	)


func _remove_if_exists(path: String) -> void:
	if FileAccess.file_exists(
		path
	):
		DirAccess.remove_absolute(
			path
		)


func _write_atomic(
	final_path: String,
	content: String
) -> bool:
	# Nunca toca disco aqui: apenas registra a ultima versao desejada
	# desse arquivo e acorda a thread de escrita. Chamadas repetidas
	# no mesmo frame (ex.: varias lanes mudando de cor no mesmo hit)
	# colapsam automaticamente em uma unica escrita com o conteudo
	# mais recente, em vez de empilhar I/O bloqueante no frame do jogo.
	_pending_mutex.lock()
	_pending[final_path] = content
	_pending_mutex.unlock()
	_pending_semaphore.post()
	return true


func _writer_loop() -> void:
	while true:
		_pending_semaphore.wait()

		_pending_mutex.lock()
		var running: bool = _writer_running
		var batch: Dictionary = _pending.duplicate()
		_pending.clear()
		_pending_mutex.unlock()

		for final_path in batch.keys():
			_write_atomic_blocking(str(final_path), str(batch[final_path]))

		if not running:
			return


func _write_atomic_blocking(
	final_path: String,
	content: String
) -> bool:
	# So roda dentro de _writer_loop, na thread de background: pode
	# bloquear e usar OS.delay_msec livremente sem afetar o frame rate.
	var tmp := (
		final_path
		+ ".tmp_%d_%d"
		% [
			OS.get_process_id(),
			Time.get_ticks_usec(),
		]
	)

	var file := FileAccess.open(
		tmp,
		FileAccess.WRITE
	)

	if file == null:
		push_error(
			"HIT MUSIC LED: falha ao criar estado temporário."
		)
		return false

	file.store_string(
		content
	)
	file.flush()
	file.close()

	for _attempt in range(8):
		if FileAccess.file_exists(
			final_path
		):
			DirAccess.remove_absolute(
				final_path
			)

		var err := DirAccess.rename_absolute(
			tmp,
			final_path
		)

		if err == OK:
			return true

		OS.delay_msec(
			2
		)

	_remove_if_exists(
		tmp
	)

	push_error(
		"HIT MUSIC LED: falha ao publicar estado."
	)
	return false