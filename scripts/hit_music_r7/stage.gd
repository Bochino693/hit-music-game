extends Node2D

const CATALOG: Script = preload("res://scripts/hit_music_r7/catalog.gd")
const CHART_FACTORY: Script = preload("res://scripts/hit_music_r7/chart_factory.gd")
const PATH_BUILDER: Script = preload("res://scripts/hit_music_r7/path_builder.gd")
const TAP_VISUAL_SCRIPT: Script = preload("res://scripts/hit_music_r7/tap_visual.gd")
const RENDERER_SCRIPT: Script = preload("res://scripts/hit_music_r7/playfield_renderer.gd")
const LED_CLIENT: Script = preload("res://scripts/hit_music_r7/led_client.gd")

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

const SLIDE_CORRIDOR_TOLERANCE_RATIO: float = 0.115
const SLIDE_SAMPLE_STEP_RATIO: float = 0.045
const SLIDE_MAX_FORWARD_SPAN: float = 0.16

const TOP_MARGIN_RATIO: float = 0.022
const TOP_HEIGHT_RATIO: float = 0.205
const TOP_GAP_RATIO: float = 0.024
const SIDE_MARGIN_RATIO: float = 0.015
const BOTTOM_MARGIN_RATIO: float = 0.012
const CIRCLE_SCALE: float = 0.985
const PRESENTATION_SECONDS: float = 2.70
const COUNTDOWN_SECONDS: float = 3.0
const RESULT_SECONDS: float = 12.0
const RESULT_PASS_PERCENT: float = 70.0
const RESULT_INPUT_LOCK_SECONDS: float = 0.90
const RECORD_PATH: String = "user://hit_music_records.json"
const GAME_OVER_STING_PATH: String = "res://songs/game_over.mp3"

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

# Mesmo amarelo usado na fita do hold (playfield_renderer._draw_hold)
# e no LED fisico (HOLD_COLOR em stage_final.gd) — o hold e sempre
# essa cor, nunca a cor de destaque da musica.
const HOLD_VISUAL_COLOR: Color = Color(1.0, 0.83, 0.08, 1.0)

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
var _song_audio_started: bool = false
var _song_finish_requested: bool = false

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
var _progress_bar: ProgressBar
var _countdown_label: Label
var _result_panel: Panel
var _result_title: Label
var _result_score: Label
var _result_details: Label

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


func _song_id() -> String:
	return "carmine"


func _ready() -> void:
	Engine.max_fps = 60
	# Entrega eventos de controle imediatamente. O polling abaixo continua
	# como rede de seguranca para bridges que atualizam o estado entre frames.
	Input.use_accumulated_input = false
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
			if _state_time >= COUNTDOWN_SECONDS:
				_start_playing()
		GameState.PLAYING:
			_update_song_time()
			_spawn_due_events()
			_update_tap_visuals()
			_update_notes_and_misses()
			_update_hud()
			_update_dynamic_volume(delta)
			if _song_time >= _song_duration - 0.02:
				_request_song_finish()
		GameState.RESULT:
			if _state_time >= RESULT_SECONDS:
				_go_to_selector()

	_renderer.set_runtime(
		_events,
		_song_time,
		_state_name(),
		_pointer_position,
		_pointer_active
	)
	queue_redraw()


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
		240,
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
	_top_panel.add_child(_label_title)

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

	_label_score = _make_label("100.00%", int(height * 0.29), HORIZONTAL_ALIGNMENT_RIGHT, font)
	_label_score.position = Vector2(right_x, height * 0.06)
	_label_score.size = Vector2(_top_panel.size.x - right_x - inner_margin, height * 0.38)
	_label_score.add_theme_color_override("font_color", _secondary_color())
	_top_panel.add_child(_label_score)

	_label_combo = _make_label("COMBO 0", int(height * 0.14), HORIZONTAL_ALIGNMENT_RIGHT, font)
	_label_combo.position = Vector2(right_x, height * 0.46)
	_label_combo.size = Vector2(_top_panel.size.x - right_x - inner_margin, height * 0.18)
	_top_panel.add_child(_label_combo)

	_label_performance = _make_label("LIFE 100%", int(height * 0.13), HORIZONTAL_ALIGNMENT_RIGHT, font)
	_label_performance.position = Vector2(right_x, height * 0.67)
	_label_performance.size = Vector2(_top_panel.size.x - right_x - inner_margin, height * 0.18)
	_label_performance.add_theme_color_override("font_color", _primary_color())
	_top_panel.add_child(_label_performance)

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

	# Painel maior e com mais espaco reservado pros detalhes/ranking:
	# antes o texto (nome, hits/misses, cabecalho + linhas do ranking)
	# nao cabia na area reservada e vazava pra fora do painel.
	_result_panel = Panel.new()
	_result_panel.position = _center - Vector2(_radius * 0.62, _radius * 0.56)
	_result_panel.size = Vector2(_radius * 1.24, _radius * 1.12)
	_result_panel.visible = false
	_result_panel.z_index = 240
	_result_panel.add_theme_stylebox_override("panel", _result_panel_style())
	_hud_layer.add_child(_result_panel)

	_result_title = _make_label("TRACK CLEAR", int(_radius * 0.085), HORIZONTAL_ALIGNMENT_CENTER, font)
	_result_title.position = Vector2(_radius * 0.05, _radius * 0.05)
	_result_title.size = Vector2(_result_panel.size.x - _radius * 0.10, _radius * 0.14)
	_result_panel.add_child(_result_title)

	_result_score = _make_label("100.00%", int(_radius * 0.12), HORIZONTAL_ALIGNMENT_CENTER, font)
	_result_score.position = Vector2(_radius * 0.05, _radius * 0.22)
	_result_score.size = Vector2(_result_panel.size.x - _radius * 0.10, _radius * 0.18)
	_result_score.add_theme_color_override("font_color", _accent_color())
	_result_panel.add_child(_result_score)

	_result_details = _make_label("", int(_radius * 0.028), HORIZONTAL_ALIGNMENT_CENTER, font)
	_result_details.position = Vector2(_radius * 0.06, _radius * 0.42)
	_result_details.size = Vector2(_result_panel.size.x - _radius * 0.12, _radius * 0.60)
	_result_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_details.clip_text = true
	_result_panel.add_child(_result_details)


func _load_assets() -> void:
	var audio_path: String = str(_song.get("audio", ""))
	if ResourceLoader.exists(audio_path):
		var audio_resource: Resource = load(audio_path)
		if audio_resource is AudioStream:
			# A faixa do gameplay precisa terminar de verdade. Se o recurso MP3
			# vier importado com loop, o sinal finished nunca sera emitido.
			if audio_resource is AudioStreamMP3:
				(audio_resource as AudioStreamMP3).loop = false
			_music_player.stream = audio_resource as AudioStream
			_music_player.volume_db = -1.0
			_song_duration = maxf((_music_player.stream as AudioStream).get_length(), 10.0)
	else:
		push_error("Audio not found: " + audio_path)

	var video_path: String = str(_song.get("video", ""))
	if ResourceLoader.exists(video_path):
		var video_resource: Resource = load(video_path)
		if video_resource is VideoStream:
			_video_player.stream = video_resource as VideoStream
			# O MP3 e a fonte sincronizada. O video so fornece audio como fallback.
			_video_player.volume_db = -80.0 if _music_player.stream != null else -1.0
		else:
			push_warning("Arquivo nao e VideoStream: " + video_path)
	else:
		push_warning("Video nao encontrado: " + video_path)

	var cover_path: String = str(_song.get("cover", ""))
	if ResourceLoader.exists(cover_path):
		var cover_resource: Resource = load(cover_path)
		if cover_resource is Texture2D:
			_cover.texture = cover_resource as Texture2D
	else:
		_cover.visible = false


func _prepare_chart() -> void:
	_events = CHART_FACTORY.build(_song, _difficulty_name, _song_duration)
	for event_value in _events:
		if not event_value is Dictionary:
			continue
		var event: Dictionary = event_value as Dictionary
		event["_spawned"] = false
		event["_resolved"] = false
		event["_active"] = false
		event["_holding"] = false
		event["_visual_progress"] = 0.0
		if str(event.get("type", "")) == "slide":
			var path_points: PackedVector2Array = PATH_BUILDER.build(
				event,
				_center,
				_radius,
				_lane_positions
			)
			event["_path_points"] = path_points
			event["_path_lengths"] = PATH_BUILDER.build_lengths(path_points)
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


func _start_playing() -> void:
	_state = GameState.PLAYING
	_state_time = 0.0
	_countdown_label.visible = false
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


func _spawn_due_events() -> void:
	var approach: float = float(_difficulty.get("approach", 1.0))
	for event_value in _events:
		if not event_value is Dictionary:
			continue
		var event: Dictionary = event_value as Dictionary
		if bool(event.get("_spawned", false)):
			continue
		var hit_time: float = float(event.get("time", 0.0))
		if _song_time < hit_time - approach:
			continue

		event["_spawned"] = true
		var type_name: String = str(event.get("type", "tap"))
		if type_name == "tap":
			_spawn_tap_visual(event, approach)
		elif type_name == "hold":
			var lane: int = int(event.get("lane", 0))
			LED_CLIENT.set_lane(lane, _accent_color())
		elif type_name == "slide":
			pass


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


func _update_tap_visuals() -> void:
	for event_value in _events:
		if not event_value is Dictionary:
			continue
		var event: Dictionary = event_value as Dictionary
		if str(event.get("type", "")) != "tap":
			continue
		if bool(event.get("_resolved", false)):
			continue
		var node_value: Variant = event.get("_node", null)
		if node_value is Node2D and is_instance_valid(node_value):
			node_value.update_visual(_song_time)


func _update_notes_and_misses() -> void:
	var hit_window: float = float(_difficulty.get("hit_window", 0.20))
	for event_value in _events:
		if not event_value is Dictionary:
			continue
		var event: Dictionary = event_value as Dictionary
		if bool(event.get("_resolved", false)):
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
			if not bool(event.get("_active", false)) and _song_time > hit_time + hit_window:
				_resolve_miss(event)
			elif _song_time > end_time + 0.28:
				_resolve_miss(event)


func _process_physical_inputs() -> void:
	if _state == GameState.RESULT:
		if not ArcadeSettings.is_credit_mode():
			if _action_pressed("input_start") or _action_pressed("ui_accept"):
				_activate_result_action()
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
		if not ArcadeSettings.is_credit_mode():
			if event is InputEventScreenTouch and event.pressed:
				_activate_result_action()
			elif event is InputEventMouseButton and event.pressed:
				_activate_result_action()
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
	for event_value in _events:
		if not event_value is Dictionary:
			continue
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
		if progress >= 0.965:
			var end_position: Vector2 = PATH_BUILDER.point_at(points, 1.0)
			_renderer.add_effect("slide", end_position, _primary_color())
			_resolve_hit(event, "slide", 1.0)


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
	for event_value in _events:
		if not event_value is Dictionary:
			continue
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
			if float(event.get("_visual_progress", 0.0)) < 0.90:
				_resolve_miss(event)


func _handle_lane_press(
	lane: int,
	source: String,
	has_pointer: bool = false,
	press_position: Vector2 = Vector2.ZERO
) -> void:
	if _try_tap(lane):
		return
	if _try_hold(lane, source):
		return
	_try_slide(lane, source, has_pointer, press_position)


func _handle_lane_release(_lane: int, source: String) -> void:
	for event_value in _events:
		if not event_value is Dictionary:
			continue
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


func _try_tap(lane: int) -> bool:
	var hit_window: float = float(_difficulty.get("hit_window", 0.20))
	var perfect_window: float = float(_difficulty.get("perfect_window", 0.075))
	var best: Dictionary = {}
	var best_difference: float = INF

	for event_value in _events:
		if not event_value is Dictionary:
			continue
		var event: Dictionary = event_value as Dictionary
		if bool(event.get("_resolved", false)):
			continue
		if str(event.get("type", "")) != "tap":
			continue
		if int(event.get("lane", -1)) != lane:
			continue

		var difference: float = absf(_song_time - float(event.get("time", 0.0)))
		if difference <= hit_window and difference < best_difference:
			best = event
			best_difference = difference

	if best.is_empty():
		return false

	var quality: float = 1.0 if best_difference <= perfect_window else 0.72
	_resolve_hit(best, "tap", quality)
	return true


func _try_hold(lane: int, source: String) -> bool:
	var hit_window: float = float(_difficulty.get("hit_window", 0.20))
	var best: Dictionary = {}
	var best_difference: float = INF

	for event_value in _events:
		if not event_value is Dictionary:
			continue
		var event: Dictionary = event_value as Dictionary
		if bool(event.get("_resolved", false)):
			continue
		if str(event.get("type", "")) != "hold":
			continue
		if int(event.get("lane", -1)) != lane:
			continue

		var difference: float = absf(_song_time - float(event.get("time", 0.0)))
		if difference <= hit_window and difference < best_difference:
			best = event
			best_difference = difference

	if best.is_empty():
		return false

	best["_holding"] = true
	best["_source"] = source
	return true


func _try_slide(
	lane: int,
	source: String,
	has_pointer: bool = false,
	press_position: Vector2 = Vector2.ZERO
) -> bool:
	var hit_window: float = float(_difficulty.get("hit_window", 0.20))
	var best: Dictionary = {}
	var best_difference: float = INF

	for event_value in _events:
		if not event_value is Dictionary:
			continue
		var event: Dictionary = event_value as Dictionary
		if bool(event.get("_resolved", false)):
			continue
		if str(event.get("type", "")) != "slide":
			continue
		if bool(event.get("_active", false)):
			continue

		var path_value: Variant = event.get("path", [])
		if not path_value is Array or (path_value as Array).is_empty():
			continue
		if int((path_value as Array)[0]) != lane:
			continue

		var difference: float = absf(_song_time - float(event.get("time", 0.0)))
		if difference <= hit_window and difference < best_difference:
			best = event
			best_difference = difference

	if best.is_empty():
		return false

	best["_active"] = true
	best["_source"] = source
	best["_visual_progress"] = 0.0

	# Ancora o inicio do corredor na posicao real do toque/clique
	# quando existir (touch/mouse); em input fisico (botao) usa o
	# proprio inicio do trajeto, ja que nao ha ponteiro na tela.
	var start_point: Vector2 = _center
	var points_value: Variant = best.get("_path_points", PackedVector2Array())
	if points_value is PackedVector2Array and (points_value as PackedVector2Array).size() > 0:
		start_point = (points_value as PackedVector2Array)[0]
	best["_last_pointer"] = press_position if has_pointer else start_point

	return true


func _resolve_hit(event: Dictionary, kind: String, quality: float) -> void:
	if bool(event.get("_resolved", false)):
		return
	event["_resolved"] = true
	event["_active"] = false
	event["_holding"] = false

	var position_value: Vector2 = _event_end_position(event)
	var effect_kind: String = "tap"
	if kind == "slide":
		effect_kind = "slide"
	elif kind == "hold":
		effect_kind = "hold"
	_renderer.add_effect(effect_kind, position_value, _event_color(event))
	_renderer.flash_ring_at(
		position_value,
		_judgement_color(kind, quality),
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
	_renderer.register_hit(quality, _combo)
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


## Cor do flash que acende na linha de encaixe para cada tipo de
## julgamento — antes a linha era sempre branca, sem diferenciar
## PERFECT de GOOD nem de HOLD/SLIDE.
func _judgement_color(kind: String, quality: float) -> Color:
	if kind == "hold":
		return _accent_color()
	if kind == "slide":
		return _primary_color()
	# tap: PERFECT fica branco-gelo (nitido), GOOD fica na cor de destaque.
	if quality >= 0.99:
		return _secondary_color().lerp(_primary_color(), 0.30)
	return _accent_color()


func _event_color(event: Dictionary) -> Color:
	var type_name: String = str(event.get("type", "tap"))
	if type_name == "hold":
		# Hold e sempre amarelo — mesma cor da fita/capsula desenhada
		# (_draw_capsule) e do LED fisico (HOLD_COLOR em stage_final.gd).
		return HOLD_VISUAL_COLOR
	if type_name == "slide":
		return _primary_color()
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
	_result_score_percent = score
	_result_title.text = "PRÓXIMA MÚSICA" if score >= RESULT_PASS_PERCENT else "TENTE NOVAMENTE"
	_result_score.text = "%.2f%%" % score
	_result_details.text = (
		"HITS %d   MISSES %d\nMAX COMBO %d\n%s"
		% [_hits, _misses, _max_combo, _result_action_hint()]
	)
	_save_record(score)
	LED_CLIENT.clear_all()

	_play_game_over_sting()
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


func _result_action_hint() -> String:
	if ArcadeSettings.is_credit_mode():
		return "RETORNO AO MENU EM 12 SEGUNDOS"
	if _result_score_percent >= RESULT_PASS_PERCENT:
		return "START OU TOQUE: PRÓXIMA MÚSICA\nMENU AUTOMÁTICO EM 12 SEGUNDOS"
	return "START OU TOQUE: TENTAR NOVAMENTE\nMENU AUTOMÁTICO EM 12 SEGUNDOS"


func _activate_result_action() -> void:
	if _state != GameState.RESULT or _result_transitioning:
		return
	# Descarta o toque/START residual do ultimo hit. Sem esta trava o modal
	# podia ser criado e a cena recarregada no mesmo instante, parecendo
	# que o resultado nunca apareceu.
	if _state_time < RESULT_INPUT_LOCK_SECONDS:
		return
	if ArcadeSettings.is_credit_mode():
		return
	_result_transitioning = true
	LED_CLIENT.clear_all()
	if _result_score_percent >= RESULT_PASS_PERCENT:
		_go_to_next_song()
	else:
		get_tree().reload_current_scene()


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
	return best_lane if best_distance <= _radius * 0.155 else -1


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
		return (value as Dictionary).get("primary", Color(0.05, 0.92, 1.0, 1.0))
	return Color(0.05, 0.92, 1.0, 1.0)


func _secondary_color() -> Color:
	var value: Variant = _song.get("colors", {})
	if value is Dictionary:
		return (value as Dictionary).get("secondary", Color.WHITE)
	return Color.WHITE


func _accent_color() -> Color:
	var value: Variant = _song.get("colors", {})
	if value is Dictionary:
		return (value as Dictionary).get("accent", Color(1.0, 0.84, 0.05, 1.0))
	return Color(1.0, 0.84, 0.05, 1.0)


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
	match index % 3:
		1:
			return Color(1.0, 0.84, 0.08, 1.0)
		2:
			return Color(1.0, 0.14, 0.45, 1.0)
		_:
			return Color(0.08, 0.92, 1.0, 1.0)


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


func _result_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.006, 0.010, 0.022, 0.96)
	style.border_color = _primary_color()
	style.set_border_width_all(4)
	style.set_corner_radius_all(22)
	style.shadow_color = Color(
		_primary_color().r,
		_primary_color().g,
		_primary_color().b,
		0.28
	)
	style.shadow_size = 16
	return style
