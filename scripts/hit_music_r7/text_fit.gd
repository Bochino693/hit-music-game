extends RefCounted
## TEXTO QUE SE VIRA DENTRO DA CAIXA
##
## O PROBLEMA REAL
## Um Label posicionado a mao (fora de container) NAO aceita ficar menor
## que o texto que carrega: `size` e sempre elevado ate o minimo calculado
## a partir do conteudo. Entao um nome comprido estourava o card por baixo
## dos panos — o retangulo do proprio Label crescia junto com o texto, e
## `clip_text` passava a nao cortar nada, porque dentro daquele retangulo
## inflado cabia tudo. Era assim que um titulo como
##
##   "EVANGELION - A CRUEL ANGEL'S THESIS (OPENING COMPLETO ...)"
##
## atravessava o card do seletor e ia parar por cima do painel de
## informacoes, com 659 px de largura num card de 94 px. Encolher a fonte
## adiava o problema; nome maior ainda voltava a estourar.
##
## A SOLUCAO
## Em vez de confiar no corte do Label, o texto e ENCURTADO aqui. Depois
## do ajuste o conteudo cabe de fato, o minimo do Label volta a ser menor
## que a caixa, e o retangulo finalmente obedece ao tamanho reservado.
##
## A ordem e sempre a mesma:
##   1. encolhe a fonte ate caber em UMA linha;
##   2. se nem no menor corpo couber, quebra em DUAS linhas (quando a
##      caixa tem altura para isso) e usa o maior corpo que caiba;
##   3. se ainda faltar espaco, corta com reticencias — que e um corte que
##      o jogador entende, diferente da letra pela metade.
##
## O texto original fica guardado no proprio Label: reajustar depois de
## uma troca de resolucao parte sempre do nome inteiro, nunca do que
## sobrou do corte anterior.

const META_TEXTO: String = "hit_music_texto_completo"
const RETICENCIAS: String = "…"

## Espaco entre as duas linhas, como fracao da altura da fonte. Duas
## linhas coladas ficam ilegiveis no vidro da mesa.
const ALTURA_LINHA: float = 1.12


## Troca o texto do Label e ajusta na mesma passada. E o ponto de entrada
## normal: usar isto sempre que o texto muda (outra musica selecionada,
## outro card, outro recorde).
static func definir(
	label: Label,
	texto: String,
	largura: float,
	altura: float,
	tamanho_base: int,
	tamanho_min: int,
	duas_linhas: bool = true
) -> void:
	if label == null or not is_instance_valid(label):
		return

	label.set_meta(META_TEXTO, texto)
	ajustar(label, largura, altura, tamanho_base, tamanho_min, duas_linhas)


## Reajusta usando o texto original guardado no Label. Serve para quando
## so a caixa muda (redimensionamento da janela), sem troca de texto.
static func ajustar(
	label: Label,
	largura: float,
	altura: float,
	tamanho_base: int,
	tamanho_min: int,
	duas_linhas: bool = true
) -> void:
	if label == null or not is_instance_valid(label):
		return
	if largura <= 0.0:
		return

	var texto: String = str(label.get_meta(META_TEXTO, label.text)).strip_edges()
	if texto.is_empty():
		return

	var fonte: Font = label.get_theme_font("font")
	if fonte == null:
		return

	var base: int = maxi(tamanho_base, tamanho_min)
	var minimo: int = maxi(tamanho_min, 1)

	# O corte e nosso, entao o Label nao precisa do dele. Manter o
	# clip_text ligado e so um cinto de seguranca.
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	label.autowrap_mode = TextServer.AUTOWRAP_OFF

	# 1) Uma linha, encolhendo a fonte.
	var tamanho: int = base
	while tamanho > minimo and largura_do_texto(fonte, texto, tamanho) > largura:
		tamanho -= 1

	if largura_do_texto(fonte, texto, tamanho) <= largura:
		_aplicar(label, texto, tamanho, 1, largura, altura)
		return

	# 2) Duas linhas, do maior corpo para o menor.
	if duas_linhas and altura > 0.0:
		var corpo: int = base
		while corpo >= minimo:
			if _altura_de_duas_linhas(fonte, corpo) <= altura:
				var linhas: PackedStringArray = _quebrar_em_duas(
					fonte, texto, largura, corpo
				)
				if linhas.size() == 2 and largura_do_texto(fonte, linhas[1], corpo) <= largura:
					_aplicar(
						label,
						linhas[0] + "\n" + linhas[1],
						corpo,
						2,
						largura,
						altura
					)
					return
			corpo -= 1

		# Duas linhas no menor corpo, com a segunda cortada.
		if _altura_de_duas_linhas(fonte, minimo) <= altura:
			var ultimas: PackedStringArray = _quebrar_em_duas(
				fonte, texto, largura, minimo
			)
			if ultimas.size() == 2:
				_aplicar(
					label,
					ultimas[0] + "\n" + truncar(fonte, ultimas[1], largura, minimo),
					minimo,
					2,
					largura,
					altura
				)
				return

	# 3) Uma linha no menor corpo, cortada com reticencias.
	_aplicar(
		label,
		truncar(fonte, texto, largura, minimo),
		minimo,
		1,
		largura,
		altura
	)


## Maior pedaco do texto que cabe na largura, terminando em reticencias.
static func truncar(
	fonte: Font,
	texto: String,
	largura: float,
	tamanho: int
) -> String:
	if largura_do_texto(fonte, texto, tamanho) <= largura:
		return texto

	var fim: int = texto.length()
	while fim > 0:
		var tentativa: String = texto.substr(0, fim).strip_edges() + RETICENCIAS
		if largura_do_texto(fonte, tentativa, tamanho) <= largura:
			return tentativa
		fim -= 1

	return RETICENCIAS


static func largura_do_texto(fonte: Font, texto: String, tamanho: int) -> float:
	return fonte.get_string_size(
		texto,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		tamanho
	).x


## Quebra por palavra: a primeira linha leva o maximo que couber, o resto
## vai para a segunda. Devolve vazio quando nem a primeira palavra cabe —
## nesse caso so sobra cortar.
static func _quebrar_em_duas(
	fonte: Font,
	texto: String,
	largura: float,
	tamanho: int
) -> PackedStringArray:
	var palavras: PackedStringArray = texto.split(" ", false)
	if palavras.size() < 2:
		return PackedStringArray()

	var primeira: String = ""
	var indice: int = 0

	while indice < palavras.size():
		var tentativa: String = (
			palavras[indice]
			if primeira.is_empty()
			else primeira + " " + palavras[indice]
		)
		if largura_do_texto(fonte, tentativa, tamanho) > largura:
			break
		primeira = tentativa
		indice += 1

	if primeira.is_empty() or indice >= palavras.size():
		return PackedStringArray()

	var restantes: PackedStringArray = palavras.slice(indice)
	return PackedStringArray([primeira, " ".join(restantes)])


static func _altura_de_duas_linhas(fonte: Font, tamanho: int) -> float:
	return fonte.get_height(tamanho) * ALTURA_LINHA * 2.0


static func _aplicar(
	label: Label,
	texto: String,
	tamanho: int,
	linhas: int,
	largura: float,
	altura: float
) -> void:
	label.text = texto
	label.add_theme_font_size_override("font_size", tamanho)
	label.max_lines_visible = linhas

	# Agora o conteudo cabe, entao o Label aceita voltar ao tamanho da
	# caixa reservada — que e o que impede o card do vizinho de ser
	# invadido.
	#
	# O `size` precisa ser aplicado DUAS vezes, e nao e redundancia: o
	# Godot recalcula o minimo do Label em fila (o texto mudou agora, o
	# minimo novo so vale no proximo idle). A atribuicao direta ainda
	# esbarra no minimo ANTIGO — o do nome inteiro, 659 px num card de
	# 94 — e e devolvida inflada. A versao adiada roda depois do
	# recalculo e e a que realmente cola o Label na caixa.
	label.custom_minimum_size = Vector2.ZERO

	var caixa := Vector2(
		largura,
		altura if altura > 0.0 else label.size.y
	)
	label.size = caixa
	label.set_deferred("size", caixa)
