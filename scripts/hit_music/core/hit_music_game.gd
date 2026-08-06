class_name HitMusicGame
extends Node2D

@export var musica: HitMusicSongConfig

@export_enum("FACIL", "DIFICIL")
var dificuldade_teste: String = "FACIL"

@onready var ring_renderer: HitMusicLaneRingRenderer = $Playfield/RingRenderer
@onready var background_renderer: HitMusicBackgroundThemeRenderer = $Background/ThemeRenderer
@onready var note_manager: HitMusicNoteManager = $Playfield/Notes
@onready var effects: HitMusicHitEffectManager = $Playfield/Effects
@onready var song_clock: HitMusicSongClock = $Managers/SongClock
@onready var chart_player: HitMusicChartPlayer = $Managers/ChartPlayer
@onready var judgement: HitMusicJudgementSystem = $Managers/JudgementSystem
@onready var input_router: HitMusicInputRouter = $Managers/InputRouter
@onready var music_player: AudioStreamPlayer = $Audio/MusicPlayer
@onready var video_player: VideoStreamPlayer = $Background/VideoBackground

var difficulty: HitMusicDifficultyConfig
var layout: Dictionary = {}

func _ready() -> void:
	if musica == null:
		push_error("A scene HitMusicGame esta sem o Resource de musica.")
		return

	difficulty = musica.dificil if dificuldade_teste == "DIFICIL" else musica.facil
	if difficulty == null:
		push_error("A musica nao possui configuracao para " + dificuldade_teste)
		return

	layout = HitMusicPlayfieldLayout.calculate(get_viewport_rect().size)
	ring_renderer.configure(layout)
	background_renderer.configure(layout, musica, difficulty)
	note_manager.configure(layout, musica, difficulty)
	effects.configure(float(layout.get("radius", 100.0)))
	judgement.configure(difficulty)

	chart_player.event_ready.connect(note_manager.spawn_event)
	input_router.lane_pressed.connect(_on_lane_pressed)
	judgement.tap_judged.connect(note_manager.resolve_tap)
	note_manager.tap_hit.connect(effects.spawn_tap_hit)

	_configure_audio_and_video()
	if not chart_player.load_chart(difficulty.chart_path):
		return

	song_clock.configure(music_player)
	song_clock.start()

func _process(_delta: float) -> void:
	if difficulty == null:
		return
	var song_time: float = song_clock.get_time()
	chart_player.update_chart(song_time)
	note_manager.update_notes(song_time)
	background_renderer.set_song_time(song_time)

func _configure_audio_and_video() -> void:
	if ResourceLoader.exists(musica.musica_path):
		music_player.stream = load(musica.musica_path)
	else:
		push_error("Musica nao encontrada: " + musica.musica_path)

	if not musica.video_fundo_path.is_empty() and ResourceLoader.exists(musica.video_fundo_path):
		video_player.stream = load(musica.video_fundo_path)
		video_player.loop = true
		video_player.play()

func _on_lane_pressed(lane: int) -> void:
	judgement.judge_lane(lane, song_clock.get_time(), note_manager.active_taps)