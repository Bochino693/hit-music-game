extends RefCounted

const CATALOG_PATH: String = "res://data/hit_music_songs.json"

static func all_songs() -> Array:
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if file == null:
		push_error("Hit Music catalog not found: " + CATALOG_PATH)
		return []

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("Hit Music catalog root must be a Dictionary.")
		return []

	var raw_songs: Variant = (parsed as Dictionary).get("songs", [])
	if not raw_songs is Array:
		push_error("Hit Music catalog field 'songs' must be an Array.")
		return []

	var result: Array = []
	for raw_song in raw_songs:
		if not raw_song is Dictionary:
			continue
		var song: Dictionary = (raw_song as Dictionary).duplicate(true)
		_prepare_colors(song)
		result.append(song)
	return result


static func get_song(song_id: String) -> Dictionary:
	for song in all_songs():
		if str(song.get("id", "")) == song_id:
			return song
	return {}


static func get_difficulty(song: Dictionary, difficulty_name: String) -> Dictionary:
	var key: String = "hard" if difficulty_name.to_lower() == "hard" else "easy"
	var value: Variant = song.get(key, {})
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}


static func _prepare_colors(song: Dictionary) -> void:
	var colors_value: Variant = song.get("colors", {})
	if not colors_value is Dictionary:
		song["colors"] = {
			"primary": Color(0.05, 0.92, 1.0, 1.0),
			"secondary": Color.WHITE,
			"accent": Color(1.0, 0.84, 0.05, 1.0),
			"dark": Color(0.01, 0.02, 0.05, 1.0),
		}
		return

	var raw_colors: Dictionary = colors_value as Dictionary
	var prepared: Dictionary = {}
	prepared["primary"] = _color_from_value(raw_colors.get("primary", "#10E6F2"))
	prepared["secondary"] = _color_from_value(raw_colors.get("secondary", "#FFFFFF"))
	prepared["accent"] = _color_from_value(raw_colors.get("accent", "#FFE11A"))
	prepared["dark"] = _color_from_value(raw_colors.get("dark", "#020611"))
	song["colors"] = prepared


static func _color_from_value(value: Variant) -> Color:
	if value is Color:
		return value
	return Color.from_string(str(value), Color.WHITE)