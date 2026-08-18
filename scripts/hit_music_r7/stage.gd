extends Node2D

const CATALOG: Script = preload("res://scripts/hit_music_r7/catalog.gd")
const CHART_FACTORY: Script = preload("res://scripts/hit_music_r7/chart_factory.gd")
const PATH_BUILDER: Script = preload("res://scripts/hit_music_r7/path_builder.gd")
const TAP_VISUAL_SCRIPT: Script = preload("res://scripts/hit_music_r7/tap_visual.gd")
const RENDERER_SCRIPT: Script = preload("res://scripts/hit_music_r7/playfield_renderer.gd")
const LED_CLIENT: Script = preload("res://scripts/hit_music_r7/led_client.gd")
const TAP_PALETTE: Script = preload("res://scripts/hit_music_r7/tap_palette.gd")
const USER_CATALOG: Script = preload("res://scripts/hit_music_r7/user_catalog.gd")

enum GameState {
	PRESENTATION,
	COUNTDOWN,
	PLAYING,
	RESULT,
}

const NUM_LANES: int = 8
const INPUT_ACTIONS: Array[String] = [
	"input_a",
	"input_b",
	"input_c",
	"input_d",
	"input_e",
	"input_f",
	"input_g",
	"input_h",
]

## Largura do corredor do arrasto, em fracao do raio. Era 0.115: num
## disco de 340px isso da 39px de folga para um dedo que cobre uns 45px
## de tela. Encostar "quase" na linha nao avancava nada e o gesto
## parecia nao ser lido. 0.165 da a folga de um dedo inteiro sem
## permitir cortar caminho — quem garante que o trajeto foi varrido e
## SLIDE_MAX_FORWARD_SPAN, nao a largura.
const SLIDE_CORRIDOR_TOLERANCE_RATIO: float = 0.165
const SLIDE_SAMPLE_STEP_RATIO: float = 0.045
## Quanto uma amostra pode avancar no caminho. Subiu de 0.16 para 0.22
## porque com engasgo de quadro o dedo anda muito entre duas leituras;
## com 0.16 o avanco travava justamente quando a tela estava lenta.
const SLIDE_MAX_FORWARD_SPAN: float = 0.22

## Fracao do trajeto que ja conta como arrasto completo. Era 0.965 —
## exigia os ultimos pixels em cima da marca. 0.93 fecha a nota quando
## o gesto ja foi claramente feito.
const SLIDE_COMPLETE_RATIO: float = 0.93
## Folga depois do fim do gesto antes de marcar erro.
const SLIDE_GRACE_SECONDS: float = 0.45
## A janela para INICIAR um arrasto e maior que a de um tap: o jogador
## precisa achar o ponto de partida e so entao comecar a varrer, e a
## nota dura varias batidas. Usar a mesma janela do tap era o que fazia
## o arrasto "durar pouco tempo para acionar".
const SLIDE_START_WINDOW_SCALE: float = 2.10
## Raio de captura do dedo em volta da marca da lane, em fracao do
## raio. Era 0.155. As lanes ficam a 0.693*raio uma da outra, entao ate
## 0.34 nao ha ambiguidade; 0.26 e um dedo folgado sem sobreposicao.
const POINTER_LANE_RADIUS_RATIO: float = 0.26

## Fisica do desenho do arrasto. O progresso LOGICO pode saltar (o
## avanco por botao pula direto para o proximo ponto do caminho, e um
## ponteiro rapido varre varios passos num quadro so); o progresso
## DESENHADO persegue esse alvo a uma velocidade maxima, entao a estrela
## sempre percorre o trajeto em vez de teleportar. Em fracao de caminho
## por segundo: 2.6 faz a trilha inteira levar ~0.38s no pior caso —
## rapido para nao atrasar a leitura, lento para o olho acompanhar.
const SLIDE_DRAW_SPEED: float = 2.6
## Quando o alvo ja chegou ao fim, a imagem ganha um empurrao para nao
## ficar faltando um pedaco depois da nota ter sido resolvida.
const SLIDE_DRAW_FINISH_SPEED: float = 5.2

const TOP_MARGIN_RATIO: float = 0.022
const TOP_HEIGHT_RATIO: float = 0.205
const TOP_GAP_RATIO: float = 0.024
const SIDE_MARGIN_RATIO: float = 0.015
const BOTTOM_MARGIN_RATIO: float = 0.012
const CIRCLE_SCALE: float = 0.985
const PRESENTATION_SECONDS: float = 2.70
const COUNTDOWN_SECONDS: float = 3.0
const RESULT_SECONDS: float = 12.0
## Cor propria do modal. Ele NAO usa mais a paleta da musica: o painel
## precisa se destacar do cenario que acabou de rodar atras dele, senao
## um resultado vermelho em cima do carmine (que ja e vermelho) some.
## Cores da contagem regressiva: um segundo para cada cor da mesa.
## 3 = azul, 2 = vermelho, 1 = amarelo. As mesmas tres cores dos tazos,
## entao a contagem ja apresenta a paleta do jogo antes da primeira nota.
const COUNTDOWN_COLORS: Array[Color] = [
	TAP_PALETTE.TAP_CYAN,
	TAP_PALETTE.TAP_RED,
	TAP_PALETTE.TAP_YELLOW,
]

const RESULT_BASE_COLOR: Color = Color(0.055, 0.045, 0.135, 1.0)
const RESULT_PASS_COLOR: Color = Color(0.25, 1.0, 0.62, 1.0)
const RESULT_FAIL_COLOR: Color = Color(1.0, 0.32, 0.42, 1.0)
const RESULT_PASS_PERCENT: float = 70.0
const RESULT_INPUT_LOCK_SECONDS: float = 0.90
const RECORD_PATH: String = "user://hit_music_records.json"
const GAME_OVER_STING_PATH: String = "res://songs/game_over.mp3"
const NEW_RECORD_SCENE_PATH: String = "res://scenes/new_record_celebration.tscn"

const MUSIC_VOLUME_MIN_DB: float = -16.0
const MUSIC_VOLUME_MAX_DB: float = -1.0
const MUSIC_VOLUME_SMOOTH_SPEED: float = 2.4

## Energia da musica: comeca CHEIA (1.0) e a musica ja entra alta.
## Acertar MANTEM (e recupera de volta ao topo se tiver caido);
## errar ABAIXA. Antes o volume era derivado do combo, o que fazia a
## musica nascer abafada e so "ligar" depois de uma sequencia de
## acertos — o oposto do que se quer.
const MUSIC_ENERGY_MISS_PENALTY: float = 0.16
const MUSIC_ENERGY_HIT_RECOVERY: float = 0.10

## O hold deixou de ser sempre amarelo: ele usa a cor do proprio evento,
## igual ao tap. Assim as fitas variam entre as tres cores da mesa e o
## estouro de cada uma sai na cor dela. HOLD_YELLOW continua existindo
## como valor de retorno seguro quando o evento nao trouxer indice.
const HOLD_FALLBACK_COLOR: Color = TAP_PALETTE.HOLD_YELLOW

var _song: Dictionary = {}
var _difficulty_name: String = "easy"
var _difficulty: Dictionary = {}
var _events: Array = []
var _state: int = GameState.PRESENTATION
var _state_time: float = 0.0
var _song_time: float = 0.0
var _song_duration: float = 90.0
var _failed: bool = false
var _result_score_percent: float = 0.0
var _result_transitioning: bool = false
var _record_celebration_active: bool = false
var _song_audio_started: bool = false
var _song_finish_requested: bool = false
var _best_score: float = 0.0
## Ultimo numero ja publicado da contagem, para nao reenviar o mesmo
## COUNT dezenas de vezes por segundo.
var _countdown_published: int = -1
## Saldo de fichas ja refletido no modal de resultado, para redesenha-lo
## quando o jogador inserir credito com o painel aberto.
var _result_credits_shown: int = -1

var _center: Vector2 = Vector2.ZERO
var _radius: float = 100.0
var _lane_positions: PackedVector2Array = PackedVector2Array()
var _video_rect: Rect2 = Rect2()

var _music_player: AudioStreamPlayer
var _video_player: VideoStreamPlayer
var _cover: TextureRect
var _renderer

var _hud_layer: CanvasLayer
var _top_panel: Panel
var _label_title: Label
var _label_difficulty: Label
var _label_score: Label
var _label_combo: Label
var _label_performance: Label
var _label_time: Label
var _label_best: Label
var _record_badge: Panel
var _progress_bar: ProgressBar
var _countdown_label: Label
var _result_panel: Panel
var _result_title: Label
var _result_score: Label
var _result_details: Label
var _result_timer_label: Label
var _result_primary_button: Panel
var _result_primary_label: Label
var _result_secondary_button: Panel
var _result_secondary_label: Label

var _score_quality_sum: float = 0.0
var _judgement_count: int = 0
var _hits: int = 0
var _misses: int = 0
var _combo: int = 0
var _max_combo: int = 0
var _performance: float = 100.0
## 1.0 = musica no volume cheio. Ver MUSIC_ENERGY_* acima.
var _music_energy: float = 1.0

var _touch_positions: Dictionary = {}
var _mouse_down: bool = false
var _mouse_position: Vector2 = Vector2.ZERO
var _pointer_active: bool = false
var _pointer_position: Vector2 = Vector2.ZERO
var _physical_lane_down: Array[bool] = []
## Eventos que ja nasceram e ainda nao foram resolvidos. Os lacos de
## quadro andam por aqui em vez de varrerem a fase inteira.
var _live_events: Array = []
var _spawn_cursor: int = 0


func _song_id() -> String:
	return "carmine"


func _ready() -> void:
	Engine.max_fps = 60
	# Amostras de ARRASTO passam a ser agrupadas por quadro. Isto vale
	# so para InputEventScreenDrag/MouseMotion — botao continua chegando
	# na hora, e o polling de _process_physical_inputs segue como rede
	# de seguranca para as bridges.
	#
	# Com false, um painel de toque de 150 Hz disparava 150 execucoes de
	# _handle_pointer_move por segundo, cada uma varrendo _events e
	# rodando ate 96 amostragens de corredor. Nao se perde precisao ao
	# agrupar: _advance_slide_progress INTERPOLA entre a ultima posicao
	# conhecida e a nova, entao o corredor continua sendo varrido ponto
	# a ponto.
	Input.use_accumulated_input = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_physical_lane_down.resize(NUM_LANES)
	_physical_lane_down.fill(false)

	_song = CATALOG.get_song(_song_id())
	if _song.is_empty():
		push_error("Song not found in catalog: " + _song_id())
		return

	if get_tree().has_meta("hit_music_difficulty"):
		_difficulty_name = str(get_tree().get_meta("hit_music_difficulty")).to_lower()
	if _difficulty_name != "hard":
		_difficulty_name = "easy"

	_difficulty = CATALOG.get_difficulty(_song, _difficulty_name)
	if _difficulty.is_empty():
		push_error("Difficulty not found for song: " + _song_id())
		return
	_best_score = _read_best_score()

	_calculate_geometry()
	_build_scene()
	_load_assets()
	_prepare_chart()
	_update_hud()
	_set_gameplay_hud_visible(true)
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	LED_CLIENT.clear_all()


func _process(delta: float) -> void:
	_state_time += delta
	_process_physical_inputs()

	match _state:
		GameState.PRESENTATION:
			if _state_time >= PRESENTATION_SECONDS:
				_start_countdown()
		GameState.COUNTDOWN:
			_update_song_time()
			var count_value: int = maxi(1, int(ceil(COUNTDOWN_SECONDS - _state_time)))
			_countdown_label.text = str(count_value)
			_publish_countdown_step(count_value)
			if _state_time >= COUNTDOWN_SECONDS:
				_start_playing()
		GameState.PLAYING:
			_update_song_time()
			_spawn_due_events()
			_update_tap_visuals()
			_update_slide_draw_progress(delta)
			_update_notes_and_misses()
			_update_hud()
			_update_dynamic_volume(delta)
			if _song_time >= _song_duration - 0.02:
				_request_song_finish()
		GameState.RESULT:
			if not _record_celebration_active:
				_update_result_countdown()
				if _state_time >= RESULT_SECONDS:
					_expire_result()

	_renderer.set_runtime(
		_events,
		_song_time,
		_state_name(),
		_pointer_position,
		_pointer_active
	)


## Moldura da mesa: fundo preto, o disco escuro e o halo da borda.
##
## Isto NAO muda durante a partida — so quando a janela e redimensionada.
## Mesmo assim era redesenhado a cada quadro, porque _process() chamava
## queue_redraw() sem condicao: um retangulo de tela cheia mais um arco
## de 240 segmentos antialiasados por quadro, sempre pintando a mesma
## imagem. Agora o redesenho so acontece quando a geometria muda (ver
## _calculate_geometry e _on_viewport_size_changed), e o arco caiu para
## 64 segmentos — a R=340px isso da menos de 0.5px de erro de corda,
## invisivel.
func _draw() -> void:
	var screen: Vector2 = get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, screen), Color.BLACK, true)
	draw_circle(_center, _radius * 1.012, Color(0.0, 0.0, 0.0, 0.96), true)
	draw_circle(_center, _radius * 0.995, _dark_color(), true)

	var glow_color: Color = _primary_color()
	draw_arc(
		_center,
		_radius * 1.002,
		0.0,
		TAU,
		64,
		Color(glow_color.r, glow_color.g, glow_color.b, 0.12),
		maxf(4.0, _radius * 0.014),
		true
	)


func _calculate_geometry() -> void:
	var screen: Vector2 = get_viewport_rect().size
	var side_margin: float = maxf(4.0, screen.x * SIDE_MARGIN_RATIO)
	var bottom_margin: float = maxf(4.0, screen.y * BOTTOM_MARGIN_RATIO)
	var top_reserved: float = screen.y * (
		TOP_MARGIN_RATIO + TOP_HEIGHT_RATIO + TOP_GAP_RATIO
	)

	var radius_by_width: float = (screen.x - side_margin * 2.0) * 0.5
	var radius_by_height: float = (screen.y - top_reserved - bottom_margin) * 0.5
	_radius = maxf(120.0, minf(radius_by_width, radius_by_height) * CIRCLE_SCALE)
	_center = Vector2(
		screen.x * 0.5,
		screen.y - bottom_margin - _radius
	)

	_lane_positions = PackedVector2Array()
	for lane in range(NUM_LANES):
		var angle: float = -PI * 0.5 + TAU * float(lane) / float(NUM_LANES)
		_lane_positions.append(
			_center + Vector2(cos(angle), sin(angle)) * _radius * 0.905
		)

	# A moldura so precisa ser repintada quando a geometria muda.
	queue_redraw()

	var top_margin: float = screen.x * TOP_MARGIN_RATIO
	_video_rect = Rect2(
		Vector2(top_margin, top_margin),
		Vector2(
			screen.x - top_margin * 2.0,
			screen.y * TOP_HEIGHT_RATIO
		)
	)


func _build_scene() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	_music_player.bus = "Master"
	_music_player.volume_db = -1.0
	add_child(_music_player)
	_music_player.finished.connect(_on_song_audio_finished)

	_video_player = VideoStreamPlayer.new()
	_video_player.name = "VideoBackground"
	_video_player.position = _video_rect.position
	_video_player.size = _video_rect.size
	_video_player.expand = true
	# O video acompanha uma unica execucao da musica. Se ele repetir antes
	# do resultado, parece que a partida recomecou e encobre a falha de fim.
	_video_player.loop = false
	_video_player.bus = "Master"
	_video_player.volume_db = -80.0
	_video_player.z_index = 2
	_video_player.visible = false
	_video_player.material = _rounded_video_material()
	add_child(_video_player)

	_cover = TextureRect.new()
	_cover.name = "PresentationCover"
	_cover.position = _center - Vector2(_radius * 0.72, _radius * 0.58)
	_cover.size = Vector2(_radius * 1.44, _radius * 1.16)
	_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover.z_index = 3
	add_child(_cover)

	_renderer = RENDERER_SCRIPT.new()
	_renderer.name = "PlayfieldRenderer"
	_renderer.z_index = 10
	add_child(_renderer)
	_renderer.configure(_center, _radius, _lane_positions, _song, _difficulty)

	_build_hud()


func _build_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 40
	add_child(_hud_layer)

	var screen: Vector2 = get_viewport_rect().size
	var margin: float = screen.x * TOP_MARGIN_RATIO
	var height: float = screen.y * TOP_HEIGHT_RATIO

	_top_panel = Panel.new()
	_top_panel.position = Vector2(margin, margin)
	_top_panel.size = Vector2(screen.x - margin * 2.0, height)
	_top_panel.add_theme_stylebox_override("panel", _top_panel_style())
	_hud_layer.add_child(_top_panel)

	var font: Font = _load_font()
	var inner_margin: float = _top_panel.size.x * 0.025
	var title_width: float = _top_panel.size.x * 0.52
	var right_x: float = _top_panel.size.x * 0.60

	_label_title = _make_label(
		str(_song.get("title", "HIT MUSIC")),
		int(height * 0.24),
		HORIZONTAL_ALIGNMENT_LEFT,
		font
	)
	_label_title.position = Vector2(inner_margin, height * 0.10)
	_label_title.size = Vector2(title_width, height * 0.34)
	_label_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label_title.clip_text = true
	_label_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_top_panel.add_child(_label_title)
	_fit_label_to_width(
		_label_title,
		title_width,
		int(height * 0.24),
		int(height * 0.13)
	)

	_label_difficulty = _make_label(
		"DIFICIL" if _difficulty_name == "hard" else "FACIL",
		int(height * 0.15),
		HORIZONTAL_ALIGNMENT_LEFT,
		font
	)
	_label_difficulty.position = Vector2(inner_margin, height * 0.47)
	_label_difficulty.size = Vector2(title_width, height * 0.22)
	_label_difficulty.add_theme_color_override("font_color", _accent_color())
	_top_panel.add_child(_label_difficulty)

	_label_time = _make_label("0:00", int(height * 0.14), HORIZONTAL_ALIGNMENT_LEFT, font)
	_label_time.position = Vector2(inner_margin, height * 0.70)
	_label_time.size = Vector2(title_width * 0.42, height * 0.18)
	_top_panel.add_child(_label_time)

	# A coluna da direita comeca ABAIXO do selo de recorde (que ocupa
	# 0.13..0.43 da altura do painel). Antes o placar comecava em 0.06 e
	# ficava exatamente atras do recorde.
	_label_score = _make_label("100.00%", int(height * 0.20), HORIZONTAL_ALIGNMENT_RIGHT, font)
	_label_score.position = Vector2(right_x, height * 0.45)
	_label_score.size = Vector2(_top_panel.size.x - right_x - inner_margin, height * 0.23)
	_label_score.add_theme_color_override("font_color", _secondary_color())
	_top_panel.add_child(_label_score)

	_label_combo = _make_label("COMBO 0", int(height * 0.12), HORIZONTAL_ALIGNMENT_RIGHT, font)
	_label_combo.position = Vector2(right_x, height * 0.68)
	_label_combo.size = Vector2(_top_panel.size.x - right_x - inner_margin, height * 0.11)
	_top_panel.add_child(_label_combo)

	_label_performance = _make_label("LIFE 100%", int(height * 0.11), HORIZONTAL_ALIGNMENT_RIGHT, font)
	_label_performance.position = Vector2(right_x, height * 0.79)
	_label_performance.size = Vector2(_top_panel.size.x - right_x - inner_margin, height * 0.10)
	_label_performance.add_theme_color_override("font_color", _primary_color())
	_top_panel.add_child(_label_performance)

	# RECORDE: selo proprio no canto superior direito do painel. Antes era
	# um rotulo solto que ocupava a mesma faixa vertical do placar e do
	# combo (0.35..0.65 contra 0.06..0.44 e 0.46..0.64) e ia colado na
	# borda arredondada, entao aparecia sobreposto ou cortado. Agora tem
	# moldura, respiro proprio e largura calculada a partir do texto.
	_build_record_badge(font, height, inner_margin)

	_progress_bar = ProgressBar.new()
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 1.0
	_progress_bar.value = 0.0
	_progress_bar.show_percentage = false
	_progress_bar.position = Vector2(inner_margin, height * 0.90)
	_progress_bar.size = Vector2(_top_panel.size.x - inner_margin * 2.0, maxf(7.0, height * 0.035))
	_progress_bar.add_theme_stylebox_override("background", _progress_background_style())
	_progress_bar.add_theme_stylebox_override("fill", _progress_fill_style())
	_top_panel.add_child(_progress_bar)

	_countdown_label = _make_label("", int(height * 0.56), HORIZONTAL_ALIGNMENT_CENTER, font)
	_countdown_label.position = _top_panel.position
	_countdown_label.size = _top_panel.size
	_countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown_label.add_theme_color_override("font_color", Color.WHITE)
	_countdown_label.add_theme_color_override(
		"font_outline_color",
		Color(0.0, 0.0, 0.0, 0.98)
	)
	_countdown_label.add_theme_constant_override("outline_size", 12)
	_countdown_label.visible = false
	_hud_layer.add_child(_countdown_label)

	# Painel reservado somente ao resultado da partida atual.
	_result_panel = Panel.new()
	# Painel maior: com os textos legiveis (o detalhe passou de 0.028
	# para 0.042 do raio) o conteudo nao cabia mais na caixa anterior.
	_result_panel.position = _center - Vector2(_radius * 0.72, _radius * 0.70)
	_result_panel.size = Vector2(_radius * 1.44, _radius * 1.40)
	_result_panel.visible = false
	_result_panel.z_index = 240
	_result_panel.add_theme_stylebox_override("panel", _result_panel_style())
	_hud_layer.add_child(_result_panel)

	_result_title = _make_label("TRACK CLEAR", int(_radius * 0.098), HORIZONTAL_ALIGNMENT_CENTER, font)
	_result_title.position = Vector2(_radius * 0.06, _radius * 0.05)
	_result_title.size = Vector2(_result_panel.size.x - _radius * 0.12, _radius * 0.16)
	_result_panel.add_child(_result_title)

	_result_score = _make_label("100.00%", int(_radius * 0.140), HORIZONTAL_ALIGNMENT_CENTER, font)
	_result_score.position = Vector2(_radius * 0.06, _radius * 0.235)
	_result_score.size = Vector2(_result_panel.size.x - _radius * 0.12, _radius * 0.21)
	_result_score.add_theme_color_override("font_color", _accent_color())
	_result_panel.add_child(_result_score)

	_result_details = _make_label("", int(_radius * 0.042), HORIZONTAL_ALIGNMENT_CENTER, font)
	_result_details.position = Vector2(_radius * 0.07, _radius * 0.475)
	_result_details.size = Vector2(_result_panel.size.x - _radius * 0.14, _radius * 0.30)
	_result_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_details.clip_text = true
	_result_panel.add_child(_result_details)

	_build_result_actions(font)


## Botoes e cronometro do modal. Ficam abaixo dos detalhes, dentro do
## painel, com area de toque propria — antes o modal era so texto e
## qualquer clique na tela disparava a mesma acao.
func _build_result_actions(font: Font) -> void:
	var margin: float = _radius * 0.08
	var width: float = _result_panel.size.x - margin * 2.0
	var button_height: float = _radius * 0.140

	_result_primary_button = Panel.new()
	_result_primary_button.position = Vector2(margin, _radius * 0.815)
	_result_primary_button.size = Vector2(width, button_height)
	_result_primary_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_panel.add_child(_result_primary_button)

	_result_primary_label = _make_label(
		"CONTINUAR",
		int(_radius * 0.054),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	_result_primary_label.size = _result_primary_button.size
	_result_primary_label.clip_text = true
	_result_primary_button.add_child(_result_primary_label)

	_result_secondary_button = Panel.new()
	_result_secondary_button.position = Vector2(margin, _radius * 0.815 + button_height + _radius * 0.040)
	_result_secondary_button.size = Vector2(width, button_height)
	_result_secondary_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_panel.add_child(_result_secondary_button)

	_result_secondary_label = _make_label(
		"ESCOLHER OUTRA MUSICA",
		int(_radius * 0.046),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	_result_secondary_label.size = _result_secondary_button.size
	_result_secondary_label.clip_text = true
	_result_secondary_button.add_child(_result_secondary_label)

	_result_timer_label = _make_label(
		"",
		int(_radius * 0.050),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	_result_timer_label.position = Vector2(margin, _result_panel.size.y - _radius * 0.135)
	_result_timer_label.size = Vector2(width, _radius * 0.095)
	_result_panel.add_child(_result_timer_label)


## Selo do recorde. Fica encostado no canto superior direito do painel,
## com margem propria para nao tocar a borda arredondada, altura menor
## que a faixa do titulo e base acima da barra de progresso. A largura
## nasce da medida real do texto (limitada ao espaco livre a direita do
## titulo), entao o valor nunca sai cortado.
func _build_record_badge(
	font: Font,
	height: float,
	inner_margin: float
) -> void:
	var text_value: String = _record_text()
	var font_size: int = maxi(12, int(height * 0.185))
	var badge_height: float = height * 0.30
	var padding: float = height * 0.10

	var available_width: float = _top_panel.size.x * 0.36 - inner_margin
	var measured: float = font.get_string_size(
		text_value,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size
	).x
	var badge_width: float = clampf(
		measured + padding * 2.0,
		_top_panel.size.x * 0.16,
		maxf(available_width, _top_panel.size.x * 0.16)
	)

	_record_badge = Panel.new()
	_record_badge.position = Vector2(
		_top_panel.size.x - inner_margin - badge_width,
		height * 0.13
	)
	_record_badge.size = Vector2(badge_width, badge_height)
	_record_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_record_badge.add_theme_stylebox_override("panel", _record_badge_style())
	_top_panel.add_child(_record_badge)

	_label_best = _make_label(
		text_value,
		font_size,
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	_label_best.position = Vector2(padding * 0.5, 0.0)
	_label_best.size = Vector2(badge_width - padding, badge_height)
	_label_best.clip_text = true
	_label_best.add_theme_color_override("font_color", _accent_color())
	_record_badge.add_child(_label_best)
	_fit_record_badge()


func _record_text() -> String:
	return "RECORDE  %.2f%%" % _best_score


## Reduz a fonte ate o texto caber na largura util do selo. Assim um
## recorde de 100.00% continua inteiro, sem reticencias.
func _fit_record_badge() -> void:
	if _label_best == null or not is_instance_valid(_label_best):
		return
	_label_best.text = _record_text()
	_fit_label_to_width(
		_label_best,
		_label_best.size.x,
		maxi(12, int(get_viewport_rect().size.y * TOP_HEIGHT_RATIO * 0.185)),
		12
	)


## Ao redimensionar a janela o painel superior muda de largura: o selo
## volta a se ancorar no canto e o texto e remedido, para nunca invadir
## o titulo nem estourar a borda.
func _reposition_record_badge() -> void:
	if _record_badge == null or not is_instance_valid(_record_badge):
		return
	if _top_panel == null or not is_instance_valid(_top_panel):
		return

	var screen: Vector2 = get_viewport_rect().size
	var margin: float = screen.x * TOP_MARGIN_RATIO
	var height: float = screen.y * TOP_HEIGHT_RATIO
	_top_panel.position = Vector2(margin, margin)
	_top_panel.size = Vector2(screen.x - margin * 2.0, height)

	var inner_margin: float = _top_panel.size.x * 0.025
	var badge_width: float = clampf(
		_record_badge.size.x,
		_top_panel.size.x * 0.16,
		maxf(_top_panel.size.x * 0.36 - inner_margin, _top_panel.size.x * 0.16)
	)
	_record_badge.size = Vector2(badge_width, height * 0.30)
	_record_badge.position = Vector2(
		_top_panel.size.x - inner_margin - badge_width,
		height * 0.13
	)

	if _label_best != null and is_instance_valid(_label_best):
		var padding: float = height * 0.10
		_label_best.position = Vector2(padding * 0.5, 0.0)
		_label_best.size = Vector2(badge_width - padding, _record_badge.size.y)
		_fit_record_badge()


func _record_badge_style() -> StyleBoxFlat:
	var accent: Color = _accent_color()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.010, 0.016, 0.034, 0.62)
	style.border_color = Color(accent.r, accent.g, accent.b, 0.58)
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.shadow_color = Color(accent.r, accent.g, accent.b, 0.16)
	style.shadow_size = 8
	return style


## Carrega audio, video e capa. Passa por USER_CATALOG porque a musica
## pode ser de fabrica (res://, importada pelo Godot) ou cadastrada pelo
## operador (user://, sem importacao — lida em bytes em tempo de
## execucao). Uma musica de operador sem video continua jogavel.
func _load_assets() -> void:
	var audio_path: String = str(_song.get("audio", ""))
	var audio_stream: AudioStream = USER_CATALOG.load_audio(audio_path)
	if audio_stream != null:
		# A faixa do gameplay precisa terminar de verdade. Se o recurso MP3
		# vier importado com loop, o sinal finished nunca sera emitido.
		if audio_stream is AudioStreamMP3:
			(audio_stream as AudioStreamMP3).loop = false
		_music_player.stream = audio_stream
		_music_player.volume_db = -1.0
		_song_duration = maxf(audio_stream.get_length(), 10.0)
	else:
		push_error("Audio nao carregado: " + audio_path)

	var video_path: String = str(_song.get("video", ""))
	var video_stream: VideoStream = USER_CATALOG.load_video(video_path)
	if video_stream != null:
		_video_player.stream = video_stream
		# O MP3 e a fonte sincronizada. O video so fornece audio como fallback.
		_video_player.volume_db = -80.0 if _music_player.stream != null else -1.0
	elif not video_path.is_empty():
		push_warning("Video nao carregado: " + video_path)

	var cover_texture: Texture2D = USER_CATALOG.load_cover(str(_song.get("cover", "")))
	if cover_texture != null:
		_cover.texture = cover_texture
	else:
		_cover.visible = false


func _prepare_chart() -> void:
	_events = CHART_FACTORY.build(_song, _difficulty_name, _song_duration)
	_live_events.clear()
	_spawn_cursor = 0
	for event_value in _events:
		if not event_value is Dictionary:
			continue
		var event: Dictionary = event_value as Dictionary
		event["_spawned"] = false
		event["_resolved"] = false
		event["_active"] = false
		event["_started"] = false
		event["_holding"] = false
		event["_visual_progress"] = 0.0
		event["_draw_progress"] = 0.0
		if str(event.get("type", "")) == "slide":
			var path_points: PackedVector2Array = PATH_BUILDER.build(
				event,
				_center,
				_radius,
				_lane_positions
			)
			event["_path_points"] = path_points
			event["_path_lengths"] = PATH_BUILDER.build_lengths(path_points)
			event["_lane_gates"] = _build_lane_gates(event, path_points)
			event["_last_pointer"] = (
				path_points[0] if path_points.size() > 0 else _center
			)


func _start_countdown() -> void:
	_state = GameState.COUNTDOWN
	_state_time = 0.0
	_song_time = 0.0
	_song_audio_started = false
	_song_finish_requested = false
	_cover.visible = false
	_video_player.visible = true
	if _video_player.stream != null:
		_video_player.play()
	else:
		push_warning("Video da musica nao foi carregado: " + str(_song.get("video", "")))
	if _music_player.stream != null:
		_music_player.play()
		_song_audio_started = true
	_set_gameplay_hud_visible(false)
	_countdown_label.visible = true
	_countdown_label.text = "3"
	_countdown_published = -1
	_countdown_label.add_theme_color_override("font_color", _countdown_color(3))


## Publica o numero da contagem e pinta o passo com a cor da vez.
##
## O jogo mandava so BLINKALL e nunca o COUNT, entao o firmware ficava
## com numero_contagem = 5, que cai no ramo padrao de cor_contagem — o
## ciano. Por isso a contagem era sempre azul. Enviando o numero, cada
## segundo assume a sua cor.
func _publish_countdown_step(count_value: int) -> void:
	if count_value == _countdown_published:
		return
	_countdown_published = count_value
	LED_CLIENT.countdown_value(count_value)

	if _countdown_label != null and is_instance_valid(_countdown_label):
		_countdown_label.add_theme_color_override(
			"font_color",
			_countdown_color(count_value)
		)


## 3 = azul, 2 = vermelho, 1 = amarelo. Numeros fora dessa faixa caem na
## primeira cor, entao uma contagem mais longa comeca do azul de novo.
func _countdown_color(count_value: int) -> Color:
	var index: int = COUNTDOWN_COLORS.size() - count_value
	if index < 0 or index >= COUNTDOWN_COLORS.size():
		return COUNTDOWN_COLORS[0]
	return COUNTDOWN_COLORS[index]


func _start_playing() -> void:
	_state = GameState.PLAYING
	_state_time = 0.0
	_countdown_label.visible = false
	_countdown_published = -1
	_set_gameplay_hud_visible(true)


func _set_gameplay_hud_visible(value: bool) -> void:
	for control in [
		_label_title,
		_label_difficulty,
		_label_score,
		_label_combo,
		_label_performance,
		_label_time,
		_progress_bar,
	]:
		if control != null and is_instance_valid(control):
			control.visible = value


func _rounded_video_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;

uniform float corner_radius : hint_range(0.01, 0.30) = 0.085;
uniform float feather : hint_range(0.0005, 0.03) = 0.004;

float rounded_rect_mask(vec2 uv, float radius_value) {
	vec2 half_size = vec2(0.5);
	vec2 q = abs(uv - vec2(0.5)) - (half_size - vec2(radius_value));
	float distance_value = length(max(q, vec2(0.0))) - radius_value;
	return 1.0 - smoothstep(-feather, feather, distance_value);
}

void fragment() {
	vec4 source_color = texture(TEXTURE, UV);
	float mask_value = rounded_rect_mask(UV, corner_radius);
	COLOR = vec4(source_color.rgb, source_color.a * mask_value);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material


func _update_song_time() -> void:
	if _music_player == null:
		return
	if not _music_player.playing:
		# Rede de seguranca para drivers/backends que encerram o stream sem
		# entregar o sinal finished. So vale depois que PLAYING ja comecou.
		if _song_audio_started and _state == GameState.PLAYING and _state_time > 0.10:
			_song_time = _song_duration
			_request_song_finish()
		return
	var value: float = _music_player.get_playback_position()
	value += AudioServer.get_time_since_last_mix()
	value -= AudioServer.get_output_latency()
	_song_time = clampf(value, 0.0, _song_duration)


func _on_song_audio_finished() -> void:
	# O MP3 pode mudar playing para false antes que o ultimo _process()
	# consiga observar song_time == duration. O sinal finished e a fonte
	# confiavel para encerrar a partida e abrir o modal exatamente uma vez.
	if not _song_audio_started:
		return
	if _state != GameState.COUNTDOWN and _state != GameState.PLAYING:
		return
	_song_time = _song_duration
	_request_song_finish()


func _request_song_finish() -> void:
	if _song_finish_requested or _state == GameState.RESULT:
		return
	_song_finish_requested = true
	# Evita trocar de estado no meio da emissao do sinal do player.
	call_deferred("_finish_game", false)


## A musica "respira" com o desempenho do jogador: fica mais cheia
## conforme ele mantem os acertos em sequencia e abafa assim que erra
## (combo cai pra 0) — feedback de audio que existia antes e se
## perdeu nos refinos. O volume desliza suavemente (nao troca de
## patamar de golpe) pra nao soar como um corte abrupto.
func _update_dynamic_volume(delta: float) -> void:
	if _music_player == null or not _music_player.playing:
		return

	var target_db: float = lerpf(
		MUSIC_VOLUME_MIN_DB,
		MUSIC_VOLUME_MAX_DB,
		clampf(_music_energy, 0.0, 1.0)
	)

	var rate: float = clampf(delta * MUSIC_VOLUME_SMOOTH_SPEED, 0.0, 1.0)
	_music_player.volume_db = lerpf(_music_player.volume_db, target_db, rate)


## _events esta ordenado por tempo, entao nao ha motivo para varrer a
## fase INTEIRA a cada quadro procurando o que nasceu: basta continuar
## de onde parou. Numa musica de 400 notas isso troca 400 leituras de
## dicionario por quadro por uma ou duas.
func _spawn_due_events() -> void:
	var approach: float = float(_difficulty.get("approach", 1.0))
	while _spawn_cursor < _events.size():
		var event_value: Variant = _events[_spawn_cursor]
		if not event_value is Dictionary:
			_spawn_cursor += 1
			continue
		var event: Dictionary = event_value as Dictionary
		var hit_time: float = float(event.get("time", 0.0))
		if _song_time < hit_time - approach:
			break
		_spawn_cursor += 1

		event["_spawned"] = true
		var type_name: String = str(event.get("type", "tap"))
		if type_name == "tap":
			_spawn_tap_visual(event, approach)
		elif type_name == "hold":
			# O LED acende na cor da propria fita do hold (amarelo), nao
			# na cor de destaque do cenario: o botao fisico precisa dizer
			# a mesma coisa que a tela esta mostrando.
			var lane: int = int(event.get("lane", 0))
			LED_CLIENT.set_lane(lane, _event_color(event))
		elif type_name == "slide":
			pass

		_live_events.append(event)


func _spawn_tap_visual(event: Dictionary, approach: float) -> void:
	var lane: int = clampi(int(event.get("lane", 0)), 0, NUM_LANES - 1)
	var visual = TAP_VISUAL_SCRIPT.new()
	add_child(visual)
	visual.configure(
		_center,
		_lane_positions[lane],
		float(event.get("time", 0.0)) - approach,
		float(event.get("time", 0.0)),
		_radius * 0.158 * float(_difficulty.get("tap_scale", 1.0)),
		int(event.get("color_index", lane % 3))
	)
	event["_node"] = visual
	LED_CLIENT.set_lane(lane, _tap_color(int(event.get("color_index", 0))))


## Todos os lacos de quadro andam sobre _live_events (o que ja nasceu e
## ainda nao foi resolvido) em vez da fase inteira.
func _update_tap_visuals() -> void:
	for event_value in _live_events:
		var event: Dictionary = event_value as Dictionary
		if str(event.get("type", "")) != "tap":
			continue
		if bool(event.get("_resolved", false)):
			continue
		var node_value: Variant = event.get("_node", null)
		if node_value is Node2D and is_instance_valid(node_value):
			node_value.update_visual(_song_time)


## Aproxima o progresso desenhado do progresso logico de cada arrasto.
##
## O alvo continua exato para a MECANICA (o acerto e imediato, o jogador
## nao perde nada) e a IMAGEM corre atras dele, que e o que se le como
## movimento. Sem isto a estrela saltava de um ponto do caminho para o
## outro e o gesto parecia acontecer do nada.
func _update_slide_draw_progress(delta: float) -> void:
	for event_value in _live_events:
		var event: Dictionary = event_value as Dictionary
		if str(event.get("type", "")) != "slide":
			continue

		var target: float = clampf(float(event.get("_visual_progress", 0.0)), 0.0, 1.0)
		var drawn: float = clampf(float(event.get("_draw_progress", 0.0)), 0.0, 1.0)
		if bool(event.get("_resolved", false)):
			event["_draw_progress"] = target
			continue
		if is_equal_approx(drawn, target):
			continue

		var speed: float = (
			SLIDE_DRAW_FINISH_SPEED
			if target >= 0.999 or bool(event.get("_resolved", false))
			else SLIDE_DRAW_SPEED
		)
		event["_draw_progress"] = move_toward(drawn, target, delta * speed)


func _update_notes_and_misses() -> void:
	var hit_window: float = float(_difficulty.get("hit_window", 0.20))
	var slide_window: float = _slide_start_window()

	# De tras para frente: eventos resolvidos saem da lista viva no
	# mesmo passo, sem precisar de uma segunda varredura.
	for index in range(_live_events.size() - 1, -1, -1):
		var event: Dictionary = _live_events[index] as Dictionary
		if bool(event.get("_resolved", false)):
			# Resolvido sai da lista de trabalho e da camada visual no mesmo quadro.
			_live_events.remove_at(index)
			continue

		var type_name: String = str(event.get("type", "tap"))
		var hit_time: float = float(event.get("time", 0.0))
		var end_time: float = float(event.get("end_time", hit_time))

		if type_name == "tap":
			if _song_time > hit_time + hit_window:
				_resolve_miss(event)
		elif type_name == "hold":
			if bool(event.get("_holding", false)):
				if _song_time >= end_time:
					_resolve_hit(event, "hold", 1.0)
			elif _song_time > hit_time + hit_window:
				_resolve_miss(event)
		elif type_name == "slide":
			# Depois de COMECADO, o arrasto e julgado pelo fim do gesto,
			# nunca mais pela janela de entrada. Antes, soltar o dedo no
			# meio devolvia o evento para a regra de entrada e ele
			# morria no quadro seguinte.
			if bool(event.get("_started", false)):
				if _song_time > end_time + SLIDE_GRACE_SECONDS:
					_resolve_miss(event)
			elif _song_time > hit_time + slide_window:
				_resolve_miss(event)


func _process_physical_inputs() -> void:
	if _state == GameState.RESULT:
		# Os dois modos aceitam comando agora. Quem decide se a acao vale
		# e o proprio _activate_*: no modo credito ela so passa se houver
		# ficha, e sem ficha o cronometro leva para a abertura.
		if _action_pressed("input_start") or _action_pressed("ui_accept"):
			_activate_result_action()
		elif _action_pressed("input_b"):
			_activate_result_change_song()
		return

	if _state != GameState.PLAYING:
		return

	for lane in range(INPUT_ACTIONS.size()):
		var action: String = INPUT_ACTIONS[lane]
		if not InputMap.has_action(action):
			continue
		var pressed: bool = Input.is_action_pressed(action)
		if pressed and not _physical_lane_down[lane]:
			_physical_lane_down[lane] = true
			_handle_lane_press(lane, "lane_%d" % lane)
		elif not pressed and _physical_lane_down[lane]:
			_physical_lane_down[lane] = false
			_handle_lane_release(lane, "lane_%d" % lane)


func _input(event: InputEvent) -> void:
	if _state == GameState.RESULT:
		if event is InputEventScreenTouch and event.pressed:
			_handle_result_pointer((event as InputEventScreenTouch).position)
		elif event is InputEventMouseButton and event.pressed:
			_handle_result_pointer((event as InputEventMouseButton).position)
		return

	if _state != GameState.PLAYING:
		return

	# Processa a borda do botao no proprio evento, antes do proximo frame.
	# O estado compartilhado impede que o polling em _process() duplique o hit.
	for lane in range(INPUT_ACTIONS.size()):
		var action: String = INPUT_ACTIONS[lane]
		if not InputMap.has_action(action):
			continue
		if event.is_action_pressed(action):
			if not _physical_lane_down[lane]:
				_physical_lane_down[lane] = true
				_handle_lane_press(lane, "lane_%d" % lane)
			return
		if event.is_action_released(action):
			if _physical_lane_down[lane]:
				_physical_lane_down[lane] = false
				_handle_lane_release(lane, "lane_%d" % lane)
			return

	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		_pointer_position = touch.position
		_pointer_active = touch.pressed
		if touch.pressed:
			_touch_positions[touch.index] = touch.position
			_handle_pointer_press("touch_%d" % touch.index, touch.position)
		else:
			_touch_positions.erase(touch.index)
			_handle_pointer_release("touch_%d" % touch.index, touch.position)
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		_touch_positions[drag.index] = drag.position
		_pointer_position = drag.position
		_pointer_active = true
		_handle_pointer_move("touch_%d" % drag.index, drag.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_button: InputEventMouseButton = event
		_mouse_down = mouse_button.pressed
		_mouse_position = mouse_button.position
		_pointer_position = mouse_button.position
		_pointer_active = mouse_button.pressed
		if mouse_button.pressed:
			_handle_pointer_press("mouse", mouse_button.position)
		else:
			_handle_pointer_release("mouse", mouse_button.position)
	elif event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event
		_mouse_position = motion.position
		_pointer_position = motion.position
		_pointer_active = _mouse_down
		if _mouse_down:
			_handle_pointer_move("mouse", motion.position)


func _handle_pointer_press(source: String, position_value: Vector2) -> void:
	var lane: int = _nearest_lane(position_value)
	if lane < 0:
		return
	_handle_lane_press(lane, source, true, position_value)


func _handle_pointer_move(source: String, position_value: Vector2) -> void:
	# Se este dedo nao esta conduzindo nenhum arrasto, ele pode ADOTAR
	# um que ainda nao comecou e cujo ponto de partida esteja embaixo
	# dele. Sem isto, um toque que caiu alguns pixels fora da marca
	# perdia a nota para sempre: _handle_pointer_press saia sem fazer
	# nada e o movimento seguinte era ignorado, porque este laco so
	# aceita arrastos que ja estao _active com a mesma origem. Era a
	# causa direta do "nem sempre sao detectados".
	_try_adopt_slide(source, position_value)

	for event_value in _live_events:
		var event: Dictionary = event_value as Dictionary
		if bool(event.get("_resolved", false)):
			continue
		if str(event.get("type", "")) != "slide":
			continue
		if not bool(event.get("_active", false)):
			continue
		if str(event.get("_source", "")) != source:
			continue

		var points_value: Variant = event.get("_path_points", PackedVector2Array())
		if not points_value is PackedVector2Array:
			continue
		var points: PackedVector2Array = points_value as PackedVector2Array
		if points.size() < 2:
			continue

		_advance_slide_progress(event, points, position_value)
		event["_last_pointer"] = position_value

		var progress: float = float(event.get("_visual_progress", 0.0))
		if progress >= SLIDE_COMPLETE_RATIO:
			# _resolve_hit ja publica o estouro na cor do proprio arrasto.
			# Antes havia um segundo efeito aqui, na cor de tema da musica,
			# que pintava por cima do primeiro com a cor errada.
			_resolve_hit(event, "slide", 1.0)


## Procura um arrasto ainda nao iniciado cujo ponto de partida esteja
## debaixo do dedo, e o entrega a este ponteiro. So age quando o dedo
## nao esta ocupado com outro gesto.
func _try_adopt_slide(source: String, position_value: Vector2) -> void:
	for event_value in _live_events:
		var busy: Dictionary = event_value as Dictionary
		if str(busy.get("_source", "")) != source:
			continue
		if bool(busy.get("_active", false)) or bool(busy.get("_holding", false)):
			return

	var tolerance: float = _radius * SLIDE_CORRIDOR_TOLERANCE_RATIO
	var best: Dictionary = {}
	var best_distance: float = INF

	for event_value in _live_events:
		var event: Dictionary = event_value as Dictionary
		if bool(event.get("_resolved", false)) or bool(event.get("_active", false)):
			continue
		if str(event.get("type", "")) != "slide":
			continue
		if not _is_selectable(event):
			continue

		var points_value: Variant = event.get("_path_points", PackedVector2Array())
		if not points_value is PackedVector2Array:
			continue
		var points: PackedVector2Array = points_value as PackedVector2Array
		if points.size() < 2:
			continue

		var distance_value: float = points[0].distance_to(position_value)
		if distance_value <= tolerance and distance_value < best_distance:
			best_distance = distance_value
			best = event

	if not best.is_empty():
		_begin_slide(best, source, true, position_value)


# O jogador precisa realmente varrer o caminho do arrasto. Antes, o
# progresso era calculado projetando so a posicao ATUAL do ponteiro
# sobre o trajeto inteiro - isso permitia "clicar no comeco e no fim"
# (ou arrastar reto, cortando caminho) e o arrasto contar como
# completo mesmo sem seguir o desenho. Agora a trajetoria entre a
# ultima posicao conhecida do ponteiro e a posicao nova e amostrada em
# pequenos passos; cada passo so avanca o progresso se cair dentro do
# corredor do caminho (e um pouco a frente do que ja foi percorrido).
# Assim que uma amostra sai do corredor o avanco para, entao pular
# direto para o fim nao completa mais a nota.
func _advance_slide_progress(
	event: Dictionary,
	points: PackedVector2Array,
	position_value: Vector2
) -> void:
	var tolerance: float = _radius * SLIDE_CORRIDOR_TOLERANCE_RATIO
	var step_size: float = maxf(_radius * SLIDE_SAMPLE_STEP_RATIO, 1.0)
	var last_position: Vector2 = event.get("_last_pointer", position_value)
	var current_progress: float = float(event.get("_visual_progress", 0.0))

	var travel: float = last_position.distance_to(position_value)
	var steps: int = clampi(int(ceil(travel / step_size)), 1, 96)

	for step in range(1, steps + 1):
		var sample: Vector2 = last_position.lerp(position_value, float(step) / float(steps))
		var nearest: Dictionary = PATH_BUILDER.nearest_progress(
			points,
			sample,
			current_progress,
			SLIDE_MAX_FORWARD_SPAN
		)
		if float(nearest.get("distance", INF)) > tolerance:
			break
		current_progress = maxf(
			current_progress,
			float(nearest.get("progress", current_progress))
		)

	event["_visual_progress"] = current_progress


func _handle_pointer_release(source: String, _position_value: Vector2) -> void:
	for event_value in _live_events:
		var event: Dictionary = event_value as Dictionary
		if bool(event.get("_resolved", false)):
			continue
		if str(event.get("_source", "")) != source:
			continue

		var type_name: String = str(event.get("type", ""))
		if type_name == "hold" and bool(event.get("_holding", false)):
			var end_time: float = float(event.get("end_time", 0.0))
			if _song_time >= end_time - 0.12:
				_resolve_hit(event, "hold", 1.0)
			else:
				_resolve_miss(event)
		elif type_name == "slide" and bool(event.get("_active", false)):
			if float(event.get("_visual_progress", 0.0)) >= SLIDE_COMPLETE_RATIO:
				_resolve_hit(event, "slide", 1.0)
			else:
				# Soltar o dedo no meio NAO e mais erro imediato. O gesto
				# so e solto (o progresso ja feito fica guardado) e o
				# jogador pode retomar enquanto a nota viver; o erro sai
				# no fim do prazo, em _update_notes_and_misses.
				event["_active"] = false
				event["_source"] = ""
				event.erase("_last_pointer")


func _handle_lane_press(
	lane: int,
	source: String,
	has_pointer: bool = false,
	press_position: Vector2 = Vector2.ZERO
) -> void:
	if _advance_slide_with_lane(lane):
		return

	# Com a janela aberta desde o nascimento do tazo, varios objetos da
	# mesma lane podem estar na tela ao mesmo tempo. Vence o mais proximo
	# do proprio tempo, e nao o tipo que aparecer primeiro na lista: antes
	# a ordem era fixa (tap, depois hold, depois arrasto) e um tap ainda
	# distante roubava o toque que era do arrasto que ja estava chegando.
	var best: Dictionary = {}
	var best_difference: float = INF

	for event_value in _live_events:
		var event: Dictionary = event_value as Dictionary
		if bool(event.get("_resolved", false)):
			continue
		if not _is_selectable(event):
			continue

		match str(event.get("type", "")):
			"tap", "hold":
				if int(event.get("lane", -1)) != lane:
					continue
			"slide":
				if bool(event.get("_active", false)):
					continue
				var path_value: Variant = event.get("path", [])
				if not path_value is Array or (path_value as Array).is_empty():
					continue
				if int((path_value as Array)[0]) != lane:
					continue
			_:
				continue

		var difference: float = absf(_song_time - float(event.get("time", 0.0)))
		if difference < best_difference:
			best = event
			best_difference = difference

	if best.is_empty():
		return

	match str(best.get("type", "tap")):
		"hold":
			best["_holding"] = true
			best["_source"] = source
		"slide":
			_begin_slide(best, source, has_pointer, press_position)
		_:
			_resolve_hit(best, "tap", _timing_quality(best_difference))


## Arrasto no gabinete: sem tela sensivel ao toque nao existe ponteiro
## para varrer o corredor, entao o percurso avanca apertando os botoes
## das lanes do caminho, em ordem. Isso so vale para arrastos iniciados
## por botao fisico — no toque/mouse continua valendo a varredura
## completa de _advance_slide_progress, sem atalho.
func _advance_slide_with_lane(lane: int) -> bool:
	for event_value in _live_events:
		var event: Dictionary = event_value as Dictionary
		if bool(event.get("_resolved", false)):
			continue
		if str(event.get("type", "")) != "slide":
			continue
		if not bool(event.get("_active", false)):
			continue
		if not str(event.get("_source", "")).begins_with("lane_"):
			continue

		var gate: Dictionary = _next_slide_gate(event)
		if gate.is_empty():
			continue
		if int(gate.get("lane", -1)) != lane:
			continue

		var gate_progress: float = float(gate.get("progress", 0.0))
		event["_visual_progress"] = gate_progress
		event["_last_pointer"] = _lane_positions[
			clampi(lane, 0, _lane_positions.size() - 1)
		]

		if gate_progress >= SLIDE_COMPLETE_RATIO:
			_resolve_hit(event, "slide", 1.0)
		return true

	return false


## Proximo ponto do caminho que ainda falta ser tocado. Voltar ou pular
## etapas nao conta: so o gate imediatamente a frente e aceito.
func _next_slide_gate(event: Dictionary) -> Dictionary:
	var gates_value: Variant = event.get("_lane_gates", [])
	if not gates_value is Array:
		return {}

	var progress: float = float(event.get("_visual_progress", 0.0))
	for gate_value in (gates_value as Array):
		if not gate_value is Dictionary:
			continue
		var gate: Dictionary = gate_value as Dictionary
		if float(gate.get("progress", 0.0)) > progress + 0.02:
			return gate
	return {}


## Progresso de cada lane do caminho dentro da polilinha ja amostrada.
## Serve tanto para o avanco por botao quanto para o LED indicar qual
## e o proximo botao do arrasto.
func _build_lane_gates(
	event: Dictionary,
	points: PackedVector2Array
) -> Array:
	var gates: Array = []
	var lanes_value: Variant = event.get("path", [])
	if not lanes_value is Array or points.size() < 2:
		return gates

	var last_index: int = points.size() - 1
	for lane_value in (lanes_value as Array):
		var lane_index: int = clampi(int(lane_value), 0, _lane_positions.size() - 1)
		var target: Vector2 = _lane_positions[lane_index]
		var best_progress: float = 0.0
		var best_distance: float = INF
		for index in range(points.size()):
			var distance_value: float = points[index].distance_to(target)
			if distance_value < best_distance:
				best_distance = distance_value
				best_progress = float(index) / float(last_index)
		gates.append({"lane": lane_index, "progress": best_progress})

	# O ultimo ponto do caminho fecha a nota, mesmo que a amostragem tenha
	# parado alguns pixels antes da marca da lane.
	if not gates.is_empty():
		(gates[gates.size() - 1] as Dictionary)["progress"] = 1.0
	return gates


func _handle_lane_release(_lane: int, source: String) -> void:
	for event_value in _live_events:
		var event: Dictionary = event_value as Dictionary
		if bool(event.get("_resolved", false)):
			continue
		if str(event.get("type", "")) != "hold":
			continue
		if str(event.get("_source", "")) != source:
			continue
		var end_time: float = float(event.get("end_time", 0.0))
		if _song_time >= end_time - 0.12:
			_resolve_hit(event, "hold", 1.0)
		else:
			_resolve_miss(event)


## Assim que o objeto aparece na tela ele ja pode ser escolhido: nao e
## mais preciso esperar ele encostar no anel. Antecipar deixou de ser
## erro (o estouro sai onde o tazo estiver); atrasar continua limitado
## pelo hit_window da dificuldade, senao a nota some sem chance.
func _is_selectable(event: Dictionary) -> bool:
	if not bool(event.get("_spawned", false)):
		return false

	# Arrasto que ja foi comecado e largado no meio pode ser RETOMADO
	# ate o fim do proprio gesto, e nao so dentro da janela de entrada.
	# Sem isto, tirar o dedo por um instante matava a nota mesmo com
	# tempo de sobra no relogio dela.
	if bool(event.get("_started", false)):
		var end_time: float = float(event.get("end_time", 0.0))
		return _song_time <= end_time + SLIDE_GRACE_SECONDS

	var window: float = float(_difficulty.get("hit_window", 0.20))
	if str(event.get("type", "")) == "slide":
		window = _slide_start_window()
	return _song_time <= float(event.get("time", 0.0)) + window


## Janela para INICIAR um arrasto. Fica em cima da janela da
## dificuldade, entao continua acompanhando o BPM da musica.
func _slide_start_window() -> float:
	return float(_difficulty.get("hit_window", 0.20)) * SLIDE_START_WINDOW_SCALE


## Pontuacao por precisao. Encaixar no anel continua valendo mais, entao
## o jogador que espera o tempo certo e recompensado mesmo podendo
## acertar antes.
func _timing_quality(difference: float) -> float:
	var perfect_window: float = float(_difficulty.get("perfect_window", 0.075))
	var hit_window: float = float(_difficulty.get("hit_window", 0.20))
	if difference <= perfect_window:
		return 1.0
	if difference <= hit_window:
		return 0.72
	var approach: float = maxf(float(_difficulty.get("approach", 1.0)), 0.001)
	var early: float = clampf((difference - hit_window) / approach, 0.0, 1.0)
	return lerpf(0.72, 0.50, early)


## Comeca um arrasto. O corredor e ancorado na posicao real do toque
## quando existe ponteiro (touch/mouse); no botao fisico usa o proprio
## inicio do trajeto, ja que nao ha ponteiro na tela.
func _begin_slide(
	event: Dictionary,
	source: String,
	has_pointer: bool = false,
	press_position: Vector2 = Vector2.ZERO
) -> void:
	# Retomada NAO zera o progresso: o trecho que o jogador ja varreu
	# continua valendo. Quem impede que a retomada vire atalho e
	# SLIDE_MAX_FORWARD_SPAN, que so deixa cada amostra avancar uma
	# fatia curta a partir do progresso atual — pegar direto no fim do
	# traco cai fora do corredor e nao conta.
	var resuming: bool = bool(event.get("_started", false))

	event["_active"] = true
	event["_started"] = true
	event["_source"] = source
	if not resuming:
		event["_visual_progress"] = 0.0
		event["_draw_progress"] = 0.0

	var start_point: Vector2 = _center
	var points_value: Variant = event.get("_path_points", PackedVector2Array())
	if points_value is PackedVector2Array and (points_value as PackedVector2Array).size() > 0:
		start_point = (points_value as PackedVector2Array)[0]
	event["_last_pointer"] = press_position if has_pointer else start_point


func _resolve_hit(event: Dictionary, kind: String, quality: float) -> void:
	if bool(event.get("_resolved", false)):
		return
	event["_resolved"] = true
	event["_active"] = false
	event["_holding"] = false

	var effect_kind: String = "tap"
	if kind == "slide":
		# Mantem a assinatura visual de cada estrela no BURST. O sprite que
		# percorre o caminho e encerrado separadamente no mesmo quadro.
		effect_kind = "slide"
		event["_draw_progress"] = event.get("_visual_progress", 1.0)
	elif kind == "hold":
		effect_kind = "hold"
	# Uma unica cor governa todo o feedback deste acerto: burst, roda,
	# mandala e LED. Assim um tazo vermelho nunca gera efeito de outra cor.
	var hit_color: Color = _event_color(event)
	# O estouro nasce ONDE O OBJETO ESTA no momento do acerto (no meio do
	# trajeto, se foi acertado cedo). O flash da roda continua ancorado no
	# ponto de encaixe da lane, que e onde a linha fica.
	_renderer.add_effect(
		effect_kind,
		_event_hit_position(event),
		hit_color,
		int(event.get("arrow_style", 0)),
		int(event.get("star_style", 0))
	)
	_renderer.flash_ring_at(
		_event_end_position(event),
		hit_color,
		0.95 + quality * 0.35,
		3.1
	)

	_remove_tap_node(event)
	_clear_event_led(event)

	_score_quality_sum += quality
	_judgement_count += 1
	_hits += 1
	_combo += 1
	_max_combo = maxi(_max_combo, _combo)
	_renderer.register_hit(quality, _combo, hit_color)
	_performance = minf(100.0, _performance + (1.15 if quality >= 0.99 else 0.55))
	# Acertar MANTEM a musica cheia (e recupera se ela tinha caido).
	_music_energy = minf(1.0, _music_energy + MUSIC_ENERGY_HIT_RECOVERY)


func _resolve_miss(event: Dictionary) -> void:
	if bool(event.get("_resolved", false)):
		return
	event["_resolved"] = true
	event["_active"] = false
	event["_holding"] = false

	# Miss silencioso: sem X vermelho ou explosao sobre a proxima nota.
	_remove_tap_node(event)
	_clear_event_led(event)

	_judgement_count += 1
	_misses += 1
	_combo = 0
	_performance = maxf(0.0, _performance - 6.0)
	# Errar ABAIXA a musica. A partida NAO e mais cancelada por
	# desempenho: o jogador sempre toca a musica ate o fim.
	_music_energy = maxf(0.0, _music_energy - MUSIC_ENERGY_MISS_PENALTY)


func _remove_tap_node(event: Dictionary) -> void:
	var node_value: Variant = event.get("_node", null)
	if node_value is Node and is_instance_valid(node_value):
		(node_value as Node).queue_free()
	event.erase("_node")


func _clear_event_led(event: Dictionary) -> void:
	var type_name: String = str(event.get("type", ""))
	if type_name == "tap" or type_name == "hold":
		LED_CLIENT.clear_lane(int(event.get("lane", 0)))


func _event_end_position(event: Dictionary) -> Vector2:
	var type_name: String = str(event.get("type", "tap"))
	if type_name == "slide":
		var points_value: Variant = event.get("_path_points", PackedVector2Array())
		if points_value is PackedVector2Array and not (points_value as PackedVector2Array).is_empty():
			return (points_value as PackedVector2Array)[(points_value as PackedVector2Array).size() - 1]
	var lane: int = clampi(int(event.get("lane", 0)), 0, NUM_LANES - 1)
	return _lane_positions[lane]


## Onde o objeto esta AGORA na tela. Como o acerto nao espera mais o
## tazo chegar no anel, o efeito precisa nascer no ponto real em que ele
## foi acertado — no meio do caminho, se foi cedo — e nao no alvo fixo.
## As formulas seguem as mesmas do desenho (tap_visual.update_visual,
## playfield_renderer._draw_hold e _draw_slide) para o estouro cair
## exatamente em cima do desenho.
func _event_hit_position(event: Dictionary) -> Vector2:
	var type_name: String = str(event.get("type", "tap"))
	var approach: float = maxf(float(_difficulty.get("approach", 1.0)), 0.001)
	var hit_time: float = float(event.get("time", 0.0))
	var arrival: float = clampf((_song_time - (hit_time - approach)) / approach, 0.0, 1.0)
	var eased: float = 1.0 - pow(1.0 - arrival, 4.0)

	if type_name == "slide":
		var points_value: Variant = event.get("_path_points", PackedVector2Array())
		if not points_value is PackedVector2Array:
			return _event_end_position(event)
		var points: PackedVector2Array = points_value as PackedVector2Array
		if points.is_empty():
			return _event_end_position(event)
		if _song_time < hit_time:
			return _center.lerp(points[0], eased)
		var lengths_value: Variant = event.get("_path_lengths", {})
		var lengths: Dictionary = lengths_value if lengths_value is Dictionary else {}
		# Usa o progresso DESENHADO: o estouro tem de sair de onde a
		# estrela esta na tela, nao de onde a mecanica ja considerou que
		# ela chegou.
		return PATH_BUILDER.point_at_cached(
			points,
			lengths,
			clampf(float(event.get("_draw_progress", 0.0)), 0.0, 1.0)
		)

	if type_name == "tap":
		var node_value: Variant = event.get("_node", null)
		if node_value is Node2D and is_instance_valid(node_value):
			return (node_value as Node2D).position

	var target: Vector2 = _event_end_position(event)
	if _song_time >= hit_time:
		return target
	return _center.lerp(target, eased)


## Tap, hold e arrasto seguem a MESMA regra: a cor e a do proprio
## objeto, dada pelo color_index. Nenhum tipo usa mais a cor de tema da
## musica, entao um objeto nunca estoura numa cor que nao e a dele.
func _event_color(event: Dictionary) -> Color:
	if not event.has("color_index"):
		return HOLD_FALLBACK_COLOR
	return _tap_color(int(event.get("color_index", 0)))


func _finish_game(failed: bool) -> void:
	if _state == GameState.RESULT:
		return
	_song_audio_started = false
	_song_finish_requested = true
	_state = GameState.RESULT
	_state_time = 0.0
	_failed = failed
	_result_transitioning = false
	_music_player.stop()
	_video_player.stop()
	_video_player.visible = false
	_countdown_label.visible = false
	_set_gameplay_hud_visible(false)

	var score: float = _score_percent()
	var previous_best: float = _best_score
	var is_new_record: bool = score > previous_best + 0.005
	_result_score_percent = score
	_result_credits_shown = ArcadeSettings.credits
	_apply_result_theme()
	_result_title.text = "CLASSIFICADO" if score >= RESULT_PASS_PERCENT else "NÃO CLASSIFICADO"
	_result_score.text = "%.2f%%" % score
	_result_score.add_theme_color_override("font_color", _result_accent_color())
	# Sem a linha de "o que fazer": os proprios botoes ja dizem. Com uma
	# linha a menos, as que sobram cabem no tamanho legivel.
	_result_details.text = (
		"ACERTOS %d   ERROS %d\nMAX COMBO %d\n%s\n%s"
		% [_hits, _misses, _max_combo, _result_qualification_text(), _result_action_hint()]
	)
	_save_record(score)
	_best_score = maxf(_best_score, score)
	_fit_record_badge()
	LED_CLIENT.clear_all()

	if is_new_record:
		_show_new_record_celebration(score, previous_best)
	else:
		_play_game_over_sting()
		_reveal_result_panel()


func _show_new_record_celebration(score: float, previous_best: float) -> void:
	if not ResourceLoader.exists(NEW_RECORD_SCENE_PATH):
		_reveal_result_panel()
		return
	var packed := load(NEW_RECORD_SCENE_PATH) as PackedScene
	if packed == null:
		_reveal_result_panel()
		return
	var celebration := packed.instantiate()
	if celebration == null or not celebration.has_method("configure"):
		_reveal_result_panel()
		return

	_record_celebration_active = true
	_state_time = 0.0
	celebration.call(
		"configure",
		str(_song.get("title", _song_id())),
		score,
		previous_best,
		_primary_color(),
		_accent_color(),
		Rect2(_top_panel.position, _top_panel.size),
		_center,
		_radius
	)
	if celebration.has_signal("celebration_finished"):
		celebration.connect(
			"celebration_finished",
			_on_record_celebration_finished.bind(celebration),
			CONNECT_ONE_SHOT
		)
	# A interface do jogo vive em CanvasLayer. Na arvore 2D comum, z_index
	# nunca supera essa camada; por isso o anuncio antigo ficava escondido.
	# Inserido no proprio HUD, o recorde cobre tudo dentro das duas telas.
	_hud_layer.add_child(celebration)
	_start_record_led_celebration()


func _start_record_led_celebration() -> void:
	var client := get_node_or_null("/root/LedClient")
	if client != null and client.has_method("end_game"):
		client.call("end_game")
	LED_CLIENT.record_celebration(_primary_color(), _accent_color())


func _on_record_celebration_finished(celebration: Node) -> void:
	if is_instance_valid(celebration):
		celebration.queue_free()
	# HIT no firmware volta ao estado anterior; limpar explicitamente evita
	# qualquer lane ou botao permanecer aceso depois do anuncio.
	LED_CLIENT.clear_all()
	_record_celebration_active = false
	_state_time = 0.0
	_reveal_result_panel()


func _play_game_over_sting() -> void:
	# Marca sonoramente o fim da partida antes do modal aparecer.
	if not ResourceLoader.exists(GAME_OVER_STING_PATH):
		return
	var sting_resource: Resource = load(GAME_OVER_STING_PATH)
	if not sting_resource is AudioStream:
		return
	_music_player.stream = sting_resource as AudioStream
	_music_player.volume_db = -1.0
	_music_player.play()


func _reveal_result_panel() -> void:
	# Entrada suave (fade + leve escala) em vez do painel aparecer de
	# repente — junto com o sting de game over, deixa claro que a
	# partida terminou, sem susto/corte seco.
	_result_panel.visible = true
	_result_panel.z_index = 240
	_result_panel.move_to_front()
	_result_panel.modulate.a = 0.0
	_result_panel.pivot_offset = _result_panel.size * 0.5
	_result_panel.scale = Vector2(0.94, 0.94)

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUINT)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(_result_panel, "modulate:a", 1.0, 0.50)
	tween.tween_property(_result_panel, "scale", Vector2.ONE, 0.50)


func _force_result_panel_visible() -> void:
	if _state != GameState.RESULT:
		return
	if _result_panel == null or not is_instance_valid(_result_panel):
		return
	if _hud_layer != null and is_instance_valid(_hud_layer):
		_hud_layer.layer = 90
	_result_panel.visible = true
	_result_panel.z_index = 240
	_result_panel.modulate = Color.WHITE
	_result_panel.scale = Vector2.ONE
	_result_panel.move_to_front()


## Texto de apoio do modal. As acoes reais estao nos botoes; aqui fica
## so a explicacao curta do que cada caminho faz.
func _result_action_hint() -> String:
	if ArcadeSettings.is_credit_mode():
		if ArcadeSettings.credits > 0:
			return "VOCÊ TEM %d FICHA(S)" % ArcadeSettings.credits
		return "SEM FICHA • INSIRA CRÉDITO PARA JOGAR"
	return "TOQUE EM UMA OPÇÃO PARA CONTINUAR"


func _result_qualification_text() -> String:
	if _result_score_percent >= RESULT_PASS_PERCENT:
		return "APROVADO • PRÓXIMA MÚSICA LIBERADA"
	return "MÍNIMO 70% • TENTE NOVAMENTE"


## Aplica a cor do modal e o texto dos dois botoes de acordo com o modo
## do gabinete. Rodado uma vez, quando o resultado aparece.
func _apply_result_theme() -> void:
	if _result_panel == null or not is_instance_valid(_result_panel):
		return

	_result_panel.add_theme_stylebox_override("panel", _result_panel_style())
	_result_title.add_theme_color_override("font_color", _result_accent_color())

	var credit_mode: bool = ArcadeSettings.is_credit_mode()
	var has_credit: bool = ArcadeSettings.credits > 0
	var passed: bool = _result_score_percent >= RESULT_PASS_PERCENT

	# Botao principal: continuar jogando. No modo credito ele so existe
	# se houver ficha — sem ficha nao ha o que oferecer.
	var primary_available: bool = (not credit_mode) or has_credit
	if credit_mode:
		_result_primary_label.text = (
			"START • USAR FICHA E SEGUIR" if passed else "START • USAR FICHA E REPETIR"
		)
	else:
		_result_primary_label.text = (
			"START • PRÓXIMA MÚSICA" if passed else "START • TENTAR DE NOVO"
		)

	_result_primary_button.visible = primary_available
	_result_primary_button.add_theme_stylebox_override(
		"panel",
		_result_button_style(true)
	)

	# Botao secundario: trocar de musica. No modo credito ele tambem
	# depende de ficha, porque escolher outra musica e comecar outra
	# partida.
	_result_secondary_button.visible = primary_available
	_result_secondary_label.text = "B • ESCOLHER OUTRA MÚSICA"
	_result_secondary_button.add_theme_stylebox_override(
		"panel",
		_result_button_style(false)
	)

	_fit_label_to_width(
		_result_primary_label,
		_result_primary_button.size.x * 0.92,
		int(_radius * 0.054),
		int(_radius * 0.036)
	)
	_fit_label_to_width(
		_result_secondary_label,
		_result_secondary_button.size.x * 0.92,
		int(_radius * 0.046),
		int(_radius * 0.032)
	)


## Cronometro visivel. Alem de contar, ele diz PARA ONDE o tempo leva,
## que muda com o modo e com o saldo de fichas.
func _update_result_countdown() -> void:
	if _result_timer_label == null or not is_instance_valid(_result_timer_label):
		return

	# _apply_result_theme rodava UMA vez, ao abrir o modal. No modo
	# credito com saldo zero os dois botoes nascem escondidos e o
	# jogador que colocasse a ficha ali continuava olhando um painel sem
	# botao nenhum ate o cronometro levar para a abertura. Aqui o painel
	# volta a se montar assim que o saldo muda.
	if ArcadeSettings.credits != _result_credits_shown:
		_result_credits_shown = ArcadeSettings.credits
		_apply_result_theme()
		_result_details.text = (
			"ACERTOS %d   ERROS %d\nMAX COMBO %d\n%s\n%s"
			% [_hits, _misses, _max_combo, _result_qualification_text(), _result_action_hint()]
		)

	var remaining: int = maxi(0, int(ceil(RESULT_SECONDS - _state_time)))
	_result_timer_label.text = "ABERTURA EM %d" % remaining

	# Fica em branco no comeco e vai puxando para o vermelho no fim.
	var urgency: float = clampf(1.0 - float(remaining) / RESULT_SECONDS, 0.0, 1.0)
	_result_timer_label.add_theme_color_override(
		"font_color",
		Color.WHITE.lerp(RESULT_FAIL_COLOR, urgency * urgency)
	)


## Fim do cronometro sem escolha: volta para a abertura, nos dois modos.
func _expire_result() -> void:
	if _result_transitioning:
		return
	_result_transitioning = true
	LED_CLIENT.clear_all()
	_go_to_opening()


## Acao principal do modal: seguir jogando. No modo credito consome uma
## ficha; sem ficha nao faz nada (o cronometro leva para a abertura).
func _activate_result_action() -> void:
	if not _can_act_on_result():
		return
	# So VERIFICA a ficha; quem gasta e _confirm_difficulty na proxima
	# tela. Consumir aqui tambem cobrava duas fichas por partida: uma no
	# modal e outra ao confirmar a dificuldade.
	if not ArcadeSettings.has_credit():
		return

	_result_transitioning = true
	LED_CLIENT.clear_all()
	if _result_score_percent >= RESULT_PASS_PERCENT:
		_go_to_next_song()
	else:
		get_tree().reload_current_scene()


## Acao secundaria: escolher outra musica no seletor.
func _activate_result_change_song() -> void:
	if not _can_act_on_result():
		return
	# Tambem so verifica: a ficha e gasta ao confirmar a dificuldade da
	# musica escolhida no seletor.
	if not ArcadeSettings.has_credit():
		return

	_result_transitioning = true
	LED_CLIENT.clear_all()
	_go_to_selector()


## Toque no modal. Cada botao tem sua area; um toque em qualquer outro
## ponto vale como "continuar", que e o atalho que o jogador espera no
## modo livre. Sem ficha (modo credito) nada responde e o cronometro
## termina levando para a abertura.
## Toque no modal.
##
## Tres correcoes aqui:
##
## 1. A area do botao vinha de Rect2(global_position, size). `size` e a
##    medida LOCAL do Panel e ignora a escala do pai — e _result_panel
##    entra com scale 0.94 e pivot_offset no centro (ver
##    _reveal_result_panel). Enquanto a escala nao fechasse em 1.0 o
##    retangulo testado ficava deslocado do botao que aparece na tela.
##    get_global_rect() ja devolve o retangulo com a transformada do
##    pai aplicada.
##
## 2. A funcao terminava com um _activate_result_action() solto: QUALQUER
##    toque que errasse os retangulos disparava "continuar". Errar por
##    pouco o botao de trocar de musica nao parecia um toque perdido,
##    parecia o botao errado funcionando. Agora um toque dentro do painel
##    que nao caia em botao nenhum nao faz nada.
##
## 3. Os retangulos ganharam uma folga de meia altura de botao, que e o
##    que um dedo pede numa mesa de vidro.
func _handle_result_pointer(position_value: Vector2) -> void:
	if _result_secondary_button != null and is_instance_valid(_result_secondary_button):
		if _result_secondary_button.visible and _touch_rect(
			_result_secondary_button
		).has_point(position_value):
			_activate_result_change_song()
			return

	if _result_primary_button != null and is_instance_valid(_result_primary_button):
		if _result_primary_button.visible and _touch_rect(
			_result_primary_button
		).has_point(position_value):
			_activate_result_action()
			return

	# Fora do painel, no modo livre, o toque continua valendo como
	# "continuar" — e o atalho que o jogador espera. Dentro do painel,
	# so botao vale.
	if _result_panel != null and is_instance_valid(_result_panel):
		if _result_panel.get_global_rect().has_point(position_value):
			return
	if not ArcadeSettings.is_credit_mode():
		_activate_result_action()


## Retangulo de toque de um Control, ja com a transformada do pai e uma
## folga vertical para o dedo.
func _touch_rect(control: Control) -> Rect2:
	var rect: Rect2 = control.get_global_rect()
	var padding: float = rect.size.y * 0.25
	return Rect2(
		rect.position - Vector2(0.0, padding),
		rect.size + Vector2(0.0, padding * 2.0)
	)


func _can_act_on_result() -> bool:
	if _state != GameState.RESULT or _result_transitioning or _record_celebration_active:
		return false
	# Descarta o toque/START residual do ultimo hit. Sem esta trava o modal
	# podia ser criado e a cena recarregada no mesmo instante, parecendo
	# que o resultado nunca apareceu.
	return _state_time >= RESULT_INPUT_LOCK_SECONDS


func _go_to_opening() -> void:
	LED_CLIENT.clear_all()
	get_tree().change_scene_to_file("res://scenes/opening.tscn")


func _go_to_next_song() -> void:
	var songs: Array = CATALOG.all_songs()
	if songs.is_empty():
		_go_to_selector()
		return

	var current_id: String = str(_song.get("id", _song_id()))
	var current_index: int = 0
	for index in range(songs.size()):
		var value: Variant = songs[index]
		if value is Dictionary and str((value as Dictionary).get("id", "")) == current_id:
			current_index = index
			break

	var next_index: int = (current_index + 1) % songs.size()
	var next_value: Variant = songs[next_index]
	if not next_value is Dictionary:
		_go_to_selector()
		return
	var next_song: Dictionary = next_value as Dictionary
	var scene_path: String = str(next_song.get("scene", ""))
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		_go_to_selector()
		return

	get_tree().set_meta("hit_music_song_id", str(next_song.get("id", "")))
	get_tree().set_meta("hit_music_selector_index", next_index)
	get_tree().set_meta("hit_music_difficulty", _difficulty_name)
	get_tree().change_scene_to_file(scene_path)


func _update_hud() -> void:
	if _label_score == null:
		return

	var score: float = _score_percent()
	_label_score.text = "%.2f%%" % score
	_label_combo.text = "COMBO %d" % _combo
	_label_performance.text = "LIFE %d%%" % int(round(_performance))
	_label_performance.add_theme_color_override(
		"font_color",
		_primary_color() if _performance > 78.0 else Color(1.0, 0.15, 0.18, 1.0)
	)

	var current_seconds: int = int(round(_song_time))
	var total_seconds: int = int(round(_song_duration))
	_label_time.text = "%d:%02d / %d:%02d" % [
		int(current_seconds / 60),
		current_seconds % 60,
		int(total_seconds / 60),
		total_seconds % 60,
	]
	_progress_bar.value = clampf(_song_time / maxf(_song_duration, 0.001), 0.0, 1.0)


func _score_percent() -> float:
	if _judgement_count <= 0:
		return 100.0
	return 100.0 * _score_quality_sum / float(_judgement_count)


func _save_record(score: float) -> void:
	var data: Dictionary = {}
	if FileAccess.file_exists(RECORD_PATH):
		var read_file := FileAccess.open(RECORD_PATH, FileAccess.READ)
		if read_file != null:
			var parsed: Variant = JSON.parse_string(read_file.get_as_text())
			if parsed is Dictionary:
				data = parsed as Dictionary

	var song_id: String = str(_song.get("id", _song_id()))
	var current_value: Variant = data.get(song_id, {})
	var song_record: Dictionary = {}
	if current_value is Dictionary:
		song_record = current_value as Dictionary
	var key: String = "dificil" if _difficulty_name == "hard" else "facil"
	song_record[key] = maxf(float(song_record.get(key, 0.0)), score)
	data[song_id] = song_record

	var write_file := FileAccess.open(RECORD_PATH, FileAccess.WRITE)
	if write_file != null:
		write_file.store_string(JSON.stringify(data, "\t"))


func _read_best_score() -> float:
	if not FileAccess.file_exists(RECORD_PATH):
		return 0.0
	var read_file := FileAccess.open(RECORD_PATH, FileAccess.READ)
	if read_file == null:
		return 0.0
	var parsed: Variant = JSON.parse_string(read_file.get_as_text())
	if not parsed is Dictionary:
		return 0.0
	var song_value: Variant = (parsed as Dictionary).get(
		str(_song.get("id", _song_id())),
		{}
	)
	if not song_value is Dictionary:
		return 0.0
	var key: String = "dificil" if _difficulty_name == "hard" else "facil"
	return float((song_value as Dictionary).get(key, 0.0))


func _go_to_selector() -> void:
	LED_CLIENT.clear_all()
	get_tree().change_scene_to_file("res://scenes/change_scenes.tscn")


func _on_viewport_size_changed() -> void:
	_calculate_geometry()
	if _video_player != null:
		_video_player.position = _video_rect.position
		_video_player.size = _video_rect.size
	if _countdown_label != null and _top_panel != null:
		_countdown_label.position = _top_panel.position
		_countdown_label.size = _top_panel.size
	_reposition_record_badge()
	if _cover != null:
		_cover.position = _center - Vector2(_radius * 0.72, _radius * 0.58)
		_cover.size = Vector2(_radius * 1.44, _radius * 1.16)
	if _renderer != null:
		_renderer.configure(_center, _radius, _lane_positions, _song, _difficulty)
	queue_redraw()


func _nearest_lane(position_value: Vector2) -> int:
	var best_lane: int = -1
	var best_distance: float = INF
	for lane in range(_lane_positions.size()):
		var distance_value: float = _lane_positions[lane].distance_to(position_value)
		if distance_value < best_distance:
			best_distance = distance_value
			best_lane = lane
	return best_lane if best_distance <= _radius * POINTER_LANE_RADIUS_RATIO else -1


func _state_name() -> String:
	match _state:
		GameState.COUNTDOWN:
			return "countdown"
		GameState.PLAYING:
			return "playing"
		GameState.RESULT:
			return "result"
		_:
			return "presentation"


func _action_pressed(action: String) -> bool:
	return InputMap.has_action(action) and Input.is_action_just_pressed(action)


func _primary_color() -> Color:
	var value: Variant = _song.get("colors", {})
	if value is Dictionary:
		return TAP_PALETTE.vivid_theme(
			(value as Dictionary).get("primary", TAP_PALETTE.TAP_CYAN)
		)
	return TAP_PALETTE.TAP_CYAN


func _secondary_color() -> Color:
	var value: Variant = _song.get("colors", {})
	if value is Dictionary:
		return TAP_PALETTE.vivid_theme(
			(value as Dictionary).get("secondary", Color.WHITE)
		)
	return Color.WHITE


func _accent_color() -> Color:
	var value: Variant = _song.get("colors", {})
	if value is Dictionary:
		return TAP_PALETTE.vivid_theme(
			(value as Dictionary).get("accent", TAP_PALETTE.TAP_YELLOW)
		)
	return TAP_PALETTE.TAP_YELLOW


func _dark_color() -> Color:
	var value: Variant = _song.get("colors", {})
	if value is Dictionary:
		return (value as Dictionary).get("dark", Color(0.01, 0.02, 0.05, 1.0))
	return Color(0.01, 0.02, 0.05, 1.0)


## Mesmo mapeamento de tap_visual.gd._frame_color(): o LED fisico da
## lane precisa acender exatamente na cor que o tazo mostra quando
## chega no lugar, nao numa cor de tema independente da musica (era
## isso que ficava dessincronizado antes).
func _tap_color(index: int) -> Color:
	return TAP_PALETTE.color_for_index(index)


func _load_font() -> Font:
	var path: String = "res://fonts/Bungee-Regular.ttf"
	if ResourceLoader.exists(path):
		var resource: Resource = load(path)
		if resource is Font:
			return resource as Font
	return ThemeDB.fallback_font


func _make_label(
	text_value: String,
	font_size: int,
	alignment: HorizontalAlignment,
	font: Font
) -> Label:
	var label := Label.new()
	label.text = text_value
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", maxi(12, font_size))
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.95))
	label.add_theme_constant_override("outline_size", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _fit_label_to_width(
	label: Label,
	max_width: float,
	base_font_size: int,
	min_font_size: int
) -> void:
	var font: Font = label.get_theme_font("font")
	if font == null:
		return
	var size_value: int = maxi(base_font_size, min_font_size)
	while size_value > min_font_size:
		var measured: float = font.get_string_size(
			label.text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			size_value
		).x
		if measured <= max_width:
			break
		size_value -= 1
	label.add_theme_font_size_override("font_size", size_value)


func _top_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.005, 0.010, 0.024, 0.40)
	style.border_color = Color(
		_primary_color().r,
		_primary_color().g,
		_primary_color().b,
		0.72
	)
	style.set_border_width_all(3)
	style.set_corner_radius_all(26)
	style.shadow_color = Color(
		_primary_color().r,
		_primary_color().g,
		_primary_color().b,
		0.18
	)
	style.shadow_size = 16
	return style


func _progress_background_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 1.0, 1.0, 0.10)
	style.set_corner_radius_all(8)
	return style


func _progress_fill_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = _primary_color()
	style.set_corner_radius_all(8)
	style.shadow_color = Color(
		_primary_color().r,
		_primary_color().g,
		_primary_color().b,
		0.36
	)
	style.shadow_size = 6
	return style


## O modal tem paleta propria (RESULT_BASE_COLOR) e o acento muda com o
## resultado: verde quando classifica, vermelho quando nao. Antes ele
## herdava a cor da musica, entao no carmine (vermelho) o painel de
## "nao classificado" se confundia com o proprio cenario.
func _result_panel_style() -> StyleBoxFlat:
	var accent: Color = _result_accent_color()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(RESULT_BASE_COLOR.r, RESULT_BASE_COLOR.g, RESULT_BASE_COLOR.b, 0.97)
	style.border_color = accent
	style.set_border_width_all(4)
	style.set_corner_radius_all(22)
	style.shadow_color = Color(accent.r, accent.g, accent.b, 0.34)
	style.shadow_size = 20
	return style


func _result_accent_color() -> Color:
	return (
		RESULT_PASS_COLOR
		if _result_score_percent >= RESULT_PASS_PERCENT
		else RESULT_FAIL_COLOR
	)


func _result_button_style(highlighted: bool) -> StyleBoxFlat:
	var accent: Color = _result_accent_color()
	var style := StyleBoxFlat.new()
	style.bg_color = (
		Color(accent.r, accent.g, accent.b, 0.20)
		if highlighted
		else Color(1.0, 1.0, 1.0, 0.06)
	)
	style.border_color = (
		Color(accent.r, accent.g, accent.b, 0.90)
		if highlighted
		else Color(1.0, 1.0, 1.0, 0.24)
	)
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	return style
