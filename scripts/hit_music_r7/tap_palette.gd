extends RefCounted

## Paleta unica do gameplay. A mesma cor alimenta a arte do tazo,
## o LED fisico, a roda de encaixe e os efeitos de acerto.
const TAP_CYAN: Color = Color(0.0, 0.86, 1.0, 1.0)
const TAP_YELLOW: Color = Color(1.0, 0.72, 0.0, 1.0)
const TAP_RED: Color = Color(1.0, 0.025, 0.055, 1.0)
const HOLD_YELLOW: Color = TAP_YELLOW


static func color_for_index(index: int) -> Color:
	match posmod(index, 3):
		1:
			return TAP_YELLOW
		2:
			return TAP_RED
		_:
			return TAP_CYAN


static func vivid_theme(color: Color) -> Color:
	# Branco/cinza nao ganha matiz artificial; cores de tema recebem mais
	# saturacao e luminosidade para continuarem legiveis no fundo escuro.
	if color.s < 0.025:
		return Color(color.r, color.g, color.b, color.a)
	var saturation: float = clampf(color.s * 1.20 + 0.055, 0.0, 1.0)
	var value: float = clampf(maxf(color.v, 0.72) * 1.08, 0.0, 1.0)
	return Color.from_hsv(color.h, saturation, value, color.a)
