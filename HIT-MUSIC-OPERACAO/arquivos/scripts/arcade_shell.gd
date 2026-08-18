extends Node
## ArcadeShell — a casca da maquina: atalho global de Configuracoes e
## travamento de quiosque.
##
## POR QUE ISTO E UM AUTOLOAD
## O F9 antes dependia de cada tela lembrar de chamar o SettingsGate no
## proprio _input(). Tres telas chamavam, o resto nao — entao o atalho
## simplesmente nao existia na maioria do jogo, e qualquer tela nova
## nasceria sem ele. Aqui o autoload escuta uma vez so e vale em todo
## lugar, inclusive nas telas que ainda nem foram escritas.

const SETTINGS_GATE: Script = preload("res://scripts/hit_music_r7/settings_gate.gd")
const CONFIG_SCENE_PATH: String = "res://scenes/config.tscn"

## Reafirma o foco/topo neste intervalo. A janela pode perder o foco por
## coisa que o jogo nao controla (notificacao do sistema, outro processo
## subindo), e sem isso a tela do jogo ficaria atras para sempre.
const REAFIRMAR_FOCO_SEG: float = 1.0

var _tempo_desde_foco: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	## O jogo decide quando morre, nao o gerenciador de janelas: sem isto,
	## o X da janela e o Alt+F4 fecham a maquina no meio de uma partida.
	get_tree().set_auto_accept_quit(false)
	_aplicar_quiosque()


func _notification(what: int) -> void:
	## Fechar pela janela (X, Alt+F4, "encerrar tarefa" leve) e ignorado.
	## A unica saida e o atalho de servico em _input().
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_tempo_desde_foco = REAFIRMAR_FOCO_SEG


func _process(delta: float) -> void:
	_tempo_desde_foco += delta
	if _tempo_desde_foco < REAFIRMAR_FOCO_SEG:
		return
	_tempo_desde_foco = 0.0
	if not DisplayServer.window_is_focused():
		_trazer_para_frente()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var tecla: InputEventKey = event as InputEventKey

	## SAIDA DE SERVICO: Ctrl+Tab. E o unico jeito de fechar o jogo.
	if tecla.keycode == KEY_TAB and tecla.ctrl_pressed:
		get_viewport().set_input_as_handled()
		_sair_de_verdade()
		return

	## Marca como tratado SO quando o painel foi realmente aberto. Dentro
	## das Configuracoes o proprio F9 e o atalho de FECHAR, e durante a
	## partida a tecla e ignorada de proposito — engolir a tecla nesses dois
	## casos deixaria o operador preso na tela sem saida pelo teclado.
	if tecla.keycode == KEY_F9:
		if abrir_configuracoes():
			get_viewport().set_input_as_handled()


## F9 vale em qualquer tela MENOS durante uma partida: abrir o painel do
## operador no meio da musica cortaria audio e LED com a mesa em jogo.
func abrir_configuracoes() -> bool:
	if em_partida():
		return false
	var cena: Node = get_tree().current_scene
	if cena != null and cena.scene_file_path == CONFIG_SCENE_PATH:
		return false   # ja esta nas Configuracoes
	return SETTINGS_GATE.open_settings()


## Uma tela e "partida" quando ela responde por uma musica. Todas as cenas
## de jogo (carmine, demon, naruto...) herdam de stage_final.gd e definem
## `_song_id()`; menu nenhum define. Marcar por metodo evita manter uma
## lista de cenas que envelhece a cada musica nova.
##
## Mas a cena da musica comeca como TELA DE DIFICULDADE, com a musica ainda
## parada — ali o painel do operador nao atrapalha nada, e o atalho ja
## funcionava antes. Por isso, quando a cena sabe responder
## `em_partida_ativa()`, e ela quem decide; o `_song_id()` sozinho fica
## como resposta conservadora para qualquer cena de musica que nao responda.
func em_partida() -> bool:
	var cena: Node = get_tree().current_scene
	if cena == null:
		return false
	if cena.has_method("em_partida_ativa"):
		return bool(cena.call("em_partida_ativa"))
	return cena.has_method("_song_id")


func _aplicar_quiosque() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)


func _trazer_para_frente() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_move_to_foreground()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)


func _sair_de_verdade() -> void:
	## Solta o sempre-no-topo antes de sair: se o processo morrer com a
	## flag ligada, a janela pode ficar presa na frente enquanto fecha.
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, false)
	get_tree().quit()
