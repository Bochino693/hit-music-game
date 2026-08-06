param(
    [string]$ProjectRoot = (Get-Location).Path
)

$ErrorActionPreference = "Stop"
$Version = "R8_REFERENCE_PRECISION_20260806"

function Project-Path {
    param([Parameter(Mandatory = $true)][string]$RelativePath)
    return Join-Path $ProjectRoot $RelativePath
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $Parent = Split-Path -Parent $Path
    if ($Parent -and -not (Test-Path -LiteralPath $Parent)) {
        New-Item -ItemType Directory -Path $Parent -Force | Out-Null
    }

    $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $Utf8NoBom)
}

function Require-File {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $FullPath = Project-Path $RelativePath
    if (-not (Test-Path -LiteralPath $FullPath)) {
        throw "Arquivo obrigatorio nao encontrado: $RelativePath"
    }
}

function Backup-File {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$BackupRoot
    )

    $Source = Project-Path $RelativePath
    if (-not (Test-Path -LiteralPath $Source)) {
        return
    }

    $Destination = Join-Path $BackupRoot $RelativePath
    $DestinationParent = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Path $DestinationParent -Force | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

function Test-LfsPointer {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    $Item = Get-Item -LiteralPath $Path
    if ($Item.Length -gt 1024) {
        return $false
    }

    $FirstLine = Get-Content -LiteralPath $Path -TotalCount 1 -ErrorAction SilentlyContinue
    return $FirstLine -like "version https://git-lfs.github.com/spec/v1*"
}

function Validate-CatalogAssets {
    $CatalogPath = Project-Path "data\hit_music_songs.json"
    $Catalog = Get-Content -LiteralPath $CatalogPath -Raw | ConvertFrom-Json

    Write-Host ""
    Write-Host "VALIDACAO DOS ASSETS:" -ForegroundColor Cyan

    foreach ($Song in $Catalog.songs) {
        $SongName = [string]$Song.title

        foreach ($PropertyName in @("audio", "video", "cover", "scene")) {
            $ResourcePath = [string]$Song.$PropertyName
            if ([string]::IsNullOrWhiteSpace($ResourcePath)) {
                Write-Warning "$SongName - $PropertyName vazio."
                continue
            }

            $RelativePath = $ResourcePath.Replace("res://", "").Replace("/", [IO.Path]::DirectorySeparatorChar)
            $FullPath = Project-Path $RelativePath

            if (Test-Path -LiteralPath $FullPath) {
                $SizeMb = [math]::Round((Get-Item -LiteralPath $FullPath).Length / 1MB, 2)
                Write-Host "[OK] $SongName - $PropertyName - $ResourcePath ($SizeMb MB)" -ForegroundColor Green
            }
            else {
                Write-Warning "$SongName - arquivo nao encontrado: $ResourcePath"
            }
        }
    }
}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " HIT MUSIC R8 - REFERENCE PRECISION" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Versao: $Version" -ForegroundColor DarkGray
Write-Host "Projeto: $ProjectRoot"
Write-Host ""

Require-File "project.godot"
Require-File "data\hit_music_songs.json"
Require-File "scripts\hit_music_r7\stage.gd"
Require-File "scripts\hit_music_r7\selector.gd"
Require-File "scripts\hit_music_r7\playfield_renderer.gd"
Require-File "scripts\hit_music_r7\tap_visual.gd"
Require-File "scripts\hit_music_r7\catalog.gd"
Require-File "scripts\hit_music_r7\chart_factory.gd"
Require-File "scripts\hit_music_r7\path_builder.gd"
Require-File "entities\tazo.tscn"

$GitAvailable = $null -ne (Get-Command git -ErrorAction SilentlyContinue)
$GitRepository = Test-Path -LiteralPath (Project-Path ".git")

if ($GitAvailable -and $GitRepository) {
    $PointersFound = $false

    Get-ChildItem -LiteralPath (Project-Path "medias") -File -Filter "*.ogv" -ErrorAction SilentlyContinue |
        ForEach-Object {
            if (Test-LfsPointer $_.FullName) {
                $PointersFound = $true
                Write-Warning "Ponteiro Git LFS detectado: $($_.FullName)"
            }
        }

    if ($PointersFound) {
        Write-Host "Baixando os videos reais pelo Git LFS..." -ForegroundColor Yellow
        git lfs pull
    }
}

Validate-CatalogAssets

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupRoot = Project-Path "_backup_hit_music_r8_$Stamp"
New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null

$FilesToBackup = @(
    "scripts\hit_music_r7\stage.gd",
    "scripts\hit_music_r7\selector.gd",
    "scripts\hit_music_r7\playfield_renderer.gd",
    "scripts\change_scenes.gd"
)

foreach ($RelativePath in $FilesToBackup) {
    Backup-File -RelativePath $RelativePath -BackupRoot $BackupRoot
}

if ($GitAvailable -and $GitRepository) {
    $Dirty = git status --porcelain

    if ($Dirty) {
        git add -A
        git commit -m "Checkpoint before R8 reference precision"
    }

    $BackupBranch = "backup/pre-r8-$Stamp"
    git branch $BackupBranch HEAD

    $TargetBranch = "r8-reference-precision"
    $BranchExists = git branch --list $TargetBranch

    if ($BranchExists) {
        git switch $TargetBranch
    }
    else {
        git switch -c $TargetBranch
    }

    Write-Host "Branch de seguranca: $BackupBranch" -ForegroundColor DarkGray
    Write-Host "Branch de trabalho: $TargetBranch" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "Aplicando correcao estrutural e visual..." -ForegroundColor Yellow

Write-Utf8NoBom (Project-Path "scripts\hit_music_r7\stage.gd") @'
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

const TOP_MARGIN_RATIO: float = 0.022
const TOP_HEIGHT_RATIO: float = 0.205
const TOP_GAP_RATIO: float = 0.024
const SIDE_MARGIN_RATIO: float = 0.015
const BOTTOM_MARGIN_RATIO: float = 0.012
const CIRCLE_SCALE: float = 0.985
const PRESENTATION_SECONDS: float = 2.70
const COUNTDOWN_SECONDS: float = 3.0
const RESULT_SECONDS: float = 12.0
const RECORD_PATH: String = "user://hit_music_records.json"

var _song: Dictionary = {}
var _difficulty_name: String = "easy"
var _difficulty: Dictionary = {}
var _events: Array = []
var _state: int = GameState.PRESENTATION
var _state_time: float = 0.0
var _song_time: float = 0.0
var _song_duration: float = 90.0
var _failed: bool = false

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

var _touch_positions: Dictionary = {}
var _mouse_down: bool = false
var _mouse_position: Vector2 = Vector2.ZERO
var _pointer_active: bool = false
var _pointer_position: Vector2 = Vector2.ZERO


func _song_id() -> String:
	return "carmine"


func _ready() -> void:
	Engine.max_fps = 60
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

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
			if _song_time >= _song_duration - 0.02:
				_finish_game(false)
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
	add_child(_music_player)

	_video_player = VideoStreamPlayer.new()
	_video_player.name = "VideoBackground"
	_video_player.position = _video_rect.position
	_video_player.size = _video_rect.size
	_video_player.expand = true
	_video_player.loop = true
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

	_result_panel = Panel.new()
	_result_panel.position = _center - Vector2(_radius * 0.56, _radius * 0.40)
	_result_panel.size = Vector2(_radius * 1.12, _radius * 0.80)
	_result_panel.visible = false
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

	_result_details = _make_label("", int(_radius * 0.038), HORIZONTAL_ALIGNMENT_CENTER, font)
	_result_details.position = Vector2(_radius * 0.06, _radius * 0.45)
	_result_details.size = Vector2(_result_panel.size.x - _radius * 0.12, _radius * 0.25)
	_result_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_panel.add_child(_result_details)


func _load_assets() -> void:
	var audio_path: String = str(_song.get("audio", ""))
	if ResourceLoader.exists(audio_path):
		var audio_resource: Resource = load(audio_path)
		if audio_resource is AudioStream:
			_music_player.stream = audio_resource as AudioStream
			_song_duration = maxf((_music_player.stream as AudioStream).get_length(), 10.0)
	else:
		push_error("Audio not found: " + audio_path)

	var video_path: String = str(_song.get("video", ""))
	if ResourceLoader.exists(video_path):
		var video_resource: Resource = load(video_path)
		if video_resource is VideoStream:
			_video_player.stream = video_resource as VideoStream
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
			event["_path_points"] = PATH_BUILDER.build(
				event,
				_center,
				_radius,
				_lane_positions
			)


func _start_countdown() -> void:
	_state = GameState.COUNTDOWN
	_state_time = 0.0
	_cover.visible = false
	_video_player.visible = true
	if _video_player.stream != null:
		_video_player.play()
	else:
		push_warning("Video da musica nao foi carregado: " + str(_song.get("video", "")))
	if _music_player.stream != null:
		_music_player.play()
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
	if _music_player == null or not _music_player.playing:
		return
	var value: float = _music_player.get_playback_position()
	value += AudioServer.get_time_since_last_mix()
	value -= AudioServer.get_output_latency()
	_song_time = clampf(value, 0.0, _song_duration)


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
		_radius * 0.145 * float(_difficulty.get("tap_scale", 1.0)),
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
		if _action_pressed("input_start") or _action_pressed("ui_accept"):
			get_tree().reload_current_scene()
		elif _action_pressed("input_b") or _action_pressed("ui_cancel"):
			_go_to_selector()
		return

	if _state != GameState.PLAYING:
		return

	for lane in range(INPUT_ACTIONS.size()):
		var action: String = INPUT_ACTIONS[lane]
		if not InputMap.has_action(action):
			continue
		if Input.is_action_just_pressed(action):
			_handle_lane_press(lane, "lane_%d" % lane)
		if Input.is_action_just_released(action):
			_handle_lane_release(lane, "lane_%d" % lane)


func _input(event: InputEvent) -> void:
	if _state == GameState.RESULT:
		if event is InputEventScreenTouch and event.pressed:
			get_tree().reload_current_scene()
		elif event is InputEventMouseButton and event.pressed:
			get_tree().reload_current_scene()
		return

	if _state != GameState.PLAYING:
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
	_handle_lane_press(lane, source)


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
		var current_progress: float = float(event.get("_visual_progress", 0.0))
		var nearest: Dictionary = PATH_BUILDER.nearest_progress(
			points,
			position_value,
			current_progress
		)
		var distance_value: float = float(nearest.get("distance", INF))
		if distance_value <= _radius * 0.115:
			var next_progress: float = maxf(
				current_progress,
				float(nearest.get("progress", current_progress))
			)
			event["_visual_progress"] = next_progress
			if next_progress >= 0.965:
				var end_position: Vector2 = PATH_BUILDER.point_at(points, 1.0)
				_renderer.add_effect("slide", end_position, _primary_color())
				_resolve_hit(event, "slide", 1.0)


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


func _handle_lane_press(lane: int, source: String) -> void:
	if _try_tap(lane):
		return
	if _try_hold(lane, source):
		return
	_try_slide(lane, source)


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


func _try_slide(lane: int, source: String) -> bool:
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

	_remove_tap_node(event)
	_clear_event_led(event)

	_score_quality_sum += quality
	_judgement_count += 1
	_hits += 1
	_combo += 1
	_max_combo = maxi(_max_combo, _combo)
	_performance = minf(100.0, _performance + (1.15 if quality >= 0.99 else 0.55))


func _resolve_miss(event: Dictionary) -> void:
	if bool(event.get("_resolved", false)):
		return
	event["_resolved"] = true
	event["_active"] = false
	event["_holding"] = false

	var position_value: Vector2 = _event_end_position(event)
	_renderer.add_effect("miss", position_value, Color(1.0, 0.12, 0.16, 1.0))
	_remove_tap_node(event)
	_clear_event_led(event)

	_judgement_count += 1
	_misses += 1
	_combo = 0
	_performance = maxf(0.0, _performance - 6.0)
	if _performance <= 70.0:
		_finish_game(true)


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


func _event_color(event: Dictionary) -> Color:
	var type_name: String = str(event.get("type", "tap"))
	if type_name == "hold":
		return _accent_color()
	if type_name == "slide":
		return _primary_color()
	return _tap_color(int(event.get("color_index", 0)))


func _finish_game(failed: bool) -> void:
	if _state == GameState.RESULT:
		return
	_state = GameState.RESULT
	_state_time = 0.0
	_failed = failed
	_music_player.stop()
	_video_player.stop()
	_video_player.visible = false
	_countdown_label.visible = false
	_set_gameplay_hud_visible(false)
	_result_panel.visible = true

	var score: float = _score_percent()
	_result_title.text = "TRACK FAILED" if failed else "TRACK CLEAR"
	_result_score.text = "%.2f%%" % score
	_result_details.text = (
		"HITS %d   MISSES %d\nMAX COMBO %d\nSTART: REPLAY   B: MENU"
		% [_hits, _misses, _max_combo]
	)
	_save_record(score)
	LED_CLIENT.clear_all()


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
	return best_lane if best_distance <= _radius * 0.14 else -1


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


func _tap_color(index: int) -> Color:
	match index % 3:
		0:
			return _accent_color()
		1:
			return _primary_color()
		_:
			return Color(1.0, 0.18, 0.55, 1.0)


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
'@

Write-Utf8NoBom (Project-Path "scripts\hit_music_r7\playfield_renderer.gd") @'
extends Node2D

const PATH_BUILDER: Script = preload("res://scripts/hit_music_r7/path_builder.gd")

var center: Vector2 = Vector2.ZERO
var radius: float = 100.0
var lane_positions: PackedVector2Array = PackedVector2Array()
var song: Dictionary = {}
var difficulty: Dictionary = {}
var events: Array = []
var song_time: float = 0.0
var game_state: String = "presentation"
var pointer_position: Vector2 = Vector2.ZERO
var pointer_active: bool = false
var effects: Array = []

var _video_style: StyleBoxFlat
var _video_inner_style: StyleBoxFlat


func _ready() -> void:
	_video_style = StyleBoxFlat.new()
	_video_style.bg_color = Color(0.002, 0.004, 0.012, 0.78)
	_video_style.border_color = Color(1.0, 1.0, 1.0, 0.22)
	_video_style.set_border_width_all(3)
	_video_style.set_corner_radius_all(24)
	_video_style.shadow_color = Color(0.0, 0.0, 0.0, 0.70)
	_video_style.shadow_size = 14

	_video_inner_style = StyleBoxFlat.new()
	_video_inner_style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	_video_inner_style.border_color = Color(1.0, 1.0, 1.0, 0.15)
	_video_inner_style.set_border_width_all(1)
	_video_inner_style.set_corner_radius_all(19)


func configure(
	new_center: Vector2,
	new_radius: float,
	new_lanes: PackedVector2Array,
	new_song: Dictionary,
	new_difficulty: Dictionary
) -> void:
	center = new_center
	radius = new_radius
	lane_positions = new_lanes
	song = new_song
	difficulty = new_difficulty
	queue_redraw()


func set_runtime(
	new_events: Array,
	new_song_time: float,
	new_state: String,
	new_pointer_position: Vector2,
	new_pointer_active: bool
) -> void:
	events = new_events
	song_time = new_song_time
	game_state = new_state
	pointer_position = new_pointer_position
	pointer_active = new_pointer_active
	queue_redraw()


func add_effect(kind: String, position_value: Vector2, color: Color) -> void:
	var duration: float = 0.46
	if kind == "slide":
		duration = 0.64
	elif kind == "hold":
		duration = 0.56
	elif kind == "miss":
		duration = 0.48

	effects.append({
		"kind": kind,
		"position": position_value,
		"color": color,
		"start": float(Time.get_ticks_msec()) / 1000.0,
		"duration": duration,
		"rotation": fmod(position_value.x * 0.017 + position_value.y * 0.013, TAU),
	})
	queue_redraw()


func _process(_delta: float) -> void:
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	for index in range(effects.size() - 1, -1, -1):
		var effect: Dictionary = effects[index]
		if now - float(effect.get("start", now)) >= float(effect.get("duration", 0.5)):
			effects.remove_at(index)

	if not effects.is_empty() or game_state == "playing" or game_state == "selector":
		queue_redraw()


func _draw() -> void:
	if radius <= 0.0:
		return

	_draw_circle_base()
	_draw_theme_geometry()
	_draw_inner_technical_rings()
	_draw_ring()
	_draw_lane_energy()

	if game_state == "playing" or game_state == "countdown":
		for event_value in events:
			if not event_value is Dictionary:
				continue
			var event: Dictionary = event_value as Dictionary
			if bool(event.get("_resolved", false)):
				continue

			var type_name: String = str(event.get("type", "tap"))
			if type_name == "hold":
				_draw_hold(event)
			elif type_name == "slide":
				_draw_slide(event)

	_draw_effects()

	if pointer_active and game_state == "playing":
		_draw_pointer(pointer_position)


func _colors() -> Dictionary:
	var value: Variant = song.get("colors", {})
	if value is Dictionary:
		return value as Dictionary
	return {}


func _primary() -> Color:
	return _colors().get("primary", Color(0.05, 0.92, 1.0, 1.0))


func _secondary() -> Color:
	return _colors().get("secondary", Color.WHITE)


func _accent() -> Color:
	return _colors().get("accent", Color(1.0, 0.84, 0.05, 1.0))


func _dark() -> Color:
	return _colors().get("dark", Color(0.01, 0.02, 0.05, 1.0))


func _idle_time() -> float:
	if game_state == "selector" or game_state == "presentation":
		return float(Time.get_ticks_msec()) / 1000.0
	return song_time


func _beat_pulse() -> float:
	var bpm: float = maxf(float(song.get("bpm", 120.0)), 1.0)
	var beat_position: float = fmod(maxf(_idle_time(), 0.0) * bpm / 60.0, 1.0)
	return pow(maxf(0.0, 1.0 - beat_position * 5.5), 2.0)


func _draw_circle_base() -> void:
	var pulse: float = _beat_pulse()
	var base_alpha: float = 0.50 if game_state == "selector" else 1.0
	draw_circle(
		center,
		radius * 0.995,
		Color(0.002, 0.004, 0.012, base_alpha),
		true
	)
	draw_circle(
		center,
		radius * (0.86 + pulse * 0.012),
		Color(_primary().r, _primary().g, _primary().b, 0.022 + pulse * 0.018),
		true
	)


func _draw_theme_geometry() -> void:
	var configured_pattern: String = str(song.get("pattern", "diamonds")).to_lower()
	var intensity: float = clampf(float(difficulty.get("background_intensity", 0.18)), 0.04, 0.38)
	var time_value: float = _idle_time()
	var speed: float = float(difficulty.get("background_speed", 0.22))
	var rotation: float = time_value * speed
	var beat: float = _beat_pulse()
	var section: int = int(floor(time_value / 10.0)) % 4
	var pattern: String = configured_pattern

	match section:
		1:
			pattern = "radial"
		2:
			pattern = "diamonds"
		3:
			pattern = "hex" if configured_pattern != "hex" else "grid"

	var primary: Color = _primary()
	var secondary: Color = _secondary()
	var accent: Color = _accent()

	for ring in range(1, 6):
		var ring_radius: float = radius * (0.13 + float(ring) * 0.115)
		var alpha: float = intensity * (0.045 + float(ring) * 0.012) + beat * 0.018
		draw_arc(
			center,
			ring_radius,
			rotation * (0.20 if ring % 2 == 0 else -0.16),
			TAU + rotation * (0.20 if ring % 2 == 0 else -0.16),
			120,
			Color(primary.r, primary.g, primary.b, alpha),
			maxf(1.0, radius * 0.0017),
			true
		)

	match pattern:
		"hex":
			_draw_hex_field(rotation, intensity, primary, accent, section)
		"radial":
			_draw_radial_field(rotation, intensity, primary, secondary, beat)
		"grid":
			_draw_grid_field(rotation, intensity, primary, accent)
		_:
			_draw_diamond_field(rotation, intensity, primary, secondary, section)

	_draw_orbit_nodes(rotation, intensity, accent)


func _draw_diamond_field(
	rotation: float,
	intensity: float,
	primary: Color,
	secondary: Color,
	section: int
) -> void:
	for ring in range(2, 6):
		var count: int = 8 + section * 2
		var ring_radius: float = radius * (0.16 + float(ring) * 0.115)
		for index in range(count):
			var angle: float = rotation * (1.0 if ring % 2 == 0 else -0.65)
			angle += TAU * float(index) / float(count)
			var position_value: Vector2 = center + Vector2(cos(angle), sin(angle)) * ring_radius
			var size: float = radius * (0.026 + float(ring) * 0.0025)
			var color: Color = primary.lerp(secondary, float(index % 3) * 0.16)
			color.a = intensity * (0.27 + float(ring) * 0.025)
			_draw_diamond(position_value, size, color, maxf(1.0, radius * 0.0022))


func _draw_hex_field(
	rotation: float,
	intensity: float,
	primary: Color,
	accent: Color,
	section: int
) -> void:
	for ring in range(2, 6):
		var count: int = 6 + (section % 2) * 6
		var ring_radius: float = radius * (0.14 + float(ring) * 0.125)
		for index in range(count):
			var angle: float = rotation * (0.65 if ring % 2 == 0 else -0.44)
			angle += TAU * float(index) / float(count)
			var position_value: Vector2 = center + Vector2(cos(angle), sin(angle)) * ring_radius
			var color: Color = primary.lerp(accent, float(index % 4) * 0.08)
			color.a = intensity * 0.34
			_draw_regular_polygon(
				position_value,
				radius * (0.032 + float(ring) * 0.002),
				6,
				rotation * 0.30,
				color,
				maxf(1.0, radius * 0.002)
			)


func _draw_radial_field(
	rotation: float,
	intensity: float,
	primary: Color,
	secondary: Color,
	beat: float
) -> void:
	for index in range(32):
		var angle: float = rotation * 0.30 + TAU * float(index) / 32.0
		var direction := Vector2(cos(angle), sin(angle))
		var length_factor: float = 0.54 + 0.11 * absf(sin(float(index) * 0.72 + rotation))
		var color: Color = primary.lerp(secondary, float(index % 4) * 0.10)
		color.a = intensity * (0.12 + beat * 0.08)
		draw_line(
			center + direction * radius * 0.20,
			center + direction * radius * length_factor,
			color,
			maxf(1.0, radius * 0.0018),
			true
		)


func _draw_grid_field(
	rotation: float,
	intensity: float,
	primary: Color,
	accent: Color
) -> void:
	var spacing: float = radius * 0.115
	var offset: float = fmod(rotation * radius * 0.08, spacing)
	for index in range(-6, 7):
		var value: float = float(index) * spacing + offset
		draw_line(
			center + Vector2(value, -radius * 0.68),
			center + Vector2(value, radius * 0.68),
			Color(primary.r, primary.g, primary.b, intensity * 0.12),
			maxf(1.0, radius * 0.0015),
			true
		)
		draw_line(
			center + Vector2(-radius * 0.68, value),
			center + Vector2(radius * 0.68, value),
			Color(accent.r, accent.g, accent.b, intensity * 0.09),
			maxf(1.0, radius * 0.0015),
			true
		)


func _draw_orbit_nodes(rotation: float, intensity: float, color: Color) -> void:
	for index in range(12):
		var angle: float = -rotation * 0.48 + TAU * float(index) / 12.0
		var orbit_radius: float = radius * (0.28 + 0.028 * float(index % 4))
		var position_value: Vector2 = center + Vector2(cos(angle), sin(angle)) * orbit_radius
		draw_circle(
			position_value,
			maxf(1.5, radius * 0.004),
			Color(color.r, color.g, color.b, intensity * 0.30),
			true
		)


func _draw_inner_technical_rings() -> void:
	var time_value: float = _idle_time()
	var primary: Color = _primary()
	var accent: Color = _accent()

	for ring in range(3):
		var ring_radius: float = radius * (0.34 + float(ring) * 0.12)
		var start_angle: float = time_value * (0.18 + float(ring) * 0.05)
		for segment in range(8):
			var angle_a: float = start_angle + TAU * float(segment) / 8.0
			var angle_b: float = angle_a + TAU / 8.0 * 0.56
			var color: Color = primary if (segment + ring) % 2 == 0 else accent
			draw_arc(
				center,
				ring_radius,
				angle_a,
				angle_b,
				18,
				Color(color.r, color.g, color.b, 0.075),
				maxf(1.0, radius * 0.002),
				true
			)


func _draw_ring() -> void:
	var ring_radius: float = radius * 0.905
	var width: float = maxf(4.0, radius * 0.0072)
	var marker_radius: float = maxf(6.0, radius * 0.0195)
	var pulse: float = _beat_pulse()
	var primary: Color = _primary()

	draw_arc(
		center,
		ring_radius + radius * 0.004,
		0.0,
		TAU,
		320,
		Color(primary.r, primary.g, primary.b, 0.10 + pulse * 0.05),
		width * 3.4,
		true
	)
	draw_arc(
		center,
		ring_radius,
		0.0,
		TAU,
		320,
		Color.WHITE,
		width,
		true
	)

	for position_value in lane_positions:
		draw_circle(
			position_value,
			marker_radius * 1.75,
			Color(1.0, 1.0, 1.0, 0.08),
			true
		)
		draw_circle(position_value, marker_radius, Color.WHITE, true)



func _draw_lane_energy() -> void:
	if events.is_empty():
		return

	var approach: float = maxf(float(difficulty.get("approach", 1.0)), 0.001)
	for event_value in events:
		if not event_value is Dictionary:
			continue
		var event: Dictionary = event_value as Dictionary
		if bool(event.get("_resolved", false)):
			continue

		var type_name: String = str(event.get("type", "tap"))
		if type_name != "tap" and type_name != "hold":
			continue

		var lane: int = clampi(int(event.get("lane", 0)), 0, lane_positions.size() - 1)
		var hit_time: float = float(event.get("time", 0.0))
		var progress: float = clampf(
			(song_time - (hit_time - approach)) / approach,
			0.0,
			1.0
		)
		if progress <= 0.0 or progress >= 1.0:
			continue

		var position_value: Vector2 = lane_positions[lane]
		var color: Color = _accent() if type_name == "hold" else _primary()
		var size: float = radius * (0.028 + progress * 0.032)
		draw_arc(
			position_value,
			size,
			-PI * 0.5,
			-PI * 0.5 + TAU * progress,
			32,
			Color(color.r, color.g, color.b, 0.22 + progress * 0.62),
			maxf(2.0, radius * 0.006),
			true
		)


func _draw_hold(event: Dictionary) -> void:
	if not bool(event.get("_spawned", false)):
		return

	var hit_time: float = float(event.get("time", 0.0))
	var end_time: float = float(event.get("end_time", hit_time + 1.0))
	var approach: float = float(difficulty.get("approach", 1.0))
	if song_time < hit_time - approach or song_time > end_time + 0.25:
		return

	var lane: int = clampi(int(event.get("lane", 0)), 0, lane_positions.size() - 1)
	var target: Vector2 = lane_positions[lane]
	var direction: Vector2 = (target - center).normalized()
	var start_time: float = hit_time - approach
	var arrival: float = clampf((song_time - start_time) / maxf(approach, 0.001), 0.0, 1.0)
	var eased: float = 1.0 - pow(1.0 - arrival, 4.0)
	var head: Vector2 = center.lerp(target, eased)

	var hold_progress: float = 0.0
	if song_time >= hit_time:
		hold_progress = clampf(
			(song_time - hit_time) / maxf(end_time - hit_time, 0.001),
			0.0,
			1.0
		)
		head = target

	var remaining: float = 1.0 - hold_progress
	var length: float = radius * (0.52 if song_time < hit_time else maxf(0.085, 0.52 * remaining))
	var tail: Vector2 = head - direction * length
	var width: float = radius * 0.071 * float(difficulty.get("hold_width", 1.0))
	var color: Color = Color(1.0, 0.83, 0.08, 1.0)
	var holding: bool = bool(event.get("_holding", false))
	if holding:
		color = color.lerp(Color.WHITE, 0.16)

	_draw_capsule(tail, head, width, color, holding, hold_progress)


func _draw_capsule(
	tail: Vector2,
	head: Vector2,
	half_width: float,
	color: Color,
	active: bool,
	progress: float
) -> void:
	var direction: Vector2 = (head - tail).normalized()
	var length: float = tail.distance_to(head)
	var glow: float = 0.30 if active else 0.17
	var dark: Color = Color(0.003, 0.006, 0.018, 0.98)

	draw_line(tail, head, Color(color.r, color.g, color.b, glow), half_width * 4.7, true)
	draw_circle(tail, half_width * 2.35, Color(color.r, color.g, color.b, glow), true)
	draw_circle(head, half_width * 2.35, Color(color.r, color.g, color.b, glow), true)

	draw_line(tail, head, Color.WHITE, half_width * 2.65, true)
	draw_circle(tail, half_width * 1.33, Color.WHITE, true)
	draw_circle(head, half_width * 1.33, Color.WHITE, true)

	draw_line(tail, head, color, half_width * 2.30, true)
	draw_circle(tail, half_width * 1.15, color, true)
	draw_circle(head, half_width * 1.15, color, true)

	draw_line(tail, head, dark, half_width * 1.28, true)
	draw_circle(tail, half_width * 0.64, dark, true)
	draw_circle(head, half_width * 0.64, dark, true)

	var dash_spacing: float = half_width * 1.45
	var dash_count: int = maxi(2, int(length / maxf(dash_spacing, 1.0)))
	var phase: float = fmod(_idle_time() * (1.8 if active else 0.85), 1.0)
	for index in range(dash_count):
		var t: float = fmod((float(index) + phase) / float(dash_count), 1.0)
		var dash_position: Vector2 = tail.lerp(head, t)
		var dash_size: float = half_width * (0.22 + 0.05 * sin(float(index)))
		draw_circle(
			dash_position,
			dash_size,
			Color(color.r, color.g, color.b, 0.42 if active else 0.20),
			true
		)

	var head_pulse: float = 0.5 + 0.5 * sin(_idle_time() * 8.0)
	draw_arc(
		head,
		half_width * (0.80 + head_pulse * 0.08),
		0.0,
		TAU,
		42,
		Color.WHITE,
		maxf(2.0, half_width * 0.13),
		true
	)
	draw_arc(
		head,
		half_width * 0.58,
		-PI * 0.5,
		-PI * 0.5 + TAU * progress,
		36,
		color,
		maxf(2.0, half_width * 0.14),
		true
	)
	draw_circle(head, half_width * 0.12, Color.WHITE, true)

	var tail_indicator: Vector2 = tail - direction * half_width * 0.15
	_draw_diamond(
		tail_indicator,
		half_width * 0.42,
		Color.WHITE,
		maxf(2.0, half_width * 0.12)
	)


func _draw_slide(event: Dictionary) -> void:
	if not bool(event.get("_spawned", false)):
		return

	var path_value: Variant = event.get("_path_points", PackedVector2Array())
	if not path_value is PackedVector2Array:
		return

	var points: PackedVector2Array = path_value as PackedVector2Array
	if points.size() < 2:
		return

	var hit_time: float = float(event.get("time", 0.0))
	var end_time: float = float(event.get("end_time", hit_time + 1.0))
	var approach: float = float(difficulty.get("approach", 1.0))
	if song_time < hit_time - approach or song_time > end_time + 0.35:
		return

	var color: Color = Color(0.04, 0.93, 1.0, 1.0)
	var accent: Color = Color(0.82, 1.0, 1.0, 1.0)
	var visual_progress: float = clampf(float(event.get("_visual_progress", 0.0)), 0.0, 1.0)
	var active: bool = bool(event.get("_active", false))
	var arrows_from: float = visual_progress if active else 0.0

	_draw_slide_rail(points, color)
	_draw_chevrons(points, arrows_from, color, accent)

	var star_position: Vector2
	var tangent: Vector2
	var star_progress: float = visual_progress

	if song_time < hit_time:
		var arrival: float = clampf(
			(song_time - (hit_time - approach)) / maxf(approach, 0.001),
			0.0,
			1.0
		)
		var eased: float = 1.0 - pow(1.0 - arrival, 4.0)
		star_position = center.lerp(points[0], eased)
		tangent = (points[0] - center).normalized()
		star_progress = 0.0
	else:
		star_position = PATH_BUILDER.point_at(points, visual_progress)
		tangent = PATH_BUILDER.tangent_at(points, visual_progress)

	if active:
		for ghost_index in range(1, 4):
			var ghost_progress: float = maxf(0.0, star_progress - float(ghost_index) * 0.035)
			var ghost_position: Vector2 = PATH_BUILDER.point_at(points, ghost_progress)
			var ghost_tangent: Vector2 = PATH_BUILDER.tangent_at(points, ghost_progress)
			_draw_star(
				ghost_position,
				ghost_tangent.angle(),
				radius * (0.080 - float(ghost_index) * 0.008),
				Color(color.r, color.g, color.b, 0.14),
				Color(accent.r, accent.g, accent.b, 0.08)
			)

	_draw_star(
		star_position,
		tangent.angle(),
		radius * 0.105 * float(difficulty.get("star_scale", 1.0)),
		color,
		accent
	)


func _draw_slide_rail(points: PackedVector2Array, color: Color) -> void:
	for index in range(points.size() - 1):
		draw_line(
			points[index],
			points[index + 1],
			Color(0.0, 0.0, 0.0, 0.76),
			maxf(8.0, radius * 0.026),
			true
		)
		draw_line(
			points[index],
			points[index + 1],
			Color(color.r, color.g, color.b, 0.16),
			maxf(3.0, radius * 0.008),
			true
		)


func _draw_chevrons(
	points: PackedVector2Array,
	start_progress: float,
	color: Color,
	accent: Color
) -> void:
	var spacing: float = radius * 0.052
	var estimated_length: float = 0.0
	for index in range(points.size() - 1):
		estimated_length += points[index].distance_to(points[index + 1])

	var count: int = maxi(5, int(ceil(estimated_length / maxf(spacing, 1.0))))
	var start_index: int = clampi(int(floor(start_progress * float(count))), 0, count - 1)

	for index in range(start_index, count):
		var progress: float = (float(index) + 0.50) / float(count)
		var position_value: Vector2 = PATH_BUILDER.point_at(points, progress)
		var tangent: Vector2 = PATH_BUILDER.tangent_at(points, progress)
		var mix_value: float = 0.10 + 0.18 * float(index % 3)
		var arrow_color: Color = color.lerp(accent, mix_value)
		_draw_chevron(position_value, tangent, radius * 0.058, arrow_color)


func _draw_chevron(
	position_value: Vector2,
	direction: Vector2,
	size: float,
	color: Color
) -> void:
	var tangent: Vector2 = direction.normalized()
	var perpendicular := Vector2(-tangent.y, tangent.x)
	var length: float = size * 2.10
	var half_height: float = size * 0.88

	var tip: Vector2 = position_value + tangent * length * 0.62
	var rear: Vector2 = position_value - tangent * length * 0.48
	var inner: Vector2 = position_value - tangent * length * 0.02

	var polygon := PackedVector2Array([
		rear + perpendicular * half_height,
		inner + perpendicular * half_height * 0.42,
		tip,
		inner - perpendicular * half_height * 0.42,
		rear - perpendicular * half_height,
		position_value - tangent * length * 0.20,
	])

	var shadow_offset := Vector2(radius * 0.009, radius * 0.010)
	var shadow := PackedVector2Array()
	for point in polygon:
		shadow.append(point + shadow_offset)

	draw_colored_polygon(shadow, Color(0.0, 0.0, 0.0, 0.96))
	draw_colored_polygon(polygon, color)

	var outline := polygon.duplicate()
	outline.append(outline[0])
	draw_polyline(
		outline,
		Color(0.01, 0.04, 0.07, 0.98),
		maxf(5.0, size * 0.19),
		true
	)

	var highlight := PackedVector2Array([
		rear + perpendicular * half_height * 0.58,
		inner + perpendicular * half_height * 0.22,
		tip - tangent * length * 0.10,
	])
	draw_polyline(
		highlight,
		Color(0.90, 1.0, 1.0, 0.98),
		maxf(2.0, size * 0.075),
		true
	)



func _draw_star(
	position_value: Vector2,
	rotation_value: float,
	size: float,
	color: Color,
	accent: Color
) -> void:
	var pulse: float = 0.5 + 0.5 * sin(_idle_time() * 9.0)
	var outer: PackedVector2Array = _star_points(
		size * (1.0 + pulse * 0.045),
		size * 0.44,
		rotation_value,
		position_value
	)
	var middle: PackedVector2Array = _star_points(
		size * 0.73,
		size * 0.31,
		rotation_value,
		position_value
	)
	var inner: PackedVector2Array = _star_points(
		size * 0.48,
		size * 0.20,
		rotation_value,
		position_value
	)
	outer.append(outer[0])
	middle.append(middle[0])
	inner.append(inner[0])

	draw_polyline(outer, Color(0.0, 0.0, 0.0, 0.90), maxf(12.0, size * 0.30), true)
	draw_polyline(outer, Color.WHITE, maxf(7.0, size * 0.16), true)
	draw_polyline(middle, color, maxf(5.0, size * 0.13), true)
	draw_polyline(inner, accent, maxf(3.5, size * 0.10), true)
	draw_circle(position_value, size * 0.18, Color(0.002, 0.006, 0.016, 0.96), true)
	draw_circle(position_value, size * 0.075, Color.WHITE, true)


func _draw_effects() -> void:
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	for effect_value in effects:
		if not effect_value is Dictionary:
			continue

		var effect: Dictionary = effect_value as Dictionary
		var duration: float = maxf(float(effect.get("duration", 0.5)), 0.001)
		var progress: float = clampf(
			(now - float(effect.get("start", now))) / duration,
			0.0,
			1.0
		)
		var life: float = 1.0 - progress
		var position_value: Vector2 = effect.get("position", center)
		var color: Color = effect.get("color", Color.WHITE)
		var kind: String = str(effect.get("kind", "tap"))
		var rotation_value: float = float(effect.get("rotation", 0.0))

		if kind == "slide":
			_draw_slide_burst(position_value, color, progress, life, rotation_value)
		elif kind == "hold":
			_draw_hold_burst(position_value, color, progress, life)
		elif kind == "miss":
			_draw_miss_burst(position_value, progress, life, rotation_value)
		else:
			_draw_tap_prism(position_value, color, progress, life, rotation_value)


func _draw_tap_prism(
	position_value: Vector2,
	color: Color,
	progress: float,
	life: float,
	rotation_value: float
) -> void:
	var flash_radius: float = radius * (0.025 + progress * 0.105)
	draw_circle(
		position_value,
		flash_radius,
		Color(1.0, 1.0, 1.0, life * 0.16),
		true
	)

	for layer in range(4):
		var size: float = radius * (0.055 + float(layer) * 0.022)
		size *= 0.22 + progress * 1.18
		var alpha: float = life * (1.0 - float(layer) * 0.17)
		var layer_color: Color = Color.WHITE.lerp(color, 0.22 + float(layer) * 0.22)
		layer_color.a = alpha
		_draw_rotated_diamond(
			position_value,
			size,
			rotation_value + float(layer) * PI * 0.25,
			layer_color,
			maxf(3.0, radius * (0.010 - float(layer) * 0.0014))
		)

	for index in range(8):
		var angle: float = rotation_value + TAU * float(index) / 8.0
		var direction := Vector2(cos(angle), sin(angle))
		var shard_center: Vector2 = position_value + direction * radius * (0.040 + progress * 0.145)
		var shard_size: float = radius * (0.016 + progress * 0.020)
		_draw_rotated_diamond(
			shard_center,
			shard_size,
			angle,
			Color(color.r, color.g, color.b, life * 0.76),
			maxf(2.0, radius * 0.0045)
		)

	for ring in range(2):
		draw_arc(
			position_value,
			radius * (0.045 + float(ring) * 0.035 + progress * 0.12),
			rotation_value + float(ring) * PI * 0.5,
			rotation_value + float(ring) * PI * 0.5 + PI * 1.36,
			38,
			Color(1.0, 1.0, 1.0, life * (0.48 - float(ring) * 0.14)),
			maxf(2.0, radius * 0.005),
			true
		)


func _draw_slide_burst(
	position_value: Vector2,
	color: Color,
	progress: float,
	life: float,
	rotation_value: float
) -> void:
	for layer in range(4):
		var size: float = radius * (0.080 + float(layer) * 0.022)
		size *= 0.30 + progress * 1.10
		var points: PackedVector2Array = _star_points(
			size,
			size * 0.43,
			rotation_value + progress * (1.4 if layer % 2 == 0 else -1.1),
			position_value
		)
		points.append(points[0])
		draw_polyline(
			points,
			Color(color.r, color.g, color.b, life * (0.96 - float(layer) * 0.16)),
			maxf(3.0, radius * (0.010 - float(layer) * 0.0012)),
			true
		)

	for index in range(6):
		var angle: float = rotation_value + TAU * float(index) / 6.0
		var direction := Vector2(cos(angle), sin(angle))
		var p: Vector2 = position_value + direction * radius * (0.055 + progress * 0.14)
		_draw_chevron(
			p,
			direction,
			radius * (0.018 + progress * 0.012),
			Color(color.r, color.g, color.b, life * 0.72)
		)


func _draw_hold_burst(
	position_value: Vector2,
	color: Color,
	progress: float,
	life: float
) -> void:
	for ring in range(4):
		draw_arc(
			position_value,
			radius * (0.030 + float(ring) * 0.026 + progress * 0.11),
			0.0,
			TAU,
			56,
			Color(color.r, color.g, color.b, life * (0.94 - float(ring) * 0.19)),
			maxf(2.0, radius * (0.010 - float(ring) * 0.0014)),
			true
		)

	for index in range(4):
		var angle: float = PI * 0.25 + float(index) * PI * 0.5
		var direction := Vector2(cos(angle), sin(angle))
		var inner: Vector2 = position_value + direction * radius * (0.025 + progress * 0.03)
		var outer: Vector2 = position_value + direction * radius * (0.075 + progress * 0.12)
		draw_line(
			inner,
			outer,
			Color.WHITE,
			maxf(2.0, radius * 0.006),
			true
		)


func _draw_miss_burst(
	position_value: Vector2,
	progress: float,
	life: float,
	rotation_value: float
) -> void:
	var size: float = radius * (0.040 + progress * 0.095)
	var a: Vector2 = Vector2(cos(rotation_value), sin(rotation_value)) * size
	var b: Vector2 = Vector2(-a.y, a.x)
	draw_line(
		position_value - a,
		position_value + a,
		Color(1.0, 0.08, 0.13, life),
		maxf(4.0, radius * 0.012),
		true
	)
	draw_line(
		position_value - b,
		position_value + b,
		Color(1.0, 0.08, 0.13, life),
		maxf(4.0, radius * 0.012),
		true
	)
	draw_arc(
		position_value,
		size * 1.18,
		0.0,
		TAU,
		40,
		Color(1.0, 0.12, 0.18, life * 0.42),
		maxf(2.0, radius * 0.005),
		true
	)


func _draw_pointer(position_value: Vector2) -> void:
	var color: Color = _primary()
	var pulse: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.025)
	var outer_radius: float = radius * (0.044 + pulse * 0.006)

	draw_circle(
		position_value,
		outer_radius * 1.28,
		Color(color.r, color.g, color.b, 0.09),
		true
	)
	draw_arc(
		position_value,
		outer_radius,
		0.0,
		TAU,
		40,
		Color.WHITE,
		maxf(2.0, radius * 0.0045),
		true
	)
	draw_arc(
		position_value,
		outer_radius * 0.70,
		-PI * 0.5,
		-PI * 0.5 + PI * 1.30,
		28,
		Color(color.r, color.g, color.b, 0.92),
		maxf(2.0, radius * 0.005),
		true
	)

	for index in range(4):
		var angle: float = PI * 0.25 + float(index) * PI * 0.5
		var direction := Vector2(cos(angle), sin(angle))
		var side := Vector2(-direction.y, direction.x)
		var corner: Vector2 = position_value + direction * outer_radius * 1.20
		draw_line(
			corner - side * outer_radius * 0.20,
			corner + side * outer_radius * 0.20,
			Color(color.r, color.g, color.b, 0.75),
			maxf(2.0, radius * 0.004),
			true
		)


func _draw_diamond(
	position_value: Vector2,
	size: float,
	color: Color,
	width: float
) -> void:
	var points := PackedVector2Array([
		position_value + Vector2(0.0, -size),
		position_value + Vector2(size, 0.0),
		position_value + Vector2(0.0, size),
		position_value + Vector2(-size, 0.0),
		position_value + Vector2(0.0, -size),
	])
	draw_polyline(points, color, width, true)


func _draw_rotated_diamond(
	position_value: Vector2,
	size: float,
	rotation_value: float,
	color: Color,
	width: float
) -> void:
	var points := PackedVector2Array()
	for index in range(5):
		var angle: float = rotation_value - PI * 0.5 + float(index) * PI * 0.5
		points.append(position_value + Vector2(cos(angle), sin(angle)) * size)
	draw_polyline(points, color, width, true)


func _draw_regular_polygon(
	position_value: Vector2,
	size: float,
	sides: int,
	rotation_value: float,
	color: Color,
	width: float
) -> void:
	var points := PackedVector2Array()
	for index in range(sides + 1):
		var angle: float = rotation_value + TAU * float(index) / float(sides)
		points.append(position_value + Vector2(cos(angle), sin(angle)) * size)
	draw_polyline(points, color, width, true)


func _star_points(
	outer_radius: float,
	inner_radius: float,
	rotation_value: float,
	position_value: Vector2
) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(10):
		var angle: float = rotation_value - PI * 0.5 + PI * float(index) / 5.0
		var point_radius: float = outer_radius if index % 2 == 0 else inner_radius
		points.append(position_value + Vector2(cos(angle), sin(angle)) * point_radius)
	return points
'@

Write-Utf8NoBom (Project-Path "scripts\hit_music_r7\selector.gd") @'
extends Node2D

const CATALOG: Script = preload("res://scripts/hit_music_r7/catalog.gd")
const RENDERER_SCRIPT: Script = preload("res://scripts/hit_music_r7/playfield_renderer.gd")
const LED_CLIENT: Script = preload("res://scripts/hit_music_r7/led_client.gd")

const TOP_MARGIN_RATIO: float = 0.022
const TOP_HEIGHT_RATIO: float = 0.205
const TOP_GAP_RATIO: float = 0.024
const SIDE_MARGIN_RATIO: float = 0.015
const BOTTOM_MARGIN_RATIO: float = 0.012
const CIRCLE_SCALE: float = 0.985
const PREVIEW_DELAY: float = 0.75
const PREVIEW_ALPHA: float = 0.62
const CARD_SPACING_RATIO: float = 0.205

var _songs: Array = []
var _index: int = 0
var _difficulty: String = "easy"
var _center: Vector2 = Vector2.ZERO
var _radius: float = 100.0
var _lane_positions: PackedVector2Array = PackedVector2Array()
var _video_rect: Rect2 = Rect2()
var _preview_wait: float = 0.0
var _transitioning: bool = false
var _visual_time: float = 0.0

var _video: VideoStreamPlayer
var _renderer
var _ui: CanvasLayer
var _top_panel: Panel
var _brand_label: Label
var _subtitle_label: Label
var _instruction_label: Label
var _easy_chip: Panel
var _hard_chip: Panel
var _easy_label: Label
var _hard_label: Label
var _content_root: Control
var _list_root: Control
var _info_panel: Panel
var _cover_frame: Panel
var _cover: TextureRect
var _track_badge: Panel
var _track_label: Label
var _song_name: Label
var _category_label: Label
var _bpm_label: Label
var _mode_label: Label
var _record_label: Label
var _start_panel: Panel
var _start_label: Label
var _cards: Array[Panel] = []
var _card_labels: Array[Label] = []
var _card_track_labels: Array[Label] = []
var _card_covers: Array[TextureRect] = []


func _ready() -> void:
	Engine.max_fps = 60
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	_songs = CATALOG.all_songs()
	if _songs.is_empty():
		push_error("Catalogo Hit Music vazio.")
		return

	if get_tree().has_meta("hit_music_selector_index"):
		_index = clampi(
			int(get_tree().get_meta("hit_music_selector_index")),
			0,
			_songs.size() - 1
		)

	if get_tree().has_meta("hit_music_selector_difficulty"):
		_difficulty = str(get_tree().get_meta("hit_music_selector_difficulty"))

	if _difficulty != "hard":
		_difficulty = "easy"

	_calculate_geometry()
	_build_scene()
	_apply_selection(true)
	get_viewport().size_changed.connect(_on_viewport_size_changed)


func _process(delta: float) -> void:
	_visual_time += delta

	if not _transitioning:
		if _action_pressed("input_a") or _action_pressed("ui_down") or _action_pressed("ui_right"):
			_change_selection(1)
		elif _action_pressed("ui_up") or _action_pressed("ui_left"):
			_change_selection(-1)

		if _action_pressed("input_b"):
			_toggle_difficulty()

		if _action_pressed("input_start") or _action_pressed("ui_accept"):
			_start_selected()

		_preview_wait += delta
		if _preview_wait >= PREVIEW_DELAY and _video.stream != null and not _video.is_playing():
			_video.play()
			var preview_tween: Tween = create_tween()
			preview_tween.set_trans(Tween.TRANS_QUINT)
			preview_tween.set_ease(Tween.EASE_OUT)
			preview_tween.tween_property(_video, "modulate:a", PREVIEW_ALPHA, 0.48)

	_update_card_animation(delta)
	_update_live_styles()
	_renderer.set_runtime([], _visual_time, "selector", Vector2.ZERO, false)
	queue_redraw()


func _draw() -> void:
	var screen: Vector2 = get_viewport_rect().size
	var primary: Color = _song_primary(_songs[_index] as Dictionary)
	var accent: Color = _song_accent(_songs[_index] as Dictionary)
	var pulse: float = 0.5 + 0.5 * sin(_visual_time * 1.7)

	draw_rect(Rect2(Vector2.ZERO, screen), Color.BLACK, true)
	draw_circle(_center, _radius * 1.028, Color(primary.r, primary.g, primary.b, 0.055), true)
	draw_circle(_center, _radius * 1.010, Color(0.0, 0.0, 0.0, 0.98), true)
	draw_circle(_center, _radius * 0.997, _dark_color(), true)

	draw_arc(
		_center,
		_radius * 1.003,
		0.0,
		TAU,
		260,
		Color(primary.r, primary.g, primary.b, 0.18 + pulse * 0.06),
		maxf(4.0, _radius * 0.012),
		true
	)
	draw_arc(
		_center,
		_radius * 0.982,
		0.0,
		TAU,
		260,
		Color(accent.r, accent.g, accent.b, 0.12),
		maxf(1.0, _radius * 0.0025),
		true
	)

	for index in range(32):
		var angle: float = TAU * float(index) / 32.0
		var direction := Vector2(cos(angle), sin(angle))
		var inner: Vector2 = _center + direction * _radius * 0.953
		var outer: Vector2 = _center + direction * _radius * (
			0.970 + 0.006 * absf(sin(_visual_time * 1.2 + float(index)))
		)
		var color: Color = primary if index % 2 == 0 else accent
		draw_line(
			inner,
			outer,
			Color(color.r, color.g, color.b, 0.24),
			maxf(1.0, _radius * 0.002),
			true
		)


func _input(event: InputEvent) -> void:
	if _transitioning:
		return

	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed:
			_handle_touch(touch.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse: InputEventMouseButton = event
		if mouse.pressed:
			_handle_touch(mouse.position)


func _handle_touch(position_value: Vector2) -> void:
	if _easy_chip != null and Rect2(_easy_chip.global_position, _easy_chip.size).has_point(position_value):
		if _difficulty != "easy":
			_difficulty = "easy"
			_apply_selection(false)
		return

	if _hard_chip != null and Rect2(_hard_chip.global_position, _hard_chip.size).has_point(position_value):
		if _difficulty != "hard":
			_difficulty = "hard"
			_apply_selection(false)
		return

	for card_index in range(_cards.size()):
		var card: Panel = _cards[card_index]
		if not card.visible:
			continue
		if Rect2(card.global_position, card.size).has_point(position_value):
			if card_index == _index:
				_start_selected()
			else:
				_index = card_index
				_apply_selection(false)
			return

	if _start_panel != null and Rect2(_start_panel.global_position, _start_panel.size).has_point(position_value):
		_start_selected()
		return

	if _info_panel != null and Rect2(_info_panel.global_position, _info_panel.size).has_point(position_value):
		_start_selected()


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
	_center = Vector2(screen.x * 0.5, screen.y - bottom_margin - _radius)

	_lane_positions = PackedVector2Array()
	for lane in range(8):
		var angle: float = -PI * 0.5 + TAU * float(lane) / 8.0
		_lane_positions.append(
			_center + Vector2(cos(angle), sin(angle)) * _radius * 0.905
		)

	_video_rect = Rect2(
		_center - Vector2.ONE * _radius,
		Vector2.ONE * (_radius * 2.0)
	)


func _build_scene() -> void:
	_video = VideoStreamPlayer.new()
	_video.position = _video_rect.position
	_video.size = _video_rect.size
	_video.expand = true
	_video.loop = true
	_video.volume_db = -80.0
	_video.modulate.a = 0.0
	_video.z_index = 2
	_video.material = _circular_video_material()
	add_child(_video)

	_renderer = RENDERER_SCRIPT.new()
	_renderer.z_index = 10
	add_child(_renderer)

	_ui = CanvasLayer.new()
	_ui.layer = 30
	add_child(_ui)

	var screen: Vector2 = get_viewport_rect().size
	var margin: float = screen.x * TOP_MARGIN_RATIO
	var top_height: float = screen.y * TOP_HEIGHT_RATIO
	var font: Font = _load_font()

	_top_panel = Panel.new()
	_top_panel.position = Vector2(margin, margin)
	_top_panel.size = Vector2(screen.x - margin * 2.0, top_height)
	_top_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_top_panel)

	_brand_label = _make_label(
		"HIT MUSIC",
		int(top_height * 0.235),
		HORIZONTAL_ALIGNMENT_LEFT,
		font
	)
	_brand_label.position = Vector2(top_height * 0.12, top_height * 0.055)
	_brand_label.size = Vector2(_top_panel.size.x * 0.50, top_height * 0.34)
	_top_panel.add_child(_brand_label)

	_subtitle_label = _make_label(
		"SELECT YOUR TRACK",
		int(top_height * 0.105),
		HORIZONTAL_ALIGNMENT_LEFT,
		font
	)
	_subtitle_label.position = Vector2(top_height * 0.13, top_height * 0.34)
	_subtitle_label.size = Vector2(_top_panel.size.x * 0.48, top_height * 0.20)
	_subtitle_label.add_theme_color_override("font_color", Color(0.72, 0.78, 0.90, 1.0))
	_top_panel.add_child(_subtitle_label)

	_easy_chip = Panel.new()
	_easy_chip.position = Vector2(_top_panel.size.x * 0.62, top_height * 0.11)
	_easy_chip.size = Vector2(_top_panel.size.x * 0.145, top_height * 0.34)
	_top_panel.add_child(_easy_chip)

	_easy_label = _make_label(
		"FACIL",
		int(top_height * 0.13),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	_easy_label.size = _easy_chip.size
	_easy_chip.add_child(_easy_label)

	_hard_chip = Panel.new()
	_hard_chip.position = Vector2(_top_panel.size.x * 0.775, top_height * 0.11)
	_hard_chip.size = Vector2(_top_panel.size.x * 0.17, top_height * 0.34)
	_top_panel.add_child(_hard_chip)

	_hard_label = _make_label(
		"DIFICIL",
		int(top_height * 0.13),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	_hard_label.size = _hard_chip.size
	_hard_chip.add_child(_hard_label)

	_instruction_label = _make_label(
		"A  NEXT TRACK     B  DIFFICULTY     START  PLAY",
		int(top_height * 0.10),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	_instruction_label.position = Vector2(top_height * 0.10, top_height * 0.65)
	_instruction_label.size = Vector2(_top_panel.size.x - top_height * 0.20, top_height * 0.22)
	_instruction_label.add_theme_color_override("font_color", Color(0.78, 0.83, 0.93, 1.0))
	_top_panel.add_child(_instruction_label)

	_content_root = Control.new()
	_content_root.position = _center - Vector2(_radius, _radius)
	_content_root.size = Vector2(_radius * 2.0, _radius * 2.0)
	_content_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_content_root)

	_list_root = Control.new()
	_list_root.position = Vector2.ZERO
	_list_root.size = _content_root.size
	_list_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_root.add_child(_list_root)

	_build_cards(font)
	_build_info_panel(font)


func _build_cards(font: Font) -> void:
	_cards.clear()
	_card_labels.clear()
	_card_track_labels.clear()
	_card_covers.clear()

	var card_size := Vector2(_radius * 0.78, _radius * 0.145)
	for song_index in range(_songs.size()):
		var song: Dictionary = _songs[song_index] as Dictionary
		var card := Panel.new()
		card.size = card_size
		card.pivot_offset = card.size * 0.5
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_list_root.add_child(card)

		var cover := TextureRect.new()
		cover.position = Vector2(card.size.y * 0.09, card.size.y * 0.09)
		cover.size = Vector2(card.size.y * 0.82, card.size.y * 0.82)
		cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cover.texture = _load_texture(str(song.get("cover", "")))
		card.add_child(cover)

		var text_x: float = cover.position.x + cover.size.x + card.size.x * 0.045
		var track := _make_label(
			"TRACK %02d" % (song_index + 1),
			int(_radius * 0.019),
			HORIZONTAL_ALIGNMENT_LEFT,
			font
		)
		track.position = Vector2(text_x, card.size.y * 0.08)
		track.size = Vector2(card.size.x - text_x - card.size.x * 0.05, card.size.y * 0.29)
		track.add_theme_color_override("font_color", Color(0.64, 0.72, 0.84, 1.0))
		card.add_child(track)

		var label := _make_label(
			str(song.get("title", "TRACK")),
			int(_radius * 0.032),
			HORIZONTAL_ALIGNMENT_LEFT,
			font
		)
		label.position = Vector2(text_x, card.size.y * 0.34)
		label.size = Vector2(card.size.x - text_x - card.size.x * 0.05, card.size.y * 0.57)
		label.clip_text = true
		card.add_child(label)

		_cards.append(card)
		_card_labels.append(label)
		_card_track_labels.append(track)
		_card_covers.append(cover)


func _build_info_panel(font: Font) -> void:
	_info_panel = Panel.new()
	_info_panel.position = Vector2(_radius * 1.03, _radius * 0.365)
	_info_panel.size = Vector2(_radius * 0.75, _radius * 1.19)
	_info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_root.add_child(_info_panel)

	_cover_frame = Panel.new()
	_cover_frame.position = Vector2(_info_panel.size.x * 0.055, _info_panel.size.y * 0.045)
	_cover_frame.size = Vector2(_info_panel.size.x * 0.89, _info_panel.size.y * 0.35)
	_cover_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info_panel.add_child(_cover_frame)

	_cover = TextureRect.new()
	_cover.position = Vector2(_cover_frame.size.x * 0.025, _cover_frame.size.y * 0.04)
	_cover.size = Vector2(_cover_frame.size.x * 0.95, _cover_frame.size.y * 0.92)
	_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover_frame.add_child(_cover)

	_track_badge = Panel.new()
	_track_badge.position = Vector2(_info_panel.size.x * 0.055, _info_panel.size.y * 0.425)
	_track_badge.size = Vector2(_info_panel.size.x * 0.37, _info_panel.size.y * 0.075)
	_info_panel.add_child(_track_badge)

	_track_label = _make_label(
		"TRACK 01",
		int(_radius * 0.022),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	_track_label.size = _track_badge.size
	_track_badge.add_child(_track_label)

	_song_name = _make_label(
		"TRACK",
		int(_radius * 0.046),
		HORIZONTAL_ALIGNMENT_LEFT,
		font
	)
	_song_name.position = Vector2(_info_panel.size.x * 0.06, _info_panel.size.y * 0.51)
	_song_name.size = Vector2(_info_panel.size.x * 0.88, _info_panel.size.y * 0.16)
	_song_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_panel.add_child(_song_name)

	_category_label = _make_label(
		"ANIME MUSIC",
		int(_radius * 0.022),
		HORIZONTAL_ALIGNMENT_LEFT,
		font
	)
	_category_label.position = Vector2(_info_panel.size.x * 0.06, _info_panel.size.y * 0.675)
	_category_label.size = Vector2(_info_panel.size.x * 0.88, _info_panel.size.y * 0.055)
	_category_label.add_theme_color_override("font_color", Color(0.70, 0.76, 0.86, 1.0))
	_info_panel.add_child(_category_label)

	_bpm_label = _make_label(
		"BPM 120",
		int(_radius * 0.022),
		HORIZONTAL_ALIGNMENT_LEFT,
		font
	)
	_bpm_label.position = Vector2(_info_panel.size.x * 0.06, _info_panel.size.y * 0.735)
	_bpm_label.size = Vector2(_info_panel.size.x * 0.43, _info_panel.size.y * 0.055)
	_info_panel.add_child(_bpm_label)

	_mode_label = _make_label(
		"MODE FACIL",
		int(_radius * 0.022),
		HORIZONTAL_ALIGNMENT_RIGHT,
		font
	)
	_mode_label.position = Vector2(_info_panel.size.x * 0.48, _info_panel.size.y * 0.735)
	_mode_label.size = Vector2(_info_panel.size.x * 0.46, _info_panel.size.y * 0.055)
	_info_panel.add_child(_mode_label)

	_record_label = _make_label(
		"BEST 0.00%",
		int(_radius * 0.026),
		HORIZONTAL_ALIGNMENT_LEFT,
		font
	)
	_record_label.position = Vector2(_info_panel.size.x * 0.06, _info_panel.size.y * 0.80)
	_record_label.size = Vector2(_info_panel.size.x * 0.88, _info_panel.size.y * 0.07)
	_info_panel.add_child(_record_label)

	_start_panel = Panel.new()
	_start_panel.position = Vector2(_info_panel.size.x * 0.055, _info_panel.size.y * 0.89)
	_start_panel.size = Vector2(_info_panel.size.x * 0.89, _info_panel.size.y * 0.075)
	_info_panel.add_child(_start_panel)

	_start_label = _make_label(
		"PRESS START",
		int(_radius * 0.028),
		HORIZONTAL_ALIGNMENT_CENTER,
		font
	)
	_start_label.size = _start_panel.size
	_start_panel.add_child(_start_label)


func _change_selection(direction: int) -> void:
	_index = posmod(_index + direction, _songs.size())
	_apply_selection(false)


func _toggle_difficulty() -> void:
	_difficulty = "hard" if _difficulty == "easy" else "easy"
	_apply_selection(false)


func _apply_selection(immediate: bool) -> void:
	if _songs.is_empty():
		return

	var song: Dictionary = _songs[_index] as Dictionary
	var difficulty_data: Dictionary = CATALOG.get_difficulty(song, _difficulty)

	_renderer.configure(_center, _radius, _lane_positions, song, difficulty_data)
	_track_label.text = "TRACK %02d / %02d" % [_index + 1, _songs.size()]
	_song_name.text = str(song.get("title", "TRACK"))
	_category_label.text = "ANIME / RHYTHM"
	_bpm_label.text = "BPM %d" % int(round(float(song.get("bpm", 120.0))))
	_mode_label.text = "MODE " + ("DIFICIL" if _difficulty == "hard" else "FACIL")
	_record_label.text = "BEST " + _best_record(song)
	_cover.texture = _load_texture(str(song.get("cover", "")))

	_load_preview(song)
	_update_cards(immediate)
	_update_live_styles()
	LED_CLIENT.menu_state(_index, _song_primary(song))


func _update_cards(immediate: bool) -> void:
	var total: int = _cards.size()
	for card_index in range(total):
		var card: Panel = _cards[card_index]
		var relative: int = card_index - _index
		if relative > total / 2:
			relative -= total
		elif relative < -total / 2:
			relative += total

		var target_y: float = _radius * 0.91 + float(relative) * _radius * CARD_SPACING_RATIO
		var target_x: float = _radius * 0.19 + (_radius * 0.055 if relative == 0 else 0.0)
		var visible_range: bool = abs(relative) <= 2
		var target_scale: Vector2 = (
			Vector2(1.055, 1.055)
			if relative == 0
			else Vector2(0.91, 0.91)
		)
		var target_alpha: float = (
			1.0
			if relative == 0
			else (0.62 if visible_range else 0.0)
		)

		card.set_meta("target_position", Vector2(target_x, target_y))
		card.set_meta("target_scale", target_scale)
		card.set_meta("target_alpha", target_alpha)
		card.set_meta("relative", relative)
		card.add_theme_stylebox_override(
			"panel",
			_card_style(_songs[card_index] as Dictionary, relative == 0)
		)

		_card_labels[card_index].add_theme_color_override(
			"font_color",
			Color.WHITE if relative == 0 else Color(0.72, 0.77, 0.86, 1.0)
		)

		if immediate:
			card.position = card.get_meta("target_position")
			card.scale = card.get_meta("target_scale")
			card.modulate.a = float(card.get_meta("target_alpha"))
			card.visible = card.modulate.a > 0.01


func _update_card_animation(delta: float) -> void:
	var position_factor: float = 1.0 - exp(-12.0 * delta)
	var alpha_factor: float = 1.0 - exp(-15.0 * delta)
	var scale_factor: float = 1.0 - exp(-10.0 * delta)

	for card in _cards:
		var target_position: Vector2 = card.get_meta("target_position", card.position)
		var target_scale: Vector2 = card.get_meta("target_scale", card.scale)
		var target_alpha: float = float(card.get_meta("target_alpha", card.modulate.a))

		card.position = card.position.lerp(target_position, position_factor)
		card.scale = card.scale.lerp(target_scale, scale_factor)
		card.modulate.a = lerpf(card.modulate.a, target_alpha, alpha_factor)
		card.visible = card.modulate.a > 0.01


func _update_live_styles() -> void:
	if _songs.is_empty():
		return

	var song: Dictionary = _songs[_index] as Dictionary
	var primary: Color = _song_primary(song)
	var accent: Color = _song_accent(song)
	var pulse: float = 0.5 + 0.5 * sin(_visual_time * 2.2)

	_top_panel.add_theme_stylebox_override("panel", _top_style(song, pulse))
	_info_panel.add_theme_stylebox_override("panel", _info_style(song, pulse))
	_cover_frame.add_theme_stylebox_override("panel", _cover_style(song))
	_track_badge.add_theme_stylebox_override("panel", _badge_style(primary))
	_start_panel.add_theme_stylebox_override("panel", _start_style(song, pulse))
	_easy_chip.add_theme_stylebox_override(
		"panel",
		_difficulty_style(song, _difficulty == "easy")
	)
	_hard_chip.add_theme_stylebox_override(
		"panel",
		_difficulty_style(song, _difficulty == "hard")
	)

	_brand_label.add_theme_color_override("font_color", Color.WHITE)
	_subtitle_label.add_theme_color_override(
		"font_color",
		Color(primary.r, primary.g, primary.b, 0.92)
	)
	_easy_label.add_theme_color_override(
		"font_color",
		Color.WHITE if _difficulty == "easy" else Color(0.58, 0.64, 0.74, 1.0)
	)
	_hard_label.add_theme_color_override(
		"font_color",
		Color.WHITE if _difficulty == "hard" else Color(0.58, 0.64, 0.74, 1.0)
	)
	_track_label.add_theme_color_override("font_color", Color.WHITE)
	_bpm_label.add_theme_color_override("font_color", primary)
	_mode_label.add_theme_color_override("font_color", accent)
	_record_label.add_theme_color_override("font_color", Color.WHITE)
	_start_label.add_theme_color_override("font_color", Color.WHITE)


func _load_preview(song: Dictionary) -> void:
	_preview_wait = 0.0
	if _video.is_playing():
		_video.stop()
	_video.stream = null
	_video.modulate.a = 0.0

	var path: String = str(song.get("video", ""))
	if not ResourceLoader.exists(path):
		return

	var resource: Resource = load(path)
	if resource is VideoStream:
		_video.stream = resource as VideoStream


func _start_selected() -> void:
	if _transitioning or _songs.is_empty():
		return

	_transitioning = true
	var song: Dictionary = _songs[_index] as Dictionary
	get_tree().set_meta("hit_music_song_id", str(song.get("id", "")))
	get_tree().set_meta("hit_music_difficulty", _difficulty)
	get_tree().set_meta("hit_music_selector_index", _index)
	get_tree().set_meta("hit_music_selector_difficulty", _difficulty)
	LED_CLIENT.clear_all()

	var scene_path: String = str(song.get("scene", ""))
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		_transitioning = false
		push_error("Scene nao encontrada: " + scene_path)
		return

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUINT)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(_top_panel, "position:y", _top_panel.position.y - get_viewport_rect().size.y * 0.035, 0.30)
	tween.tween_property(_top_panel, "modulate:a", 0.0, 0.25)
	tween.tween_property(_content_root, "scale", Vector2(0.94, 0.94), 0.32)
	tween.tween_property(_content_root, "modulate:a", 0.0, 0.27)
	tween.tween_property(_video, "modulate:a", 0.0, 0.25)
	tween.finished.connect(
		func() -> void:
			get_tree().change_scene_to_file(scene_path)
	)


func _best_record(song: Dictionary) -> String:
	var path: String = "user://hit_music_records.json"
	if not FileAccess.file_exists(path):
		return "0.00%"

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "0.00%"

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return "0.00%"

	var song_id: String = str(song.get("id", ""))
	var value: Variant = (parsed as Dictionary).get(song_id, {})
	if not value is Dictionary:
		return "0.00%"

	var record: Dictionary = value as Dictionary
	var key: String = "dificil" if _difficulty == "hard" else "facil"
	return "%.2f%%" % float(record.get(key, 0.0))


func _on_viewport_size_changed() -> void:
	get_tree().set_meta("hit_music_selector_index", _index)
	get_tree().set_meta("hit_music_selector_difficulty", _difficulty)
	call_deferred("_reload_after_resize")


func _reload_after_resize() -> void:
	get_tree().reload_current_scene()


func _action_pressed(action: String) -> bool:
	return InputMap.has_action(action) and Input.is_action_just_pressed(action)


func _circular_video_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;

void fragment() {
	vec4 source_color = texture(TEXTURE, UV);
	float distance_value = distance(UV, vec2(0.5));
	float mask_value = 1.0 - smoothstep(0.488, 0.500, distance_value);
	COLOR = vec4(source_color.rgb, source_color.a * mask_value);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material


func _load_font() -> Font:
	for path in [
		"res://fonts/Bungee-Regular.ttf",
		"res://fonts/Oxanium-VariableFont_wght.ttf",
	]:
		if ResourceLoader.exists(path):
			var resource: Resource = load(path)
			if resource is Font:
				return resource as Font
	return ThemeDB.fallback_font


func _load_texture(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var resource: Resource = load(path)
	if resource is Texture2D:
		return resource as Texture2D
	return null


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
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.98))
	label.add_theme_constant_override("outline_size", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _song_primary(song: Dictionary) -> Color:
	var colors_value: Variant = song.get("colors", {})
	if colors_value is Dictionary:
		return (colors_value as Dictionary).get("primary", Color(0.05, 0.92, 1.0, 1.0))
	return Color(0.05, 0.92, 1.0, 1.0)


func _song_accent(song: Dictionary) -> Color:
	var colors_value: Variant = song.get("colors", {})
	if colors_value is Dictionary:
		return (colors_value as Dictionary).get("accent", Color(1.0, 0.84, 0.05, 1.0))
	return Color(1.0, 0.84, 0.05, 1.0)


func _dark_color() -> Color:
	if _songs.is_empty():
		return Color(0.01, 0.02, 0.05, 1.0)
	var colors_value: Variant = (_songs[_index] as Dictionary).get("colors", {})
	if colors_value is Dictionary:
		return (colors_value as Dictionary).get("dark", Color(0.01, 0.02, 0.05, 1.0))
	return Color(0.01, 0.02, 0.05, 1.0)


func _top_style(song: Dictionary, pulse: float) -> StyleBoxFlat:
	var primary: Color = _song_primary(song)
	var accent: Color = _song_accent(song)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.004, 0.008, 0.022, 0.975)
	style.border_color = primary.lerp(accent, pulse * 0.22)
	style.border_color.a = 0.78
	style.set_border_width_all(3)
	style.set_corner_radius_all(28)
	style.shadow_color = Color(primary.r, primary.g, primary.b, 0.16 + pulse * 0.06)
	style.shadow_size = 16
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	return style


func _info_style(song: Dictionary, pulse: float) -> StyleBoxFlat:
	var primary: Color = _song_primary(song)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.004, 0.008, 0.021, 0.94)
	style.border_color = Color(primary.r, primary.g, primary.b, 0.54 + pulse * 0.12)
	style.set_border_width_all(2)
	style.set_corner_radius_all(28)
	style.shadow_color = Color(primary.r, primary.g, primary.b, 0.18)
	style.shadow_size = 13
	return style


func _cover_style(song: Dictionary) -> StyleBoxFlat:
	var primary: Color = _song_primary(song)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.75)
	style.border_color = Color(primary.r, primary.g, primary.b, 0.72)
	style.set_border_width_all(2)
	style.set_corner_radius_all(20)
	style.shadow_color = Color(primary.r, primary.g, primary.b, 0.16)
	style.shadow_size = 8
	return style


func _badge_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.r, color.g, color.b, 0.16)
	style.border_color = Color(color.r, color.g, color.b, 0.72)
	style.set_border_width_all(2)
	style.set_corner_radius_all(18)
	return style


func _difficulty_style(song: Dictionary, selected: bool) -> StyleBoxFlat:
	var primary: Color = _song_primary(song)
	var accent: Color = _song_accent(song)
	var color: Color = accent if selected else primary
	var style := StyleBoxFlat.new()
	style.bg_color = (
		Color(color.r, color.g, color.b, 0.24)
		if selected
		else Color(0.009, 0.016, 0.034, 0.90)
	)
	style.border_color = (
		Color(color.r, color.g, color.b, 0.96)
		if selected
		else Color(0.50, 0.58, 0.72, 0.20)
	)
	style.set_border_width_all(2)
	style.set_corner_radius_all(20)
	style.shadow_color = Color(color.r, color.g, color.b, 0.18 if selected else 0.0)
	style.shadow_size = 8 if selected else 0
	return style


func _start_style(song: Dictionary, pulse: float) -> StyleBoxFlat:
	var primary: Color = _song_primary(song)
	var accent: Color = _song_accent(song)
	var color: Color = primary.lerp(accent, 0.30 + pulse * 0.22)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.r, color.g, color.b, 0.20 + pulse * 0.05)
	style.border_color = Color(color.r, color.g, color.b, 0.98)
	style.set_border_width_all(3)
	style.set_corner_radius_all(22)
	style.shadow_color = Color(color.r, color.g, color.b, 0.30 + pulse * 0.10)
	style.shadow_size = 12
	return style


func _card_style(song: Dictionary, selected: bool) -> StyleBoxFlat:
	var primary: Color = _song_primary(song)
	var accent: Color = _song_accent(song)
	var style := StyleBoxFlat.new()
	style.bg_color = (
		Color(0.015, 0.027, 0.055, 0.98)
		if selected
		else Color(0.005, 0.010, 0.024, 0.88)
	)
	style.border_color = (
		Color(accent.r, accent.g, accent.b, 0.98)
		if selected
		else Color(primary.r, primary.g, primary.b, 0.22)
	)
	style.border_width_left = 7 if selected else 2
	style.border_width_top = 3 if selected else 1
	style.border_width_right = 3 if selected else 1
	style.border_width_bottom = 3 if selected else 1
	style.set_corner_radius_all(24)
	style.shadow_color = Color(primary.r, primary.g, primary.b, 0.26 if selected else 0.06)
	style.shadow_size = 12 if selected else 3
	return style
'@

Write-Utf8NoBom (Project-Path "scripts\change_scenes.gd") @'
extends "res://scripts/hit_music_r7/selector.gd"
'@

Write-Host ""
Write-Host "VALIDANDO ARQUIVOS GERADOS:" -ForegroundColor Cyan

$GeneratedFiles = @(
    "scripts\hit_music_r7\stage.gd",
    "scripts\hit_music_r7\playfield_renderer.gd",
    "scripts\hit_music_r7\selector.gd",
    "scripts\change_scenes.gd"
)

foreach ($RelativePath in $GeneratedFiles) {
    $FullPath = Project-Path $RelativePath

    if (-not (Test-Path -LiteralPath $FullPath)) {
        throw "Falha ao criar: $RelativePath"
    }

    $Length = (Get-Item -LiteralPath $FullPath).Length
    if ($Length -le 20) {
        throw "Arquivo criado com tamanho invalido: $RelativePath"
    }

    Write-Host "[OK] $RelativePath - $Length bytes" -ForegroundColor Green
}

$RendererContent = Get-Content -LiteralPath (Project-Path "scripts\hit_music_r7\playfield_renderer.gd") -Raw
$StageContent = Get-Content -LiteralPath (Project-Path "scripts\hit_music_r7\stage.gd") -Raw
$SelectorContent = Get-Content -LiteralPath (Project-Path "scripts\hit_music_r7\selector.gd") -Raw

if ($RendererContent -match "_draw_video_frame") {
    throw "A faixa central antiga ainda existe no renderer."
}

if ($StageContent -notmatch "_rounded_video_material") {
    throw "A mascara arredondada do video superior nao foi criada."
}

if ($SelectorContent -notmatch "_circular_video_material") {
    throw "A mascara circular do preview do menu nao foi criada."
}

if ($RendererContent -notmatch "draw_arc\(\s*center,\s*ring_radius") {
    throw "O arco circular conectado nao foi localizado."
}

if ($GitAvailable -and $GitRepository) {
    git add scripts/hit_music_r7/stage.gd
    git add scripts/hit_music_r7/playfield_renderer.gd
    git add scripts/hit_music_r7/selector.gd
    git add scripts/change_scenes.gd
    git commit -m "R8 remove central video band and refine maimai style effects"
}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Green
Write-Host " R8 APLICADO COM SUCESSO" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "Backup local: $BackupRoot"
Write-Host "Branch: r8-reference-precision"
Write-Host ""
Write-Host "CORRECOES PRINCIPAIS:" -ForegroundColor Cyan
Write-Host "- Remove a faixa de video do centro do circulo."
Write-Host "- Coloca video e contagem no retangulo superior."
Write-Host "- Preview do menu ocupa o fundo circular e deixa de ficar escondido."
Write-Host "- Arco branco fica totalmente conectado."
Write-Host "- Oito bolinhas fixas marcam os destinos."
Write-Host "- Nenhum tazo fica parado esperando na borda."
Write-Host "- Setas, estrela e hold ficam maiores e mais nitidos."
Write-Host "- Fundo muda de desenho a cada secao da musica."
Write-Host ""
Write-Host "Abra o Godot, aguarde a importacao e rode com F5." -ForegroundColor Yellow
