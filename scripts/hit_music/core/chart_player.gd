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