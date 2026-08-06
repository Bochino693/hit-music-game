param(
    [Parameter(Mandatory = $true)][string]$Id,
    [Parameter(Mandatory = $true)][string]$Title,
    [Parameter(Mandatory = $true)][string]$Audio,
    [Parameter(Mandatory = $true)][string]$Video,
    [Parameter(Mandatory = $true)][string]$Cover,
    [double]$Bpm = 140.0,
    [string]$Primary = "#16E6F2",
    [string]$Secondary = "#FFFFFF",
    [string]$Accent = "#FFE11A",
    [string]$Pattern = "diamonds"
)

$ErrorActionPreference = "Stop"
$Root = (Get-Location).Path
$CatalogPath = Join-Path $Root "data\hit_music_songs.json"
if (-not (Test-Path $CatalogPath)) {
    throw "Run aplicar_hit_music_r7.ps1 first."
}

function Write-Utf8NoBom {
    param([string]$Path, [string]$Content)
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8)
}

$idClean = $Id.ToLower().Replace(" ", "_").Replace("-", "_")
$scenePath = "res://scenes/$idClean.tscn"
$scriptPath = "res://scripts/$idClean.gd"

$data = Get-Content -Raw -LiteralPath $CatalogPath | ConvertFrom-Json
if ($data.songs.id -contains $idClean) {
    throw "Song id already exists: $idClean"
}

$newSong = [ordered]@{
    id = $idClean
    title = $Title
    scene = $scenePath
    audio = $Audio
    video = $Video
    cover = $Cover
    bpm = $Bpm
    chart_start = 4.0
    seed = [Math]::Abs($idClean.GetHashCode())
    pattern = $Pattern
    colors = [ordered]@{
        primary = $Primary
        secondary = $Secondary
        accent = $Accent
        dark = "#050812"
    }
    lane_pattern_easy = @(0,2,4,6,1,3,5,7)
    lane_pattern_hard = @(0,4,1,5,2,6,3,7,0,3,6,1,4,7,2,5)
    slides_easy = @(
        [ordered]@{path=@(0,4);shape="straight"},
        [ordered]@{path=@(2,6);shape="arc_cw";curve=0.60}
    )
    slides_hard = @(
        [ordered]@{path=@(0,4);shape="cross"},
        [ordered]@{path=@(7,2,5);shape="zigzag"},
        [ordered]@{path=@(1,6);shape="hook";curve=0.75}
    )
    easy = [ordered]@{
        approach=1.12; hit_window=0.24; perfect_window=0.09; step_beats=2.0
        slide_every=9; hold_every=13; double_every=0; slide_beats=4.0
        hold_beats=4.0; tap_scale=1.08; star_scale=1.08; hold_width=1.10
        background_intensity=0.14; background_speed=0.16; jitter=0.01
    }
    hard = [ordered]@{
        approach=0.85; hit_window=0.16; perfect_window=0.065; step_beats=1.0
        slide_every=6; hold_every=10; double_every=5; double_distance=4
        slide_beats=3.0; hold_beats=3.0; tap_scale=0.97; star_scale=1.02
        hold_width=0.95; background_intensity=0.24; background_speed=0.32
        jitter=0.02
    }
}

$data.songs += [pscustomobject]$newSong
$json = $data | ConvertTo-Json -Depth 20
Write-Utf8NoBom $CatalogPath $json

$wrapper = @"
extends "res://scripts/hit_music_r7/stage.gd"

func _song_id() -> String:
    return "$idClean"
"@
Write-Utf8NoBom (Join-Path $Root "scripts\$idClean.gd") $wrapper

$scene = @"
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="$scriptPath" id="1"]

[node name="$Title" type="Node2D"]
script = ExtResource("1")
"@
Write-Utf8NoBom (Join-Path $Root "scenes\$idClean.tscn") $scene

git add "data/hit_music_songs.json" "scripts/$idClean.gd" "scenes/$idClean.tscn"
git commit -m "Add Hit Music song pack $idClean"

Write-Host "Song added: $idClean" -ForegroundColor Green
Write-Host "Scene: $scenePath"