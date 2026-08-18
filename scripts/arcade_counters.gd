extends Node
## ArcadeCounters — quantas vezes a maquina recebeu START, separado por
## modo de operacao E por quem estava usando.
##
## POR QUE DOIS CONJUNTOS DE CONTADORES
## A maquina roda em dois momentos da vida dela: aqui na bancada, sendo
## testada, e la no cliente, faturando. Se os dois somassem no mesmo lugar,
## o numero entregue ao cliente ja viria inflado por todo o teste de
## fabrica, e nao daria pra saber quanto foi jogo de verdade.
##
## Por isso existe o interruptor NO_CLIENTE:
##   false -> bancada/fabrica: tudo cai no balde "fabrica"
##   true  -> cliente:         tudo cai no balde "cliente"
##
## Os dois baldes sao guardados sempre, lado a lado. Virar o interruptor
## NAO zera nada: so muda qual balde recebe dali pra frente, entao da pra
## olhar depois quanto foi teste e quanto foi cliente.

## ===================================================================
## INTERRUPTOR DE PRODUCAO — vire para `true` ANTES de exportar pro cliente.
## ===================================================================
const NO_CLIENTE: bool = false

const COUNTERS_PATH: String = "user://hit_music_arcade_counters.json"

signal changed

## balde -> { "total": int, "livre": int, "credito": int }
var _baldes: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_carregar()


## Nome do balde que recebe as contagens agora.
func balde_atual() -> String:
	return "cliente" if NO_CLIENTE else "fabrica"


func _balde_vazio() -> Dictionary:
	return {"total": 0, "livre": 0, "credito": 0}


## Registra UM aperto de START. `em_credito` diz o modo em que a maquina
## estava naquele instante — e o modo do momento do aperto que importa,
## nao o modo de agora, porque o operador pode trocar depois.
func registrar_start(em_credito: bool) -> void:
	var chave: String = balde_atual()
	if not _baldes.has(chave):
		_baldes[chave] = _balde_vazio()
	var balde: Dictionary = _baldes[chave]
	balde["total"] = int(balde.get("total", 0)) + 1
	if em_credito:
		balde["credito"] = int(balde.get("credito", 0)) + 1
	else:
		balde["livre"] = int(balde.get("livre", 0)) + 1
	_baldes[chave] = balde
	_salvar()
	changed.emit()


func contagem(balde: String) -> Dictionary:
	var dados: Dictionary = _baldes.get(balde, {})
	return {
		"total": int(dados.get("total", 0)),
		"livre": int(dados.get("livre", 0)),
		"credito": int(dados.get("credito", 0)),
	}


func contagem_atual() -> Dictionary:
	return contagem(balde_atual())


## Soma dos dois baldes — o total real de aperto de START da vida da maquina.
func contagem_geral() -> Dictionary:
	var fab: Dictionary = contagem("fabrica")
	var cli: Dictionary = contagem("cliente")
	return {
		"total": int(fab["total"]) + int(cli["total"]),
		"livre": int(fab["livre"]) + int(cli["livre"]),
		"credito": int(fab["credito"]) + int(cli["credito"]),
	}


## Zera UM balde. Nao existe "zerar tudo" de proposito: apagar o historico
## do cliente inteiro nunca deveria ser um clique so.
func zerar(balde: String) -> void:
	_baldes[balde] = _balde_vazio()
	_salvar()
	changed.emit()


func _salvar() -> void:
	var arquivo := FileAccess.open(COUNTERS_PATH, FileAccess.WRITE)
	if arquivo == null:
		push_warning("ArcadeCounters: não consegui gravar em %s" % COUNTERS_PATH)
		return
	arquivo.store_string(JSON.stringify({"version": 1, "baldes": _baldes}, "\t"))


func _carregar() -> void:
	_baldes = {"fabrica": _balde_vazio(), "cliente": _balde_vazio()}
	if not FileAccess.file_exists(COUNTERS_PATH):
		return
	var arquivo := FileAccess.open(COUNTERS_PATH, FileAccess.READ)
	if arquivo == null:
		return
	var lido: Variant = JSON.parse_string(arquivo.get_as_text())
	if not lido is Dictionary:
		push_warning("ArcadeCounters: arquivo ilegível; começando do zero.")
		return
	var guardados: Variant = (lido as Dictionary).get("baldes", {})
	if not guardados is Dictionary:
		return
	for chave: Variant in (guardados as Dictionary).keys():
		var nome: String = str(chave)
		if nome != "fabrica" and nome != "cliente":
			continue
		var bruto: Variant = (guardados as Dictionary)[chave]
		if not bruto is Dictionary:
			continue
		var d: Dictionary = bruto as Dictionary
		_baldes[nome] = {
			"total": maxi(0, int(d.get("total", 0))),
			"livre": maxi(0, int(d.get("livre", 0))),
			"credito": maxi(0, int(d.get("credito", 0))),
		}
