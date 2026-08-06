extends RefCounted

static func build(song: Dictionary, difficulty_name: String, duration: float) -> Array:
	var hard_mode: bool = difficulty_name.to_lower() == "hard"
	var profile_value: Variant = song.get("hard" if hard_mode else "easy", {})
	if not profile_value is Dictionary:
		return []

	var profile: Dictionary = profile_value as Dictionary
	var easy_value: Variant = song.get("easy", {})
	var hard_value: Variant = song.get("hard", {})
	var easy_profile: Dictionary = easy_value as Dictionary if easy_value is Dictionary else {}
	var hard_profile: Dictionary = hard_value as Dictionary if hard_value is Dictionary else {}

	var bpm: float = maxf(float(song.get("bpm", 120.0)), 1.0)
	var beat: float = 60.0 / bpm

	var easy_step_beats: float = maxf(float(easy_profile.get("step_beats", 2.0)), 0.25)
	var hard_step_beats: float = maxf(float(hard_profile.get("step_beats", 1.0)), 0.25)
	var rhythm_step_beats: float = minf(easy_step_beats, hard_step_beats)
	var rhythm_step: float = beat * rhythm_step_beats

	var selected_step_beats: float = maxf(
		float(profile.get("step_beats", rhythm_step_beats)),
		rhythm_step_beats
	)
	var stride: int = maxi(1, int(round(selected_step_beats / rhythm_step_beats)))

	var start_time: float = maxf(float(song.get("chart_start", 4.0)), 3.2)
	var end_time: float = maxf(start_time + rhythm_step, duration - 2.2)

	var lane_pattern: Array = _array_value(
		song.get(
			"lane_pattern_hard" if hard_mode else "lane_pattern_easy",
			[0, 2, 4, 6, 1, 3, 5, 7]
		)
	)
	if lane_pattern.is_empty():
		lane_pattern = [0, 2, 4, 6, 1, 3, 5, 7]

	var slide_patterns: Array = _array_value(
		song.get(
			"slides_hard" if hard_mode else "slides_easy",
			[
				{"path": [0, 4], "shape": "cross"},
				{"path": [2, 6], "shape": "straight"},
			]
		)
	)

	var slide_every: int = maxi(int(profile.get("slide_every", 10)), 0)
	var hold_every: int = maxi(int(profile.get("hold_every", 14)), 0)
	var configured_double_every: int = maxi(int(profile.get("double_every", 0)), 0)
	var two_hand_every: int = configured_double_every
	if two_hand_every <= 0:
		two_hand_every = 8 if hard_mode else 14

	var slide_beats: float = maxf(float(profile.get("slide_beats", 3.0)), 1.0)
	var hold_beats: float = maxf(float(profile.get("hold_beats", 3.0)), 1.0)
	var double_distance: int = clampi(int(profile.get("double_distance", 4)), 1, 7)

	var events: Array = []
	var grid_index: int = 0
	var note_index: int = 0
	var time_value: float = start_time

	while time_value < end_time:
		if grid_index % stride != 0:
			grid_index += 1
			time_value += rhythm_step
			continue

		var base_lane: int = posmod(
			int(lane_pattern[note_index % lane_pattern.size()]),
			8
		)
		var event_time: float = time_value
		var made_special: bool = false

		if (
			slide_every > 0
			and note_index > 0
			and note_index % slide_every == 0
			and not slide_patterns.is_empty()
		):
			var pattern_value: Variant = slide_patterns[
				int(note_index / slide_every) % slide_patterns.size()
			]
			if pattern_value is Dictionary:
				var pattern: Dictionary = (pattern_value as Dictionary).duplicate(true)
				var path: Array = _array_value(
					pattern.get("path", [base_lane, (base_lane + 4) % 8])
				)
				if path.size() >= 2:
					events.append({
						"type": "slide",
						"time": event_time,
						"end_time": minf(
							event_time + beat * slide_beats,
							end_time + beat
						),
						"path": path,
						"shape": str(pattern.get("shape", "straight")),
						"curve": float(pattern.get("curve", 0.55)),
						"color_index": note_index % 3,
						"rhythm_slot": grid_index,
					})
					made_special = true

		if (
			not made_special
			and hold_every > 0
			and note_index > 0
			and note_index % hold_every == 0
		):
			events.append({
				"type": "hold",
				"time": event_time,
				"end_time": minf(
					event_time + beat * hold_beats,
					end_time + beat
				),
				"lane": base_lane,
				"color_index": note_index % 3,
				"rhythm_slot": grid_index,
			})
			made_special = true

		if not made_special:
			events.append({
				"type": "tap",
				"time": event_time,
				"lane": base_lane,
				"color_index": note_index % 3,
				"rhythm_slot": grid_index,
			})

			if (
				two_hand_every > 0
				and note_index > 0
				and note_index % two_hand_every == 0
			):
				var second_lane: int = posmod(base_lane + double_distance, 8)
				events.append({
					"type": "tap",
					"time": event_time,
					"lane": second_lane,
					"color_index": (note_index + 1) % 3,
					"rhythm_slot": grid_index,
					"two_hand_pair": true,
				})

		note_index += 1
		grid_index += 1
		time_value += rhythm_step

	events.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var time_a: float = float(a.get("time", 0.0))
			var time_b: float = float(b.get("time", 0.0))
			if is_equal_approx(time_a, time_b):
				return int(a.get("lane", 0)) < int(b.get("lane", 0))
			return time_a < time_b
	)

	return events


static func _array_value(value: Variant) -> Array:
	if value is Array:
		return (value as Array).duplicate(true)
	return []
