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
##
## O intervalo e curto de proposito: numa mesa touch o jogador nao "clica
## de volta" na janela do jogo, ele so ve a partida sumir. Um segundo
## inteiro atras de outra janela ja perde notas.
const REAFIRMAR_FOCO_SEG: float = 0.35

## Script que desliga o que o Windows desenha ou abre por cima do jogo
## (marca cinza do dedo, notificacoes, teclado virtual, janela do
## pendrive, protetor de tela). Mesmo esquema da bridge de LED: no editor
## roda o arquivo da raiz; no executavel os bytes saem do PCK para o
## user:// e a copia e que e executada.
const QUIOSQUE_RES: String = "res://QUIOSQUE_HIT_MUSIC.ps1"
const QUIOSQUE_USER_DIR: String = "user://hit_music_quiosque"
const QUIOSQUE_USER: String = QUIOSQUE_USER_DIR + "/QUIOSQUE_HIT_MUSIC.ps1"

var _tempo_desde_foco: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	## O jogo decide quando morre, nao o gerenciador de janelas: sem isto,
	## o X da janela e o Alt+F4 fecham a maquina no meio de uma partida.
	get_tree().set_auto_accept_quit(false)
	_aplicar_quiosque()
	_instalar_cursor_invisivel()
	_preparar_windows_para_touch()


func _notification(what: int) -> void:
	## Fechar pela janela (X, Alt+F4, "encerrar tarefa" leve) e ignorado.
	## A unica saida e o atalho de servico em _input().
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_tempo_desde_foco = REAFIRMAR_FOCO_SEG


func _process(delta: float) -> void:
	## Todo quadro, em qualquer tela: o ponteiro nao pode existir. E so
	## uma leitura de enum; a escrita so acontece se alguem tiver mudado.
	_esconder_ponteiro()

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
	_esconder_ponteiro()


func _trazer_para_frente() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_move_to_foreground()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	DisplayServer.window_request_attention()


## ---------------------------------------------------------------
## PONTEIRO: NUNCA, EM TELA NENHUMA
##
## A moldura touch emula um mouse. Bastava UMA tela pedir
## MOUSE_MODE_VISIBLE para a seta branca ficar parada no vidro no lugar
## onde o ultimo dedo encostou — e era exatamente o que a cena da musica
## fazia, entao o ponteiro so aparecia dentro da partida.
##
## Aqui vale para o jogo inteiro, inclusive telas que ainda nao existem:
##
##   1. o modo escondido e reafirmado a cada quadro (a checagem e so uma
##      leitura de enum; escrever mesmo, so quando alguem mudou);
##   2. alem disso, TODAS as formas de cursor recebem uma imagem
##      totalmente transparente. Se algum ponto do Godot (ou um Control
##      com cursor proprio) devolver o ponteiro por um quadro, o que
##      aparece na mesa continua sendo nada.
## ---------------------------------------------------------------
func _esconder_ponteiro() -> void:
	if Input.get_mouse_mode() != Input.MOUSE_MODE_HIDDEN:
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)


func _instalar_cursor_invisivel() -> void:
	var imagem := Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
	imagem.fill(Color(0.0, 0.0, 0.0, 0.0))

	var textura := ImageTexture.create_from_image(imagem)
	if textura == null:
		return

	for forma in [
		Input.CURSOR_ARROW,
		Input.CURSOR_IBEAM,
		Input.CURSOR_POINTING_HAND,
		Input.CURSOR_CROSS,
		Input.CURSOR_WAIT,
		Input.CURSOR_BUSY,
		Input.CURSOR_DRAG,
		Input.CURSOR_CAN_DROP,
		Input.CURSOR_FORBIDDEN,
		Input.CURSOR_VSIZE,
		Input.CURSOR_HSIZE,
		Input.CURSOR_BDIAGSIZE,
		Input.CURSOR_FDIAGSIZE,
		Input.CURSOR_MOVE,
		Input.CURSOR_VSPLIT,
		Input.CURSOR_HSPLIT,
		Input.CURSOR_HELP,
	]:
		Input.set_custom_mouse_cursor(textura, forma)


## ---------------------------------------------------------------
## MOLDURA TOUCH: NADA POR CIMA DO JOGO
##
## A mesa e uma tela deitada. O jogador apoia a mao, esbarra na borda,
## segura o dedo parado — e o Windows responde a cada um desses gestos
## com alguma coisa DESENHADA POR CIMA da partida: a bolinha cinza do
## toque, o anel de "segurar = botao direito", a Central de Acoes vindo
## da borda, um aviso de atualizacao, a janela do pendrive, o teclado
## virtual. Nenhum deles some com codigo de jogo: sao ajustes do proprio
## Windows, e e por isso que existe o QUIOSQUE_HIT_MUSIC.ps1.
##
## Roda uma vez por inicializacao, escondido, e nao trava a abertura: o
## processo e disparado e o jogo segue montando a cena.
## ---------------------------------------------------------------
func _preparar_windows_para_touch() -> void:
	if OS.get_name() != "Windows":
		return

	var caminho: String = _resolver_script_quiosque()
	if caminho.is_empty():
		return

	var argumentos := PackedStringArray([
		"-NoLogo",
		"-NoProfile",
		"-NonInteractive",
		"-ExecutionPolicy", "Bypass",
		"-WindowStyle", "Hidden",
		"-File", caminho,
	])

	var pid: int = OS.create_process(_powershell(), argumentos, false)
	if pid <= 0:
		push_warning(
			"HIT MUSIC QUIOSQUE: nao foi possivel preparar o Windows "
			+ "para a moldura touch."
		)


func _resolver_script_quiosque() -> String:
	if OS.has_feature("editor"):
		var no_projeto: String = ProjectSettings.globalize_path(QUIOSQUE_RES)
		if FileAccess.file_exists(no_projeto):
			return no_projeto
		push_warning(
			"HIT MUSIC QUIOSQUE: QUIOSQUE_HIT_MUSIC.ps1 nao esta na raiz "
			+ "do projeto."
		)
		return ""

	# No executavel o .ps1 vive dentro do PCK e precisa virar arquivo
	# fisico para o PowerShell conseguir abrir.
	var origem := FileAccess.open(QUIOSQUE_RES, FileAccess.READ)
	if origem == null:
		push_warning("HIT MUSIC QUIOSQUE: script nao entrou no export.")
		return ""

	var tamanho: int = origem.get_length()
	if tamanho <= 0:
		origem.close()
		return ""

	var bytes: PackedByteArray = origem.get_buffer(tamanho)
	origem.close()

	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(QUIOSQUE_USER_DIR)
	)

	var destino := FileAccess.open(QUIOSQUE_USER, FileAccess.WRITE)
	if destino == null:
		push_warning("HIT MUSIC QUIOSQUE: falha ao extrair o script.")
		return ""

	destino.store_buffer(bytes)
	destino.flush()
	destino.close()

	var fisico: String = ProjectSettings.globalize_path(QUIOSQUE_USER)
	if not FileAccess.file_exists(fisico):
		return ""
	return fisico


func _powershell() -> String:
	var windir: String = OS.get_environment("WINDIR")
	if not windir.is_empty():
		var candidato: String = windir.path_join(
			"System32/WindowsPowerShell/v1.0/powershell.exe"
		)
		if FileAccess.file_exists(candidato):
			return candidato
	return "powershell.exe"


func _sair_de_verdade() -> void:
	## Solta o sempre-no-topo antes de sair: se o processo morrer com a
	## flag ligada, a janela pode ficar presa na frente enquanto fecha.
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, false)
	get_tree().quit()
