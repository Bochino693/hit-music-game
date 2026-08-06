extends RefCounted

static func build(song: Dictionary, difficulty_name: String, duration: float) -> Array:
	var profile_value: Variant = song.get(
		"hard" if difficulty_name.to_lower() == "hard" else "easy",
		{}
	)
	if not profile_value is Dictionary:
		return []

	var profile: Dictionary = profile_value as Dictionary
	var events: Array = []
	var bpm: float = maxf(float(song.get("bpm", 120.0)), 1.0)
	var beat: float = 60.0 / bpm
	var step_beats: float = maxf(float(profile.get("step_beats", 1.0)), 0.25)
	var step: float = beat * step_beats
	var start_time: float = maxf(float(song.get("chart_start", 4.0)), 3.2)
	var end_time: float = maxf(start_time + step, duration - 2.2)
	var seed_value: int = int(song.get("seed", 1001))
	if difficulty_name.to_lower() == "hard":
		seed_value += 100000

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var lane_pattern: Array = _array_value(
		song.get(
			"lane_pattern_hard" if difficulty_name.to_lower() == "hard" else "lane_pattern_easy",
			[0, 2, 4, 6, 1, 3, 5, 7]
		)
	)
	if lane_pattern.is_empty():
		lane_pattern = [0, 2, 4, 6, 1, 3, 5, 7]

	var slide_patterns: Array = _array_value(
		song.get(
			"slides_hard" if difficulty_name.to_lower() == "hard" else "slides_easy",
			[
				{"path": [0, 4], "shape": "cross"},
				{"path": [2, 6], "shape": "straight"},
			]
		)
	)

	var slide_every: int = maxi(int(profile.get("slide_every", 10)), 0)
	var hold_every: int = maxi(int(profile.get("hold_every", 14)), 0)
	var double_every: int = maxi(int(profile.get("double_every", 0)), 0)
	var slide_beats: float = maxf(float(profile.get("slide_beats", 3.0)), 1.0)
	var hold_beats: float = maxf(float(profile.get("hold_beats", 3.0)), 1.0)
	var jitter: float = clampf(float(profile.get("jitter", 0.0)), 0.0, 0.20)
	var index: int = 0
	var time_value: float = start_time

	while time_value < end_time:
		var base_lane: int = int(lane_pattern[index % lane_pattern.size()]) % 8
		var event_time: float = time_value
		if jitter > 0.0:
			event_time += rng.randf_range(-step * jitter, step * jitter)
			event_time = maxf(event_time, start_time)

		var made_special: bool = false

		if (
			slide_every > 0
			and index > 0
			and index % slide_every == 0
			and not slide_patterns.is_empty()
		):
			var pattern_value: Variant = slide_patterns[int(index / slide_every) % slide_patterns.size()]
			if pattern_value is Dictionary:
				var pattern: Dictionary = (pattern_value as Dictionary).duplicate(true)
				var path: Array = _array_value(pattern.get("path", [base_lane, (base_lane + 4) % 8]))
				if path.size() >= 2:
					events.append({
						"type": "slide",
						"time": event_time,
						"end_time": minf(event_time + beat * slide_beats, end_time + 1.0),
						"path": path,
						"shape": str(pattern.get("shape", "straight")),
						"curve": float(pattern.get("curve", 0.55)),
						"color_index": index % 3,
					})
					made_special = true

		if (
			not made_special
			and hold_every > 0
			and index > 0
			and index % hold_every == 0
		):
			events.append({
				"type": "hold",
				"time": event_time,
				"end_time": minf(event_time + beat * hold_beats, end_time + 1.0),
				"lane": base_lane,
				"color_index": index % 3,
			})
			made_special = true

		if not made_special:
			events.append({
				"type": "tap",
				"time": event_time,
				"lane": base_lane,
				"color_index": index % 3,
			})

			if double_every > 0 and index > 0 and index % double_every == 0:
				var second_lane: int = (base_lane + int(profile.get("double_distance", 4))) % 8
				events.append({
					"type": "tap",
					"time": event_time,
					"lane": second_lane,
					"color_index": (index + 1) % 3,
				})

		index += 1
		time_value += step

	events.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.get("time", 0.0)) < float(b.get("time", 0.0))
	)
	return events


static func _array_value(value: Variant) -> Array:
	if value is Array:
		return (value as Array).duplicate(true)
	return []