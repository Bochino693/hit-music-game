extends Node
## Teste de fumaca dos ajustes de operacao (contadores, F9 global, quiosque).
## Rodar com:
##   godot --headless --path . res://tools/smoke_arcade.tscn

var _falhas: Array[String] = []


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

	print("=== AUTOLOADS ===")
	_checar(get_node_or_null("/root/ArcadeSettings") != null, "ArcadeSettings existe")
	_checar(get_node_or_null("/root/ArcadeCounters") != null, "ArcadeCounters existe")
	_checar(get_node_or_null("/root/ArcadeShell") != null, "ArcadeShell existe")

	print("=== CONTADORES ===")
	ArcadeCounters.zerar("fabrica")
	ArcadeCounters.zerar("cliente")
	var balde: String = ArcadeCounters.balde_atual()
	print("  balde ativo: ", balde, "  (NO_CLIENTE = ", ArcadeCounters.NO_CLIENTE, ")")

	ArcadeCounters.registrar_start(false)   # modo livre
	ArcadeCounters.registrar_start(false)
	ArcadeCounters.registrar_start(true)    # modo credito
	var c: Dictionary = ArcadeCounters.contagem(balde)
	_checar(int(c["total"]) == 3, "total = 3 (deu %d)" % int(c["total"]))
	_checar(int(c["livre"]) == 2, "livre = 2 (deu %d)" % int(c["livre"]))
	_checar(int(c["credito"]) == 1, "credito = 1 (deu %d)" % int(c["credito"]))

	var outro: String = "cliente" if balde == "fabrica" else "fabrica"
	var o: Dictionary = ArcadeCounters.contagem(outro)
	_checar(
		int(o["total"]) == 0,
		"o balde '%s' NAO foi tocado (deu %d)" % [outro, int(o["total"])]
	)
	var geral: Dictionary = ArcadeCounters.contagem_geral()
	_checar(int(geral["total"]) == 3, "soma geral = 3 (deu %d)" % int(geral["total"]))
	_checar(
		int(geral["livre"]) + int(geral["credito"]) == int(geral["total"]),
		"livre + credito bate com o total"
	)

	print("=== PERSISTENCIA ===")
	_checar(FileAccess.file_exists(ArcadeCounters.COUNTERS_PATH), "arquivo gravado")
	ArcadeCounters._carregar()
	var recarregado: Dictionary = ArcadeCounters.contagem(balde)
	_checar(int(recarregado["total"]) == 3, "sobreviveu ao recarregar")

	print("=== F9 GLOBAL ===")
	_checar(not ArcadeShell.em_partida(), "fora de partida na cena de teste")
	_checar(ArcadeShell.has_method("abrir_configuracoes"), "atalho global existe")

	print("=== CENAS ===")
	for caminho in ["res://scenes/opening.tscn", "res://scenes/config.tscn"]:
		var packed: PackedScene = load(caminho)
		if packed == null:
			_checar(false, "carregar " + caminho)
			continue
		var no: Node = packed.instantiate()
		get_tree().root.add_child(no)
		for i in 10:
			await get_tree().process_frame
		_checar(true, "abriu " + caminho)
		no.queue_free()
		await get_tree().process_frame

	print("=== DETECCAO DE PARTIDA ===")
	## Uma cena de musica responde por `_song_id()`; um menu nao. E esse
	## marcador que faz o F9 valer em tudo MENOS durante a partida.
	##
	## Testado numa INSTANCIA, nao no Script: e num objeto vivo que o
	## ArcadeShell faz a pergunta, e Script.has_method() responde outra
	## coisa — checar o script daria "passou" mesmo com a regra quebrada.
	for caminho_script in [
		"res://scripts/carmine.gd", "res://scripts/demon.gd",
		"res://scripts/naruto.gd", "res://scripts/user_song.gd",
	]:
		var sc: Script = load(caminho_script)
		if sc == null:
			_checar(false, "carregar " + caminho_script)
			continue
		var inst: Object = sc.new()
		_checar(
			inst.has_method("_song_id"),
			"%s conta como PARTIDA (F9 bloqueado)" % caminho_script.get_file()
		)
		if inst is Node:
			(inst as Node).free()

	for caminho_menu in ["res://scripts/opening.gd", "res://scripts/config.gd"]:
		var sm: Script = load(caminho_menu)
		var im: Object = sm.new()
		_checar(
			not im.has_method("_song_id"),
			"%s NAO conta como partida (F9 liberado)" % caminho_menu.get_file()
		)
		if im is Node:
			(im as Node).free()

	print("=== DECISAO DO SHELL (caminho real) ===")
	## Troca o current_scene por uma cena falsa que finge ser musica. E o
	## unico jeito de exercitar em_partida() de ponta a ponta sem subir o
	## stage inteiro — e e a decisao que libera ou bloqueia o F9.
	var anterior: Node = get_tree().current_scene
	var stub: Node = load("res://tools/_stub_partida.gd").new()
	get_tree().root.add_child(stub)
	get_tree().current_scene = stub

	stub.set("ativa", true)
	_checar(ArcadeShell.em_partida(), "musica TOCANDO -> em_partida = true")
	_checar(not ArcadeShell.abrir_configuracoes(), "F9 BLOQUEADO durante a partida")

	stub.set("ativa", false)
	_checar(
		not ArcadeShell.em_partida(),
		"tela de dificuldade (musica parada) -> em_partida = false"
	)

	get_tree().current_scene = anterior
	stub.queue_free()
	await get_tree().process_frame

	await get_tree().create_timer(0.2).timeout
	if _falhas.is_empty():
		print("SMOKE_ARCADE_OK")
		get_tree().quit(0)
	else:
		for f in _falhas:
			push_error("FALHOU: " + f)
		print("SMOKE_ARCADE_FALHOU: %d" % _falhas.size())
		get_tree().quit(1)
