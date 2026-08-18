extends Node
## Cena falsa que finge ser uma musica, para provar a decisao do ArcadeShell
## sem precisar subir o stage inteiro (que carrega audio, LED e chart).
var ativa: bool = true
func _song_id() -> String:
	return "stub"
func em_partida_ativa() -> bool:
	return ativa
