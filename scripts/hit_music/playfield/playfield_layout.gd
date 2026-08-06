class_name HitMusicPlayfieldLayout
extends RefCounted

const NUM_LANES: int = 8
const CIRCLE_WIDTH_RATIO: float = 0.970
const TOP_RESERVED_RATIO: float = 0.255
const BOTTOM_MARGIN_RATIO: float = 0.012
const SIDE_MARGIN_RATIO: float = 0.015
const LANE_RADIUS_RATIO: float = 0.905

static func calculate(viewport_size: Vector2) -> Dictionary:
	var reference: float = minf(viewport_size.x, viewport_size.y)
	var side_margin: float = maxf(4.0, reference * SIDE_MARGIN_RATIO)
	var bottom_margin: float = maxf(4.0, viewport_size.y * BOTTOM_MARGIN_RATIO)
	var top_reserved: float = viewport_size.y * TOP_RESERVED_RATIO

	var radius_by_width: float = (viewport_size.x - side_margin * 2.0) * 0.5
	var radius_by_height: float = (viewport_size.y - top_reserved - bottom_margin) * 0.5
	var radius: float = maxf(120.0, minf(radius_by_width, radius_by_height) * CIRCLE_WIDTH_RATIO)

	var center := Vector2(
		viewport_size.x * 0.5,
		viewport_size.y - bottom_margin - radius
	)

	var lane_positions := PackedVector2Array()
	for lane in range(NUM_LANES):
		var angle: float = -PI * 0.5 + TAU * float(lane) / float(NUM_LANES)
		lane_positions.append(
			center + Vector2(cos(angle), sin(angle)) * radius * LANE_RADIUS_RATIO
		)

	return {
		"center": center,
		"radius": radius,
		"lane_positions": lane_positions,
	}