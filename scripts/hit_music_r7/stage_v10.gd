extends "res://scripts/hit_music_r7/stage_v9.gd"

var _difficulty_cursor: int = -1
var _display_score: float = 0.0


func _ready() -> void:
	Engine.max_fps = 120
	super._ready()

	# Hover ja comeca em FACIL (cursor 0), nao em "nada selecionado"
	# (-1) — antes o jogador via os dois botoes apagados ate apertar
	# A pela primeira vez.
	_difficulty_cursor = 0
	_difficulty_confirmed = false
	_display_score = 0.0
	_select_difficulty("easy", true)
	_centralizar_botao_voltar()

	if _pre_game_title != null:
		_pre_game_title.text = "ESCOLHA A DIFICULDADE"
	if _pre_game_subtitle != null:
		_pre_game_subtitle.text = (
			"A SOBE     E DESCE     B CONFIRMA\n"
			+ "FACIL   •   DIFICIL   •   VOLTAR PARA TROCAR DE MUSICA"
		)

	_update_pre_game_styles()
	_set_center_hud_visible(false)

	LED_CLIENT.scene_state(
		_primary_color(),
		_accent_color()
	)
	# A/B/E ficam acesos persistentes nesta tela: A e E movem o cursor e
	# B seleciona. E o mesmo trio do seletor de musicas, entao o jogador
	# nao troca de botao entre uma tela e outra.
	_apply_menu_leds()


## A sobe, E desce, B confirma — exatamente como no seletor de musicas e
## nas Configuracoes. O cursor passeia por FACIL, DIFICIL e VOLTAR, entao
## desistir da musica usa os mesmos tres botoes acesos na mesa: nao existe
## um quarto botao apagado que o jogador teria que adivinhar.
func _process_pre_game_inputs() -> void:
	if _action_pressed("input_a") or _action_pressed("ui_up") or _action_pressed("ui_left"):
		_move_difficulty_cursor(-1)
	elif _action_pressed("input_e") or _action_pressed("ui_down") or _action_pressed("ui_right"):
		_move_difficulty_cursor(1)
	elif _action_pressed("input_b") or _action_pressed("ui_accept"):
		_confirmar_item_do_cursor()


func _handle_pre_game_touch(
	position_value: Vector2
) -> void:
	if (
		_easy_button != null
		and Rect2(
			_easy_button.global_position,
			_easy_button.size
		).has_point(position_value)
	):
		_difficulty_cursor = 0
		_select_difficulty("easy")
		_confirm_difficulty()
		return

	if (
		_hard_button != null
		and Rect2(
			_hard_button.global_position,
			_hard_button.size
		).has_point(position_value)
	):
		_difficulty_cursor = 1
		_select_difficulty("hard")
		_confirm_difficulty()
		return

	if _toque_no_voltar(position_value):
		_difficulty_cursor = BACK_CURSOR
		_update_pre_game_styles()
		_voltar_para_selecao()


## Trio de LEDs dos menus (A = mover, B = selecionar, E = descer).
## As lanes vem de led_client.gd, que e a fonte unica do mapeamento.
func _apply_menu_leds() -> void:
	LED_CLIENT.menu_state_three(
		LED_CLIENT.MENU_NEXT_COLOR,
		LED_CLIENT.MENU_SELECT_COLOR,
		LED_CLIENT.MENU_NEXT_COLOR,
		LED_CLIENT.NAV_NEXT_LANE,
		LED_CLIENT.NAV_SELECT_LANE,
		LED_CLIENT.NAV_DOWN_LANE
	)


## Itens da tela, na ordem em que o cursor anda: FACIL, DIFICIL, VOLTAR.
const CURSOR_ITEM_COUNT: int = 3
const BACK_CURSOR: int = 2


func _centralizar_botao_voltar() -> void:
	# Nesta cadeia o JOGAR nao aparece (confirmar e o proprio B), entao o
	# VOLTAR assume a linha inteira, centralizado.
	if _back_button == null or not is_instance_valid(_back_button):
		return
	if _pre_game_panel == null or not is_instance_valid(_pre_game_panel):
		return

	var panel_size: Vector2 = _pre_game_panel.size
	_back_button.size = Vector2(
		panel_size.x * 0.42,
		panel_size.y * 0.185
	)
	_back_button.position = Vector2(
		(panel_size.x - _back_button.size.x) * 0.5,
		panel_size.y * 0.665
	)

	if _back_button_label != null and is_instance_valid(_back_button_label):
		_back_button_label.size = _back_button.size


func _move_difficulty_cursor(direction: int = 1) -> void:
	_difficulty_cursor = (
		0
		if _difficulty_cursor < 0
		else posmod(_difficulty_cursor + direction, CURSOR_ITEM_COUNT)
	)

	# VOLTAR nao mexe na dificuldade: sair da linha do VOLTAR devolve
	# exatamente o nivel que estava marcado.
	if _difficulty_cursor != BACK_CURSOR:
		_select_difficulty(
			"easy"
			if _difficulty_cursor == 0
			else "hard"
		)
	else:
		_update_pre_game_styles()

	LED_CLIENT.menu_next_feedback()
	_apply_menu_leds()


## B confirma o item onde o cursor estiver.
func _confirmar_item_do_cursor() -> void:
	if _difficulty_cursor == BACK_CURSOR:
		LED_CLIENT.menu_select_feedback()
		_voltar_para_selecao()
		return

	_confirm_difficulty()


func _confirm_difficulty() -> void:
	if _difficulty_cursor < 0:
		return

	LED_CLIENT.menu_select_feedback()
	super._confirm_difficulty()

	# A tela de dificuldade escurece o fundo de proposito para o painel
	# ler bem (background_intensity = 0.045, logo abaixo). Esse valor
	# continuava valendo durante a PARTIDA inteira, porque nada refazia
	# o perfil depois de confirmar — o universo da musica entrava
	# apagado. Aqui o perfil real volta antes do jogo comecar.
	if _difficulty_confirmed:
		_restore_gameplay_difficulty()


func _restore_gameplay_difficulty() -> void:
	_difficulty = CATALOG.get_difficulty(_song, _difficulty_name)

	if _renderer != null:
		_renderer.configure(
			_center,
			_radius,
			_lane_positions,
			_song,
			_difficulty
		)


func _select_difficulty(
	name_value: String,
	immediate: bool = false
) -> void:
	super._select_difficulty(
		name_value,
		immediate
	)

	_difficulty["background_intensity"] = 0.045

	if _renderer != null:
		_renderer.configure(
			_center,
			_radius,
			_lane_positions,
			_song,
			_difficulty
		)


func _update_pre_game_styles() -> void:
	if _easy_button == null:
		return

	var easy_selected: bool = _difficulty_cursor == 0
	var hard_selected: bool = _difficulty_cursor == 1
	_aplicar_estilo_voltar(_difficulty_cursor == BACK_CURSOR)

	_easy_button.add_theme_stylebox_override(
		"panel",
		_difficulty_button_style(
			easy_selected,
			Color(0.13, 0.90, 1.0, 1.0)
		)
	)
	_hard_button.add_theme_stylebox_override(
		"panel",
		_difficulty_button_style(
			hard_selected,
			_accent_color()
		)
	)
	_play_button.visible = false

	_easy_button_label.add_theme_color_override(
		"font_color",
		Color.WHITE
		if easy_selected
		else Color(0.58, 0.65, 0.76, 1.0)
	)
	_hard_button_label.add_theme_color_override(
		"font_color",
		Color.WHITE
		if hard_selected
		else Color(0.58, 0.65, 0.76, 1.0)
	)


func _score_percent() -> float:
	var total_notes: int = _events.size()
	if total_notes <= 0:
		return 0.0

	return clampf(
		100.0
		* _score_quality_sum
		/ float(total_notes),
		0.0,
		100.0
	)


func _update_hud() -> void:
	super._update_hud()

	var target_score: float = _score_percent()
	_display_score = lerpf(
		_display_score,
		target_score,
		0.18
	)

	if absf(_display_score - target_score) < 0.005:
		_display_score = target_score

	if _center_score != null:
		_center_score.text = "%.2f%%" % _display_score

	if _label_score != null:
		_label_score.visible = false
	if _label_combo != null:
		_label_combo.visible = false


func _set_gameplay_hud_visible(value: bool) -> void:
	super._set_gameplay_hud_visible(value)

	if _label_score != null:
		_label_score.visible = false
	if _label_combo != null:
		_label_combo.visible = false


func _handle_lane_press(
	lane: int,
	source: String,
	has_pointer: bool = false,
	press_position: Vector2 = Vector2.ZERO
) -> void:
	LED_CLIENT.pulse_lane(lane)
	super._handle_lane_press(lane, source, has_pointer, press_position)


func _resolve_hit(
	event: Dictionary,
	kind: String,
	quality: float
) -> void:
	var type_name: String = str(
		event.get("type", kind)
	)

	if type_name == "tap" or type_name == "hold":
		LED_CLIENT.hit_lane(
			int(event.get("lane", 0)),
			_event_color(event),
			220 if type_name == "hold" else 180
		)

	super._resolve_hit(
		event,
		kind,
		quality
	)


func _resolve_miss(event: Dictionary) -> void:
	var type_name: String = str(
		event.get("type", "tap")
	)

	if type_name == "tap" or type_name == "hold":
		LED_CLIENT.error_lane(
			int(event.get("lane", 0))
		)

	super._resolve_miss(event)


func _start_countdown() -> void:
	LED_CLIENT.countdown_start()
	super._start_countdown()


func _start_playing() -> void:
	LED_CLIENT.ready()
	super._start_playing()
