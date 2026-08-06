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