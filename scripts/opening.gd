extends Node2D
## ============================================================
## ABERTURA — HIT MUSIC (mesa redonda / tela circular)
##
## Reaproveita o MESMO padrão físico já usado no play.gd do
## BEAT ORBIT: a área jogável (e aqui, a área da abertura) é
## recortada em círculo de 38 cm de circunferência física,
## com tudo fora do círculo mascarado em preto -- exatamente
## como a mesa redonda física do gabinete.
##
## O que essa cena faz:
## 1. Carrega a imagem "hit_musi.png" como fundo, encaixada e
##    cortada (cover) dentro do diâmetro do círculo.
## 2. Aplica um shader no fundo que faz as áreas neon da própria
##    arte (rosa/ciano) pulsarem em brilho, com um leve anel de
##    onda saindo do centro.
## 3. Mascara tudo fora do círculo em preto e usa uma borda temática
##    limpa, igual à linguagem visual das scenes, sem partículas.
## 4. Mostra "APERTE START" pulsando perto da base do círculo.
## 5. No input_start, dispara o sinal `iniciar_jogo` (troque pelo
##    change_scene_to_file da sua próxima cena).
##
## Pasta esperada:
## res://images/hitmusi.png
## ============================================================

signal iniciar_jogo


# -----------------------------------------------------------------------------
# PORTAL CIRCULAR — DESENHADO DIRETAMENTE, SEM SHADER DE RECORTE
# -----------------------------------------------------------------------------
# O portal é uma máscara radial real:
# - raio 0: tela completamente fechada no centro;
# - raio máximo: tela circular totalmente revelada;
# - a borda usa somente as duas cores da música selecionada.
class PortalCircular:
	extends Node2D

	signal animacao_concluida

	var tamanho_tela: Vector2 = Vector2(1080.0, 1920.0)
	var raio_maximo: float = 500.0
	var raio_atual: float = 0.0
	var cor_principal: Color = Color(0.12, 1.0, 0.40, 1.0)
	var cor_secundaria: Color = Color(0.10, 0.58, 1.0, 1.0)

	var _animando: bool = false
	var _raio_inicio: float = 0.0
	var _raio_fim: float = 0.0
	var _duracao: float = 1.0
	var _tempo_animacao: float = 0.0
	var _atraso: float = 0.0
	var _liberar_pai_ao_final: bool = false

	func configurar(
		novo_tamanho: Vector2,
		novo_raio_maximo: float,
		nova_cor_principal: Color,
		nova_cor_secundaria: Color
	) -> void:
		tamanho_tela = novo_tamanho
		raio_maximo = max(novo_raio_maximo, 1.0)
		cor_principal = nova_cor_principal
		cor_secundaria = nova_cor_secundaria
		queue_redraw()

	func iniciar_animacao(
		de: float,
		para: float,
		duracao_seg: float,
		liberar_pai_ao_final: bool = false,
		atraso_seg: float = 0.0
	) -> void:
		_raio_inicio = max(de, 0.0)
		_raio_fim = max(para, 0.0)
		raio_atual = _raio_inicio
		_duracao = max(duracao_seg, 0.01)
		_tempo_animacao = 0.0
		_atraso = max(atraso_seg, 0.0)
		_liberar_pai_ao_final = liberar_pai_ao_final
		_animando = true
		visible = true
		set_process(true)
		queue_redraw()

	func cancelar_animacao() -> void:
		_animando = false
		_liberar_pai_ao_final = false
		set_process(false)

	func _process(delta: float) -> void:
		if not _animando:
			return

		if _atraso > 0.0:
			_atraso = max(_atraso - delta, 0.0)
			queue_redraw()
			return

		_tempo_animacao += delta
		var t: float = clamp(_tempo_animacao / _duracao, 0.0, 1.0)
		# Smoothstep: movimento contínuo, sem pulo no começo ou no fim.
		var suave: float = t * t * (3.0 - 2.0 * t)
		raio_atual = lerp(_raio_inicio, _raio_fim, suave)
		queue_redraw()

		if t >= 1.0:
			raio_atual = _raio_fim
			_animando = false
			set_process(false)
			queue_redraw()
			animacao_concluida.emit()

			if _liberar_pai_ao_final:
				var pai: Node = get_parent()
				if pai != null and is_instance_valid(pai):
					pai.queue_free()

	func _draw() -> void:
		if not visible:
			return

		var raio_externo: float = tamanho_tela.length() * 0.5 + 96.0
		var raio_interno: float = clamp(raio_atual, 0.0, raio_externo)
		var fundo: Color = Color(0.0015, 0.003, 0.009, 1.0)
		var segmentos_mascara: int = 220

		# Preto absoluto fora da tela circular.
		if raio_interno <= 0.8:
			draw_circle(Vector2.ZERO, raio_externo, fundo)
		else:
			for i in range(segmentos_mascara):
				var a0: float = TAU * float(i) / float(segmentos_mascara)
				var a1: float = TAU * float(i + 1) / float(segmentos_mascara)
				var interno_0: Vector2 = Vector2(cos(a0), sin(a0)) * raio_interno
				var interno_1: Vector2 = Vector2(cos(a1), sin(a1)) * raio_interno
				var externo_1: Vector2 = Vector2(cos(a1), sin(a1)) * raio_externo
				var externo_0: Vector2 = Vector2(cos(a0), sin(a0)) * raio_externo
				draw_colored_polygon(
					PackedVector2Array([interno_0, interno_1, externo_1, externo_0]),
					fundo
				)

		if raio_interno <= 1.5:
			return

		var tempo: float = float(Time.get_ticks_msec()) * 0.001
		var pulso: float = 0.5 + 0.5 * sin(tempo * 1.55)
		var espessura_base: float = max(3.0, raio_interno * 0.0062)

		# Halo discreto exatamente na separação entre o preto e o círculo.
		draw_arc(
			Vector2.ZERO,
			raio_interno + 5.0,
			0.0,
			TAU,
			260,
			Color(cor_principal.r, cor_principal.g, cor_principal.b, 0.12 + pulso * 0.05),
			espessura_base * 3.2,
			true
		)

		# Linha externa principal da scene.
		draw_arc(
			Vector2.ZERO,
			raio_interno + 1.0,
			0.0,
			TAU,
			280,
			Color(cor_principal.r, cor_principal.g, cor_principal.b, 0.97),
			espessura_base,
			true
		)

		# Linha interna secundária, sem partículas.
		draw_arc(
			Vector2.ZERO,
			max(raio_interno - espessura_base * 1.35, 0.0),
			0.0,
			TAU,
			280,
			Color(cor_secundaria.r, cor_secundaria.g, cor_secundaria.b, 0.90),
			max(1.8, espessura_base * 0.52),
			true
		)

		# Barras radiais internas iguais à linguagem das scenes do jogo.
		# São linhas contínuas e limpas; não são partículas soltas.
		var segmentos_borda: int = 72
		var linhas_halo: PackedVector2Array = PackedVector2Array()
		var linhas_cor: PackedVector2Array = PackedVector2Array()
		var raio_barras_interno: float = raio_interno * 0.902
		var raio_barras_base: float = raio_interno * 0.928
		var amplitude: float = raio_interno * (0.006 + pulso * 0.005)

		for i in range(segmentos_borda):
			var t: float = float(i) / float(segmentos_borda)
			var angulo: float = t * TAU
			var forma_1: float = abs(sin(angulo * 6.0 + tempo * 1.10))
			var forma_2: float = abs(sin(angulo * 10.0 - tempo * 0.74))
			var forma: float = clampf(0.42 + forma_1 * 0.42 + forma_2 * 0.16, 0.0, 1.0)
			var direcao: Vector2 = Vector2(cos(angulo), sin(angulo))
			var p0: Vector2 = direcao * raio_barras_interno
			var p1: Vector2 = direcao * (raio_barras_base + amplitude * forma)
			linhas_halo.append(p0)
			linhas_halo.append(p1)
			linhas_cor.append(p0)
			linhas_cor.append(p1)

		var mistura: float = 0.5 + 0.5 * sin(tempo * 0.52)
		var cor_borda: Color = cor_principal.lerp(cor_secundaria, mistura * 0.48)
		draw_multiline(
			linhas_halo,
			Color(cor_borda.r, cor_borda.g, cor_borda.b, 0.13),
			max(4.0, espessura_base * 1.8),
			true
		)
		draw_multiline(
			linhas_cor,
			Color(cor_borda.r, cor_borda.g, cor_borda.b, 0.78),
			max(1.3, espessura_base * 0.34),
			true
		)

		# Filete branco interno para acabamento de gabinete.
		draw_arc(
			Vector2.ZERO,
			raio_interno * 0.894,
			0.0,
			TAU,
			220,
			Color(1.0, 1.0, 1.0, 0.08 + pulso * 0.05),
			max(1.0, espessura_base * 0.24),
			true
		)




# --- Constantes físicas da mesa redonda (iguais às do Rick and Morty) ---
const RAIO_FISICO_CM: float = 48.0
const DIAMETRO_FISICO_CM: float = RAIO_FISICO_CM * 2.0
const CIRCUNFERENCIA_FISICA_CM: float = DIAMETRO_FISICO_CM * PI

## Mesmo tamanho visual usado na cena rick_morty: 98,5% do menor lado da tela.
const PORCENTAGEM_TELA_CIRCULO: float = 0.985
const CIRCULO_MARGEM_INFERIOR_RATIO: float = 0.012
const JANELA_TOPO_MARGEM_RATIO: float = 0.022
const JANELA_TOPO_ALTURA_RATIO: float = 0.205

## Feather da borda da máscara circular -- suaviza o corte.
const SUAVIZACAO_MASCARA_PX: float = 3.0

# --- Imagem de fundo ---
const PASTA_ABERTURA: String = "res://images/"
const IMAGEM_FUNDO: String = PASTA_ABERTURA + "hit_music.png"

# --- Música da abertura ---
# O script procura automaticamente as extensões mais comuns.
const CAMINHOS_MUSICA_ABERTURA: Array[String] = [
	"res://songs/opening_music.mp3",
	"res://songs/opening_music.ogg",
	"res://songs/opening_music.wav",
]
const VOLUME_MUSICA_ABERTURA_DB: float = -3.0
const VOLUME_INICIAL_MUSICA_DB: float = -30.0
const VOLUME_SAIDA_MUSICA_DB: float = -45.0
const DURACAO_FADE_ENTRADA_MUSICA: float = 0.65
const DURACAO_FADE_SAIDA_MUSICA: float = 0.72

# Portal temático compartilhado com o seletor para uma troca sem quadros cinza.
const META_TRANSICAO_PORTAL: String = "hit_music_transicao_portal"
const DURACAO_TRANSICAO_PORTAL_SEG: float = 1.32
const TEMPO_QUADRO_FINAL_PORTAL_SEG: float = 0.10
# Mesmas cores da primeira música do seletor (Rick and Morty).
const COR_PORTAL_PRINCIPAL: Color = Color(0.12, 1.0, 0.40, 1.0)
const COR_PORTAL_SECUNDARIA: Color = Color(0.10, 0.58, 1.0, 1.0)

# --- Cores neon da arte, usadas no pulso do texto e da borda ---
const COR_NEON_ROSA: Color = Color(1.0, 0.15, 0.85)
const COR_NEON_CIANO: Color = Color(0.25, 0.85, 1.0)

# --- LEDs / comunicação ---
# Toda comunicação passa pelo Autoload /root/LedClient.
var _led_assinatura_atual: String = ""
var _led_feedback_bloqueio_ate_msec: int = 0

# --- Nodes internos ---
var _sprite_fundo: Sprite2D
var _mascara_layer: CanvasLayer
var _hud_superior_layer: CanvasLayer
var _hud_superior: Panel
var _borda_portal_inicio: PortalCircular
var _label_start: Label
var _config_start: LabelSettings
var _tween_start: Tween
var _musica_abertura: AudioStreamPlayer
var _tween_musica: Tween
var _transicao_layer: CanvasLayer
var _portal_visual: PortalCircular
var _tween_transicao: Tween

var _raio_circulo_px: float = 0.0
var _centro_tela: Vector2 = Vector2.ZERO
var _ja_iniciando: bool = false
var _portal_entrada_em_andamento: bool = false


func _ready() -> void:
	var cliente_modo := get_node_or_null("/root/LedClient")
	if cliente_modo != null and cliente_modo.has_method("begin_opening"):
		cliente_modo.call("begin_opening")
	print("ABERTURA HIT MUSIC — PORTAL TEMÁTICO LIMPO UNIFICADO ATIVO")
	RenderingServer.set_default_clear_color(Color(0.002, 0.005, 0.018, 1.0))
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)  # padrão do gabinete: sem mouse visível
	var cliente := get_node_or_null("/root/LedClient")
	if cliente != null and cliente.has_method("ensure_bridge"):
		cliente.call("ensure_bridge")
	_arduino_enviar_forcado("ATTRACT")
	_montar_cena()
	_criar_transicao_portal()
	_criar_musica_abertura()
	_iniciar_pulso_start()
	_iniciar_portal_entrada()
	get_viewport().size_changed.connect(_on_tela_redimensionada)


func _process(_delta: float) -> void:
	var cliente_serial := get_node_or_null("/root/LedClient")
	if cliente_serial != null and cliente_serial.has_method("tick"):
		cliente_serial.call("tick")
	# A borda temática parada também é redesenhada para manter o movimento suave.
	if _borda_portal_inicio != null and is_instance_valid(_borda_portal_inicio):
		if _borda_portal_inicio.visible:
			_borda_portal_inicio.queue_redraw()

	if _portal_visual != null and is_instance_valid(_portal_visual):
		if _portal_visual.visible:
			_portal_visual.queue_redraw()

	if Input.is_action_just_pressed("input_start"):
		_ao_apertar_start()


func _input(event: InputEvent) -> void:
	# Tecla "1" também funciona como START (além do input_start do encoder).
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_1:
		_ao_apertar_start()


func _criar_tween_seguro() -> Tween:
	var arvore: SceneTree = get_tree()
	if arvore == null:
		return null

	var tween: Tween = arvore.create_tween()
	if tween == null:
		return null

	tween.bind_node(self)
	return tween



# ---------------------------------------------------------------
# MÚSICA DA ABERTURA
# ---------------------------------------------------------------
func _criar_musica_abertura() -> void:
	var caminho_encontrado: String = ""
	for caminho in CAMINHOS_MUSICA_ABERTURA:
		if ResourceLoader.exists(caminho):
			caminho_encontrado = caminho
			break

	if caminho_encontrado.is_empty():
		push_warning(
			"Música opening_music não encontrada. Coloque o arquivo em res://songs/ "
			+ "com extensão .mp3, .ogg ou .wav."
		)
		return

	var stream: Resource = load(caminho_encontrado)
	if not stream is AudioStream:
		push_warning("O arquivo opening_music não é um AudioStream válido: " + caminho_encontrado)
		return

	_musica_abertura = AudioStreamPlayer.new()
	_musica_abertura.name = "OpeningMusic"
	_musica_abertura.stream = stream
	_musica_abertura.volume_db = VOLUME_INICIAL_MUSICA_DB
	_musica_abertura.finished.connect(_ao_terminar_musica_abertura)
	add_child(_musica_abertura)
	_musica_abertura.play()

	_tween_musica = _criar_tween_seguro()
	if _tween_musica == null:
		_musica_abertura.volume_db = VOLUME_MUSICA_ABERTURA_DB
		return

	_tween_musica.set_trans(Tween.TRANS_SINE)
	_tween_musica.set_ease(Tween.EASE_OUT)
	_tween_musica.tween_property(
		_musica_abertura,
		"volume_db",
		VOLUME_MUSICA_ABERTURA_DB,
		DURACAO_FADE_ENTRADA_MUSICA
	)


func _ao_terminar_musica_abertura() -> void:
	# Mantém opening_music tocando em loop enquanto esta tela estiver aberta.
	if not _ja_iniciando and is_instance_valid(_musica_abertura):
		_musica_abertura.play()


func _abaixar_musica_e_abrir_seletor() -> void:
	if _tween_musica and _tween_musica.is_valid():
		_tween_musica.kill()
	if _tween_transicao and _tween_transicao.is_valid():
		_tween_transicao.kill()

	var escala_original: Vector2 = (
		_sprite_fundo.scale if is_instance_valid(_sprite_fundo) else Vector2.ONE
	)

	if _borda_portal_inicio != null and is_instance_valid(_borda_portal_inicio):
		_borda_portal_inicio.visible = false

	if _portal_visual == null or not is_instance_valid(_portal_visual):
		push_error("Portal de transição da abertura não foi criado.")
		_ja_iniciando = false
		return

	_portal_visual.cancelar_animacao()
	_portal_visual.position = _centro_tela
	_portal_visual.configurar(
		get_viewport_rect().size,
		_raio_circulo_px,
		COR_PORTAL_PRINCIPAL,
		COR_PORTAL_SECUNDARIA
	)
	_portal_visual.raio_atual = _raio_circulo_px
	_portal_visual.visible = true
	_portal_visual.queue_redraw()

	# Exibe a borda completa antes de começar a fechar.
	await get_tree().process_frame
	await get_tree().process_frame

	_tween_transicao = _criar_tween_seguro()
	if _tween_transicao != null:
		_tween_transicao.set_parallel(true)
		_tween_transicao.set_trans(Tween.TRANS_QUINT)
		_tween_transicao.set_ease(Tween.EASE_IN_OUT)

		if is_instance_valid(_musica_abertura) and _musica_abertura.playing:
			_tween_transicao.tween_property(
				_musica_abertura,
				"volume_db",
				VOLUME_SAIDA_MUSICA_DB,
				DURACAO_FADE_SAIDA_MUSICA
			)

		if is_instance_valid(_label_start):
			_tween_transicao.tween_property(
				_label_start,
				"modulate:a",
				0.0,
				DURACAO_TRANSICAO_PORTAL_SEG * 0.55
			)
			_tween_transicao.tween_property(
				_label_start,
				"scale",
				Vector2.ONE * 1.10,
				DURACAO_TRANSICAO_PORTAL_SEG
			)

		if is_instance_valid(_sprite_fundo):
			_tween_transicao.tween_property(
				_sprite_fundo,
				"scale",
				escala_original * 1.055,
				DURACAO_TRANSICAO_PORTAL_SEG
			)
	else:
		if is_instance_valid(_musica_abertura):
			_musica_abertura.volume_db = VOLUME_SAIDA_MUSICA_DB
		if is_instance_valid(_label_start):
			_label_start.modulate.a = 0.0

	# Mesmo movimento do seletor: sai da borda e fecha naturalmente no centro.
	await _animar_portal_frame_a_frame(
		_portal_visual,
		_raio_circulo_px,
		0.0,
		DURACAO_TRANSICAO_PORTAL_SEG
	)

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(TEMPO_QUADRO_FINAL_PORTAL_SEG, false).timeout

	get_tree().set_meta(META_TRANSICAO_PORTAL, true)
	iniciar_jogo.emit()
	var erro: int = get_tree().change_scene_to_file("res://scenes/change_scenes.tscn")
	if erro != OK:
		_ja_iniciando = false
		get_tree().remove_meta(META_TRANSICAO_PORTAL)
		push_error("Não foi possível abrir res://scenes/change_scenes.tscn. Erro: " + str(erro))

		if _portal_visual != null and is_instance_valid(_portal_visual):
			_portal_visual.cancelar_animacao()
			_portal_visual.visible = false

		if _borda_portal_inicio != null and is_instance_valid(_borda_portal_inicio):
			_borda_portal_inicio.position = _centro_tela
			_borda_portal_inicio.configurar(
				get_viewport_rect().size,
				_raio_circulo_px,
				COR_PORTAL_PRINCIPAL,
				COR_PORTAL_SECUNDARIA
			)
			_borda_portal_inicio.raio_atual = _raio_circulo_px
			_borda_portal_inicio.visible = true
			_borda_portal_inicio.queue_redraw()

		if is_instance_valid(_label_start):
			_label_start.modulate.a = 0.85
			_label_start.scale = Vector2.ONE

		if is_instance_valid(_sprite_fundo):
			_sprite_fundo.scale = escala_original

		if is_instance_valid(_musica_abertura):
			_musica_abertura.volume_db = VOLUME_MUSICA_ABERTURA_DB
			if not _musica_abertura.playing:
				_musica_abertura.play()

		_iniciar_pulso_start()


# ---------------------------------------------------------------
# PORTAL TEMÁTICO DE TRANSIÇÃO — OPENING -> SELETOR
# ---------------------------------------------------------------
func _criar_transicao_portal() -> void:
	_transicao_layer = CanvasLayer.new()
	_transicao_layer.name = "PortalTransicaoTematico"
	_transicao_layer.layer = 100
	_transicao_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_transicao_layer)

	_portal_visual = PortalCircular.new()
	_portal_visual.name = "PortalTematicoAbertura"
	_portal_visual.position = _centro_tela
	_portal_visual.process_mode = Node.PROCESS_MODE_ALWAYS
	_portal_visual.configurar(
		get_viewport_rect().size,
		_raio_circulo_px,
		COR_PORTAL_PRINCIPAL,
		COR_PORTAL_SECUNDARIA
	)
	_portal_visual.raio_atual = 0.0
	_portal_visual.visible = true
	_portal_visual.queue_redraw()
	_transicao_layer.add_child(_portal_visual)


func _animar_portal_frame_a_frame(
	portal: PortalCircular,
	raio_inicial: float,
	raio_final: float,
	duracao_seg: float
) -> void:
	if portal == null or not is_instance_valid(portal):
		return

	portal.cancelar_animacao()
	portal.visible = true
	portal.raio_atual = max(raio_inicial, 0.0)
	portal.queue_redraw()

	var duracao: float = max(duracao_seg, 0.05)
	var decorrido: float = 0.0
	var ultimo_msec: int = Time.get_ticks_msec()

	while decorrido < duracao:
		await get_tree().process_frame
		if portal == null or not is_instance_valid(portal):
			return

		var agora_msec: int = Time.get_ticks_msec()
		var delta_real: float = max(
			float(agora_msec - ultimo_msec) / 1000.0,
			0.0001
		)
		ultimo_msec = agora_msec
		decorrido = min(decorrido + delta_real, duracao)

		var t: float = clamp(decorrido / duracao, 0.0, 1.0)
		# Curva quintic smoothstep: começo, meio e final naturais.
		var suave: float = t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
		portal.raio_atual = lerp(raio_inicial, raio_final, suave)
		portal.queue_redraw()

	portal.raio_atual = max(raio_final, 0.0)
	portal.queue_redraw()
	await get_tree().process_frame


func _iniciar_portal_entrada() -> void:
	if _portal_visual == null or not is_instance_valid(_portal_visual):
		return

	_portal_entrada_em_andamento = true

	if _borda_portal_inicio != null and is_instance_valid(_borda_portal_inicio):
		_borda_portal_inicio.visible = false

	_portal_visual.cancelar_animacao()
	_portal_visual.position = _centro_tela
	_portal_visual.configurar(
		get_viewport_rect().size,
		_raio_circulo_px,
		COR_PORTAL_PRINCIPAL,
		COR_PORTAL_SECUNDARIA
	)
	_portal_visual.raio_atual = 0.0
	_portal_visual.visible = true
	_portal_visual.queue_redraw()

	# Dois quadros totalmente fechados antes de começar a revelar a abertura.
	await get_tree().process_frame
	await get_tree().process_frame

	await _animar_portal_frame_a_frame(
		_portal_visual,
		0.0,
		_raio_circulo_px,
		DURACAO_TRANSICAO_PORTAL_SEG
	)

	_portal_visual.visible = false

	if _borda_portal_inicio != null and is_instance_valid(_borda_portal_inicio):
		_borda_portal_inicio.position = _centro_tela
		_borda_portal_inicio.configurar(
			get_viewport_rect().size,
			_raio_circulo_px,
			COR_PORTAL_PRINCIPAL,
			COR_PORTAL_SECUNDARIA
		)
		_borda_portal_inicio.raio_atual = _raio_circulo_px
		_borda_portal_inicio.visible = true
		_borda_portal_inicio.queue_redraw()

	_portal_entrada_em_andamento = false


# ---------------------------------------------------------------
# COM5 PERSISTENTE ENTRE AS DUAS CENAS
# ---------------------------------------------------------------
func _arduino_enviar_unico(linha: String) -> void:
	var comando := linha.strip_edges()
	if comando.is_empty() or comando == _led_assinatura_atual:
		return
	var cliente := get_node_or_null("/root/LedClient")
	if cliente != null and cliente.has_method("send"):
		if bool(cliente.call("send", comando)):
			_led_assinatura_atual = comando


func _arduino_enviar_forcado(linha: String) -> void:
	var comando := linha.strip_edges()
	if comando.is_empty():
		return
	_led_assinatura_atual = ""
	var cliente := get_node_or_null("/root/LedClient")
	if cliente != null and cliente.has_method("send"):
		cliente.call("send", comando)

func _serial_encerrar_aplicativo() -> void:
	# O LedClient é a única autoridade serial.
	# Ao fechar o aplicativo, ele manda o pedido de shutdown para a bridge,
	# que envia CLEAR e libera a COM5.
	var cliente := get_node_or_null("/root/LedClient")
	if cliente != null and cliente.has_method("shutdown"):
		cliente.call("shutdown")


func _notification(what: int) -> void:
	# Não encerra serial durante troca de cena; somente ao fechar a janela.
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_serial_encerrar_aplicativo()


func _montar_cena() -> void:
	var tam_tela: Vector2 = get_viewport_rect().size
	var menor_lado: float = min(tam_tela.x, tam_tela.y)
	_raio_circulo_px = (menor_lado * PORCENTAGEM_TELA_CIRCULO) / 2.0
	_centro_tela = Vector2(
		tam_tela.x * 0.5,
		tam_tela.y - _raio_circulo_px - tam_tela.y * CIRCULO_MARGEM_INFERIOR_RATIO
	)

	# Fundo preto total por baixo de tudo -- evita flash branco antes de montar.
	var fundo_preto := ColorRect.new()
	fundo_preto.color = Color.BLACK
	fundo_preto.size = tam_tela
	fundo_preto.position = Vector2.ZERO
	fundo_preto.z_index = -10
	add_child(fundo_preto)

	_criar_sprite_fundo(tam_tela)
	_criar_mascara_circular(tam_tela)
	_criar_janela_superior(tam_tela)
	_criar_texto_start(tam_tela)


# ---------------------------------------------------------------
# FUNDO: imagem + shader de pulso neon
# ---------------------------------------------------------------
func _criar_sprite_fundo(_tam_tela: Vector2) -> void:
	var textura: Texture2D = load(IMAGEM_FUNDO)
	if textura == null:
		push_warning("Imagem de fundo não encontrada em: " + IMAGEM_FUNDO)
		return

	_sprite_fundo = Sprite2D.new()
	_sprite_fundo.texture = textura
	_sprite_fundo.position = _centro_tela
	_sprite_fundo.z_index = 0
	_sprite_fundo.z_as_relative = false

	_ajustar_sprite_fundo()

	var mat := ShaderMaterial.new()
	mat.shader = _criar_shader_pulso_neon()
	_sprite_fundo.material = mat

	add_child(_sprite_fundo)


func _ajustar_sprite_fundo() -> void:
	if not is_instance_valid(_sprite_fundo) or _sprite_fundo.texture == null:
		return
	var textura: Texture2D = _sprite_fundo.texture
	var diametro: float = _raio_circulo_px * 2.0
	var lado_menor_textura: float = min(
		float(textura.get_width()),
		float(textura.get_height())
	)
	var escala_necessaria: float = (diametro / max(lado_menor_textura, 1.0)) * 1.05
	_sprite_fundo.position = _centro_tela
	_sprite_fundo.scale = Vector2.ONE * escala_necessaria


func _criar_shader_pulso_neon() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;

uniform float velocidade_pulso : hint_range(0.1, 5.0) = 1.3;
uniform float intensidade_pulso : hint_range(0.0, 1.0) = 0.45;
uniform float limiar_brilho : hint_range(0.0, 1.0) = 0.55;

void fragment() {
	vec4 cor = texture(TEXTURE, UV);

	// Detecta as áreas mais claras/neon da própria arte (letreiro, anéis, luzes).
	float brilho = dot(cor.rgb, vec3(0.299, 0.587, 0.114));
	float mascara_neon = smoothstep(limiar_brilho - 0.15, limiar_brilho + 0.25, brilho);

	// Pulso de brilho só nas áreas neon -- o preto de fundo da arte não pisca.
	float pulso = sin(TIME * velocidade_pulso * 6.283185) * 0.5 + 0.5;
	vec3 cor_realcada = cor.rgb + (cor.rgb * pulso * intensidade_pulso * mascara_neon);

	// Onda sutil saindo do centro, acompanhando o tema de "batida" do jogo.
	float dist_centro = distance(UV, vec2(0.5));
	float anel = sin(dist_centro * 26.0 - TIME * velocidade_pulso * 3.0) * 0.5 + 0.5;
	anel *= mascara_neon * 0.12;

	COLOR = vec4(cor_realcada + anel, cor.a);
}
"""
	return sh


# ---------------------------------------------------------------
# MÁSCARA CIRCULAR: preto fora do círculo + anel de borda pulsante
# ---------------------------------------------------------------
func _criar_mascara_circular(tam_tela: Vector2) -> void:
	_mascara_layer = CanvasLayer.new()
	_mascara_layer.name = "BordaPermanenteTematica"
	_mascara_layer.layer = 10
	_mascara_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_mascara_layer)

	# A borda permanente é a mesma classe usada para abrir e fechar.
	_borda_portal_inicio = PortalCircular.new()
	_borda_portal_inicio.name = "BordaPortalInicioUnificada"
	_borda_portal_inicio.position = _centro_tela
	_borda_portal_inicio.process_mode = Node.PROCESS_MODE_ALWAYS
	_borda_portal_inicio.configurar(
		tam_tela,
		_raio_circulo_px,
		COR_PORTAL_PRINCIPAL,
		COR_PORTAL_SECUNDARIA
	)
	_borda_portal_inicio.raio_atual = _raio_circulo_px
	# Começa escondida porque a entrada será desenhada pelo portal animado.
	_borda_portal_inicio.visible = false
	_borda_portal_inicio.queue_redraw()
	_mascara_layer.add_child(_borda_portal_inicio)


# ---------------------------------------------------------------
# JANELA RETANGULAR SUPERIOR — vazia, no mesmo esquema das scenes
# ---------------------------------------------------------------
func _criar_janela_superior(tam_tela: Vector2) -> void:
	_hud_superior_layer = CanvasLayer.new()
	_hud_superior_layer.name = "JanelaSuperiorAbertura"
	_hud_superior_layer.layer = 20
	_hud_superior_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_hud_superior_layer)

	_hud_superior = Panel.new()
	_hud_superior.name = "JanelaSuperiorVazia"
	_hud_superior.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_superior_layer.add_child(_hud_superior)
	_posicionar_janela_superior(tam_tela)


func _posicionar_janela_superior(tam_tela: Vector2) -> void:
	if _hud_superior == null or not is_instance_valid(_hud_superior):
		return

	var margem: float = tam_tela.x * JANELA_TOPO_MARGEM_RATIO
	var altura: float = tam_tela.y * JANELA_TOPO_ALTURA_RATIO
	_hud_superior.position = Vector2(margem, margem)
	_hud_superior.size = Vector2(tam_tela.x - margem * 2.0, altura)
	_hud_superior.add_theme_stylebox_override("panel", _style_janela_superior())


func _style_janela_superior() -> StyleBoxFlat:
	var estilo: StyleBoxFlat = StyleBoxFlat.new()
	estilo.bg_color = Color(0.006, 0.010, 0.024, 0.96)
	estilo.border_color = Color(
		COR_PORTAL_PRINCIPAL.r,
		COR_PORTAL_PRINCIPAL.g,
		COR_PORTAL_PRINCIPAL.b,
		0.62
	)
	estilo.set_border_width_all(2)
	estilo.set_corner_radius_all(18)
	estilo.shadow_color = Color(
		COR_PORTAL_SECUNDARIA.r,
		COR_PORTAL_SECUNDARIA.g,
		COR_PORTAL_SECUNDARIA.b,
		0.18
	)
	estilo.shadow_size = 10
	return estilo


# ---------------------------------------------------------------
# TEXTO "APERTE START"
# ---------------------------------------------------------------
func _criar_texto_start(tam_tela: Vector2) -> void:
	# Menor e mais discreto -- só um "convite" sutil, sem competir com a arte de fundo.
	_config_start = LabelSettings.new()
	_config_start.font_size = int(tam_tela.x * 0.042)
	_config_start.outline_size = 5
	# Quase preto: mantém contraste sem fazer o contorno piscar.
	_config_start.outline_color = Color(0.02, 0.0, 0.05, 0.95)
	_config_start.font_color = COR_NEON_ROSA
	_config_start.shadow_size = 12
	_config_start.shadow_offset = Vector2.ZERO
	_config_start.shadow_color = Color(COR_NEON_ROSA.r, COR_NEON_ROSA.g, COR_NEON_ROSA.b, 0.35)

	_label_start = Label.new()
	_label_start.text = "APERTE START"
	_label_start.label_settings = _config_start
	_label_start.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label_start.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label_start.modulate = Color(1.0, 1.0, 1.0, 0.85)
	_label_start.z_index = 5

	var largura_label: float = tam_tela.x * 0.55
	var altura_label: float = _config_start.font_size * 1.6
	_label_start.size = Vector2(largura_label, altura_label)
	_label_start.pivot_offset = _label_start.size / 2.0
	_posicionar_label_start()

	add_child(_label_start)


func _posicionar_label_start() -> void:
	if _label_start == null:
		return
	# Mais perto da borda inferior do círculo -- fora da área central "quente"
	# (logo, contadores e o rastro de movimento da arte).
	_label_start.position = Vector2(
		_centro_tela.x - _label_start.size.x / 2.0,
		_centro_tela.y + _raio_circulo_px * 0.74 - _label_start.size.y / 2.0
	)


func _iniciar_pulso_start() -> void:
	if _tween_start:
		_tween_start.kill()

	var y_base: float = _label_start.position.y
	var cor_shadow_fraca := Color(COR_NEON_ROSA.r, COR_NEON_ROSA.g, COR_NEON_ROSA.b, 0.35)
	var cor_shadow_forte := Color(COR_NEON_CIANO.r, COR_NEON_CIANO.g, COR_NEON_CIANO.b, 0.9)

	_tween_start = _criar_tween_seguro()
	if _tween_start == null:
		return

	_tween_start.set_loops()
	_tween_start.set_trans(Tween.TRANS_SINE)
	_tween_start.set_ease(Tween.EASE_IN_OUT)

	# Pico: cresce um pouco, sobe de leve, esquenta pra ciano, halo mais forte, opacidade máxima.
	_tween_start.tween_property(_label_start, "scale", Vector2(1.04, 1.04), 0.85)
	_tween_start.parallel().tween_property(_label_start, "position:y", y_base - 3.0, 0.85)
	_tween_start.parallel().tween_property(_label_start, "modulate:a", 1.0, 0.85)
	_tween_start.parallel().tween_property(_config_start, "font_color", COR_NEON_CIANO, 0.85)
	_tween_start.parallel().tween_property(_config_start, "shadow_color", cor_shadow_forte, 0.85)
	_tween_start.parallel().tween_property(_config_start, "shadow_size", 20.0, 0.85)

	# Repouso: volta ao rosa, halo mais fraco, leve transparência -- "respira" em vez de gritar.
	_tween_start.tween_property(_label_start, "scale", Vector2(1.0, 1.0), 0.85)
	_tween_start.parallel().tween_property(_label_start, "position:y", y_base, 0.85)
	_tween_start.parallel().tween_property(_label_start, "modulate:a", 0.85, 0.85)
	_tween_start.parallel().tween_property(_config_start, "font_color", COR_NEON_ROSA, 0.85)
	_tween_start.parallel().tween_property(_config_start, "shadow_color", cor_shadow_fraca, 0.85)
	_tween_start.parallel().tween_property(_config_start, "shadow_size", 12.0, 0.85)


# ---------------------------------------------------------------
# START pressionado
# ---------------------------------------------------------------
func _ao_apertar_start() -> void:
	if _ja_iniciando or _portal_entrada_em_andamento:
		return
	_ja_iniciando = true
	if _tween_start:
		_tween_start.kill()
	_arduino_enviar_forcado("READY")
	_abaixar_musica_e_abrir_seletor()


# ---------------------------------------------------------------
# Reajuste se a janela mudar de tamanho
# ---------------------------------------------------------------
func _on_tela_redimensionada() -> void:
	var tam_tela: Vector2 = get_viewport_rect().size
	var menor_lado: float = min(tam_tela.x, tam_tela.y)
	_raio_circulo_px = (menor_lado * PORCENTAGEM_TELA_CIRCULO) / 2.0
	_centro_tela = Vector2(
		tam_tela.x * 0.5,
		tam_tela.y - _raio_circulo_px - tam_tela.y * CIRCULO_MARGEM_INFERIOR_RATIO
	)

	if _sprite_fundo:
		_ajustar_sprite_fundo()

	if _borda_portal_inicio != null and is_instance_valid(_borda_portal_inicio):
		_borda_portal_inicio.position = _centro_tela
		_borda_portal_inicio.configurar(
			tam_tela,
			_raio_circulo_px,
			COR_PORTAL_PRINCIPAL,
			COR_PORTAL_SECUNDARIA
		)
		_borda_portal_inicio.raio_atual = _raio_circulo_px
		_borda_portal_inicio.queue_redraw()

	if _portal_visual != null and is_instance_valid(_portal_visual):
		_portal_visual.position = _centro_tela
		_portal_visual.configurar(
			tam_tela,
			_raio_circulo_px,
			COR_PORTAL_PRINCIPAL,
			COR_PORTAL_SECUNDARIA
		)
		if not _portal_entrada_em_andamento and not _ja_iniciando:
			_portal_visual.raio_atual = _raio_circulo_px
		_portal_visual.visible = false
		_portal_visual.queue_redraw()

	_posicionar_janela_superior(tam_tela)
	_posicionar_label_start()
