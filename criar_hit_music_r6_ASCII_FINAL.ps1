param(
    [string]$ProjectRoot = (Get-Location).Path
)

$ErrorActionPreference = "Stop"
$scriptVersion = "R6_ASCII_FINAL_20260806"

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Project-Path {
    param([Parameter(Mandatory = $true)][string]$RelativePath)
    return Join-Path $ProjectRoot $RelativePath
}

function Ensure-Directory {
    param([Parameter(Mandatory = $true)][string]$RelativePath)
    $full = Project-Path $RelativePath
    New-Item -ItemType Directory -Path $full -Force | Out-Null
}

function Backup-CurrentHitMusicScript {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $createdBackupPath = Project-Path "_backup_hit_music_r5_$stamp"
    New-Item -ItemType Directory -Path $createdBackupPath -Force | Out-Null

    $candidate = Get-ChildItem -LiteralPath $ProjectRoot -Recurse -File -Filter "*.gd" |
        Where-Object {
            try {
                Select-String -LiteralPath $_.FullName -SimpleMatch "PLAY - HIT MUSIC - CARMINE" -Quiet
            }
            catch {
                $false
            }
        } |
        Select-Object -First 1

    if ($null -ne $candidate) {
        Copy-Item -LiteralPath $candidate.FullName -Destination (Join-Path $createdBackupPath $candidate.Name) -Force
        Write-Host "Backup do script atual: $($candidate.FullName)" -ForegroundColor DarkGray
    }
    else {
        Write-Warning "Nao encontrei automaticamente o script antigo da Carmine. Nenhum arquivo atual sera alterado."
    }

    Write-Output -NoEnumerate $createdBackupPath
}

$projectFile = Project-Path "project.godot"
if (-not (Test-Path -LiteralPath $projectFile)) {
    throw @"
Nao encontrei project.godot em:
$ProjectRoot

Abra o PowerShell na pasta raiz do projeto Godot e execute novamente:
powershell -NoProfile -ExecutionPolicy Bypass -File .\criar_hit_music_r6_ASCII_FINAL.ps1
"@
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " HIT MUSIC R6 - CRIACAO MODULAR SEGURA - ASCII FINAL" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "Versao: $scriptVersion" -ForegroundColor DarkGray
Write-Host "Projeto: $ProjectRoot"
Write-Host ""

Write-Host "Criando backup de seguranca..." -ForegroundColor DarkGray
$createdBackupPath = [string](Backup-CurrentHitMusicScript)
Write-Host "Backup preparado: $createdBackupPath" -ForegroundColor DarkGray

$directories = @(
    "entities\hit_music",
    "entities\hit_music\effects",

    "images\hit_music",
    "images\hit_music\shared",
    "images\hit_music\carmine",

    "medias\hit_music",
    "medias\hit_music\carmine",

    "scenes\hit_music",
    "scenes\hit_music\base",
    "scenes\hit_music\template",
    "scenes\hit_music\carmine",

    "scripts\hit_music",
    "scripts\hit_music\core",
    "scripts\hit_music\configs",
    "scripts\hit_music\notes",
    "scripts\hit_music\playfield",
    "scripts\hit_music\effects",
    "scripts\hit_music\hud",
    "scripts\hit_music\services",

    "songs\carmine",
    "songs\carmine\charts"
)

foreach ($dir in $directories) {
    Ensure-Directory $dir
}

# ---------------------------------------------------------------------
# CONFIGURACOES
# ---------------------------------------------------------------------

Write-Utf8NoBom (Project-Path "scripts\hit_music\configs\hit_music_difficulty_config.gd") @'
class_name HitMusicDifficultyConfig
extends Resource

@export_enum("FACIL", "DIFICIL")
var nome: String = "FACIL"

@export_file("*.json")
var chart_path: String = ""

@export_group("Jogabilidade")
@export_range(0.50, 2.00, 0.01)
var tempo_aproximacao: float = 1.10

@export_range(0.05, 0.40, 0.005)
var janela_acerto: float = 0.20

@export_range(0.02, 0.20, 0.005)
var janela_perfeito: float = 0.075

@export_range(1, 4, 1)
var max_notas_simultaneas: int = 2

@export_group("Visual")
@export_range(0.50, 1.50, 0.01)
var escala_tap: float = 1.0

@export_range(0.50, 1.50, 0.01)
var escala_estrela: float = 1.0

@export_range(0.50, 1.50, 0.01)
var largura_hold: float = 1.0

@export_range(0.50, 2.00, 0.01)
var velocidade_slide: float = 1.0

@export_range(0.0, 1.0, 0.01)
var intensidade_fundo: float = 0.18

@export_range(0.0, 2.0, 0.01)
var velocidade_fundo: float = 0.50

@export_group("Combinacoes")
@export var permitir_slides_cruzados: bool = false
@export var permitir_slides_curvos: bool = true
@export var permitir_duplas: bool = false
@export var permitir_hold_com_slide: bool = false
'@

Write-Utf8NoBom (Project-Path "scripts\hit_music\configs\hit_music_song_config.gd") @'
class_name HitMusicSongConfig
extends Resource

@export_group("Identificacao")
@export var id: String = ""
@export var nome: String = ""
@export var artista: String = ""

@export_group("Arquivos")
@export_file var musica_path: String = ""
@export_file var imagem_capa_path: String = ""
@export_file var video_contagem_path: String = ""
@export_file var video_fundo_path: String = ""
@export_file var video_preview_path: String = ""

@export_group("Tema")
@export var cor_primaria: Color = Color.WHITE
@export var cor_secundaria: Color = Color.WHITE
@export var cor_slide: Color = Color(0.0, 0.95, 1.0, 1.0)
@export var cor_hold: Color = Color(1.0, 0.84, 0.05, 1.0)

@export_enum(
	"NENHUM",
	"LOSANGOS",
	"HEXAGONOS",
	"QUADRADOS",
	"LINHAS TECNICAS",
	"COLMEIA",
	"RADIAL"
)
var padrao_fundo_principal: String = "LOSANGOS"

@export_enum(
	"NENHUM",
	"LOSANGOS",
	"HEXAGONOS",
	"QUADRADOS",
	"LINHAS TECNICAS",
	"COLMEIA",
	"RADIAL"
)
var padrao_fundo_secundario: String = "HEXAGONOS"

@export_group("Dificuldades")
@export var facil: HitMusicDifficultyConfig
@export var dificil: HitMusicDifficultyConfig
'@

# ---------------------------------------------------------------------
# LAYOUT E CAMPO
# ---------------------------------------------------------------------

Write-Utf8NoBom (Project-Path "scripts\hit_music\playfield\playfield_layout.gd") @'
class_name HitMusicPlayfieldLayout
extends RefCounted

const NUM_LANES: int = 8
const CIRCLE_WIDTH_RATIO: float = 0.970
const TOP_RESERVED_RATIO: float = 0.255
const BOTTOM_MARGIN_RATIO: float = 0.012
const SIDE_MARGIN_RATIO: float = 0.015
const LANE_RADIUS_RATIO: float = 0.905

static func calculate(viewport_size: Vector2) -> Dictionary:
	var reference: float = minf(viewport_size.x, viewport_size.y)
	var side_margin: float = maxf(4.0, reference * SIDE_MARGIN_RATIO)
	var bottom_margin: float = maxf(4.0, viewport_size.y * BOTTOM_MARGIN_RATIO)
	var top_reserved: float = viewport_size.y * TOP_RESERVED_RATIO

	var radius_by_width: float = (viewport_size.x - side_margin * 2.0) * 0.5
	var radius_by_height: float = (viewport_size.y - top_reserved - bottom_margin) * 0.5
	var radius: float = maxf(120.0, minf(radius_by_width, radius_by_height) * CIRCLE_WIDTH_RATIO)

	var center := Vector2(
		viewport_size.x * 0.5,
		viewport_size.y - bottom_margin - radius
	)

	var lane_positions := PackedVector2Array()
	for lane in range(NUM_LANES):
		var angle: float = -PI * 0.5 + TAU * float(lane) / float(NUM_LANES)
		lane_positions.append(
			center + Vector2(cos(angle), sin(angle)) * radius * LANE_RADIUS_RATIO
		)

	return {
		"center": center,
		"radius": radius,
		"lane_positions": lane_positions,
	}
'@

Write-Utf8NoBom (Project-Path "scripts\hit_music\playfield\lane_ring_renderer.gd") @'
class_name HitMusicLaneRingRenderer
extends Node2D

const NUM_LANES: int = 8

var center: Vector2 = Vector2.ZERO
var radius: float = 100.0
var lane_positions: PackedVector2Array = PackedVector2Array()

func configure(layout: Dictionary) -> void:
	center = layout.get("center", Vector2.ZERO)
	radius = float(layout.get("radius", 100.0))
	lane_positions = layout.get("lane_positions", PackedVector2Array())
	queue_redraw()

func _draw() -> void:
	var ring_radius: float = radius * 0.905
	var ring_width: float = maxf(3.0, radius * 0.0065)
	var marker_radius: float = maxf(6.0, radius * 0.022)

	# Halo discreto, sem particulas e sem segmentos.
	draw_arc(
		center,
		ring_radius,
		0.0,
		TAU,
		192,
		Color(1.0, 1.0, 1.0, 0.10),
		ring_width * 3.2,
		true
	)

	# Linha continua que separa o preto do circulo.
	draw_arc(
		center,
		ring_radius,
		0.0,
		TAU,
		192,
		Color.WHITE,
		ring_width,
		true
	)

	# Oito bolinhas fixas. Nunca sao tazos ou notas.
	for lane in range(mini(NUM_LANES, lane_positions.size())):
		var pos: Vector2 = lane_positions[lane]
		draw_circle(pos, marker_radius * 1.65, Color(1.0, 1.0, 1.0, 0.09), true)
		draw_circle(pos, marker_radius, Color.WHITE, true)
'@

Write-Utf8NoBom (Project-Path "scripts\hit_music\playfield\background_theme_renderer.gd") @'
class_name HitMusicBackgroundThemeRenderer
extends Node2D

var center: Vector2 = Vector2.ZERO
var radius: float = 100.0
var primary_color: Color = Color.WHITE
var secondary_color: Color = Color.WHITE
var pattern_primary: String = "LOSANGOS"
var pattern_secondary: String = "HEXAGONOS"
var intensity: float = 0.18
var speed: float = 0.5
var song_time: float = 0.0

func configure(
	layout: Dictionary,
	song: HitMusicSongConfig,
	difficulty: HitMusicDifficultyConfig
) -> void:
	center = layout.get("center", Vector2.ZERO)
	radius = float(layout.get("radius", 100.0))
	primary_color = song.cor_primaria
	secondary_color = song.cor_secundaria
	pattern_primary = song.padrao_fundo_principal
	pattern_secondary = song.padrao_fundo_secundario
	intensity = difficulty.intensidade_fundo
	speed = difficulty.velocidade_fundo
	queue_redraw()

func set_song_time(value: float) -> void:
	song_time = value
	queue_redraw()

func _draw() -> void:
	_draw_base()
	var section: int = int(floor(song_time / 16.0)) % 2
	var pattern: String = pattern_primary if section == 0 else pattern_secondary
	match pattern:
		"LOSANGOS":
			_draw_diamonds()
		"HEXAGONOS", "COLMEIA":
			_draw_hexagons()
		"QUADRADOS":
			_draw_squares()
		"RADIAL":
			_draw_radial()
		"LINHAS TECNICAS":
			_draw_technical_lines()

func _draw_base() -> void:
	draw_circle(center, radius * 0.995, Color(0.005, 0.008, 0.018, 1.0), true)

func _draw_diamonds() -> void:
	var rotation: float = song_time * speed * 0.08
	for ring in range(2, 6):
		var r: float = radius * (0.16 + float(ring) * 0.12)
		for i in range(8):
			var angle: float = rotation + TAU * float(i) / 8.0
			var pos: Vector2 = center + Vector2(cos(angle), sin(angle)) * r
			var size: float = radius * (0.034 + float(ring) * 0.002)
			var points := PackedVector2Array([
				pos + Vector2(0, -size),
				pos + Vector2(size, 0),
				pos + Vector2(0, size),
				pos + Vector2(-size, 0),
				pos + Vector2(0, -size),
			])
			draw_polyline(
				points,
				Color(primary_color.r, primary_color.g, primary_color.b, intensity * 0.42),
				maxf(1.0, radius * 0.002),
				true
			)

func _draw_hexagons() -> void:
	var rotation: float = -song_time * speed * 0.05
	for ring in range(2, 5):
		var r: float = radius * (0.18 + float(ring) * 0.14)
		for i in range(6):
			var angle: float = rotation + TAU * float(i) / 6.0
			var pos: Vector2 = center + Vector2(cos(angle), sin(angle)) * r
			var points := PackedVector2Array()
			var size: float = radius * 0.055
			for p in range(7):
				var a: float = TAU * float(p) / 6.0
				points.append(pos + Vector2(cos(a), sin(a)) * size)
			draw_polyline(
				points,
				Color(secondary_color.r, secondary_color.g, secondary_color.b, intensity * 0.38),
				maxf(1.0, radius * 0.002),
				true
			)

func _draw_squares() -> void:
	var rotation: float = song_time * speed * 0.06
	for i in range(12):
		var angle: float = rotation + TAU * float(i) / 12.0
		var pos: Vector2 = center + Vector2(cos(angle), sin(angle)) * radius * 0.54
		var size: float = radius * 0.045
		var rect := Rect2(pos - Vector2.ONE * size, Vector2.ONE * size * 2.0)
		draw_rect(
			rect,
			Color(primary_color.r, primary_color.g, primary_color.b, intensity * 0.30),
			false,
			maxf(1.0, radius * 0.002)
		)

func _draw_radial() -> void:
	var rotation: float = song_time * speed * 0.12
	for i in range(24):
		var angle: float = rotation + TAU * float(i) / 24.0
		var direction := Vector2(cos(angle), sin(angle))
		draw_line(
			center + direction * radius * 0.18,
			center + direction * radius * 0.72,
			Color(primary_color.r, primary_color.g, primary_color.b, intensity * 0.18),
			maxf(1.0, radius * 0.0015),
			true
		)

func _draw_technical_lines() -> void:
	for i in range(8):
		var angle: float = -PI * 0.5 + TAU * float(i) / 8.0
		var direction := Vector2(cos(angle), sin(angle))
		draw_dashed_line(
			center + direction * radius * 0.12,
			center + direction * radius * 0.75,
			Color(secondary_color.r, secondary_color.g, secondary_color.b, intensity * 0.28),
			maxf(1.0, radius * 0.002),
			radius * 0.015,
			true
		)
'@

# ---------------------------------------------------------------------
# NOTAS
# ---------------------------------------------------------------------

Write-Utf8NoBom (Project-Path "scripts\hit_music\notes\note_base.gd") @'
class_name HitMusicNoteBase
extends Node2D

enum NoteState {
	SCHEDULED,
	APPROACHING,
	ACTIVE,
	HIT,
	MISSED,
	FINISHED,
}

var event_data: Dictionary = {}
var state: NoteState = NoteState.SCHEDULED
var hit_time: float = 0.0
var end_time: float = 0.0
var approach_time: float = 1.0
var origin: Vector2 = Vector2.ZERO
var target: Vector2 = Vector2.ZERO
var resolved: bool = false

func configure(
	data: Dictionary,
	new_origin: Vector2,
	new_target: Vector2,
	difficulty: HitMusicDifficultyConfig
) -> void:
	event_data = data
	origin = new_origin
	target = new_target
	hit_time = float(data.get("time", 0.0))
	end_time = float(data.get("end_time", hit_time))
	approach_time = difficulty.tempo_aproximacao
	position = origin
	state = NoteState.APPROACHING

func update_note(song_time: float) -> void:
	pass

func hit() -> void:
	resolved = true
	state = NoteState.HIT
	queue_free()

func miss() -> void:
	resolved = true
	state = NoteState.MISSED
	queue_free()
'@

Write-Utf8NoBom (Project-Path "scripts\hit_music\notes\tap_note.gd") @'
class_name HitMusicTapNote
extends HitMusicNoteBase

const TAZO_SCENE: PackedScene = preload("res://entities/tazo.tscn")

var visual_tazo: Node2D
var scale_multiplier: float = 1.0

func _ready() -> void:
	var instance: Node = TAZO_SCENE.instantiate()
	if not instance is Node2D:
		push_error("A raiz de res://entities/tazo.tscn precisa ser Node2D.")
		instance.queue_free()
		return

	visual_tazo = instance as Node2D
	visual_tazo.position = Vector2.ZERO
	visual_tazo.rotation = 0.0
	add_child(visual_tazo)

func configure(
	data: Dictionary,
	new_origin: Vector2,
	new_target: Vector2,
	difficulty: HitMusicDifficultyConfig
) -> void:
	super.configure(data, new_origin, new_target, difficulty)
	scale_multiplier = difficulty.escala_tap

func update_note(song_time: float) -> void:
	if resolved:
		return

	var start_time: float = hit_time - approach_time
	var progress: float = clampf(
		(song_time - start_time) / maxf(approach_time, 0.001),
		0.0,
		1.0
	)
	var eased: float = 1.0 - pow(1.0 - progress, 4.0)
	position = origin.lerp(target, eased)

	var visual_scale: float = lerpf(0.72, 1.0, eased) * scale_multiplier
	scale = Vector2.ONE * visual_scale

	if song_time > hit_time + 0.35:
		miss()
'@

Write-Utf8NoBom (Project-Path "scripts\hit_music\notes\hold_note.gd") @'
class_name HitMusicHoldNote
extends HitMusicNoteBase

var color: Color = Color(1.0, 0.84, 0.05, 1.0)
var width_multiplier: float = 1.0
var current_song_time: float = 0.0
var pressed: bool = false

func configure(
	data: Dictionary,
	new_origin: Vector2,
	new_target: Vector2,
	difficulty: HitMusicDifficultyConfig
) -> void:
	super.configure(data, new_origin, new_target, difficulty)
	width_multiplier = difficulty.largura_hold
	queue_redraw()

func set_pressed(value: bool) -> void:
	pressed = value
	queue_redraw()

func update_note(song_time: float) -> void:
	if resolved:
		return

	current_song_time = song_time
	var start_time: float = hit_time - approach_time
	var arrival: float = clampf(
		(song_time - start_time) / maxf(approach_time, 0.001),
		0.0,
		1.0
	)
	position = origin.lerp(target, 1.0 - pow(1.0 - arrival, 4.0))
	queue_redraw()

	if song_time > end_time + 0.25:
		miss()

func _draw() -> void:
	var direction: Vector2 = (target - origin).normalized()
	var local_direction: Vector2 = direction
	var lateral := Vector2(-local_direction.y, local_direction.x)

	var duration: float = maxf(end_time - hit_time, 0.001)
	var progress: float = (
		clampf((current_song_time - hit_time) / duration, 0.0, 1.0)
		if current_song_time >= hit_time
		else 0.0
	)
	var remaining: float = 1.0 - progress
	var length: float = maxf(28.0, target.distance_to(origin) * 0.48 * remaining)
	var width: float = maxf(18.0, target.distance_to(origin) * 0.060 * width_multiplier)
	var back: Vector2 = -local_direction * length
	var front: Vector2 = Vector2.ZERO

	var a0: Vector2 = back + lateral * width
	var a1: Vector2 = front + lateral * width
	var b0: Vector2 = back - lateral * width
	var b1: Vector2 = front - lateral * width

	var active_color: Color = color.lerp(Color.WHITE, 0.12 if pressed else 0.0)
	var glow_alpha: float = 0.24 if pressed else 0.13

	draw_line(a0, a1, Color(color.r, color.g, color.b, glow_alpha), width * 0.90, true)
	draw_line(b0, b1, Color(color.r, color.g, color.b, glow_alpha), width * 0.90, true)

	draw_line(a0, a1, active_color, maxf(4.0, width * 0.22), true)
	draw_line(b0, b1, active_color, maxf(4.0, width * 0.22), true)

	draw_arc(
		front,
		width,
		-local_direction.angle() - PI * 0.5,
		-local_direction.angle() + PI * 0.5,
		32,
		Color.WHITE,
		maxf(4.0, width * 0.22),
		true
	)
	draw_arc(
		back,
		width,
		local_direction.angle() - PI * 0.5,
		local_direction.angle() + PI * 0.5,
		32,
		active_color,
		maxf(4.0, width * 0.22),
		true
	)

	draw_circle(front, width * 0.35, Color(0.015, 0.020, 0.035, 0.96), true)
	draw_arc(front, width * 0.35, 0.0, TAU, 28, active_color, maxf(2.0, width * 0.10), true)
'@

Write-Utf8NoBom (Project-Path "scripts\hit_music\notes\slide_note.gd") @'
class_name HitMusicSlideNote
extends HitMusicNoteBase

var path_points: PackedVector2Array = PackedVector2Array()
var slide_color: Color = Color(0.0, 0.95, 1.0, 1.0)
var star_scale: float = 1.0
var current_song_time: float = 0.0

func configure_slide(
	data: Dictionary,
	points: PackedVector2Array,
	difficulty: HitMusicDifficultyConfig,
	color: Color
) -> void:
	event_data = data
	path_points = points
	hit_time = float(data.get("time", 0.0))
	end_time = float(data.get("end_time", hit_time + 1.0))
	approach_time = difficulty.tempo_aproximacao
	star_scale = difficulty.escala_estrela
	slide_color = color
	state = NoteState.APPROACHING
	queue_redraw()

func update_note(song_time: float) -> void:
	if resolved:
		return
	current_song_time = song_time
	queue_redraw()
	if song_time > end_time + 0.35:
		miss()

func _draw() -> void:
	if path_points.size() < 2:
		return

	var width: float = 24.0
	for index in range(path_points.size() - 1):
		var a: Vector2 = path_points[index]
		var b: Vector2 = path_points[index + 1]
		var segment: Vector2 = b - a
		var length: float = segment.length()
		if length <= 0.001:
			continue

		var direction: Vector2 = segment / length
		var perpendicular := Vector2(-direction.y, direction.x)
		var count: int = maxi(4, int(length / 38.0))

		for i in range(count):
			var t: float = (float(i) + 0.5) / float(count)
			var center_point: Vector2 = a.lerp(b, t)
			_draw_chevron(center_point, direction, perpendicular, width)

	var duration: float = maxf(end_time - hit_time, 0.001)
	var progress: float = clampf(
		(current_song_time - hit_time) / duration,
		0.0,
		1.0
	)
	var star_position: Vector2 = _sample_polyline(progress)
	_draw_star(star_position, width * 1.45 * star_scale)

func _draw_chevron(
	center_point: Vector2,
	direction: Vector2,
	perpendicular: Vector2,
	width: float
) -> void:
	var length: float = width * 1.55
	var opening: float = width * 0.72
	var tip: Vector2 = center_point + direction * length * 0.50
	var base: Vector2 = center_point - direction * length * 0.42
	var top: Vector2 = base + perpendicular * opening
	var bottom: Vector2 = base - perpendicular * opening

	var shadow_offset := Vector2(4.0, 5.0)
	var shadow := PackedVector2Array([
		bottom + shadow_offset,
		tip + shadow_offset,
		top + shadow_offset,
	])
	var body := PackedVector2Array([bottom, tip, top])

	draw_polyline(shadow, Color(0.0, 0.0, 0.0, 0.92), maxf(8.0, width * 0.38), true)
	draw_polyline(body, Color(slide_color.r, slide_color.g, slide_color.b, 0.98), maxf(7.0, width * 0.30), true)
	draw_polyline(body, Color(0.72, 1.0, 1.0, 0.94), maxf(2.0, width * 0.075), true)

func _draw_star(pos: Vector2, radius: float) -> void:
	var exterior := _star_polygon(radius, radius * 0.46)
	var interior := _star_polygon(radius * 0.55, radius * 0.24)
	for i in range(exterior.size()):
		exterior[i] += pos
	for i in range(interior.size()):
		interior[i] += pos
	exterior.append(exterior[0])
	interior.append(interior[0])

	draw_polyline(exterior, Color(0.0, 0.0, 0.0, 0.75), maxf(10.0, radius * 0.22), true)
	draw_polyline(exterior, Color.WHITE, maxf(5.0, radius * 0.12), true)
	draw_polyline(interior, slide_color, maxf(4.0, radius * 0.10), true)

func _star_polygon(outer_radius: float, inner_radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(10):
		var angle: float = -PI * 0.5 + PI * float(i) / 5.0
		var radius: float = outer_radius if i % 2 == 0 else inner_radius
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points

func _sample_polyline(progress: float) -> Vector2:
	var lengths: Array[float] = []
	var total: float = 0.0
	for i in range(path_points.size() - 1):
		var length: float = path_points[i].distance_to(path_points[i + 1])
		lengths.append(length)
		total += length

	var target_distance: float = total * clampf(progress, 0.0, 1.0)
	var accumulated: float = 0.0
	for i in range(lengths.size()):
		var length: float = lengths[i]
		if target_distance <= accumulated + length:
			var local_progress: float = (target_distance - accumulated) / maxf(length, 0.001)
			return path_points[i].lerp(path_points[i + 1], local_progress)
		accumulated += length

	return path_points[path_points.size() - 1]
'@

# ---------------------------------------------------------------------
# EFEITOS
# ---------------------------------------------------------------------

Write-Utf8NoBom (Project-Path "scripts\hit_music\effects\diamond_hit_effect.gd") @'
class_name HitMusicDiamondHitEffect
extends Node2D

var color: Color = Color.WHITE
var life: float = 0.0
var duration: float = 0.32
var base_size: float = 80.0

func configure(effect_color: Color, size: float) -> void:
	color = effect_color
	base_size = size
	queue_redraw()

func _process(delta: float) -> void:
	life += delta
	if life >= duration:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var t: float = clampf(life / duration, 0.0, 1.0)
	var scale_value: float = lerpf(0.12, 1.12, 1.0 - pow(1.0 - t, 4.0))
	var alpha: float = 1.0 - t
	for layer in range(3):
		var size: float = base_size * scale_value * (1.0 - float(layer) * 0.18)
		var points := PackedVector2Array([
			Vector2(0, -size),
			Vector2(size, 0),
			Vector2(0, size),
			Vector2(-size, 0),
			Vector2(0, -size),
		])
		var layer_color: Color = Color.WHITE.lerp(color, 0.30 + float(layer) * 0.25)
		draw_polyline(
			points,
			Color(layer_color.r, layer_color.g, layer_color.b, alpha * (0.98 - float(layer) * 0.12)),
			maxf(3.0, base_size * (0.055 - float(layer) * 0.010)),
			true
		)
'@

Write-Utf8NoBom (Project-Path "scripts\hit_music\effects\hit_effect_manager.gd") @'
class_name HitMusicHitEffectManager
extends Node2D

const DIAMOND_SCRIPT: Script = preload("res://scripts/hit_music/effects/diamond_hit_effect.gd")

var playfield_radius: float = 500.0

func configure(radius: float) -> void:
	playfield_radius = radius

func spawn_tap_hit(position_value: Vector2, color: Color) -> void:
	var effect := HitMusicDiamondHitEffect.new()
	effect.position = position_value
	effect.configure(color, playfield_radius * 0.115)
	add_child(effect)
'@

# ---------------------------------------------------------------------
# CORE
# ---------------------------------------------------------------------

Write-Utf8NoBom (Project-Path "scripts\hit_music\core\song_clock.gd") @'
class_name HitMusicSongClock
extends Node

var player: AudioStreamPlayer
var running: bool = false

func configure(audio_player: AudioStreamPlayer) -> void:
	player = audio_player

func start() -> void:
	if player == null:
		push_error("SongClock sem AudioStreamPlayer.")
		return
	player.play()
	running = true

func get_time() -> float:
	if not running or player == null:
		return 0.0
	var position_value: float = player.get_playback_position()
	position_value += AudioServer.get_time_since_last_mix()
	position_value -= AudioServer.get_output_latency()
	return maxf(position_value, 0.0)
'@

Write-Utf8NoBom (Project-Path "scripts\hit_music\core\chart_player.gd") @'
class_name HitMusicChartPlayer
extends Node

signal event_ready(event_data: Dictionary)

var events: Array[Dictionary] = []
var next_index: int = 0
var lookahead: float = 1.35

func load_chart(path: String) -> bool:
	events.clear()
	next_index = 0

	if path.is_empty() or not FileAccess.file_exists(path):
		push_error("Chart nao encontrado: " + path)
		return false

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Nao foi possivel abrir o chart: " + path)
		return false

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("Chart invalido: raiz precisa ser Dictionary.")
		return false

	var raw_events: Variant = (parsed as Dictionary).get("events", [])
	if not raw_events is Array:
		push_error("Chart invalido: events precisa ser Array.")
		return false

	for item in raw_events:
		if item is Dictionary:
			events.append((item as Dictionary).duplicate(true))

	events.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.get("time", 0.0)) < float(b.get("time", 0.0))
	)
	return true

func update_chart(song_time: float) -> void:
	while next_index < events.size():
		var event_data: Dictionary = events[next_index]
		var event_time: float = float(event_data.get("time", 0.0))
		if event_time - song_time > lookahead:
			break
		event_ready.emit(event_data)
		next_index += 1
'@

Write-Utf8NoBom (Project-Path "scripts\hit_music\core\input_router.gd") @'
class_name HitMusicInputRouter
extends Node

signal lane_pressed(lane: int)
signal lane_released(lane: int)
signal pointer_pressed(pointer_id: int, position_value: Vector2)
signal pointer_moved(pointer_id: int, position_value: Vector2)
signal pointer_released(pointer_id: int, position_value: Vector2)

const INPUTS: Array[String] = [
	"input_a",
	"input_b",
	"input_c",
	"input_d",
	"input_e",
	"input_f",
	"input_g",
	"input_h",
]

func _process(_delta: float) -> void:
	for lane in range(INPUTS.size()):
		var action: String = INPUTS[lane]
		if not InputMap.has_action(action):
			continue
		if Input.is_action_just_pressed(action):
			lane_pressed.emit(lane)
		if Input.is_action_just_released(action):
			lane_released.emit(lane)

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			pointer_pressed.emit(event.index, event.position)
		else:
			pointer_released.emit(event.index, event.position)
	elif event is InputEventScreenDrag:
		pointer_moved.emit(event.index, event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			pointer_pressed.emit(-1, event.position)
		else:
			pointer_released.emit(-1, event.position)
	elif event is InputEventMouseMotion:
		pointer_moved.emit(-1, event.position)
'@

Write-Utf8NoBom (Project-Path "scripts\hit_music\core\judgement_system.gd") @'
class_name HitMusicJudgementSystem
extends Node

signal tap_judged(note: HitMusicTapNote, judgement: String)

var difficulty: HitMusicDifficultyConfig

func configure(config: HitMusicDifficultyConfig) -> void:
	difficulty = config

func judge_lane(
	lane: int,
	song_time: float,
	active_taps: Array[HitMusicTapNote]
) -> void:
	if difficulty == null:
		return

	var best_note: HitMusicTapNote
	var best_difference: float = INF

	for note in active_taps:
		if note == null or not is_instance_valid(note) or note.resolved:
			continue
		if int(note.event_data.get("lane", -1)) != lane:
			continue
		var difference: float = absf(song_time - note.hit_time)
		if difference < best_difference:
			best_difference = difference
			best_note = note

	if best_note == null or best_difference > difficulty.janela_acerto:
		return

	var judgement: String = (
		"PERFECT"
		if best_difference <= difficulty.janela_perfeito
		else "GOOD"
	)
	tap_judged.emit(best_note, judgement)
'@

Write-Utf8NoBom (Project-Path "scripts\hit_music\core\note_manager.gd") @'
class_name HitMusicNoteManager
extends Node2D

signal tap_hit(position_value: Vector2, color: Color)

const TAP_SCRIPT: Script = preload("res://scripts/hit_music/notes/tap_note.gd")
const HOLD_SCRIPT: Script = preload("res://scripts/hit_music/notes/hold_note.gd")
const SLIDE_SCRIPT: Script = preload("res://scripts/hit_music/notes/slide_note.gd")

var layout: Dictionary = {}
var difficulty: HitMusicDifficultyConfig
var song: HitMusicSongConfig
var active_taps: Array[HitMusicTapNote] = []
var active_notes: Array[HitMusicNoteBase] = []

func configure(
	new_layout: Dictionary,
	new_song: HitMusicSongConfig,
	new_difficulty: HitMusicDifficultyConfig
) -> void:
	layout = new_layout
	song = new_song
	difficulty = new_difficulty

func spawn_event(event_data: Dictionary) -> void:
	var event_type: String = str(event_data.get("type", "tap")).to_lower()
	match event_type:
		"tap":
			_spawn_tap(event_data)
		"hold":
			_spawn_hold(event_data)
		"slide":
			_spawn_slide(event_data)

func update_notes(song_time: float) -> void:
	for note in active_notes.duplicate():
		if note == null or not is_instance_valid(note):
			active_notes.erase(note)
			continue
		note.update_note(song_time)

	for note in active_taps.duplicate():
		if note == null or not is_instance_valid(note):
			active_taps.erase(note)

func resolve_tap(note: HitMusicTapNote, judgement: String) -> void:
	if note == null or not is_instance_valid(note):
		return
	var lane: int = int(note.event_data.get("lane", -1))
	var positions: PackedVector2Array = layout.get("lane_positions", PackedVector2Array())
	if lane >= 0 and lane < positions.size():
		tap_hit.emit(positions[lane], song.cor_primaria if judgement == "PERFECT" else song.cor_secundaria)
	note.hit()

func _spawn_tap(event_data: Dictionary) -> void:
	var lane: int = int(event_data.get("lane", -1))
	var positions: PackedVector2Array = layout.get("lane_positions", PackedVector2Array())
	if lane < 0 or lane >= positions.size():
		push_warning("Tap com lane invalida: " + str(lane))
		return

	var note := HitMusicTapNote.new()
	add_child(note)
	note.configure(
		event_data,
		layout.get("center", Vector2.ZERO),
		positions[lane],
		difficulty
	)
	active_notes.append(note)
	active_taps.append(note)

func _spawn_hold(event_data: Dictionary) -> void:
	var lane: int = int(event_data.get("lane", -1))
	var positions: PackedVector2Array = layout.get("lane_positions", PackedVector2Array())
	if lane < 0 or lane >= positions.size():
		return

	var note := HitMusicHoldNote.new()
	add_child(note)
	note.color = song.cor_hold
	note.configure(
		event_data,
		layout.get("center", Vector2.ZERO),
		positions[lane],
		difficulty
	)
	active_notes.append(note)

func _spawn_slide(event_data: Dictionary) -> void:
	var positions: PackedVector2Array = layout.get("lane_positions", PackedVector2Array())
	var center: Vector2 = layout.get("center", Vector2.ZERO)
	var path := PackedVector2Array()

	var raw_path: Variant = event_data.get("path", [])
	if raw_path is Array and not (raw_path as Array).is_empty():
		for raw_point in raw_path:
			if raw_point is Array and (raw_point as Array).size() >= 2:
				var point_array: Array = raw_point as Array
				path.append(
					center + Vector2(
						float(point_array[0]),
						float(point_array[1])
					) * float(layout.get("radius", 100.0))
				)
	else:
		var start_lane: int = int(event_data.get("start_lane", 0))
		var end_lane: int = int(event_data.get("end_lane", 4))
		if start_lane >= 0 and start_lane < positions.size():
			path.append(positions[start_lane])
		path.append(center)
		if end_lane >= 0 and end_lane < positions.size():
			path.append(positions[end_lane])

	var note := HitMusicSlideNote.new()
	add_child(note)
	note.configure_slide(event_data, path, difficulty, song.cor_slide)
	active_notes.append(note)
'@

Write-Utf8NoBom (Project-Path "scripts\hit_music\core\hit_music_game.gd") @'
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
'@

# ---------------------------------------------------------------------
# SERVICO DE LED - BASE SEGURA PARA AUTOLOAD
# ---------------------------------------------------------------------

Write-Utf8NoBom (Project-Path "scripts\hit_music\services\led_service.gd") @'
class_name HitMusicLedService
extends Node

signal state_changed(colors: Array[Color])

const NUM_LANES: int = 8
var desired_colors: Array[Color] = []
var revision: int = 0

func _ready() -> void:
	desired_colors.resize(NUM_LANES)
	clear_all()

func set_lane_color(lane: int, color: Color) -> void:
	if lane < 0 or lane >= NUM_LANES:
		return
	desired_colors[lane] = color
	revision += 1
	state_changed.emit(desired_colors.duplicate())

func clear_lane(lane: int) -> void:
	set_lane_color(lane, Color.BLACK)

func clear_all() -> void:
	if desired_colors.size() != NUM_LANES:
		desired_colors.resize(NUM_LANES)
	for lane in range(NUM_LANES):
		desired_colors[lane] = Color.BLACK
	revision += 1
	state_changed.emit(desired_colors.duplicate())

func create_snapshot_command() -> String:
	var values: PackedStringArray = PackedStringArray()
	values.append("STATE")
	values.append(str(revision))
	for color in desired_colors:
		values.append(str(int(round(clampf(color.r, 0.0, 1.0) * 255.0))))
		values.append(str(int(round(clampf(color.g, 0.0, 1.0) * 255.0))))
		values.append(str(int(round(clampf(color.b, 0.0, 1.0) * 255.0))))
	return " ".join(values)
'@

# ---------------------------------------------------------------------
# HUD MINIMO
# ---------------------------------------------------------------------

Write-Utf8NoBom (Project-Path "scripts\hit_music\hud\gameplay_hud.gd") @'
class_name HitMusicGameplayHud
extends Control

@onready var title_label: Label = $Panel/Title
@onready var difficulty_label: Label = $Panel/Difficulty

func configure(song: HitMusicSongConfig, difficulty: HitMusicDifficultyConfig) -> void:
	title_label.text = song.nome
	difficulty_label.text = difficulty.nome
'@

# ---------------------------------------------------------------------
# RESOURCES
# ---------------------------------------------------------------------

Write-Utf8NoBom (Project-Path "scripts\hit_music\configs\carmine_facil.tres") @'
[gd_resource type="Resource" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/hit_music/configs/hit_music_difficulty_config.gd" id="1"]

[resource]
script = ExtResource("1")
nome = "FACIL"
chart_path = "res://songs/carmine/charts/facil.json"
tempo_aproximacao = 1.2
janela_acerto = 0.24
janela_perfeito = 0.09
max_notas_simultaneas = 1
escala_tap = 1.08
escala_estrela = 1.05
largura_hold = 1.08
velocidade_slide = 0.88
intensidade_fundo = 0.12
velocidade_fundo = 0.36
permitir_slides_cruzados = false
permitir_slides_curvos = true
permitir_duplas = false
permitir_hold_com_slide = false
'@

Write-Utf8NoBom (Project-Path "scripts\hit_music\configs\carmine_dificil.tres") @'
[gd_resource type="Resource" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/hit_music/configs/hit_music_difficulty_config.gd" id="1"]

[resource]
script = ExtResource("1")
nome = "DIFICIL"
chart_path = "res://songs/carmine/charts/dificil.json"
tempo_aproximacao = 0.88
janela_acerto = 0.16
janela_perfeito = 0.07
max_notas_simultaneas = 2
escala_tap = 0.94
escala_estrela = 1.0
largura_hold = 0.94
velocidade_slide = 1.18
intensidade_fundo = 0.22
velocidade_fundo = 0.72
permitir_slides_cruzados = true
permitir_slides_curvos = true
permitir_duplas = true
permitir_hold_com_slide = true
'@

Write-Utf8NoBom (Project-Path "scripts\hit_music\configs\carmine_config.tres") @'
[gd_resource type="Resource" load_steps=4 format=3]

[ext_resource type="Script" path="res://scripts/hit_music/configs/hit_music_song_config.gd" id="1"]
[ext_resource type="Resource" path="res://scripts/hit_music/configs/carmine_facil.tres" id="2"]
[ext_resource type="Resource" path="res://scripts/hit_music/configs/carmine_dificil.tres" id="3"]

[resource]
script = ExtResource("1")
id = "carmine"
nome = "CARMINE - ONE PIECE"
artista = "HIT MUSIC"
musica_path = "res://songs/carmine.mp3"
imagem_capa_path = "res://images/carmine.jpeg"
video_contagem_path = "res://medias/carmine.ogv"
video_fundo_path = "res://medias/carmine.ogv"
video_preview_path = "res://medias/carmine.ogv"
cor_primaria = Color(0.96, 0.025, 0.075, 1)
cor_secundaria = Color(1, 0.98, 0.98, 1)
cor_slide = Color(0.02, 0.94, 1, 1)
cor_hold = Color(1, 0.84, 0.05, 1)
padrao_fundo_principal = "LOSANGOS"
padrao_fundo_secundario = "HEXAGONOS"
facil = ExtResource("2")
dificil = ExtResource("3")
'@

# ---------------------------------------------------------------------
# CHARTS DE EXEMPLO
# ---------------------------------------------------------------------

Write-Utf8NoBom (Project-Path "songs\carmine\charts\facil.json") @'
{
  "song": "carmine",
  "difficulty": "easy",
  "bpm": 174.0,
  "offset": 0.0,
  "events": [
    { "type": "tap", "time": 2.0, "lane": 0 },
    { "type": "tap", "time": 3.0, "lane": 2 },
    { "type": "tap", "time": 4.0, "lane": 4 },
    { "type": "tap", "time": 5.0, "lane": 6 },
    { "type": "hold", "time": 6.2, "end_time": 7.8, "lane": 1 },
    {
      "type": "slide",
      "time": 9.0,
      "end_time": 10.6,
      "start_lane": 7,
      "end_lane": 3,
      "path": [
        [-0.62, -0.42],
        [-0.18, -0.08],
        [0.58, 0.40]
      ]
    }
  ]
}
'@

Write-Utf8NoBom (Project-Path "songs\carmine\charts\dificil.json") @'
{
  "song": "carmine",
  "difficulty": "hard",
  "bpm": 174.0,
  "offset": 0.0,
  "events": [
    { "type": "tap", "time": 1.6, "lane": 0 },
    { "type": "tap", "time": 1.9, "lane": 4 },
    { "type": "tap", "time": 2.3, "lane": 1 },
    { "type": "tap", "time": 2.6, "lane": 5 },
    { "type": "hold", "time": 3.3, "end_time": 5.0, "lane": 2 },
    {
      "type": "slide",
      "time": 3.7,
      "end_time": 5.2,
      "start_lane": 7,
      "end_lane": 3,
      "path": [
        [-0.64, -0.52],
        [0.22, -0.18],
        [-0.12, 0.26],
        [0.64, 0.52]
      ]
    },
    {
      "type": "slide",
      "time": 6.0,
      "end_time": 7.5,
      "start_lane": 1,
      "end_lane": 6,
      "path": [
        [0.52, -0.58],
        [-0.30, -0.06],
        [0.28, 0.18],
        [-0.52, 0.58]
      ]
    }
  ]
}
'@

# ---------------------------------------------------------------------
# SVGs
# ---------------------------------------------------------------------

Write-Utf8NoBom (Project-Path "images\hit_music\shared\slide_chevron.svg") @'
<svg xmlns="http://www.w3.org/2000/svg" width="180" height="120" viewBox="0 0 180 120">
  <path d="M18 15 L96 60 L18 105 L58 105 L136 60 L58 15 Z"
        fill="#12F2FF" stroke="#04121C" stroke-width="10" stroke-linejoin="round"/>
  <path d="M35 25 L96 60 L35 95"
        fill="none" stroke="#D9FFFF" stroke-width="5" stroke-linejoin="round"/>
</svg>
'@

Write-Utf8NoBom (Project-Path "images\hit_music\shared\slide_star_cyan.svg") @'
<svg xmlns="http://www.w3.org/2000/svg" width="240" height="240" viewBox="0 0 240 240">
  <path d="M120 15 L145 83 L218 86 L160 130 L179 201 L120 160 L61 201 L80 130 L22 86 L95 83 Z"
        fill="#07131E" stroke="#04121C" stroke-width="20" stroke-linejoin="round"/>
  <path d="M120 15 L145 83 L218 86 L160 130 L179 201 L120 160 L61 201 L80 130 L22 86 L95 83 Z"
        fill="none" stroke="#FFFFFF" stroke-width="11" stroke-linejoin="round"/>
  <path d="M120 48 L136 94 L184 96 L146 125 L158 171 L120 144 L82 171 L94 125 L56 96 L104 94 Z"
        fill="none" stroke="#12F2FF" stroke-width="12" stroke-linejoin="round"/>
</svg>
'@

Write-Utf8NoBom (Project-Path "images\hit_music\shared\slide_star_yellow.svg") @'
<svg xmlns="http://www.w3.org/2000/svg" width="240" height="240" viewBox="0 0 240 240">
  <path d="M120 15 L145 83 L218 86 L160 130 L179 201 L120 160 L61 201 L80 130 L22 86 L95 83 Z"
        fill="#171200" stroke="#120E00" stroke-width="20" stroke-linejoin="round"/>
  <path d="M120 15 L145 83 L218 86 L160 130 L179 201 L120 160 L61 201 L80 130 L22 86 L95 83 Z"
        fill="none" stroke="#FFFFFF" stroke-width="11" stroke-linejoin="round"/>
  <path d="M120 48 L136 94 L184 96 L146 125 L158 171 L120 144 L82 171 L94 125 L56 96 L104 94 Z"
        fill="none" stroke="#FFE529" stroke-width="12" stroke-linejoin="round"/>
</svg>
'@

# ---------------------------------------------------------------------
# SCENES
# ---------------------------------------------------------------------

Write-Utf8NoBom (Project-Path "scenes\hit_music\base\hit_music_base.tscn") @'
[gd_scene load_steps=11 format=3]

[ext_resource type="Script" path="res://scripts/hit_music/core/hit_music_game.gd" id="1"]
[ext_resource type="Script" path="res://scripts/hit_music/playfield/background_theme_renderer.gd" id="2"]
[ext_resource type="Script" path="res://scripts/hit_music/playfield/lane_ring_renderer.gd" id="3"]
[ext_resource type="Script" path="res://scripts/hit_music/core/note_manager.gd" id="4"]
[ext_resource type="Script" path="res://scripts/hit_music/effects/hit_effect_manager.gd" id="5"]
[ext_resource type="Script" path="res://scripts/hit_music/core/song_clock.gd" id="6"]
[ext_resource type="Script" path="res://scripts/hit_music/core/chart_player.gd" id="7"]
[ext_resource type="Script" path="res://scripts/hit_music/core/judgement_system.gd" id="8"]
[ext_resource type="Script" path="res://scripts/hit_music/core/input_router.gd" id="9"]

[node name="HitMusicGame" type="Node2D"]
script = ExtResource("1")

[node name="Background" type="Node2D" parent="."]

[node name="VideoBackground" type="VideoStreamPlayer" parent="Background"]
expand = true
loop = true

[node name="ThemeRenderer" type="Node2D" parent="Background"]
script = ExtResource("2")

[node name="Playfield" type="Node2D" parent="."]

[node name="RingRenderer" type="Node2D" parent="Playfield"]
z_index = 10
script = ExtResource("3")

[node name="Notes" type="Node2D" parent="Playfield"]
z_index = 20
script = ExtResource("4")

[node name="Effects" type="Node2D" parent="Playfield"]
z_index = 30
script = ExtResource("5")

[node name="Managers" type="Node" parent="."]

[node name="SongClock" type="Node" parent="Managers"]
script = ExtResource("6")

[node name="ChartPlayer" type="Node" parent="Managers"]
script = ExtResource("7")

[node name="JudgementSystem" type="Node" parent="Managers"]
script = ExtResource("8")

[node name="InputRouter" type="Node" parent="Managers"]
script = ExtResource("9")

[node name="Audio" type="Node" parent="."]

[node name="MusicPlayer" type="AudioStreamPlayer" parent="Audio"]
'@

Write-Utf8NoBom (Project-Path "scenes\hit_music\carmine\carmine.tscn") @'
[gd_scene load_steps=3 format=3]

[ext_resource type="PackedScene" path="res://scenes/hit_music/base/hit_music_base.tscn" id="1"]
[ext_resource type="Resource" path="res://scripts/hit_music/configs/carmine_config.tres" id="2"]

[node name="Carmine" instance=ExtResource("1")]
musica = ExtResource("2")
dificuldade_teste = "FACIL"
'@

Write-Utf8NoBom (Project-Path "scenes\hit_music\template\nova_musica_template.tscn") @'
[gd_scene load_steps=2 format=3]

[ext_resource type="PackedScene" path="res://scenes/hit_music/base/hit_music_base.tscn" id="1"]

[node name="NovaMusica" instance=ExtResource("1")]
dificuldade_teste = "FACIL"
'@

# ---------------------------------------------------------------------
# PROMPT PARA CONTINUAR COM UM AGENTE DE CODIGO
# ---------------------------------------------------------------------

Write-Utf8NoBom (Project-Path "PROMPT_CONTINUAR_REFACTORACAO_HIT_MUSIC.md") @'
# PROMPT - CONTINUAR A REFATORACAO HIT MUSIC R6

Trabalhe diretamente neste projeto Godot 4. Nao apague nem altere a versao antiga antes de a versao R6 funcionar.

## Estrutura criada

- `res://scenes/hit_music/base/hit_music_base.tscn`
- `res://scenes/hit_music/carmine/carmine.tscn`
- `res://scripts/hit_music/`
- `res://songs/carmine/charts/facil.json`
- `res://songs/carmine/charts/dificil.json`

## Regras obrigatorias

1. Preserve `res://entities/tazo.tscn`.
2. O tazo e somente a nota movel. Nunca deixe um tazo parado nos oito destinos.
3. A borda do campo e uma linha branca continua com oito bolinhas fixas.
4. Tap nasce no centro, viaja ate a bolinha e desaparece no julgamento.
5. Acerto normal usa tres losangos nitidos e deterministicos.
6. Slide usa chevrons grandes, solidos, ciano, proximos e com sombra preta.
7. A estrela do slide e grande, vazada, com contornos preto, branco e tematico.
8. Hold e uma capsula fechada, amarela, grossa e com centro escuro.
9. O fundo possui video retangular e overlays geometricos que mudam por secoes.
10. Facil e dificil usam charts JSON diferentes. Nao use apenas multiplicador de velocidade.
11. Nao adicione particulas aleatorias que prejudiquem a leitura.
12. Nao coloque codigo serial dentro da scene. Use um servico persistente com estado desejado.
13. Corrija erros de tipagem GDScript. O projeto trata warnings como erros.
14. Entregue arquivos completos, nao apenas trechos.
15. Antes de afirmar que funciona, valide parsing e referencias de paths.

## Proxima tarefa

Abra e valide:

`res://scenes/hit_music/carmine/carmine.tscn`

Corrija todos os erros de parsing/importacao e deixe a scene executavel. Depois:

- aplique mascara circular ao video;
- posicione o video como retangulo horizontal no centro do circulo;
- adicione selecao de dificuldade;
- implemente hold real;
- implemente slide por touch;
- faca o chart dificil possuir caminhos cruzados;
- mantenha o chart facil simples e legivel.
'@

# ---------------------------------------------------------------------
# GUIA
# ---------------------------------------------------------------------

Write-Utf8NoBom (Project-Path "MIGRACAO_HIT_MUSIC_R6.txt") @"
HIT MUSIC R6 - ARQUIVOS CRIADOS

Backup:
$createdBackupPath

NOVA SCENE PARA TESTAR:
res://scenes/hit_music/carmine/carmine.tscn

IMPORTANTE:
1. Nao apague sua scene antiga.
2. Abra o Godot e aguarde a importacao.
3. Execute a nova scene Carmine.
4. Caso o Godot mostre erro, envie a mensagem e a linha exata.
5. A nova versao usa os assets atuais:
   res://entities/tazo.tscn
   res://songs/carmine.mp3
   res://images/carmine.jpeg
   res://medias/carmine.ogv

TROCAR DIFICULDADE:
Abra:
res://scenes/hit_music/carmine/carmine.tscn

No Inspector do no raiz:
dificuldade_teste = FACIL ou DIFICIL

CRIAR NOVA MUSICA:
1. Duplique scripts/hit_music/configs/carmine_config.tres
2. Duplique carmine_facil.tres e carmine_dificil.tres
3. Crie songs/NOME/charts/facil.json e dificil.json
4. Duplique scenes/hit_music/template/nova_musica_template.tscn
5. Atribua o novo Resource de musica no Inspector.
"@

Write-Host ""
Write-Host "Estrutura criada com sucesso." -ForegroundColor Green
Write-Host ""
Write-Host "Nova scene:" -ForegroundColor Cyan
Write-Host "res://scenes/hit_music/carmine/carmine.tscn"
Write-Host ""
Write-Host "Backup:" -ForegroundColor Cyan
Write-Host $createdBackupPath
Write-Host ""
Write-Host "Abra o Godot, aguarde a importacao e execute a nova scene." -ForegroundColor Yellow
