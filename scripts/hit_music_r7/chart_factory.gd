extends RefCounted
## Compatibilidade. O gerador de fases real e o chart_factory_v9.gd.
##
## Este arquivo existia com um algoritmo proprio ("um evento a cada N
## indices"), o que mantinha DOIS geradores divergentes no projeto: o
## stage base usava este e o stage_v9 em diante usava o outro. Qualquer
## ajuste de ritmo feito em um nao aparecia no outro. Agora ele so
## encaminha, entao existe um unico desenho de fase.

const FACTORY: Script = preload("res://scripts/hit_music_r7/chart_factory_v9.gd")


static func build(song: Dictionary, difficulty_name: String, duration: float) -> Array:
	return FACTORY.build(song, difficulty_name, duration)
