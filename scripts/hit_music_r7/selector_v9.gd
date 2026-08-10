extends "res://scripts/hit_music_r7/selector.gd"

func _ready() -> void:
	super._ready()

	if _easy_chip != null:
		_easy_chip.visible = false
	if _hard_chip != null:
		_hard_chip.visible = false
	if _instruction_label != null:
		# Sem letra de botao: quem joga nao sabe o que e "A" ou "D".
		# O que cada botao faz aparece dentro do circulo, colado no
		# botao fisico correspondente.
		_instruction_label.text = "ESCOLHA SUA MÚSICA"
	if _mode_label != null:
		_mode_label.text = "DIFICULDADE NA FASE"


func _toggle_difficulty() -> void:
	# selector_v10.gd sobrescreve isso e ja chama _start_selected() —
	# B ja funciona como start nesta tela (nao chama super aqui).
	pass


func _handle_touch(position_value: Vector2) -> void:
	for card_index in range(_cards.size()):
		var card: Panel = _cards[card_index]
		if not card.visible:
			continue

		if Rect2(
			card.global_position,
			card.size
		).has_point(position_value):
			if card_index == _index:
				_start_selected()
			else:
				_index = card_index
				_apply_selection(false)
			return

	if (
		_start_panel != null
		and Rect2(
			_start_panel.global_position,
			_start_panel.size
		).has_point(position_value)
	):
		_start_selected()
		return

	if (
		_info_panel != null
		and Rect2(
			_info_panel.global_position,
			_info_panel.size
		).has_point(position_value)
	):
		_start_selected()
