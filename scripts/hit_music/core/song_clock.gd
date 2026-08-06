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