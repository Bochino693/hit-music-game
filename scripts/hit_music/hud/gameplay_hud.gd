class_name HitMusicGameplayHud
extends Control

@onready var title_label: Label = $Panel/Title
@onready var difficulty_label: Label = $Panel/Difficulty

func configure(song: HitMusicSongConfig, difficulty: HitMusicDifficultyConfig) -> void:
	title_label.text = song.nome
	difficulty_label.text = difficulty.nome