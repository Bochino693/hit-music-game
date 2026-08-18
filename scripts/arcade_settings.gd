extends Node
## ArcadeSettings — autoload unico dono do estado "modo livre / modo
## credito" e do saldo de creditos. Persiste em disco pra sobreviver
## a fechar/abrir o jogo (o operador nao perde os creditos guardados).
##
## Uso tipico:
##   ArcadeSettings.is_credit_mode()      -> bool
##   ArcadeSettings.try_consume_credit()  -> bool (false = sem credito)
##   ArcadeSettings.add_credit(1)
##   ArcadeSettings.set_mode(ArcadeSettings.Mode.CREDIT)

signal changed
signal credit_inserted(total: int)

const SETTINGS_PATH: String = "user://hit_music_arcade_settings.json"
const CREDIT_INPUT_COOLDOWN_MSEC: int = 140
## SELECT e o botao fisico oficial de ficha. input_credito permanece como
## compatibilidade com gabinetes que ja tenham um pulso dedicado de moeda.
const CREDIT_ACTIONS: Array[String] = ["input_select", "input_credito"]

enum Mode {
	FREE,
	CREDIT,
}

var mode: int = Mode.FREE
var credits: int = 0
var _last_credit_input_msec: int = -1000


func _ready() -> void:
	load_settings()
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	# No modo livre SELECT nao altera saldo. No modo credito o autoload roda
	# sempre, inclusive em gameplay, resultado e transicoes de cena.
	if not is_credit_mode():
		return
	var credit_pressed: bool = false
	for action in CREDIT_ACTIONS:
		if InputMap.has_action(action) and Input.is_action_just_pressed(action):
			credit_pressed = true
			break
	if not credit_pressed:
		return

	var now_msec: int = Time.get_ticks_msec()
	if now_msec - _last_credit_input_msec < CREDIT_INPUT_COOLDOWN_MSEC:
		return
	_last_credit_input_msec = now_msec
	add_credit(1)
	credit_inserted.emit(credits)


func load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return

	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file == null:
		return

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return

	var data: Dictionary = parsed as Dictionary
	mode = (
		Mode.CREDIT
		if str(data.get("mode", "free")).to_lower() == "credit"
		else Mode.FREE
	)
	credits = maxi(0, int(data.get("credits", 0)))


func save_settings() -> void:
	var data := {
		"mode": "credit" if mode == Mode.CREDIT else "free",
		"credits": credits,
	}
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "\t"))
	changed.emit()


func is_credit_mode() -> bool:
	return mode == Mode.CREDIT


func set_mode(new_mode: int) -> void:
	if mode == new_mode:
		return
	mode = new_mode
	save_settings()


func toggle_mode() -> void:
	set_mode(Mode.FREE if mode == Mode.CREDIT else Mode.CREDIT)


func add_credit(amount: int = 1) -> void:
	credits = clampi(credits + amount, 0, 999)
	save_settings()


func set_credits(value: int) -> void:
	var clamped: int = clampi(value, 0, 999)
	if clamped == credits:
		return
	credits = clamped
	save_settings()


func has_credit() -> bool:
	return not is_credit_mode() or credits > 0


## Consome 1 credito se estiver em modo credito. Retorna true quando
## pode prosseguir (modo livre, ou credito consumido com sucesso);
## false quando bloqueado por falta de credito — quem chamou deve
## mostrar o aviso de "insira ficha" e nao iniciar a partida.
func try_consume_credit() -> bool:
	if not is_credit_mode():
		return true
	if credits <= 0:
		return false
	credits -= 1
	save_settings()
	return true
