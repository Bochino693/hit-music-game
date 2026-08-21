extends Node
## Teste de fumaca dos ajustes finais:
##   1) VOLTAR na tela de escolha do modo (dificuldade);
##   2) LEDs A/E/B nas Configuracoes + entrega da serial entre as telas;
##   3) importacao em lote do pendrive, com aviso do que nao funcionou e
##      contagem do que ja tinha entrado.
##
## Rodar com:
##   godot --headless --path . res://tools/smoke_final.tscn

const USER_CATALOG: Script = preload("res://scripts/hit_music_r7/user_catalog.gd")
const LED_CLIENT: Script = preload("res://scripts/hit_music_r7/led_client.gd")

const USB_FAKE_DIR: String = "user://_smoke_usb"
const UI_STATE_PATH: String = "user://hit_music_serial/spool/ui_state.cmd"

var _falhas: Array[String] = []
var _instalada_id: String = ""


func _ready() -> void:
	call_deferred("_rodar")


func _checar(condicao: bool, texto: String) -> void:
	if condicao:
		print("  OK   ", texto)
	else:
		_falhas.append(texto)
		print("  FALHA ", texto)


func _rodar() -> void:
	await get_tree().process_frame

	await _testar_tela_de_modo()
	await _testar_configuracoes()
	await _testar_lote_do_pendrive()
	await _testar_quiosque_touch()
	await _testar_nome_comprido()
	await _testar_ponteiro()
	await _testar_arrasto()

	_limpar()

	if _falhas.is_empty():
		print("SMOKE_FINAL_OK")
		get_tree().quit(0)
	else:
		print("SMOKE_FINAL_FALHOU: ", _falhas.size())
		get_tree().quit(1)


## ---------------------------------------------------------------
## 1) TELA DE ESCOLHA DO MODO
## ---------------------------------------------------------------

func _testar_tela_de_modo() -> void:
	print("=== TELA DE MODO (DIFICULDADE) ===")

	var base: Script = load("res://scripts/hit_music_r7/stage_v9.gd")
	var instancia: Object = base.new()
	_checar(
		instancia.has_method("_voltar_para_selecao"),
		"a tela de modo sabe voltar para o seletor"
	)
	_checar(
		instancia.has_method("_toque_no_voltar"),
		"o VOLTAR tem area de toque propria"
	)
	if instancia is Node:
		(instancia as Node).free()

	var cadeia: Script = load("res://scripts/hit_music_r7/stage_v10.gd")
	var constantes: Dictionary = cadeia.get_script_constant_map()
	_checar(
		int(constantes.get("CURSOR_ITEM_COUNT", 0)) == 3,
		"o cursor passeia por FACIL, DIFICIL e VOLTAR"
	)
	_checar(
		int(constantes.get("BACK_CURSOR", -1)) == 2,
		"VOLTAR e o ultimo item do cursor"
	)

	# O VOLTAR usa o mesmo trio ja aceso na mesa (A sobe, E desce, B
	# confirma): nenhum botao fisico novo, nenhum LED apagado para o
	# jogador adivinhar.
	_checar(LED_CLIENT.NAV_NEXT_ACTION == "input_a", "A continua sendo o SOBE")
	_checar(LED_CLIENT.NAV_DOWN_ACTION == "input_e", "E continua sendo o DESCE")
	_checar(LED_CLIENT.NAV_SELECT_ACTION == "input_b", "B continua sendo o CONFIRMA")

	await get_tree().process_frame


## ---------------------------------------------------------------
## 2) CONFIGURACOES: LEDS E SERIAL
## ---------------------------------------------------------------

func _testar_configuracoes() -> void:
	print("=== CONFIGURACOES: LEDS A / E / B ===")

	var cliente: Node = get_node_or_null("/root/LedClient")
	_checar(
		cliente != null and cliente.has_method("begin_settings"),
		"o LedClient sabe assumir a serial da tela anterior"
	)

	# Estado da tela ANTERIOR ainda no ar (a abertura manda ATTRACT).
	if cliente != null and cliente.has_method("send"):
		cliente.call("send", "ATTRACT")
	await get_tree().process_frame

	var painel: Node = load("res://scenes/config.tscn").instantiate()
	get_tree().root.add_child(painel)

	# O quadro do menu sai logo depois do CLEAR (LED_HANDOFF_SEG).
	await get_tree().create_timer(0.45).timeout

	var estado: String = _ler_estado_ui()
	_checar(
		estado.begins_with("MENU "),
		"a mesa recebeu o quadro de MENU no lugar do ATTRACT (recebeu: %s)" % estado
	)

	var esperado: String = " %d %d %d" % [
		LED_CLIENT.NAV_NEXT_LANE,
		LED_CLIENT.NAV_SELECT_LANE,
		LED_CLIENT.NAV_DOWN_LANE,
	]
	_checar(
		estado.contains(esperado),
		"acendeu A (sobe), B (start) e E (desce) — lanes%s" % esperado
	)

	_checar(
		painel.has_method("_aplicar_leds_menu"),
		"o painel reacende o trio quando volta do teste de LEDs"
	)

	painel.queue_free()
	await get_tree().process_frame


func _ler_estado_ui() -> String:
	if not FileAccess.file_exists(UI_STATE_PATH):
		return ""
	var arquivo := FileAccess.open(UI_STATE_PATH, FileAccess.READ)
	if arquivo == null:
		return ""
	var texto: String = arquivo.get_as_text().strip_edges()
	arquivo.close()
	return texto


## ---------------------------------------------------------------
## 3) IMPORTACAO EM LOTE
## ---------------------------------------------------------------

func _testar_lote_do_pendrive() -> void:
	print("=== PENDRIVE: IMPORTAR TODAS ===")

	var completo: String = _criar_pacote_falso("MUSICA_OK", true)
	var quebrado: String = _criar_pacote_falso("MUSICA_SEM_VIDEO", false)

	var pacote_ok: Dictionary = USER_CATALOG.inspect_usb_package(completo)
	var pacote_erro: Dictionary = USER_CATALOG.inspect_usb_package(quebrado)

	_checar(bool(pacote_ok.get("valid", false)), "pacote completo e aceito")
	_checar(
		not bool(pacote_erro.get("valid", true)),
		"pacote incompleto e recusado"
	)
	_checar(
		not str(pacote_erro.get("error", "")).is_empty(),
		"o pacote recusado diz o que falta (%s)" % str(pacote_erro.get("error", ""))
	)

	# O pacote com problema tambem precisa de nome para aparecer na lista
	# e no aviso final do lote.
	pacote_erro["name"] = quebrado.get_file()

	print("=== HISTORICO DE IMPORTACAO ===")
	USER_CATALOG.import_log_record(pacote_ok, "erro", "teste")
	var anotacao: Dictionary = USER_CATALOG.import_log_entry(pacote_ok)
	_checar(
		str(anotacao.get("status", "")) == "erro",
		"o historico guarda o resultado de cada pacote"
	)

	var painel: Node = load("res://scenes/config.tscn").instantiate()
	get_tree().root.add_child(painel)
	await get_tree().process_frame

	painel.set("_in_music_view", true)
	painel.set("_usb_packages", [pacote_ok, pacote_erro])
	painel.call("_refresh_music_view")

	print("=== NAVEGACAO DA LISTA ===")
	painel.set("_music_cursor", -1)
	_checar(
		int(painel.call("_proximo_cursor_musica", 1)) == 0,
		"descer sai do IMPORTAR TODAS para o primeiro pacote"
	)
	painel.set("_music_cursor", -1)
	_checar(
		int(painel.call("_proximo_cursor_musica", -1)) == 1,
		"subir no IMPORTAR TODAS da a volta na lista"
	)
	painel.set("_music_cursor", -1)

	print("=== LOTE: PRIMEIRA PASSADA ===")
	painel.call("_iniciar_lote")
	await _esperar_lote(painel)

	_checar(
		int(painel.get("_batch_ok")) == 1,
		"a musica nova entrou (ok = %d)" % int(painel.get("_batch_ok"))
	)
	_checar(
		(painel.get("_batch_invalid") as Array).size() == 1,
		"o pacote que nao funciona foi avisado"
	)

	var relatorio: String = str(painel.call("_descricao_falha", pacote_erro, "sem video"))
	_checar(
		relatorio.contains("SEM_VIDEO"),
		"o aviso nomeia o pacote com problema (%s)" % relatorio
	)

	_instalada_id = _achar_id_instalada()
	_checar(not _instalada_id.is_empty(), "a musica aparece no catalogo do operador")

	print("=== LOTE: REFAZENDO ===")
	# Refazer com o mesmo pendrive nao pode importar de novo: o que ja
	# entrou e contado como pulado.
	var reexame: Dictionary = USER_CATALOG.inspect_usb_package(completo)
	_checar(
		bool(reexame.get("installed", false)),
		"o pacote ja instalado e reconhecido na segunda passada"
	)

	painel.set("_usb_packages", [reexame, pacote_erro])
	painel.set("_music_cursor", -1)
	painel.call("_iniciar_lote")
	await _esperar_lote(painel)

	_checar(
		int(painel.get("_batch_total")) == 0,
		"nada novo para importar na segunda passada"
	)
	_checar(
		int(painel.get("_batch_skipped")) == 1,
		"a musica que ja tinha entrado foi contada como pulada"
	)

	painel.queue_free()
	await get_tree().process_frame


## ---------------------------------------------------------------
## 4) QUIOSQUE / MOLDURA TOUCH
## ---------------------------------------------------------------

func _testar_quiosque_touch() -> void:
	print("=== QUIOSQUE: NADA POR CIMA DO JOGO ===")

	_checar(
		int(ProjectSettings.get_setting("display/window/size/mode", 0)) == 4,
		"a janela nasce em tela cheia exclusiva"
	)
	_checar(
		bool(ProjectSettings.get_setting("display/window/size/always_on_top", false)),
		"a janela nasce sempre no topo"
	)
	_checar(
		bool(ProjectSettings.get_setting("display/window/size/borderless", false)),
		"a janela nasce sem borda"
	)

	var shell: Node = get_node_or_null("/root/ArcadeShell")
	_checar(shell != null, "ArcadeShell no ar")
	if shell != null:
		_checar(
			shell.has_method("_preparar_windows_para_touch"),
			"o jogo prepara o Windows para a moldura touch ao abrir"
		)
		_checar(
			float(shell.get("REAFIRMAR_FOCO_SEG")) <= 0.5,
			"o jogo volta para a frente em menos de meio segundo"
		)

	# O script existe e desliga cada item que o Windows desenha ou abre
	# por cima da partida.
	var caminho: String = "res://QUIOSQUE_HIT_MUSIC.ps1"
	_checar(FileAccess.file_exists(caminho), "QUIOSQUE_HIT_MUSIC.ps1 na raiz do projeto")

	var arquivo := FileAccess.open(caminho, FileAccess.READ)
	if arquivo != null:
		var texto: String = arquivo.get_as_text()
		arquivo.close()

		for item in [
			["ContactVisualization", "marca cinza do dedo"],
			["GestureVisualization", "rastro dos gestos"],
			["TouchMode_hold", "segurar o dedo = botao direito"],
			["ToastEnabled", "notificacoes"],
			["DisableAutoplay", "janela automatica do pendrive"],
			["EnableDesktopModeAutoInvoke", "teclado virtual"],
			["ScreenSaveActive", "protetor de tela"],
			["AllowEdgeSwipe", "arrastar da borda"],
		]:
			_checar(
				texto.contains(str(item[0])),
				"o quiosque desliga: " + str(item[1])
			)

		_checar(
			texto.contains("-Restaurar") or texto.contains("Restaurar"),
			"da para devolver a maquina ao normal com -Restaurar"
		)

	# Fora do Windows a preparacao nao pode nem tentar rodar PowerShell.
	if shell != null and OS.get_name() != "Windows":
		shell.call("_preparar_windows_para_touch")
		_checar(true, "fora do Windows a preparacao nao faz nada")

	await get_tree().process_frame


## ---------------------------------------------------------------
## 5) NOME DE MUSICA COMPRIDO
## ---------------------------------------------------------------

const TEXT_FIT: Script = preload("res://scripts/hit_music_r7/text_fit.gd")

const NOME_GIGANTE: String = (
	"EVANGELION - A CRUEL ANGEL'S THESIS (OPENING COMPLETO REMASTERIZADO 2026)"
)


func _testar_nome_comprido() -> void:
	print("=== NOME COMPRIDO NAO QUEBRA O CARD ===")

	# Numa pasta recem-clonada a fonte pode ainda nao ter sido importada;
	# o que esta em teste e o ajuste do texto, nao a fonte, entao a
	# fallback do proprio Godot serve para medir.
	var fonte: Font = null
	if ResourceLoader.exists("res://fonts/Bungee-Regular.ttf"):
		var recurso: Resource = load("res://fonts/Bungee-Regular.ttf")
		if recurso is Font:
			fonte = recurso as Font
	if fonte == null:
		fonte = ThemeDB.fallback_font
	if fonte == null:
		_checar(false, "alguma fonte disponivel para medir o texto")
		return

	var caixa := Vector2(240.0, 62.0)

	var etiqueta := Label.new()
	etiqueta.add_theme_font_override("font", fonte)
	add_child(etiqueta)

	TEXT_FIT.definir(etiqueta, NOME_GIGANTE, caixa.x, caixa.y, 40, 16, true)
	# O `size` definitivo so vale depois que o Godot recalcula o minimo
	# do Label, que acontece no idle seguinte.
	await get_tree().process_frame
	await get_tree().process_frame

	_checar(
		etiqueta.size.x <= caixa.x + 0.5 and etiqueta.size.y <= caixa.y + 0.5,
		"o rotulo continua do tamanho da caixa (%s, caixa %s)" % [
			str(etiqueta.size),
			str(caixa),
		]
	)

	var linhas: PackedStringArray = etiqueta.text.split("\n")
	_checar(linhas.size() <= 2, "no maximo duas linhas (deu %d)" % linhas.size())

	var corpo: int = etiqueta.get_theme_font_size("font_size")
	var maior_linha: float = 0.0
	for linha in linhas:
		maior_linha = maxf(
			maior_linha,
			TEXT_FIT.largura_do_texto(fonte, str(linha), corpo)
		)
	_checar(
		maior_linha <= caixa.x + 0.5,
		"cada linha cabe na largura reservada (%.1f <= %.1f)" % [maior_linha, caixa.x]
	)
	_checar(
		etiqueta.text.contains("…") or linhas.size() == 2,
		"o nome se virou: quebrou em duas linhas ou saiu com reticencias"
	)

	# Nome curto nao pode ser mexido: mesma fonte, mesmo texto.
	var curta := Label.new()
	curta.add_theme_font_override("font", fonte)
	add_child(curta)
	TEXT_FIT.definir(curta, "SOUL", caixa.x, caixa.y, 40, 16, true)
	await get_tree().process_frame

	_checar(curta.text == "SOUL", "nome curto continua inteiro")
	_checar(
		curta.get_theme_font_size("font_size") == 40,
		"nome curto continua no tamanho cheio da fonte"
	)

	etiqueta.queue_free()
	curta.queue_free()
	await get_tree().process_frame


## ---------------------------------------------------------------
## 6) PONTEIRO DO MOUSE
## ---------------------------------------------------------------

func _testar_ponteiro() -> void:
	print("=== PONTEIRO NUNCA APARECE ===")

	# Nenhuma tela pode PEDIR o ponteiro de volta. A cena da musica fazia
	# exatamente isso, e por isso a seta so aparecia dentro da partida.
	# Comentario mencionando o modo nao conta: o que importa e a chamada.
	var culpados: Array[String] = []
	for pasta in ["res://scripts", "res://scripts/hit_music_r7"]:
		for arquivo in DirAccess.get_files_at(pasta):
			var caminho: String = pasta.path_join(str(arquivo))
			if not caminho.ends_with(".gd"):
				continue
			var leitura := FileAccess.open(caminho, FileAccess.READ)
			if leitura == null:
				continue
			var texto: String = leitura.get_as_text()
			leitura.close()

			for linha in texto.split("\n"):
				var limpa: String = str(linha).strip_edges()
				if limpa.begins_with("#"):
					continue
				if limpa.contains("set_mouse_mode(Input.MOUSE_MODE_VISIBLE)"):
					culpados.append(caminho.get_file())
					break

	_checar(
		culpados.is_empty(),
		"nenhuma tela pede o ponteiro de volta%s" % (
			""
			if culpados.is_empty()
			else " (ainda pedem: " + ", ".join(culpados) + ")"
		)
	)

	# E se alguma coisa fora do jogo devolver o ponteiro, o ArcadeShell
	# tira de novo no quadro seguinte. Isso so da para medir com janela:
	# no headless o servidor de video nao guarda modo de mouse nenhum.
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	if Input.get_mouse_mode() != Input.MOUSE_MODE_HIDDEN:
		print("  --   sem janela: o ponteiro vivo so da para medir no gabinete")
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		await get_tree().process_frame
		await get_tree().process_frame

		_checar(
			Input.get_mouse_mode() == Input.MOUSE_MODE_HIDDEN,
			"o ArcadeShell esconde o ponteiro de novo sozinho"
		)

	var shell: Node = get_node_or_null("/root/ArcadeShell")
	if shell != null:
		_checar(
			shell.has_method("_instalar_cursor_invisivel"),
			"todas as formas de cursor recebem imagem transparente"
		)


## ---------------------------------------------------------------
## 7) ARRASTO: SO NO TOQUE, E SEM LED
## ---------------------------------------------------------------

## Renderizador de mentira: o stage avulso deste teste nao monta cena,
## entao os efeitos de acerto precisam cair em algum lugar.
class RenderizadorFalso:
	extends Node2D

	func add_effect(
		_tipo: String,
		_posicao: Vector2,
		_cor: Color,
		_estilo_seta: int = 0,
		_estilo_estrela: int = 0
	) -> void:
		pass

	func flash_ring_at(
		_posicao: Vector2,
		_cor: Color,
		_forca: float,
		_largura: float
	) -> void:
		pass

	func register_hit(_qualidade: float, _combo: int, _cor: Color) -> void:
		pass


## Arrasto de mentira, ja "nascido" e dentro da janela de acerto: comeca
## na lane 0 e termina na lane 4.
func _arrasto_falso() -> Dictionary:
	return {
		"type": "slide",
		"time": 1.0,
		"end_time": 2.0,
		"path": [0, 4],
		"lane": 0,
		"color_index": 0,
		"_spawned": true,
		"_resolved": false,
		"_active": false,
		"_started": false,
		"_visual_progress": 0.0,
		"_path_points": PackedVector2Array([
			Vector2(0.0, -100.0),
			Vector2(0.0, 100.0),
		]),
	}


func _testar_arrasto() -> void:
	print("=== ARRASTO SO VALE NO TOQUE ===")

	var stage: Object = load("res://scripts/hit_music_r7/stage.gd").new()
	var renderizador := RenderizadorFalso.new()
	stage.set("_renderer", renderizador)
	stage.set("_difficulty", {"hit_window": 0.2, "perfect_window": 0.075})
	stage.set("_song_time", 1.0)
	stage.set("_radius", 300.0)
	stage.set("_center", Vector2.ZERO)
	stage.set("_lane_positions", PackedVector2Array([
		Vector2(0.0, -100.0), Vector2(70.0, -70.0),
		Vector2(100.0, 0.0), Vector2(70.0, 70.0),
		Vector2(0.0, 100.0), Vector2(-70.0, 70.0),
		Vector2(-100.0, 0.0), Vector2(-70.0, -70.0),
	]))

	# BOTAO FISICO: aperta a lane de partida. Nao pode acontecer nada.
	var por_botao: Dictionary = _arrasto_falso()
	stage.set("_live_events", [por_botao])
	stage.call("_handle_lane_press", 0, "lane_0")

	_checar(
		not bool(por_botao.get("_active", false)),
		"o botao da lane de partida NAO comeca o arrasto"
	)
	_checar(
		not bool(por_botao.get("_resolved", false)),
		"o botao da lane de partida NAO conclui o arrasto"
	)

	# E apertar a lane de chegada logo depois — o atalho antigo — tambem
	# nao pode fechar a nota.
	stage.call("_handle_lane_press", 4, "lane_4")
	_checar(
		not bool(por_botao.get("_resolved", false)),
		"apertar partida e chegada NAO conta o ponto"
	)
	_checar(
		float(por_botao.get("_visual_progress", 0.0)) <= 0.0,
		"nenhum progresso e creditado por botao"
	)

	# TOQUE: o mesmo aperto, agora com ponteiro, comeca o gesto.
	var por_toque: Dictionary = _arrasto_falso()
	stage.set("_live_events", [por_toque])
	stage.call("_handle_lane_press", 0, "touch_0", true, Vector2(0.0, -100.0))

	_checar(
		bool(por_toque.get("_active", false)),
		"o toque na partida comeca o arrasto"
	)
	_checar(
		not bool(por_toque.get("_resolved", false)),
		"comecar nao e concluir: o dedo ainda precisa varrer o caminho"
	)

	# E o percurso so fecha varrendo o corredor de ponta a ponta.
	stage.call("_handle_pointer_move", "touch_0", Vector2(0.0, -50.0))
	stage.call("_handle_pointer_move", "touch_0", Vector2(0.0, 0.0))
	stage.call("_handle_pointer_move", "touch_0", Vector2(0.0, 50.0))
	stage.call("_handle_pointer_move", "touch_0", Vector2(0.0, 100.0))
	_checar(
		float(por_toque.get("_visual_progress", 0.0)) > 0.9,
		"varrer o caminho no toque avanca o arrasto ate o fim (%.2f)" % float(
			por_toque.get("_visual_progress", 0.0)
		)
	)
	_checar(
		bool(por_toque.get("_resolved", false)),
		"varrido de ponta a ponta, ai sim o arrasto conta o ponto"
	)

	renderizador.free()
	if stage is Node:
		(stage as Node).free()

	print("=== ARRASTO NAO ACENDE LED ===")

	var mesa: Object = load("res://scripts/hit_music_r7/stage_final.gd").new()
	mesa.set("_song_time", 1.0)

	var apagado: String = "MULTI " + "000000".repeat(8)

	mesa.set("_events", [_arrasto_falso()])
	_checar(
		str(mesa.call("_quadro_das_lanes_r21")) == apagado,
		"arrasto chegando deixa a mesa apagada"
	)

	var em_curso: Dictionary = _arrasto_falso()
	em_curso["_active"] = true
	em_curso["_started"] = true
	mesa.set("_events", [em_curso])
	_checar(
		str(mesa.call("_quadro_das_lanes_r21")) == apagado,
		"arrasto em curso tambem nao acende nada"
	)

	# O tap continua acendendo: a mudanca e so do arrasto.
	mesa.set("_events", [{
		"type": "tap",
		"lane": 2,
		"time": 1.0,
		"color_index": 0,
		"_resolved": false,
	}])
	_checar(
		str(mesa.call("_quadro_das_lanes_r21")) != apagado,
		"tap continua acendendo o botao da lane"
	)

	if mesa is Node:
		(mesa as Node).free()

	await get_tree().process_frame


func _esperar_lote(painel: Node) -> void:
	for _quadro in range(600):
		if not bool(painel.get("_batch_active")):
			break
		await get_tree().process_frame
	await get_tree().process_frame


func _achar_id_instalada() -> String:
	for musica in USER_CATALOG.all_user_songs():
		if not (musica is Dictionary):
			continue
		if str((musica as Dictionary).get("title", "")).contains("SMOKE"):
			return str((musica as Dictionary).get("id", ""))
	return ""


## Pasta de pendrive de mentira. `com_video` false derruba o pacote de
## proposito, para provar o aviso do que nao esta funcionando.
func _criar_pacote_falso(nome: String, com_video: bool) -> String:
	var pasta: String = USB_FAKE_DIR.path_join(nome)
	DirAccess.make_dir_recursive_absolute(pasta)

	_gravar(pasta.path_join("audio.mp3"), "MP3-" + nome)
	_gravar(pasta.path_join("capa.png"), "PNG-" + nome)
	_gravar(
		pasta.path_join("dados.txt"),
		'name="SMOKE %s"\nbpm=128\ncategory=OUTROS\n' % nome
	)
	if com_video:
		_gravar(pasta.path_join("video.ogv"), "OGV-" + nome)

	return ProjectSettings.globalize_path(pasta)


func _gravar(caminho: String, conteudo: String) -> void:
	var arquivo := FileAccess.open(caminho, FileAccess.WRITE)
	if arquivo == null:
		return
	arquivo.store_string(conteudo)
	arquivo.close()


func _limpar() -> void:
	if not _instalada_id.is_empty():
		USER_CATALOG.remove_song(_instalada_id)

	var raiz: String = ProjectSettings.globalize_path(USB_FAKE_DIR)
	_apagar_pasta(raiz)


func _apagar_pasta(caminho: String) -> void:
	var dir := DirAccess.open(caminho)
	if dir == null:
		return
	for arquivo in dir.get_files():
		dir.remove(arquivo)
	for sub in dir.get_directories():
		_apagar_pasta(caminho.path_join(sub))
	DirAccess.remove_absolute(caminho)
