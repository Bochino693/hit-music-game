extends RefCounted

## Paleta unica do gameplay. A mesma cor alimenta a arte do tazo,
## o LED fisico, a roda de encaixe e os efeitos de acerto.
const TAP_CYAN: Color = Color(0.0, 0.86, 1.0, 1.0)
const TAP_YELLOW: Color = Color(1.0, 0.72, 0.0, 1.0)
const TAP_RED: Color = Color(1.0, 0.025, 0.055, 1.0)
const HOLD_YELLOW: Color = TAP_YELLOW

## Quantidade de variacoes de seta e de estrela do arrasto. As formas
## mudam, mas a cor NUNCA muda de familia: uma seta/estrela sempre sai
## na cor do tazo que a originou (ver color_for_index/highlight).
const ARROW_STYLE_COUNT: int = 4
const STAR_STYLE_COUNT: int = 4


## A ORDEM AQUI E A ORDEM DOS QUADROS DA ARTE.
##
## res://images/tazos_idle_sheet_3x1_160.png tem tres tazos lado a lado:
## quadro 0 = AMARELO, quadro 1 = VERMELHO, quadro 2 = AZUL. O indice
## que chega aqui e o mesmo que vai para AnimatedSprite2D.frame (ver
## tap_visual.configure), entao a cor devolvida precisa ser a cor
## pintada naquele quadro.
##
## Estava 0=azul, 1=amarelo, 2=vermelho — deslocado em um quadro. O
## resultado era o tazo vermelho estourando amarelo, o azul estourando
## vermelho e o amarelo estourando azul.
static func color_for_index(index: int) -> Color:
	match posmod(index, 3):
		1:
			return TAP_RED
		2:
			return TAP_CYAN
		_:
			return TAP_YELLOW


## Tom claro da MESMA cor: e o brilho/realce que acompanha o objeto.
## Antes o realce do arrasto era um ciano fixo, entao um tazo vermelho
## podia aparecer com detalhe azul. Aqui o matiz e preservado e so a
## saturacao/luminosidade mudam, entao o realce continua sendo "a mesma
## cor, mais clara".
static func highlight(color: Color) -> Color:
	if color.s < 0.025:
		return Color(1.0, 1.0, 1.0, color.a)
	return Color.from_hsv(
		color.h,
		clampf(color.s * 0.45, 0.0, 1.0),
		clampf(maxf(color.v, 0.85) * 1.10, 0.0, 1.0),
		color.a
	)


## Tom escuro da MESMA cor, usado em sombra/contorno dos desenhos.
static func shade(color: Color) -> Color:
	if color.s < 0.025:
		return Color(0.02, 0.03, 0.05, color.a)
	return Color.from_hsv(
		color.h,
		clampf(color.s * 1.05 + 0.15, 0.0, 1.0),
		clampf(color.v * 0.22, 0.0, 1.0),
		color.a
	)


## Forma da seta e da estrela de cada arrasto. Deterministico: o mesmo
## evento desenha sempre a mesma variacao, sem sorteio por frame.
static func arrow_style_for(index: int) -> int:
	return posmod(index, ARROW_STYLE_COUNT)


static func star_style_for(index: int) -> int:
	return posmod(index, STAR_STYLE_COUNT)


static func vivid_theme(color: Color) -> Color:
	# Branco/cinza nao ganha matiz artificial; cores de tema recebem mais
	# saturacao e luminosidade para continuarem legiveis no fundo escuro.
	if color.s < 0.025:
		return Color(color.r, color.g, color.b, color.a)
	var saturation: float = clampf(color.s * 1.20 + 0.055, 0.0, 1.0)
	var value: float = clampf(maxf(color.v, 0.72) * 1.08, 0.0, 1.0)
	return Color.from_hsv(color.h, saturation, value, color.a)
