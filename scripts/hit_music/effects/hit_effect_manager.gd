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