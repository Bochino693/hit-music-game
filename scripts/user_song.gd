extends "res://scripts/hit_music_r7/stage_final.gd"
## Cena de gameplay das musicas cadastradas pelo operador.
##
## As musicas de fabrica tem uma cena por musica, cada uma com o id
## fixo no script. Uma musica nova nao pode gerar um .tscn em tempo de
## execucao, entao todas compartilham esta cena e descobrem qual tocar
## pela meta que o seletor grava na arvore antes de trocar de cena.

func _song_id() -> String:
	var tree: SceneTree = get_tree()
	if tree != null and tree.has_meta("hit_music_song_id"):
		return str(tree.get_meta("hit_music_song_id"))
	return ""
