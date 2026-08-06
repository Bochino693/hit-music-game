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