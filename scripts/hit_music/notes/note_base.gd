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