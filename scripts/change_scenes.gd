extends Node2D
## SELETOR HIT MUSIC — layout MaiMai
## - Mesmo círculo e posição da fase, apoiado no rodapé.
## - Lista vertical à esquerda e informações à direita, tudo dentro do círculo.
## - Janela retangular superior vazia, reservada para conteúdo futuro.
## - input_a avança; input_b seleciona; touch permite tocar ou arrastar.
## - Fundo do círculo usa vídeo da música quando existir; caso contrário, usa a capa.

const PASTA_CENAS: String = "res://scenes"
const PASTA_CAPAS: String = "res://images/capas_scenes"
const CAMINHO_RECORDES: String = "user://hit_music_records.json"

const FPS_ALVO: int = 60
const PORCENTAGEM_CIRCULO: float = 0.970
const HUD_TOPO_ALTURA_RATIO: float = 0.205
const HUD_TOPO_MARGEM_RATIO: float = 0.022
const CIRCULO_MARGEM_INFERIOR_RATIO: float = 0.012
const DURACAO_TRANSICAO: float = 0.68
const ITENS_VISIVEIS: int = 5
const VELOCIDADE_SCROLL_LISTA: float = 10.0
const VELOCIDADE_ESCALA_LISTA: float = 9.0
const VELOCIDADE_ALPHA_LISTA: float = 12.0
const MARGEM_SCROLL_LISTA_RATIO: float = 0.045
const SERIAL_MENU_ATIVADO: bool = true
const PREVIEW_ESPERA_SEG: float = 2.0
const PREVIEW_DURACAO_SEG: float = 12.0
const LED_MENU_REAFIRMAR_SEG: float = 1.0

const CENAS_EXCLUIDAS: Array[String] = [
	"abertura.tscn",
	"opening.tscn",
	"seletor_scenes.tscn",
	"ranking.tscn",
	"main.tscn",
	"config.tscn",
	"settings.tscn",
	"options.tscn",
	"play.tscn",
]

const CAPAS_POR_ARQUIVO: Dictionary = {
	"dragon_ball.tscn": "res://images/dragon-ball.jpeg",
	"rick_morty.tscn": "res://images/rick_morty.jpg",
	"soul.tscn": "res://images/soul.jpg",
	"carmine.tscn": "res://images/carmine.jpeg",
	"demon.tscn": "res://images/demon.jpeg",
	"fairy.tscn": "res://images/fairy.jpeg",
	"naruto.tscn": "res://images/naruto.jpeg",
	"naturo.tscn": "res://images/naruto.jpeg",
}

const CATEGORIA_POR_ARQUIVO: Dictionary = {
	"dragon_ball.tscn": "ANIMES",
	"rick_morty.tscn": "ANIMES",
	"soul.tscn": "ANIMES",
	"carmine.tscn": "ANIMES",
	"demon.tscn": "ANIMES",
	"fairy.tscn": "ANIMES",
	"naruto.tscn": "ANIMES",
	"naturo.tscn": "ANIMES",
}

var _cenas: Array[Dictionary] = []
var _recordes: Dictionary = {}
var _indice: int = 0

var _centro_circulo: Vector2 = Vector2.ZERO
var _raio_circulo: float = 0.0
var _cor_atual: Color = Color(0.96, 0.025, 0.075, 1.0)
var _cor_secundaria: Color = Color(1.0, 0.72, 0.12, 1.0)
var _tempo: float = 0.0
var _em_transicao: bool = false
var _portal_progresso: float = 0.0
var _destino: String = ""
var _transicao_musica: float = 1.0
var _direcao_transicao_musica: float = 1.0
var _tween_transicao_musica: Tween

var _ui: CanvasLayer
var _hud_superior: Panel
var _portal_ui: Control
var _conteudo_circular: Control
var _fundo_capa: TextureRect
var _fundo_video: VideoStreamPlayer
var _overlay_fundo: ColorRect
var _fundo_neutro: ColorRect
var _faixa_transicao: ColorRect
var _lista_container: Control
var _painel_info: Panel
var _painel_info_x_base: float = 0.0
var _capa_info: TextureRect
var _label_track: Label
var _label_nome: Label
var _label_categoria: Label
var _label_tempo: Label
var _label_facil: Label
var _label_dificil: Label
var _label_melhor: Label
var _label_ajuda: Label
var _label_aviso_menu: Label
var _chip_next: Panel
var _chip_start: Panel
var _label_next: Label
var _label_start: Label

var _itens_lista: Array[Panel] = []
var _labels_lista: Array[Label] = []
var _capas_lista: Array[TextureRect] = []
var _alvos_x_lista: Array[float] = []
var _alvos_y_lista: Array[float] = []
var _alvos_alpha_lista: Array[float] = []
var _alvos_escala_lista: Array[Vector2] = []
var _alvos_rotacao_lista: Array[float] = []
var _serial_menu_base_dir: String = ""
var _serial_menu_spool_dir: String = ""
var _serial_menu_estado_path: String = ""
var _serial_menu_sequencia: int = 0
var _ultima_assinatura_led_menu: String = ""
var _comando_led_menu_atual: String = ""
var _tempo_reenvio_led_menu: float = 0.0
const INTERVALO_REENVIO_LED_MENU: float = 999999.0
const ATRASO_ATUALIZACAO_LED_MENU: float = 0.18
var _comando_led_pendente: String = ""
var _tempo_comando_led_pendente: float = 0.0
var _tempo_preview_parado: float = 0.0
var _tempo_preview_rodando: float = 0.0
var _preview_indice: int = -1
var _preview_iniciado: bool = false
var _tempo_led_reafirmar: float = 0.0

var _touch_ativo: bool = false
var _touch_inicio: Vector2 = Vector2.ZERO
var _touch_id: int = -1


func _ready() -> void:
	Engine.max_fps = FPS_ALVO
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_carregar_recordes()
	_detectar_cenas()
	_recalcular_geometria()
	_montar_interface()
	_serial_menu_configurar()
	_serial_menu_limpar_fila_antiga()
	_indice = 0
	_aplicar_selecao(0, true)
	_tempo_reenvio_led_menu = INTERVALO_REENVIO_LED_MENU
	get_viewport().size_changed.connect(_ao_redimensionar)

	_portal_progresso = 0.0
	var tw: Tween = create_tween()
	tw.set_trans(Tween.TRANS_QUINT)
	tw.set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "_portal_progresso", 1.0, DURACAO_TRANSICAO)


func _process(delta: float) -> void:
	_tempo += delta
	_tempo_reenvio_led_menu += delta
	_tempo_led_reafirmar += delta
	_processar_input_fisico()
	_processar_led_menu_pendente(delta)
	_processar_preview_video(delta)
	_reafirmar_led_menu_sem_fila()
	_atualizar_animacao_lista(delta)
	_atualizar_borda_paineis()
	queue_redraw()
	if _portal_ui != null and is_instance_valid(_portal_ui):
		_portal_ui.queue_redraw()


func _processar_input_fisico() -> void:
	if _em_transicao:
		return

	if _acao_just_pressed("input_a") or _acao_just_pressed("ui_down") or _acao_just_pressed("ui_right"):
		_mudar_selecao(1)
	elif _acao_just_pressed("ui_up") or _acao_just_pressed("ui_left"):
		_mudar_selecao(-1)

	if _acao_just_pressed("input_b") or _acao_just_pressed("input_start") or _acao_just_pressed("ui_accept"):
		_selecionar_atual()


func _acao_just_pressed(acao: String) -> bool:
	return InputMap.has_action(acao) and Input.is_action_just_pressed(acao)


func _input(event: InputEvent) -> void:
	if _em_transicao:
		return

	if event is InputEventScreenTouch:
		var toque: InputEventScreenTouch = event
		if toque.pressed:
			_touch_ativo = true
			_touch_id = toque.index
			_touch_inicio = toque.position
		elif _touch_ativo and toque.index == _touch_id:
			_finalizar_touch(toque.position)
			_touch_ativo = false
			_touch_id = -1

	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse: InputEventMouseButton = event
		if mouse.pressed:
			_touch_ativo = true
			_touch_inicio = mouse.position
		elif _touch_ativo:
			_finalizar_touch(mouse.position)
			_touch_ativo = false


func _finalizar_touch(posicao: Vector2) -> void:
	if posicao.distance_to(_centro_circulo) > _raio_circulo:
		return

	var deslocamento: Vector2 = posicao - _touch_inicio
	if abs(deslocamento.y) > _raio_circulo * 0.075 and abs(deslocamento.y) > abs(deslocamento.x):
		_mudar_selecao(1 if deslocamento.y < 0.0 else -1)
		return

	var indice_tocado: int = _indice_por_posicao(posicao)
	if indice_tocado >= 0:
		if indice_tocado == _indice:
			_selecionar_atual()
		else:
			_aplicar_selecao(indice_tocado)


func _indice_por_posicao(posicao: Vector2) -> int:
	for i in range(_itens_lista.size()):
		var item: Panel = _itens_lista[i]
		if item.visible and Rect2(item.global_position, item.size).has_point(posicao):
			return i
	return -1


func _recalcular_geometria() -> void:
	var tela: Vector2 = get_viewport_rect().size
	var menor: float = min(tela.x, tela.y)
	_raio_circulo = menor * PORCENTAGEM_CIRCULO * 0.5
	_centro_circulo = Vector2(
		tela.x * 0.5,
		tela.y - _raio_circulo - tela.y * CIRCULO_MARGEM_INFERIOR_RATIO
	)


func _montar_interface() -> void:
	if _ui != null and is_instance_valid(_ui):
		_ui.queue_free()

	_itens_lista.clear()
	_labels_lista.clear()
	_capas_lista.clear()
	_alvos_x_lista.clear()
	_alvos_y_lista.clear()
	_alvos_alpha_lista.clear()
	_alvos_escala_lista.clear()
	_alvos_rotacao_lista.clear()

	_ui = CanvasLayer.new()
	_ui.layer = 10
	add_child(_ui)

	var tela: Vector2 = get_viewport_rect().size
	var margem_topo: float = tela.x * HUD_TOPO_MARGEM_RATIO
	var altura_topo: float = tela.y * HUD_TOPO_ALTURA_RATIO

	# Janela superior propositalmente vazia.
	_hud_superior = Panel.new()
	_hud_superior.position = Vector2(margem_topo, margem_topo)
	_hud_superior.size = Vector2(tela.x - margem_topo * 2.0, altura_topo)
	_hud_superior.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_superior.add_theme_stylebox_override("panel", _style_hud_vazio())
	_ui.add_child(_hud_superior)

	# Conteúdo direto, sem CanvasGroup: evita o efeito esbranquiçado.
	# Todos os elementos úteis são posicionados em uma área segura inscrita no círculo.
	_conteudo_circular = Control.new()
	_conteudo_circular.position = _centro_circulo - Vector2.ONE * _raio_circulo
	_conteudo_circular.size = Vector2.ONE * (_raio_circulo * 2.0)
	_conteudo_circular.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_conteudo_circular.clip_contents = true
	_ui.add_child(_conteudo_circular)

	_criar_fundo_circular()

	# Retângulo seguro totalmente inscrito no círculo. Nada encosta ou sai da borda.
	var topo_util: float = _raio_circulo * 0.40
	var base_util: float = _raio_circulo * 1.50
	var altura_util: float = base_util - topo_util
	# Área ainda mais interna para a ficha direita nunca tocar a circunferência.
	var largura_util: float = _raio_circulo * 1.36
	var origem_x: float = _raio_circulo - largura_util * 0.5
	var largura_lista: float = largura_util * 0.53
	var vao: float = _raio_circulo * 0.028
	var largura_info: float = largura_util - largura_lista - vao

	_lista_container = Control.new()
	_lista_container.position = Vector2(origem_x, topo_util)
	_lista_container.size = Vector2(largura_lista, altura_util)
	_lista_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_conteudo_circular.add_child(_lista_container)

	_painel_info = Panel.new()
	_painel_info.position = Vector2(origem_x + largura_lista + vao, topo_util)
	_painel_info_x_base = _painel_info.position.x
	_painel_info.size = Vector2(largura_info, altura_util)
	_painel_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_painel_info.clip_contents = true
	_painel_info.add_theme_stylebox_override("panel", _style_painel_info())
	_conteudo_circular.add_child(_painel_info)

	_montar_ficha_info()

	_criar_aviso_e_legendas_fisicas()

	_criar_itens_lista()

	# Portal na camada frontal. Ele é adicionado por último e nunca fica atrás do fundo.
	_portal_ui = Control.new()
	_portal_ui.position = Vector2.ZERO
	_portal_ui.size = tela
	_portal_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portal_ui.draw.connect(_desenhar_portal_frontal)
	_ui.add_child(_portal_ui)


func _criar_fundo_circular() -> void:
	# Base preta do círculo.
	_fundo_neutro = ColorRect.new()
	_fundo_neutro.position = Vector2.ZERO
	_fundo_neutro.size = _conteudo_circular.size
	_fundo_neutro.color = Color(0.004, 0.008, 0.018, 1.0)
	_fundo_neutro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fundo_neutro.material = _material_mascara_circular()
	_conteudo_circular.add_child(_fundo_neutro)

	# Preview da música: só aparece depois de 2 segundos parado na seleção
	# e toca por no máximo 12 segundos, sempre recortado dentro do círculo.
	_fundo_video = VideoStreamPlayer.new()
	_fundo_video.position = Vector2.ZERO
	_fundo_video.size = _conteudo_circular.size
	_fundo_video.expand = true
	_fundo_video.autoplay = false
	_fundo_video.volume_db = -80.0
	_fundo_video.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_fundo_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fundo_video.material = _material_mascara_circular()
	_conteudo_circular.add_child(_fundo_video)

	# Escurecimento garante leitura da lista e da ficha.
	_overlay_fundo = ColorRect.new()
	_overlay_fundo.position = Vector2.ZERO
	_overlay_fundo.size = _conteudo_circular.size
	_overlay_fundo.color = Color(0.005, 0.010, 0.024, 0.56)
	_overlay_fundo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_fundo.material = _material_mascara_circular()
	_conteudo_circular.add_child(_overlay_fundo)

	_faixa_transicao = ColorRect.new()
	_faixa_transicao.position = Vector2(_raio_circulo * 0.28, _raio_circulo * 0.40)
	_faixa_transicao.size = Vector2(_raio_circulo * 1.44, _raio_circulo * 1.10)
	_faixa_transicao.color = Color(_cor_atual.r, _cor_atual.g, _cor_atual.b, 0.0)
	_faixa_transicao.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_faixa_transicao.visible = false
	_conteudo_circular.add_child(_faixa_transicao)



func _material_mascara_circular() -> ShaderMaterial:
	var shader: Shader = Shader.new()
	shader.code = """
shader_type canvas_item;
void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float d = distance(UV, vec2(0.5));
	float mascara = 1.0 - smoothstep(0.492, 0.500, d);
	COLOR = vec4(tex.rgb, tex.a * mascara);
}
"""
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = shader
	return material


func _montar_ficha_info() -> void:
	var w: float = _painel_info.size.x
	var h: float = _painel_info.size.y
	var margem: float = w * 0.055

	_capa_info = TextureRect.new()
	_capa_info.position = Vector2(margem, margem)
	_capa_info.size = Vector2(w - margem * 2.0, h * 0.27)
	_capa_info.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_capa_info.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_capa_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_painel_info.add_child(_capa_info)

	var y: float = _capa_info.position.y + _capa_info.size.y + h * 0.025
	_label_track = _label("TRACK 01", int(clampf(w * 0.075, 16.0, _raio_circulo * 0.034)), HORIZONTAL_ALIGNMENT_LEFT)
	_label_track.position = Vector2(margem, y)
	_label_track.size = Vector2(w - margem * 2.0, h * 0.055)
	_painel_info.add_child(_label_track)

	y += h * 0.060
	_label_nome = _label("MÚSICA", int(clampf(w * 0.105, 18.0, _raio_circulo * 0.046)), HORIZONTAL_ALIGNMENT_LEFT)
	_label_nome.position = Vector2(margem, y)
	_label_nome.size = Vector2(w - margem * 2.0, h * 0.105)
	_label_nome.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_painel_info.add_child(_label_nome)

	y += h * 0.100
	_label_categoria = _label("CATEGORIA", int(clampf(w * 0.064, 14.0, _raio_circulo * 0.030)), HORIZONTAL_ALIGNMENT_LEFT)
	_label_categoria.position = Vector2(margem, y)
	_label_categoria.size = Vector2(w - margem * 2.0, h * 0.045)
	_painel_info.add_child(_label_categoria)

	y += h * 0.050
	_label_tempo = _label("TEMPO  --:--", int(clampf(w * 0.064, 14.0, _raio_circulo * 0.030)), HORIZONTAL_ALIGNMENT_LEFT)
	_label_tempo.position = Vector2(margem, y)
	_label_tempo.size = Vector2(w - margem * 2.0, h * 0.045)
	_painel_info.add_child(_label_tempo)

	y += h * 0.060
	_label_facil = _label("FÁCIL      0,00%", int(clampf(w * 0.070, 15.0, _raio_circulo * 0.032)), HORIZONTAL_ALIGNMENT_LEFT)
	_label_facil.position = Vector2(margem, y)
	_label_facil.size = Vector2(w - margem * 2.0, h * 0.052)
	_painel_info.add_child(_label_facil)

	y += h * 0.060
	_label_dificil = _label("DIFÍCIL    0,00%", int(clampf(w * 0.070, 15.0, _raio_circulo * 0.032)), HORIZONTAL_ALIGNMENT_LEFT)
	_label_dificil.position = Vector2(margem, y)
	_label_dificil.size = _label_facil.size
	_painel_info.add_child(_label_dificil)

	y += h * 0.060
	_label_melhor = _label("MELHOR     0,00%", int(clampf(w * 0.082, 17.0, _raio_circulo * 0.038)), HORIZONTAL_ALIGNMENT_LEFT)
	_label_melhor.position = Vector2(margem, y)
	_label_melhor.size = _label_facil.size
	_painel_info.add_child(_label_melhor)


func _criar_aviso_e_legendas_fisicas() -> void:
	_label_aviso_menu = _label(
		"ESCOLHA UMA MÚSICA",
		int(_raio_circulo * 0.040),
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_label_aviso_menu.position = Vector2(_raio_circulo * 0.40, _raio_circulo * 0.105)
	_label_aviso_menu.size = Vector2(_raio_circulo * 1.20, _raio_circulo * 0.12)
	_label_aviso_menu.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0, 0.90))
	_conteudo_circular.add_child(_label_aviso_menu)

	# Etiqueta retangular colada à borda superior: botão físico NEXT.
	_chip_next = Panel.new()
	_chip_next.position = Vector2(_raio_circulo * 0.79, _raio_circulo * 0.205)
	_chip_next.size = Vector2(_raio_circulo * 0.42, _raio_circulo * 0.095)
	_chip_next.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chip_next.add_theme_stylebox_override("panel", _style_legenda_fisica(_cor_atual))
	_conteudo_circular.add_child(_chip_next)

	_label_next = _label("NEXT", int(_raio_circulo * 0.036), HORIZONTAL_ALIGNMENT_CENTER)
	_label_next.size = _chip_next.size
	_chip_next.add_child(_label_next)

	# Etiqueta retangular encostada na borda direita: botão físico START.
	_chip_start = Panel.new()
	_chip_start.position = Vector2(_raio_circulo * 1.665, _raio_circulo * 0.925)
	_chip_start.size = Vector2(_raio_circulo * 0.28, _raio_circulo * 0.105)
	_chip_start.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chip_start.add_theme_stylebox_override("panel", _style_legenda_fisica(_cor_secundaria))
	_conteudo_circular.add_child(_chip_start)

	_label_start = _label("START", int(_raio_circulo * 0.031), HORIZONTAL_ALIGNMENT_CENTER)
	_label_start.size = _chip_start.size
	_chip_start.add_child(_label_start)


func _style_legenda_fisica(cor: Color) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.005, 0.010, 0.022, 0.96)
	sb.border_color = Color(cor.r, cor.g, cor.b, 0.96)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(5)
	sb.shadow_color = Color(cor.r, cor.g, cor.b, 0.18)
	sb.shadow_size = 5
	return sb


func _criar_itens_lista() -> void:
	var altura_item: float = _lista_container.size.y / float(ITENS_VISIVEIS + 0.55)
	for i in range(_cenas.size()):
		var item: Panel = Panel.new()
		item.size = Vector2(_lista_container.size.x, altura_item * 0.78)
		item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item.add_theme_stylebox_override("panel", _style_item(false))
		_lista_container.add_child(item)

		# Cada scene mostra sua própria capa, sem reaproveitar a imagem da seleção anterior.
		var miniatura: TextureRect = TextureRect.new()
		miniatura.position = Vector2(item.size.y * 0.10, item.size.y * 0.10)
		miniatura.size = Vector2(item.size.y * 0.80, item.size.y * 0.80)
		miniatura.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		miniatura.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		miniatura.texture = _cenas[i].get("capa", null)
		miniatura.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item.add_child(miniatura)

		var texto_x: float = miniatura.position.x + miniatura.size.x + item.size.x * 0.045
		var label: Label = _label(
			str(_cenas[i].get("nome", "MÚSICA")),
			int(_raio_circulo * 0.035),
			HORIZONTAL_ALIGNMENT_LEFT
		)
		label.position = Vector2(texto_x, 0.0)
		label.size = Vector2(item.size.x - texto_x - item.size.x * 0.035, item.size.y)
		label.clip_text = true
		item.add_child(label)

		_itens_lista.append(item)
		_labels_lista.append(label)
		_capas_lista.append(miniatura)
		_alvos_x_lista.append(item.position.x)
		_alvos_y_lista.append(item.position.y)
		_alvos_alpha_lista.append(0.0)
		_alvos_escala_lista.append(Vector2(0.97, 0.97))
		_alvos_rotacao_lista.append(0.0)


func _style_hud_vazio() -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.010, 0.014, 0.030, 0.96)
	sb.border_color = Color(0.76, 0.80, 0.90, 0.50)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(18)
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	sb.shadow_size = 12
	return sb


func _style_painel_info() -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.006, 0.010, 0.022, 0.92)
	sb.border_color = Color(_cor_atual.r, _cor_atual.g, _cor_atual.b, 0.62)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.shadow_size = 0
	return sb


func _style_item(selecionado: bool) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = (
		Color(0.018, 0.028, 0.052, 0.96)
		if selecionado
		else Color(0.008, 0.013, 0.026, 0.88)
	)
	sb.border_color = (
		Color(_cor_secundaria.r, _cor_secundaria.g, _cor_secundaria.b, 0.90)
		if selecionado
		else Color(0.48, 0.56, 0.68, 0.16)
	)
	sb.border_width_left = 5 if selecionado else 1
	sb.border_width_top = 2 if selecionado else 1
	sb.border_width_right = 2 if selecionado else 1
	sb.border_width_bottom = 2 if selecionado else 1
	sb.set_corner_radius_all(16)
	sb.shadow_color = (
		Color(_cor_atual.r, _cor_atual.g, _cor_atual.b, 0.13)
		if selecionado
		else Color(0.0, 0.0, 0.0, 0.12)
	)
	sb.shadow_size = 5 if selecionado else 1
	return sb


func _label(texto: String, tamanho: int, alinhamento: HorizontalAlignment) -> Label:
	var label: Label = Label.new()
	label.text = texto
	label.horizontal_alignment = alinhamento
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", max(14, tamanho))
	label.add_theme_color_override("font_color", Color(0.98, 0.99, 1.0, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.96))
	label.add_theme_constant_override("outline_size", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _detectar_cenas() -> void:
	_cenas.clear()
	var dir: DirAccess = DirAccess.open(PASTA_CENAS)
	if dir == null:
		push_error("Pasta de cenas não encontrada: " + PASTA_CENAS)
		return

	var arquivos: PackedStringArray = dir.get_files()
	arquivos.sort()
	for arquivo in arquivos:
		if arquivo.get_extension().to_lower() != "tscn":
			continue

		var arquivo_lower: String = arquivo.to_lower()
		if CENAS_EXCLUIDAS.has(arquivo_lower):
			continue
		if arquivo_lower == scene_file_path.get_file().to_lower():
			continue

		var chave: String = arquivo.get_basename()
		var cores: Array[Color] = _tema(arquivo, chave)
		var caminho_capa: String = _capa_para(arquivo, chave)
		var textura: Texture2D = (
			load(caminho_capa) as Texture2D
			if not caminho_capa.is_empty() and ResourceLoader.exists(caminho_capa)
			else null
		)

		_cenas.append({
			"path": PASTA_CENAS.path_join(arquivo),
			"arquivo": arquivo,
			"chave": chave,
			"nome": _nome_exibicao(chave),
			"categoria": str(CATEGORIA_POR_ARQUIVO.get(arquivo_lower, "OUTRAS")),
			"cor": cores[0],
			"cor2": cores[1],
			"capa": textura,
			"video": _video_para(chave),
		})

	# Ordenação estável e previsível: nome exibido, depois nome do arquivo.
	_cenas.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var nome_a: String = str(a.get("nome", "")).strip_edges()
		var nome_b: String = str(b.get("nome", "")).strip_edges()
		var comparacao: int = nome_a.naturalnocasecmp_to(nome_b)
		if comparacao == 0:
			return str(a.get("arquivo", "")).naturalnocasecmp_to(str(b.get("arquivo", ""))) < 0
		return comparacao < 0
	)


func _tema(arquivo: String, chave: String) -> Array[Color]:
	var identificador: String = (arquivo + " " + chave).to_lower()
	if identificador.contains("carmine"):
		return [Color(0.96, 0.025, 0.075), Color(1.0, 0.72, 0.12)]
	if identificador.contains("dragon"):
		return [Color(1.0, 0.30, 0.025), Color(1.0, 0.88, 0.055)]
	if identificador.contains("rick") or identificador.contains("morty"):
		return [Color(0.12, 1.0, 0.40), Color(0.10, 0.58, 1.0)]
	if identificador.contains("fairy"):
		return [Color(0.16, 0.62, 1.0), Color(1.0, 0.24, 0.72)]
	if identificador.contains("naruto") or identificador.contains("naturo"):
		return [Color(1.0, 0.43, 0.035), Color(0.12, 0.64, 1.0)]
	if identificador.contains("demon"):
		return [Color(0.96, 0.035, 0.09), Color.WHITE]
	if identificador.contains("soul"):
		return [Color(0.56, 0.16, 1.0), Color.WHITE]
	return [Color.WHITE, Color.WHITE]


func _capa_para(arquivo: String, chave: String) -> String:
	var arquivo_lower: String = arquivo.to_lower()
	var chave_lower: String = chave.to_lower()

	# Carmine possui fallback explícito porque o arquivo pode estar em formatos/pastas diferentes.
	if arquivo_lower == "carmine.tscn" or chave_lower.contains("carmine"):
		var capas_carmine: Array[String] = [
			"res://images/carmine.jpeg",
			"res://images/carmine.jpg",
			"res://images/carmine.png",
			"res://images/capas_scenes/carmine.jpeg",
			"res://images/capas_scenes/carmine.jpg",
			"res://images/capas_scenes/carmine.png",
			"res://images/one_piece_carmine.jpeg",
			"res://images/one-piece-carmine.jpeg",
		]
		for caminho_carmine in capas_carmine:
			if ResourceLoader.exists(caminho_carmine):
				return caminho_carmine

	if CAPAS_POR_ARQUIVO.has(arquivo_lower):
		var cadastrada: String = str(CAPAS_POR_ARQUIVO[arquivo_lower])
		if ResourceLoader.exists(cadastrada):
			return cadastrada

	var candidatos: Array[String] = [
		PASTA_CAPAS.path_join(chave + ".png"),
		PASTA_CAPAS.path_join(chave + ".jpg"),
		PASTA_CAPAS.path_join(chave + ".jpeg"),
		"res://images/" + chave + ".png",
		"res://images/" + chave + ".jpg",
		"res://images/" + chave + ".jpeg",
	]
	for caminho in candidatos:
		if ResourceLoader.exists(caminho):
			return caminho
	return ""


func _video_para(chave: String) -> String:
	var candidatos: Array[String] = [
		"res://medias/" + chave + ".ogv",
		"res://videos/" + chave + ".ogv",
	]
	for caminho in candidatos:
		if ResourceLoader.exists(caminho):
			return caminho
	return ""


func _nome_exibicao(chave: String) -> String:
	return chave.replace("_", " ").replace("-", " ").capitalize()


func _aplicar_selecao(novo_indice: int, imediato: bool = false) -> void:
	if _cenas.is_empty():
		return

	_indice = posmod(novo_indice, _cenas.size())
	var cena: Dictionary = _cenas[_indice]
	_cor_atual = cena.get("cor", Color.WHITE)
	_cor_secundaria = cena.get("cor2", Color.WHITE)

	_atualizar_lista()
	if imediato:
		_aplicar_posicoes_lista_imediatas()
	_atualizar_info()
	_atualizar_fundo(cena, imediato)
	_atualizar_leds_menu(cena)
	if _chip_next != null and is_instance_valid(_chip_next):
		_chip_next.add_theme_stylebox_override("panel", _style_legenda_fisica(_cor_atual))
	if _chip_start != null and is_instance_valid(_chip_start):
		_chip_start.add_theme_stylebox_override("panel", _style_legenda_fisica(_cor_secundaria))


func _mudar_selecao(direcao: int) -> void:
	if _cenas.is_empty() or _em_transicao:
		return
	_direcao_transicao_musica = 1.0 if direcao >= 0 else -1.0
	_iniciar_transicao_musica(_indice + direcao)


func _iniciar_transicao_musica(novo_indice: int) -> void:
	if _painel_info == null or not is_instance_valid(_painel_info):
		_aplicar_selecao(novo_indice)
		return

	if _tween_transicao_musica != null and _tween_transicao_musica.is_valid():
		_tween_transicao_musica.kill()

	_em_transicao = true
	var deslocamento: float = _raio_circulo * 0.040 * _direcao_transicao_musica
	var escala_saida: Vector2 = Vector2(0.985, 0.985)

	_painel_info.pivot_offset = _painel_info.size * 0.5
	_tween_transicao_musica = create_tween()
	_tween_transicao_musica.set_parallel(true)
	_tween_transicao_musica.set_trans(Tween.TRANS_CUBIC)
	_tween_transicao_musica.set_ease(Tween.EASE_IN)
	_tween_transicao_musica.tween_property(_painel_info, "position:x", _painel_info_x_base - deslocamento, 0.13)
	_tween_transicao_musica.tween_property(_painel_info, "modulate:a", 0.0, 0.11)
	_tween_transicao_musica.tween_property(_painel_info, "scale", escala_saida, 0.13)

	_tween_transicao_musica.chain().tween_callback(func() -> void:
		_aplicar_selecao(novo_indice)
		_painel_info.position.x = _painel_info_x_base + deslocamento
		_painel_info.modulate.a = 0.0
		_painel_info.scale = Vector2(0.985, 0.985)
	)

	_tween_transicao_musica.chain().set_parallel(true)
	_tween_transicao_musica.set_trans(Tween.TRANS_QUINT)
	_tween_transicao_musica.set_ease(Tween.EASE_OUT)
	_tween_transicao_musica.tween_property(_painel_info, "position:x", _painel_info_x_base, 0.24)
	_tween_transicao_musica.tween_property(_painel_info, "modulate:a", 1.0, 0.20)
	_tween_transicao_musica.tween_property(_painel_info, "scale", Vector2.ONE, 0.24)

	_tween_transicao_musica.chain().tween_callback(func() -> void:
		_painel_info.position.x = _painel_info_x_base
		_painel_info.modulate.a = 1.0
		_painel_info.scale = Vector2.ONE
		_em_transicao = false
	)


func _atualizar_lista() -> void:
	if _itens_lista.is_empty():
		return

	var altura_item: float = _lista_container.size.y / float(ITENS_VISIVEIS + 0.35)
	var margem_scroll: float = _lista_container.size.y * MARGEM_SCROLL_LISTA_RATIO
	var centro_y: float = _lista_container.size.y * 0.5
	var meio_item: float = _itens_lista[0].size.y * 0.5
	var primeiro_centro: float = margem_scroll + meio_item
	var ultimo_centro: float = _lista_container.size.y - margem_scroll - meio_item

	var centro_selecionado: float = centro_y
	if _indice == 0:
		centro_selecionado = primeiro_centro
	elif _indice == _cenas.size() - 1:
		centro_selecionado = ultimo_centro

	for i in range(_itens_lista.size()):
		var relativo: int = i - _indice
		var distancia: float = absf(float(relativo))
		var item: Panel = _itens_lista[i]

		var alvo_y: float = centro_selecionado + float(relativo) * altura_item - meio_item
		var alvo_x: float = _lista_container.size.x * (0.026 if relativo == 0 else 0.0)
		var dentro_area: bool = (
			alvo_y + item.size.y >= margem_scroll * 0.25
			and alvo_y <= _lista_container.size.y - margem_scroll * 0.25
		)

		var alvo_alpha: float = (
			1.0 if relativo == 0
			else maxf(0.0, 0.80 - distancia * 0.19)
		)
		var alvo_escala: Vector2 = (
			Vector2(1.0, 1.0) if relativo == 0
			else Vector2(0.955, 0.955)
		)

		_alvos_x_lista[i] = alvo_x
		_alvos_y_lista[i] = alvo_y
		_alvos_alpha_lista[i] = alvo_alpha if dentro_area else 0.0
		_alvos_escala_lista[i] = alvo_escala
		_alvos_rotacao_lista[i] = 0.0

		item.visible = true
		item.pivot_offset = item.size * 0.5
		item.add_theme_stylebox_override("panel", _style_item(relativo == 0))
		_labels_lista[i].add_theme_color_override(
			"font_color",
			Color.WHITE if relativo == 0 else Color(0.78, 0.82, 0.90, 1.0)
		)


func _aplicar_posicoes_lista_imediatas() -> void:
	if _itens_lista.size() != _alvos_y_lista.size():
		return
	for i in range(_itens_lista.size()):
		var item: Panel = _itens_lista[i]
		item.position.x = _alvos_x_lista[i]
		item.position.y = _alvos_y_lista[i]
		item.modulate.a = _alvos_alpha_lista[i]
		item.scale = _alvos_escala_lista[i]
		item.rotation = _alvos_rotacao_lista[i]
		item.visible = item.modulate.a > 0.015


func _atualizar_animacao_lista(delta: float) -> void:
	if _itens_lista.is_empty() or _alvos_y_lista.size() != _itens_lista.size():
		return

	var fator_pos: float = 1.0 - exp(-VELOCIDADE_SCROLL_LISTA * delta)
	var fator_escala: float = 1.0 - exp(-VELOCIDADE_ESCALA_LISTA * delta)
	var fator_alpha: float = 1.0 - exp(-VELOCIDADE_ALPHA_LISTA * delta)

	for i in range(_itens_lista.size()):
		var item: Panel = _itens_lista[i]
		item.position.x = lerpf(item.position.x, _alvos_x_lista[i], fator_pos)
		item.position.y = lerpf(item.position.y, _alvos_y_lista[i], fator_pos)
		item.modulate.a = lerpf(item.modulate.a, _alvos_alpha_lista[i], fator_alpha)
		item.scale = item.scale.lerp(_alvos_escala_lista[i], fator_escala)
		item.rotation = lerpf(item.rotation, _alvos_rotacao_lista[i], fator_escala)
		item.visible = item.modulate.a > 0.012


func _atualizar_info() -> void:
	if _cenas.is_empty():
		return

	var cena: Dictionary = _cenas[_indice]
	_capa_info.texture = cena.get("capa", null)
	_capa_info.visible = _capa_info.texture != null
	_label_track.text = "TRACK %02d / %02d" % [_indice + 1, _cenas.size()]
	_label_nome.text = str(cena.get("nome", "MÚSICA"))
	_label_categoria.text = "CATEGORIA  " + str(cena.get("categoria", "OUTRAS"))
	_label_tempo.text = "TEMPO  " + _tempo_musica(cena)

	var recorde: Dictionary = _recorde_da_cena(cena)
	var facil: float = float(recorde.get("facil", 0.0))
	var dificil: float = float(recorde.get("dificil", 0.0))
	var melhor: float = maxf(facil, dificil)

	_label_facil.text = "FÁCIL       " + _formatar_percentual(facil)
	_label_dificil.text = "DIFÍCIL     " + _formatar_percentual(dificil)
	_label_melhor.text = "MELHOR      " + _formatar_percentual(melhor)


func _atualizar_fundo(cena: Dictionary, imediato: bool) -> void:
	_tempo_preview_parado = 0.0
	_tempo_preview_rodando = 0.0
	_preview_indice = _indice
	_preview_iniciado = false

	if _fundo_video != null and is_instance_valid(_fundo_video):
		if _fundo_video.is_playing():
			_fundo_video.stop()
		_fundo_video.stream = null
		_fundo_video.modulate.a = 0.0

	if _faixa_transicao != null and is_instance_valid(_faixa_transicao):
		_faixa_transicao.color = Color(_cor_atual.r, _cor_atual.g, _cor_atual.b, 0.0)


func _processar_preview_video(delta: float) -> void:
	if _em_transicao or _cenas.is_empty() or _preview_indice != _indice:
		return

	if not _preview_iniciado:
		_tempo_preview_parado += delta
		if _tempo_preview_parado < PREVIEW_ESPERA_SEG:
			return
		_iniciar_preview_da_selecao()
		return

	if _fundo_video == null or not is_instance_valid(_fundo_video):
		return
	if not _fundo_video.is_playing():
		return

	_tempo_preview_rodando += delta
	if _tempo_preview_rodando >= PREVIEW_DURACAO_SEG:
		_parar_preview_video()


func _iniciar_preview_da_selecao() -> void:
	_preview_iniciado = true
	_tempo_preview_rodando = 0.0
	if _indice < 0 or _indice >= _cenas.size():
		return

	var caminho_video: String = str(_cenas[_indice].get("video", ""))
	if caminho_video.is_empty() or not ResourceLoader.exists(caminho_video):
		return

	var recurso: Resource = load(caminho_video)
	if not recurso is VideoStream:
		return

	_fundo_video.stream = recurso as VideoStream
	_fundo_video.modulate.a = 0.0
	_fundo_video.play()

	var tw: Tween = create_tween()
	tw.set_trans(Tween.TRANS_QUINT)
	tw.set_ease(Tween.EASE_OUT)
	tw.tween_property(_fundo_video, "modulate:a", 0.72, 0.45)


func _parar_preview_video() -> void:
	if _fundo_video == null or not is_instance_valid(_fundo_video):
		return
	var tw: Tween = create_tween()
	tw.set_trans(Tween.TRANS_CUBIC)
	tw.set_ease(Tween.EASE_IN)
	tw.tween_property(_fundo_video, "modulate:a", 0.0, 0.28)
	tw.finished.connect(func() -> void:
		if _fundo_video != null and is_instance_valid(_fundo_video):
			_fundo_video.stop()
	)



func _atualizar_borda_paineis() -> void:
	if _painel_info == null or not is_instance_valid(_painel_info):
		return
	_painel_info.add_theme_stylebox_override("panel", _style_painel_info())


func _tempo_musica(cena: Dictionary) -> String:
	var chave: String = str(cena.get("chave", ""))
	for extensao in ["mp3", "ogg", "wav"]:
		var caminho: String = "res://songs/%s.%s" % [chave, extensao]
		if ResourceLoader.exists(caminho):
			var recurso: Resource = load(caminho)
			if recurso is AudioStream:
				var total: int = int(round((recurso as AudioStream).get_length()))
				return "%d:%02d" % [int(total / 60), total % 60]
	return "--:--"


func _recorde_da_cena(cena: Dictionary) -> Dictionary:
	var chaves: Array[String] = [
		str(cena.get("chave", "")),
		str(cena.get("arquivo", "")),
		str(cena.get("path", "")),
	]
	for chave in chaves:
		if not _recordes.has(chave):
			continue

		var valor: Variant = _recordes[chave]
		if valor is Dictionary:
			var dados: Dictionary = valor
			return {
				"facil": float(dados.get("facil", dados.get("easy", dados.get("percentual", 0.0)))),
				"dificil": float(dados.get("dificil", dados.get("hard", dados.get("percentual", 0.0)))),
			}
		return {"facil": float(valor), "dificil": float(valor)}

	return {"facil": 0.0, "dificil": 0.0}


func _formatar_percentual(valor: float) -> String:
	var percentual: float = valor / 100.0 if valor > 100.0 else valor
	return ("%.2f%%" % percentual).replace(".", ",")


func _carregar_recordes() -> void:
	_recordes = {}
	if not FileAccess.file_exists(CAMINHO_RECORDES):
		return

	var arquivo: FileAccess = FileAccess.open(CAMINHO_RECORDES, FileAccess.READ)
	if arquivo == null:
		return

	var resultado: Variant = JSON.parse_string(arquivo.get_as_text())
	if resultado is Dictionary:
		var raiz: Dictionary = resultado
		var telas: Variant = raiz.get("telas", raiz)
		if telas is Dictionary:
			_recordes = telas


func _serial_menu_configurar() -> void:
	if not SERIAL_MENU_ATIVADO:
		return
	_serial_menu_base_dir = ProjectSettings.globalize_path("user://hit_music_serial")
	_serial_menu_spool_dir = _serial_menu_base_dir.path_join("spool")
	_serial_menu_estado_path = _serial_menu_base_dir.path_join("menu_state.cmd")
	DirAccess.make_dir_recursive_absolute(_serial_menu_spool_dir)


func _serial_menu_limpar_fila_antiga() -> void:
	if _serial_menu_spool_dir.is_empty():
		return
	var pasta: DirAccess = DirAccess.open(_serial_menu_spool_dir)
	if pasta == null:
		return
	for nome_arquivo in pasta.get_files():
		if nome_arquivo.ends_with(".cmd") or nome_arquivo.ends_with(".tmp"):
			DirAccess.remove_absolute(_serial_menu_spool_dir.path_join(nome_arquivo))


func _serial_menu_enviar(comando: String, forcar: bool = false) -> void:
	if not SERIAL_MENU_ATIVADO or comando.is_empty():
		return
	if not forcar and comando == _ultima_assinatura_led_menu:
		return

	_serial_menu_configurar()

	# MENU usa sempre o mesmo arquivo. Ele é sobrescrito atomicamente,
	# portanto nunca cria backlog e nunca deixa comandos antigos para trás.
	var nome: String
	if comando.begins_with("MENU "):
		nome = "menu_atual.cmd"
	else:
		_serial_menu_sequencia += 1
		nome = "cmd_%020d_%06d_%d.cmd" % [
			Time.get_ticks_usec(), _serial_menu_sequencia, OS.get_process_id()
		]

	var final_path: String = _serial_menu_spool_dir.path_join(nome)
	var temp_path: String = final_path + ".tmp"
	if FileAccess.file_exists(temp_path):
		DirAccess.remove_absolute(temp_path)

	var arquivo: FileAccess = FileAccess.open(temp_path, FileAccess.WRITE)
	if arquivo == null:
		push_warning("Não foi possível enviar o comando dos LEDs do menu.")
		return
	arquivo.store_string(comando + "\n")
	arquivo.flush()
	arquivo.close()

	if FileAccess.file_exists(final_path):
		DirAccess.remove_absolute(final_path)
	var erro: Error = DirAccess.rename_absolute(temp_path, final_path)
	if erro == OK:
		_ultima_assinatura_led_menu = comando
		_tempo_reenvio_led_menu = 0.0
	else:
		DirAccess.remove_absolute(temp_path)


func _reafirmar_led_menu_sem_fila() -> void:
	if _comando_led_menu_atual.is_empty() or _em_transicao:
		return
	if _tempo_led_reafirmar < LED_MENU_REAFIRMAR_SEG:
		return
	_tempo_led_reafirmar = 0.0
	_serial_menu_enviar(_comando_led_menu_atual, true)


func _manter_leds_menu_acesos() -> void:
	# Intencionalmente vazio: WS2812 mantém a última cor sem heartbeat.
	# Reenvios periódicos criavam backlog e permitiam que comandos antigos
	# fossem processados depois, apagando D2 e D3.
	return


func _cor_byte(cor: Color, componente: String) -> int:
	var valor: float = cor.r
	if componente == "g":
		valor = cor.g
	elif componente == "b":
		valor = cor.b
	return clampi(int(round(valor * 255.0)), 0, 255)


func _atualizar_leds_menu(cena: Dictionary) -> void:
	# Consolida várias mudanças rápidas em apenas um comando.
	# Cenas sem tema definido já chegam aqui como branco/branco.
	var principal: Color = cena.get("cor", Color.WHITE)
	var secundaria: Color = cena.get("cor2", Color.WHITE)
	_comando_led_pendente = "MENU %d %d %d %d %d %d" % [
		_cor_byte(principal, "r"), _cor_byte(principal, "g"), _cor_byte(principal, "b"),
		_cor_byte(secundaria, "r"), _cor_byte(secundaria, "g"), _cor_byte(secundaria, "b")
	]
	_tempo_comando_led_pendente = 0.0


func _processar_led_menu_pendente(delta: float) -> void:
	if _comando_led_pendente.is_empty():
		return
	_tempo_comando_led_pendente += delta
	if _tempo_comando_led_pendente < ATRASO_ATUALIZACAO_LED_MENU:
		return

	_comando_led_menu_atual = _comando_led_pendente
	_comando_led_pendente = ""
	_tempo_comando_led_pendente = 0.0
	_serial_menu_enviar(_comando_led_menu_atual, true)


func _selecionar_atual() -> void:
	if _em_transicao or _cenas.is_empty():
		return

	var caminho: String = str(_cenas[_indice].get("path", ""))
	if caminho.is_empty() or not ResourceLoader.exists(caminho):
		push_error("Cena não encontrada: " + caminho)
		return

	_em_transicao = true
	_destino = caminho

	# Para de manter o modo MENU antes de entregar o controle à próxima cena.
	_parar_preview_video()
	_comando_led_menu_atual = ""
	_comando_led_pendente = ""
	if not _serial_menu_estado_path.is_empty() and FileAccess.file_exists(_serial_menu_estado_path):
		DirAccess.remove_absolute(_serial_menu_estado_path)
	_serial_menu_limpar_fila_antiga()
	_serial_menu_enviar("CLEAR", true)

	var tw: Tween = create_tween()
	tw.set_trans(Tween.TRANS_QUINT)
	tw.set_ease(Tween.EASE_IN)
	tw.tween_property(self, "_portal_progresso", 0.0, DURACAO_TRANSICAO)
	tw.finished.connect(func() -> void:
		get_tree().change_scene_to_file(_destino)
	)


func _desenhar_portal_frontal() -> void:
	if _portal_ui == null or not is_instance_valid(_portal_ui):
		return

	# PORTAL correto: a linha externa que separa o preto do oval/círculo.
	# Fica por fora da área jogável, exatamente na borda física.
	var pulso: float = 0.5 + 0.5 * sin(_tempo * 0.90)
	var raio_portal: float = _raio_circulo * 1.002
	var espessura_base: float = maxf(7.0, _raio_circulo * 0.018)
	var espessura_luz: float = maxf(3.0, _raio_circulo * 0.008)

	# Halo externo largo, sem invadir os cards.
	_portal_ui.draw_arc(
		_centro_circulo,
		raio_portal + espessura_base * 0.45,
		0.0,
		TAU,
		240,
		Color(_cor_atual.r, _cor_atual.g, _cor_atual.b, 0.18 + pulso * 0.08),
		espessura_base * 2.2,
		true
	)

	# Base contínua com a cor principal da tela.
	_portal_ui.draw_arc(
		_centro_circulo,
		raio_portal,
		0.0,
		TAU,
		240,
		Color(_cor_atual.r, _cor_atual.g, _cor_atual.b, 0.96),
		espessura_base,
		true
	)

	# Quatro trechos da cor secundária deslizam sobre a linha principal.
	var giro: float = _tempo * 0.18
	for i in range(4):
		var inicio: float = giro + float(i) * TAU * 0.25
		_portal_ui.draw_arc(
			_centro_circulo,
			raio_portal,
			inicio,
			inicio + TAU * 0.115,
			40,
			Color(_cor_secundaria.r, _cor_secundaria.g, _cor_secundaria.b, 0.98),
			espessura_luz,
			true
		)

	# Filete branco mínimo na separação interna.
	_portal_ui.draw_arc(
		_centro_circulo,
		_raio_circulo * 0.986,
		0.0,
		TAU,
		240,
		Color(1.0, 1.0, 1.0, 0.18 + pulso * 0.08),
		maxf(1.2, _raio_circulo * 0.0025),
		true
	)



func _draw() -> void:
	var tela: Vector2 = get_viewport_rect().size
	var espessura_abertura: float = maxf(5.0, _raio_circulo * 0.014)
	draw_rect(Rect2(Vector2.ZERO, tela), Color(0.003, 0.006, 0.015, 1.0))

	# Abertura e fechamento partem do centro exato do círculo.
	if _portal_progresso < 0.999:
		var raio_aberto: float = _raio_circulo * _portal_progresso
		var raio_externo: float = tela.length()
		for i in range(180):
			var p0_ang: float = TAU * float(i) / 180.0
			var p1_ang: float = TAU * float(i + 1) / 180.0
			var p0: Vector2 = _centro_circulo + Vector2(cos(p0_ang), sin(p0_ang)) * raio_aberto
			var p1: Vector2 = _centro_circulo + Vector2(cos(p1_ang), sin(p1_ang)) * raio_aberto
			var e1: Vector2 = _centro_circulo + Vector2(cos(p1_ang), sin(p1_ang)) * raio_externo
			var e0: Vector2 = _centro_circulo + Vector2(cos(p0_ang), sin(p0_ang)) * raio_externo
			draw_colored_polygon(
				PackedVector2Array([p0, p1, e1, e0]),
				Color(0.002, 0.004, 0.012, 1.0)
			)
		draw_arc(
			_centro_circulo,
			raio_aberto,
			0.0,
			TAU,
			180,
			Color(_cor_atual.r, _cor_atual.g, _cor_atual.b, 0.92),
			maxf(4.0, espessura_abertura * 0.75),
			true
		)


func _ao_redimensionar() -> void:
	_recalcular_geometria()
	_montar_interface()
	_aplicar_selecao(_indice, true)
