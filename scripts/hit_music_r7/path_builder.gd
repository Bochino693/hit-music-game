extends RefCounted

static func build(
	event: Dictionary,
	center: Vector2,
	radius: float,
	lane_positions: PackedVector2Array
) -> PackedVector2Array:
	var lanes_value: Variant = event.get("path", [])
	if not lanes_value is Array:
		return PackedVector2Array()

	var lanes: Array = lanes_value as Array
	if lanes.size() < 2:
		return PackedVector2Array()

	var start_lane: int = clampi(int(lanes[0]), 0, lane_positions.size() - 1)
	var end_lane: int = clampi(int(lanes[lanes.size() - 1]), 0, lane_positions.size() - 1)
	var start: Vector2 = lane_positions[start_lane]
	var finish: Vector2 = lane_positions[end_lane]
	var shape: String = str(event.get("shape", "straight")).to_lower()
	var curve: float = clampf(float(event.get("curve", 0.55)), -1.0, 1.0)

	match shape:
		"cross":
			return _sample_polyline(PackedVector2Array([start, center, finish]), 18)
		"v":
			var middle_direction: Vector2 = ((start + finish) * 0.5 - center).normalized()
			if middle_direction.length_squared() < 0.01:
				middle_direction = Vector2(0.0, -1.0)
			var middle: Vector2 = center + middle_direction * radius * 0.24
			return _sample_polyline(PackedVector2Array([start, middle, finish]), 18)
		"arc_cw":
			return _sample_quadratic(
				start,
				_arc_control(start, finish, center, radius, absf(curve)),
				finish,
				42
			)
		"arc_ccw":
			return _sample_quadratic(
				start,
				_arc_control(start, finish, center, radius, -absf(curve)),
				finish,
				42
			)
		"hook":
			var direction: Vector2 = (finish - start).normalized()
			var perpendicular := Vector2(-direction.y, direction.x)
			var control_a: Vector2 = start.lerp(center, 0.60) + perpendicular * radius * curve * 0.35
			var control_b: Vector2 = finish.lerp(center, 0.42) - perpendicular * radius * curve * 0.20
			return _sample_cubic(start, control_a, control_b, finish, 48)
		"zigzag":
			var anchors := PackedVector2Array()
			for lane_value in lanes:
				var lane_index: int = clampi(int(lane_value), 0, lane_positions.size() - 1)
				anchors.append(lane_positions[lane_index])
			return _sample_polyline(anchors, 14)
		_:
			if lanes.size() > 2:
				var anchors := PackedVector2Array()
				for lane_value in lanes:
					var lane_index: int = clampi(int(lane_value), 0, lane_positions.size() - 1)
					anchors.append(lane_positions[lane_index])
				return _sample_polyline(anchors, 14)
			return _sample_polyline(PackedVector2Array([start, finish]), 42)


## Pre-calcula o comprimento acumulado do caminho uma unica vez.
## point_at/tangent_at recalculavam essa soma (com distance_to + sqrt
## por segmento) toda vez que eram chamadas — e eram chamadas varias
## vezes por frame por nota de arrasto ativa (estrela, fantasmas do
## rastro, cada seta/chevron). Em telas com varios arrastos isso pesa
## bastante. Com o cache, o custo por frame cai de O(pontos) para O(1)
## por amostra.
static func build_lengths(points: PackedVector2Array) -> Dictionary:
	var cumulative := PackedFloat32Array()
	var total: float = 0.0
	cumulative.append(0.0)
	for index in range(points.size() - 1):
		total += points[index].distance_to(points[index + 1])
		cumulative.append(total)
	return {"cumulative": cumulative, "total": total}


static func point_at_cached(
	points: PackedVector2Array,
	lengths: Dictionary,
	progress: float
) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	if points.size() == 1:
		return points[0]

	var cumulative: PackedFloat32Array = lengths.get("cumulative", PackedFloat32Array())
	var total: float = float(lengths.get("total", 0.0))
	if cumulative.size() != points.size() or total <= 0.001:
		return point_at(points, progress)

	var target_distance: float = total * clampf(progress, 0.0, 1.0)
	var low: int = 0
	var high: int = cumulative.size() - 1
	while low < high:
		var mid: int = (low + high) / 2
		if cumulative[mid] < target_distance:
			low = mid + 1
		else:
			high = mid
	var upper: int = maxi(low, 1)
	var lower: int = upper - 1
	var segment_length: float = maxf(cumulative[upper] - cumulative[lower], 0.001)
	var local: float = clampf((target_distance - cumulative[lower]) / segment_length, 0.0, 1.0)
	return points[lower].lerp(points[upper], local)


static func tangent_at_cached(
	points: PackedVector2Array,
	lengths: Dictionary,
	progress: float
) -> Vector2:
	if points.size() < 2:
		return Vector2.RIGHT
	var before: Vector2 = point_at_cached(points, lengths, maxf(progress - 0.008, 0.0))
	var after: Vector2 = point_at_cached(points, lengths, minf(progress + 0.008, 1.0))
	var tangent: Vector2 = after - before
	return tangent.normalized() if tangent.length_squared() > 0.001 else Vector2.RIGHT


static func point_at(points: PackedVector2Array, progress: float) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	if points.size() == 1:
		return points[0]

	var lengths: Array[float] = []
	var total: float = 0.0
	for index in range(points.size() - 1):
		var length_value: float = points[index].distance_to(points[index + 1])
		lengths.append(length_value)
		total += length_value

	if total <= 0.001:
		return points[0]

	var target_distance: float = total * clampf(progress, 0.0, 1.0)
	var accumulated: float = 0.0
	for index in range(lengths.size()):
		var length_value: float = lengths[index]
		if target_distance <= accumulated + length_value:
			var local: float = (target_distance - accumulated) / maxf(length_value, 0.001)
			return points[index].lerp(points[index + 1], local)
		accumulated += length_value
	return points[points.size() - 1]


static func tangent_at(points: PackedVector2Array, progress: float) -> Vector2:
	if points.size() < 2:
		return Vector2.RIGHT
	var before: Vector2 = point_at(points, maxf(progress - 0.008, 0.0))
	var after: Vector2 = point_at(points, minf(progress + 0.008, 1.0))
	var tangent: Vector2 = after - before
	return tangent.normalized() if tangent.length_squared() > 0.001 else Vector2.RIGHT


static func nearest_progress(
	points: PackedVector2Array,
	position_value: Vector2,
	minimum_progress: float = 0.0,
	max_forward_span: float = 1.0
) -> Dictionary:
	if points.is_empty():
		return {"progress": 0.0, "distance": INF}

	var last_index: int = points.size() - 1
	var start_index: int = clampi(
		int(floor(clampf(minimum_progress, 0.0, 1.0) * float(last_index))) - 2,
		0,
		last_index
	)

	# max_forward_span < 1.0 limita o quanto uma unica amostra pode
	# "pular" para frente no caminho. Isso e o que impede o gesto de
	# contar quando o dedo/mouse salta direto do inicio para o fim:
	# cada amostra so pode avancar uma fatia pequena do progresso por
	# vez, entao o percurso precisa ser realmente varrido.
	var end_index: int = last_index
	if max_forward_span < 1.0:
		var span_steps: int = int(ceil(clampf(max_forward_span, 0.0, 1.0) * float(last_index))) + 2
		end_index = clampi(start_index + span_steps, start_index, last_index)

	var best_index: int = start_index
	var best_distance: float = INF

	for index in range(start_index, end_index + 1):
		var distance_value: float = points[index].distance_to(position_value)
		if distance_value < best_distance:
			best_distance = distance_value
			best_index = index

	return {
		"progress": float(best_index) / float(maxi(last_index, 1)),
		"distance": best_distance,
	}


static func _arc_control(
	start: Vector2,
	finish: Vector2,
	center: Vector2,
	radius: float,
	curve: float
) -> Vector2:
	var midpoint: Vector2 = (start + finish) * 0.5
	var chord: Vector2 = finish - start
	var perpendicular := Vector2(-chord.y, chord.x).normalized()
	if perpendicular.dot(midpoint - center) < 0.0:
		perpendicular = -perpendicular
	return midpoint + perpendicular * radius * curve * 0.60


static func _sample_quadratic(
	a: Vector2,
	b: Vector2,
	c: Vector2,
	steps: int
) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(steps + 1):
		var t: float = float(index) / float(steps)
		var p: Vector2 = (
			a * pow(1.0 - t, 2.0)
			+ b * (2.0 * (1.0 - t) * t)
			+ c * (t * t)
		)
		points.append(p)
	return points


static func _sample_cubic(
	a: Vector2,
	b: Vector2,
	c: Vector2,
	d: Vector2,
	steps: int
) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(steps + 1):
		var t: float = float(index) / float(steps)
		var one_minus: float = 1.0 - t
		var p: Vector2 = (
			a * pow(one_minus, 3.0)
			+ b * (3.0 * pow(one_minus, 2.0) * t)
			+ c * (3.0 * one_minus * t * t)
			+ d * pow(t, 3.0)
		)
		points.append(p)
	return points


static func _sample_polyline(
	anchors: PackedVector2Array,
	steps_per_segment: int
) -> PackedVector2Array:
	var result := PackedVector2Array()
	if anchors.is_empty():
		return result
	if anchors.size() == 1:
		result.append(anchors[0])
		return result

	for segment in range(anchors.size() - 1):
		for index in range(steps_per_segment):
			var t: float = float(index) / float(steps_per_segment)
			result.append(anchors[segment].lerp(anchors[segment + 1], t))
	result.append(anchors[anchors.size() - 1])
	return result