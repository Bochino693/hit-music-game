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
## 3. Mascara tudo fora do círculo em preto, sem moldura permanente.
##    O aro espectral aparece somente quando o portal abre ou fecha.
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
	var mostrar_energia: bool = true
	var modo_estatico: bool = false

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
		# Suave em Full HD, com menos geometria durante a transicao.
		var segmentos_mascara: int = 160

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
		# A mascara permanente usa somente o recorte. A energia aparece
		# exclusivamente durante a entrada/saida para o portal ser o foco.
		if not mostrar_energia:
			return

		var pulso: float = 0.5 + 0.5 * sin(tempo * 2.4)
		var espessura_base: float = max(3.0, raio_interno * 0.0068)
		var cor_portal: Color = cor_principal.lerp(
			cor_secundaria,
			0.5 + 0.5 * sin(tempo * 0.72)
		)

		# Halo amplo e macio: substitui as antigas molduras concêntricas.
		draw_arc(
			Vector2.ZERO,
			raio_interno + espessura_base * 0.8,
			0.0,
			TAU,
			220,
			Color(cor_portal.r, cor_portal.g, cor_portal.b, 0.16 + pulso * 0.09),
			espessura_base * (5.4 + pulso * 1.2),
			true
		)

		# Um unico aro branco quente define a boca do portal.
		draw_arc(
			Vector2.ZERO,
			raio_interno,
			0.0,
			TAU,
			240,
			Color(1.0, 1.0, 1.0, 0.90 + pulso * 0.10),
			espessura_base * 0.72,
			true
		)

		# Depois da abertura o portal permanece INTEIRO. Sem arcos
		# interrompidos, portanto nenhuma parte parece cortada.
		if modo_estatico:
			draw_arc(
				Vector2.ZERO,
				max(raio_interno - espessura_base * 1.65, 0.0),
				0.0,
				TAU,
				240,
				Color(cor_principal.r, cor_principal.g, cor_principal.b, 0.88),
				espessura_base * 0.92,
				true
			)
			draw_arc(
				Vector2.ZERO,
				max(raio_interno - espessura_base * 2.75, 0.0),
				0.0,
				TAU,
				240,
				Color(cor_secundaria.r, cor_secundaria.g, cor_secundaria.b, 0.76),
				espessura_base * 0.62,
				true
			)
			return

		# Dois arcos espectrais giram em sentidos opostos sem formar borda fixa.
		var giro: float = fmod(tempo * 0.42, TAU)
		draw_arc(
			Vector2.ZERO,
			max(raio_interno - espessura_base * 1.7, 0.0),
			giro,
			giro + PI * 0.78,
			72,
			Color(cor_principal.r, cor_principal.g, cor_principal.b, 0.92),
			espessura_base * 1.18,
			true
		)
		draw_arc(
			Vector2.ZERO,
			max(raio_interno - espessura_base * 2.8, 0.0),
			-giro - PI,
			-giro - PI * 0.10,
			72,
			Color(cor_secundaria.r, cor_secundaria.g, cor_secundaria.b, 0.88),
			espessura_base * 0.82,
			true
		)




# --- Constantes físicas da mesa redonda (iguais às do Rick and Morty) ---
const SETTINGS_GATE: Script = preload("res://scripts/hit_music_r7/settings_gate.gd")

const RAIO_FISICO_CM: float = 48.0
const DIAMETRO_FISICO_CM: float = RAIO_FISICO_CM * 2.0
const CIRCUNFERENCIA_FISICA_CM: float = DIAMETRO_FISICO_CM * PI

## Mesmo tamanho visual usado na cena rick_morty: 98,5% do menor lado da tela.
const PORCENTAGEM_TELA_CIRCULO: float = 0.985
const CIRCULO_MARGEM_INFERIOR_RATIO: float = 0.012

## Feather da borda da máscara circular -- suaviza o corte.
const SUAVIZACAO_MASCARA_PX: float = 3.0

# --- Imagem de fundo ---
const PASTA_ABERTURA: String = "res://images/"
const IMAGEM_FUNDO: String = PASTA_ABERTURA + "hit_music.png"
# A arte ocupa somente 90% do diametro. Os 10% restantes formam a
# zona segura do portal e impedem a imagem de tocar/cortar o aro.
const IMAGEM_DIAMETRO_PORTAL_RATIO: float = 0.90

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
const DURACAO_TRANSICAO_PORTAL_SEG: float = 1.08
const TEMPO_QUADRO_FINAL_PORTAL_SEG: float = 0.10
# Paleta espectral da nova capa.
const COR_PORTAL_PRINCIPAL: Color = Color(1.0, 0.10, 0.78, 1.0)
const COR_PORTAL_SECUNDARIA: Color = Color(0.06, 0.88, 1.0, 1.0)

# --- Cores neon da arte, usadas no pulso do texto e da borda ---
const COR_NEON_ROSA: Color = Color(1.0, 0.15, 0.85)
const COR_NEON_CIANO: Color = Color(0.25, 0.85, 1.0)

# --- HUD superior / operacao da maquina ---
const LOGO_EMPRESA: String = "res://images/logoofi.png"
const FONTE_TITULO: String = "res://fonts/Bungee-Regular.ttf"
const FONTE_TEXTO: String = "res://fonts/Oxanium-VariableFont_wght.ttf"
const HUD_MARGEM_RATIO: float = 0.022
const HUD_ALTURA_RATIO: float = 0.205
const HUD_REFRESH_SEG: float = 0.25
const HUD_MENSAGEM_SEG: float = 3.2
const START_SFX_VOLUME_DB: float = -1.5

## O controlador de creditos pode alterar estes valores diretamente
## ou chamar definir_modo_credito() e definir_creditos().
@export var modo_credito: bool = false
@export_range(0, 999, 1) var creditos_maquina: int = 0

# --- LEDs / comunicação ---
# Toda comunicação passa pelo Autoload /root/LedClient.
var _led_assinatura_atual: String = ""
var _led_feedback_bloqueio_ate_msec: int = 0

# --- Nodes internos ---
var _sprite_fundo: Sprite2D
var _fundo_layer: CanvasLayer
var _mascara_layer: CanvasLayer
var _borda_portal_inicio: PortalCircular
var _hud_superior_layer: CanvasLayer
var _hud_superior: Panel
var _hud_fx: ColorRect
var _hud_borda: Panel
var _hud_status_fundo: Panel
var _hud_divisor: ColorRect
var _hud_logo: TextureRect
var _hud_modo: Label
var _hud_instrucao: Label
var _hud_creditos: Label
var _hud_status_livre: Label
var _hud_info: Label
var _hud_refresh_acumulado: float = 0.0
var _hud_assinatura: String = ""
var _hud_mensagem_tempo: float = 0.0
var _hud_mensagem_index: int = 0
var _hud_instrucao_base_x: float = 0.0
var _hud_mensagem_tween: Tween
var _label_start: Label
var _config_start: LabelSettings
var _tween_start: Tween
var _musica_abertura: AudioStreamPlayer
var _tween_musica: Tween
var _sfx_start: AudioStreamPlayer
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
	_criar_audio_start()
	_iniciar_pulso_start()
	_iniciar_portal_entrada()
	get_viewport().size_changed.connect(_on_tela_redimensionada)
	_sincronizar_com_arcade_settings()
	ArcadeSettings.changed.connect(_sincronizar_com_arcade_settings)


func _process(delta: float) -> void:
	var cliente_serial := get_node_or_null("/root/LedClient")
	if cliente_serial != null and cliente_serial.has_method("tick"):
		cliente_serial.call("tick")
	if _portal_visual != null and is_instance_valid(_portal_visual):
		if _portal_visual.visible:
			_portal_visual.queue_redraw()

	_hud_refresh_acumulado += delta
	if _hud_refresh_acumulado >= HUD_REFRESH_SEG:
		_hud_refresh_acumulado = 0.0
		_atualizar_hud_operacao()
	_atualizar_mensagens_hud(delta)

	if Input.is_action_just_pressed("input_start"):
		_ao_apertar_start()


func _input(event: InputEvent) -> void:
	# F9 abre a tela de Configuracoes (modo livre/credito, teste de
	# LED e input, porta COM).
	if SETTINGS_GATE.try_open_from_keyboard(event):
		return
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


# Efeito curto de confirmacao: impacto, subida espectral e sino digital.
# E sintetizado uma vez no _ready, sem depender de arquivo externo.
func _criar_audio_start() -> void:
	_sfx_start = AudioStreamPlayer.new()
	_sfx_start.name = "StartPortalSfx"
	_sfx_start.bus = "Master"
	_sfx_start.volume_db = START_SFX_VOLUME_DB
	_sfx_start.stream = _gerar_sfx_start()
	add_child(_sfx_start)


func _gerar_sfx_start() -> AudioStreamWAV:
	const TAXA: int = 44100
	const DURACAO: float = 0.62
	var total: int = int(float(TAXA) * DURACAO)
	var dados := PackedByteArray()
	dados.resize(total * 4) # stereo, 16 bits por canal

	for i in range(total):
		var tempo: float = float(i) / float(TAXA)
		var vida: float = tempo / DURACAO
		var ataque: float = smoothstep(0.0, 0.035, tempo)
		var cauda: float = pow(maxf(1.0 - vida, 0.0), 2.15)
		var envelope: float = ataque * cauda

		# Chirp ascendente = portal abrindo; harmonicos = confirmacao arcade.
		var fase_chirp: float = TAU * (155.0 * tempo + 520.0 * tempo * tempo)
		var sino_a: float = sin(TAU * 880.0 * tempo) * exp(-tempo * 5.8)
		var sino_b: float = sin(TAU * 1320.0 * tempo + 0.35) * exp(-tempo * 7.2)
		var impacto: float = sin(TAU * 92.0 * tempo) * exp(-tempo * 18.0)
		var base: float = (
			sin(fase_chirp) * 0.46
			+ sino_a * 0.23
			+ sino_b * 0.15
			+ impacto * 0.24
		) * envelope
		var abertura_stereo: float = sin(fase_chirp + PI * 0.08) * 0.055 * envelope

		var esquerda: int = clampi(roundi(base * 24500.0), -32768, 32767)
		var direita: int = clampi(roundi((base + abertura_stereo) * 24500.0), -32768, 32767)
		dados.encode_s16(i * 4, esquerda)
		dados.encode_s16(i * 4 + 2, direita)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = TAXA
	stream.stereo = true
	stream.data = dados
	return stream


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
				# Zoom minimo: continua dentro da zona segura do portal.
				escala_original * 1.015,
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
	_fundo_layer = CanvasLayer.new()
	_fundo_layer.name = "ArteFundoPortal"
	_fundo_layer.layer = -20
	add_child(_fundo_layer)

	var fundo_preto := ColorRect.new()
	fundo_preto.color = Color.BLACK
	fundo_preto.size = tam_tela
	fundo_preto.position = Vector2.ZERO
	fundo_preto.z_index = -100
	_fundo_layer.add_child(fundo_preto)

	_criar_sprite_fundo(tam_tela)
	_criar_mascara_circular(tam_tela)
	_criar_hud_superior(tam_tela)
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
	_sprite_fundo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_sprite_fundo.position = _centro_tela
	_sprite_fundo.z_index = 0
	_sprite_fundo.z_as_relative = false

	_ajustar_sprite_fundo()

	var mat := ShaderMaterial.new()
	mat.shader = _criar_shader_pulso_neon()
	_sprite_fundo.material = mat

	# Camada dedicada garante que a arte redonda sempre fique ATRAS do
	# portal, da mascara e do HUD, independentemente da ordem dos nodes.
	_fundo_layer.add_child(_sprite_fundo)


func _ajustar_sprite_fundo() -> void:
	if not is_instance_valid(_sprite_fundo) or _sprite_fundo.texture == null:
		return
	var textura: Texture2D = _sprite_fundo.texture
	var diametro_util: float = (
		_raio_circulo_px
		* 2.0
		* IMAGEM_DIAMETRO_PORTAL_RATIO
	)
	var lado_menor_textura: float = min(
		float(textura.get_width()),
		float(textura.get_height())
	)
	# FIT, nao COVER: a imagem redonda inteira cabe dentro do portao.
	# A versao anterior usava * 1.05 e ultrapassava o limite do portal.
	var escala_necessaria: float = diametro_util / max(lado_menor_textura, 1.0)
	_sprite_fundo.position = _centro_tela
	_sprite_fundo.scale = Vector2.ONE * escala_necessaria


func _criar_shader_pulso_neon() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;

uniform float velocidade_pulso : hint_range(0.1, 5.0) = 0.82;
uniform float intensidade_pulso : hint_range(0.0, 1.0) = 0.26;
uniform float limiar_brilho : hint_range(0.0, 1.0) = 0.58;

void fragment() {
	vec4 cor = texture(TEXTURE, UV);

	// Detecta as áreas mais claras/neon da própria arte (letreiro, anéis, luzes).
	float brilho = dot(cor.rgb, vec3(0.299, 0.587, 0.114));
	float mascara_neon = smoothstep(limiar_brilho - 0.15, limiar_brilho + 0.25, brilho);

	// Respiracao suave somente nas areas neon.
	float pulso = sin(TIME * velocidade_pulso * 6.283185) * 0.5 + 0.5;
	vec3 cor_realcada = cor.rgb + (cor.rgb * pulso * intensidade_pulso * mascara_neon);

	// Frentes radiais finas sugerem o portal sem criar moldura fixa.
	float dist_centro = distance(UV, vec2(0.5));
	float fase = fract(dist_centro * 1.65 - TIME * 0.10);
	float onda = 1.0 - smoothstep(0.0, 0.065, abs(fase - 0.5));
	float onda_2 = 1.0 - smoothstep(0.0, 0.045, abs(fract(fase + 0.34) - 0.5));
	float energia = (onda * 0.10 + onda_2 * 0.055) * mascara_neon;
	float vignette = 1.0 - smoothstep(0.22, 0.72, dist_centro);
	vec3 final_rgb = (cor_realcada + energia) * mix(0.86, 1.04, vignette);
	// Microcontraste para recuperar definicao sem estourar as areas brancas.
	final_rgb = clamp((final_rgb - 0.5) * 1.075 + 0.5, 0.0, 1.0);

	COLOR = vec4(final_rgb, cor.a);
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
	_borda_portal_inicio.mostrar_energia = true
	_borda_portal_inicio.modo_estatico = true
	# Começa escondida porque a entrada será desenhada pelo portal animado.
	_borda_portal_inicio.visible = false
	_borda_portal_inicio.queue_redraw()
	_mascara_layer.add_child(_borda_portal_inicio)


# ---------------------------------------------------------------
# HUD SUPERIOR — MARCA, MODO DE OPERACAO E CREDITOS
# ---------------------------------------------------------------
func _criar_hud_superior(tam_tela: Vector2) -> void:
	_hud_superior_layer = CanvasLayer.new()
	_hud_superior_layer.name = "HudOperacaoAbertura"
	# HUD independente: fica acima do portal (layer 100) e nunca e recortado.
	_hud_superior_layer.layer = 120
	_hud_superior_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_hud_superior_layer)

	_hud_superior = Panel.new()
	_hud_superior.name = "PainelOperacao"
	_hud_superior.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_superior.clip_contents = true
	_hud_superior.add_theme_stylebox_override("panel", _style_hud_superior())
	_hud_superior_layer.add_child(_hud_superior)

	# Um unico quad com shader substitui dezenas de particulas/nodes.
	_hud_fx = ColorRect.new()
	_hud_fx.name = "FundoEspectralAnimado"
	_hud_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_fx.color = Color.WHITE
	var material_fx := ShaderMaterial.new()
	material_fx.shader = _criar_shader_hud()
	_hud_fx.material = material_fx
	_hud_superior.add_child(_hud_fx)

	_hud_divisor = ColorRect.new()
	_hud_divisor.name = "DivisorLogo"
	_hud_divisor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_divisor.color = Color(COR_NEON_CIANO.r, COR_NEON_CIANO.g, COR_NEON_CIANO.b, 0.46)
	_hud_superior.add_child(_hud_divisor)

	_hud_status_fundo = Panel.new()
	_hud_status_fundo.name = "CartaoStatus"
	_hud_status_fundo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_status_fundo.add_theme_stylebox_override("panel", _style_cartao_status())
	_hud_superior.add_child(_hud_status_fundo)

	_hud_logo = TextureRect.new()
	_hud_logo.name = "LogoEmpresa"
	_hud_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hud_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_hud_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(LOGO_EMPRESA):
		var recurso_logo: Resource = load(LOGO_EMPRESA)
		if recurso_logo is Texture2D:
			_hud_logo.texture = recurso_logo as Texture2D
	else:
		push_warning("Logo da empresa nao encontrado: " + LOGO_EMPRESA)
	_hud_superior.add_child(_hud_logo)

	_hud_modo = _criar_label_hud(0.032, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	_hud_modo.name = "ModoOperacao"
	_hud_modo.label_settings.font = _carregar_fonte(FONTE_TITULO)
	_hud_superior.add_child(_hud_modo)

	_hud_instrucao = _criar_label_hud(0.022, Color(0.82, 0.94, 1.0), HORIZONTAL_ALIGNMENT_LEFT)
	_hud_instrucao.name = "InstrucaoOperacao"
	_hud_superior.add_child(_hud_instrucao)

	_hud_creditos = _criar_label_hud(0.031, COR_NEON_CIANO, HORIZONTAL_ALIGNMENT_RIGHT)
	_hud_creditos.name = "ContadorCreditos"
	_hud_creditos.label_settings.font = _carregar_fonte(FONTE_TITULO)
	_hud_superior.add_child(_hud_creditos)

	_hud_status_livre = _criar_label_hud(0.030, COR_NEON_CIANO, HORIZONTAL_ALIGNMENT_CENTER)
	_hud_status_livre.name = "StatusModoLivre"
	_hud_status_livre.label_settings.font = _carregar_fonte(FONTE_TITULO)
	_hud_superior.add_child(_hud_status_livre)

	_hud_info = _criar_label_hud(0.016, Color(0.64, 0.78, 0.92), HORIZONTAL_ALIGNMENT_LEFT)
	_hud_info.name = "InformacoesAdicionais"
	_hud_superior.add_child(_hud_info)

	# O efeito ocupa o retangulo inteiro; o filete fica em overlay separado.
	_hud_borda = Panel.new()
	_hud_borda.name = "FileteHud"
	_hud_borda.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_borda.z_index = 20
	_hud_borda.add_theme_stylebox_override("panel", _style_hud_borda())
	_hud_superior.add_child(_hud_borda)

	_posicionar_hud_superior(tam_tela)
	_atualizar_hud_operacao(true)


func _criar_label_hud(
	tamanho_ratio: float,
	cor: Color,
	alinhamento: HorizontalAlignment
) -> Label:
	var config := LabelSettings.new()
	config.font = _carregar_fonte(FONTE_TEXTO)
	config.font_size = maxi(18, int(get_viewport_rect().size.x * tamanho_ratio))
	config.font_color = cor
	config.outline_size = 3
	config.outline_color = Color(0.0, 0.0, 0.0, 0.90)
	config.shadow_size = 6
	config.shadow_offset = Vector2.ZERO
	config.shadow_color = Color(cor.r, cor.g, cor.b, 0.18)

	var label := Label.new()
	label.label_settings = config
	label.horizontal_alignment = alinhamento
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _carregar_fonte(caminho: String) -> Font:
	if ResourceLoader.exists(caminho):
		var recurso: Resource = load(caminho)
		if recurso is Font:
			return recurso as Font
	push_warning("Fonte nao encontrada: " + caminho)
	return ThemeDB.fallback_font


func _style_hud_superior() -> StyleBoxFlat:
	# Quadro mais nitido: vidro escuro opaco, cantos menores e filete definido.
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0.002, 0.007, 0.022, 0.96)
	estilo.set_border_width_all(0)
	estilo.set_corner_radius_all(14)
	estilo.shadow_color = Color(0.0, 0.0, 0.0, 0.76)
	estilo.shadow_size = 12
	return estilo


func _style_hud_borda() -> StyleBoxFlat:
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	estilo.border_color = Color(0.46, 0.95, 1.0, 0.82)
	estilo.set_border_width_all(2)
	estilo.set_corner_radius_all(14)
	return estilo


func _style_cartao_status(credito: bool = false) -> StyleBoxFlat:
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0.008, 0.026, 0.072, 0.76)
	var cor: Color = Color(1.0, 0.72, 0.12) if credito else COR_NEON_CIANO
	estilo.border_color = Color(cor.r, cor.g, cor.b, 0.46)
	estilo.set_border_width_all(1)
	estilo.set_corner_radius_all(12)
	estilo.shadow_color = Color(COR_NEON_CIANO.r, COR_NEON_CIANO.g, COR_NEON_CIANO.b, 0.10)
	estilo.shadow_size = 7
	return estilo


func _criar_shader_hud() -> Shader:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;

float rounded_mask(vec2 uv, float radius) {
	vec2 q = abs(uv - vec2(0.5)) - vec2(0.5 - radius);
	float d = length(max(q, vec2(0.0))) - radius;
	return 1.0 - smoothstep(-0.008, 0.008, d);
}

void fragment() {
	vec2 uv = UV;
	float time = TIME;
	vec3 base = vec3(0.004, 0.010, 0.035);

	float aurora_a = exp(-22.0 * pow(uv.y - (0.34 + sin(uv.x * 5.0 + time * 0.45) * 0.11), 2.0));
	float aurora_b = exp(-28.0 * pow(uv.y - (0.68 + sin(uv.x * 6.0 - time * 0.36) * 0.09), 2.0));
	vec3 spectral = vec3(0.04, 0.86, 1.0) * aurora_a * 0.20;
	spectral += vec3(1.0, 0.05, 0.72) * aurora_b * 0.16;

	float grid_x = 1.0 - smoothstep(0.0, 0.035, abs(fract(uv.x * 18.0 - time * 0.08) - 0.5));
	float grid_y = 1.0 - smoothstep(0.0, 0.05, abs(fract(uv.y * 7.0) - 0.5));
	float grid = max(grid_x, grid_y) * 0.042;

	float scan = 1.0 - smoothstep(0.0, 0.075, abs(fract(uv.x - time * 0.12) - 0.5));
	vec3 color = base + spectral + vec3(0.18, 0.46, 0.78) * grid;
	color += vec3(0.25, 0.78, 1.0) * scan * 0.055;

	float edge = 1.0 - smoothstep(0.12, 0.62, distance(uv, vec2(0.5)));
	float mask = rounded_mask(uv, 0.040);
	color = clamp((color - 0.5) * 1.12 + 0.5, 0.0, 1.0);
	COLOR = vec4(color * mix(0.78, 1.14, edge), 0.97 * mask);
}
"""
	return shader


func _posicionar_hud_superior(tam_tela: Vector2) -> void:
	if _hud_superior == null or not is_instance_valid(_hud_superior):
		return

	var margem: float = tam_tela.x * HUD_MARGEM_RATIO
	var altura: float = tam_tela.y * HUD_ALTURA_RATIO
	var largura: float = tam_tela.x - margem * 2.0
	_hud_superior.position = Vector2(margem, margem)
	_hud_superior.size = Vector2(largura, altura)
	_hud_fx.position = Vector2.ZERO
	_hud_fx.size = _hud_superior.size
	_hud_borda.position = Vector2.ZERO
	_hud_borda.size = _hud_superior.size

	var padding: float = maxf(14.0, largura * 0.022)
	var logo_ratio: float = 0.19 if modo_credito else 0.24
	var logo_largura: float = minf(altura * 1.42, largura * logo_ratio)
	_hud_logo.position = Vector2(padding, padding * 0.55)
	_hud_logo.size = Vector2(logo_largura, altura - padding * 1.10)
	_hud_divisor.position = Vector2(padding + logo_largura + padding * 0.35, altura * 0.16)
	_hud_divisor.size = Vector2(maxf(2.0, largura * 0.0025), altura * 0.68)

	var texto_x: float = _hud_divisor.position.x + _hud_divisor.size.x + padding * 0.72
	var status_largura: float = largura * (0.28 if modo_credito else 0.24)
	var texto_largura: float = maxf(100.0, largura - texto_x - status_largura - padding * 1.35)
	_hud_modo.position = Vector2(texto_x, altura * 0.10)
	_hud_modo.size = Vector2(texto_largura, altura * 0.28)
	_hud_instrucao.position = Vector2(texto_x, altura * 0.38)
	_hud_instrucao.size = Vector2(texto_largura, altura * 0.25)
	_hud_instrucao_base_x = texto_x
	_hud_info.position = Vector2(texto_x, altura * 0.66)
	_hud_info.size = Vector2(texto_largura, altura * 0.20)

	var status_x: float = largura - status_largura - padding
	_hud_status_fundo.position = Vector2(status_x, altura * 0.14)
	_hud_status_fundo.size = Vector2(status_largura, altura * 0.66)
	_hud_creditos.position = Vector2(status_x, altura * 0.18)
	_hud_creditos.size = Vector2(status_largura, altura * 0.58)
	_hud_status_livre.position = Vector2(status_x, altura * 0.18)
	_hud_status_livre.size = Vector2(status_largura, altura * 0.58)


func definir_modo_credito(ativo: bool) -> void:
	modo_credito = ativo
	ArcadeSettings.set_mode(
		ArcadeSettings.Mode.CREDIT if ativo else ArcadeSettings.Mode.FREE
	)
	_atualizar_hud_operacao(true)


func definir_creditos(valor: int) -> void:
	creditos_maquina = clampi(valor, 0, 999)
	ArcadeSettings.set_credits(creditos_maquina)
	_atualizar_hud_operacao(true)


## O modo e o saldo vivem no autoload ArcadeSettings (persistido em
## disco), nao nos @export locais — assim a escolha feita na tela de
## Configuracoes (F9) vale aqui, e o saldo sobrevive a fechar o jogo.
func _sincronizar_com_arcade_settings() -> void:
	modo_credito = ArcadeSettings.is_credit_mode()
	creditos_maquina = clampi(ArcadeSettings.credits, 0, 999)
	_atualizar_hud_operacao(true)


func _atualizar_hud_operacao(forcar: bool = false) -> void:
	if _hud_modo == null or not is_instance_valid(_hud_modo):
		return

	var creditos: int = clampi(creditos_maquina, 0, 999)
	var assinatura := "%s|%d" % [str(modo_credito), creditos]
	if not forcar and assinatura == _hud_assinatura:
		return
	_hud_assinatura = assinatura

	if modo_credito:
		_hud_status_fundo.add_theme_stylebox_override("panel", _style_cartao_status(true))
		_hud_modo.text = "MODO CRÉDITO"
		_hud_modo.label_settings.font_color = Color(1.0, 0.78, 0.16)
		_hud_creditos.visible = true
		_hud_status_livre.visible = false
		_hud_creditos.text = "CRÉDITOS\n%02d" % creditos
		if creditos > 0:
			_hud_info.text = "1 CRÉDITO = 1 PARTIDA  •  SALDO PRONTO PARA JOGAR"
			_hud_instrucao.text = "APERTE START PARA JOGAR"
			if is_instance_valid(_label_start):
				_label_start.text = "APERTE START"
		else:
			_hud_info.text = "INSIRA CRÉDITO NA MÁQUINA  •  O SALDO ATUALIZA AUTOMATICAMENTE"
			_hud_instrucao.text = "INSIRA CRÉDITO"
			if is_instance_valid(_label_start):
				_label_start.text = "INSIRA CRÉDITO"
	else:
		_hud_status_fundo.add_theme_stylebox_override("panel", _style_cartao_status(false))
		_hud_modo.text = "MODO LIVRE"
		_hud_modo.label_settings.font_color = COR_NEON_CIANO
		_hud_instrucao.text = "APERTE START PARA JOGAR"
		_hud_creditos.visible = false
		_hud_status_livre.visible = true
		_hud_status_livre.text = "JOGO\nLIVRE"
		_hud_info.text = "SEM CRÉDITOS  •  8 TAZOS  •  ESCOLHA SUA MÚSICA E DIFICULDADE"
		if is_instance_valid(_label_start):
			_label_start.text = "APERTE START"

	_posicionar_hud_superior(get_viewport_rect().size)
	_reiniciar_mensagens_hud()


func _mensagens_hud() -> Array[String]:
	if modo_credito:
		if creditos_maquina <= 0:
			return [
				"INSIRA CRÉDITO",
				"AGUARDANDO CRÉDITO",
				"PREPARE-SE PARA A BATIDA",
			]
		return [
			"APERTE START PARA JOGAR",
			"CRÉDITO PRONTO",
			"ESCOLHA SUA MÚSICA",
			"TOQUE • SEGURE • ARRASTE",
		]
	return [
		"APERTE START PARA JOGAR",
		"TOQUE • SEGURE • ARRASTE",
		"8 TAZOS • UMA BATIDA",
		"SINTA A MÚSICA",
	]


func _reiniciar_mensagens_hud() -> void:
	_hud_mensagem_tempo = 0.0
	_hud_mensagem_index = -1
	_mostrar_proxima_mensagem_hud()


func _atualizar_mensagens_hud(delta: float) -> void:
	if _hud_instrucao == null or not is_instance_valid(_hud_instrucao):
		return
	_hud_mensagem_tempo += delta
	if _hud_mensagem_tempo >= HUD_MENSAGEM_SEG:
		_hud_mensagem_tempo = 0.0
		_mostrar_proxima_mensagem_hud()


func _mostrar_proxima_mensagem_hud() -> void:
	var mensagens: Array[String] = _mensagens_hud()
	if mensagens.is_empty() or not is_instance_valid(_hud_instrucao):
		return

	_hud_mensagem_index = wrapi(_hud_mensagem_index + 1, 0, mensagens.size())
	if _hud_mensagem_tween != null and _hud_mensagem_tween.is_valid():
		_hud_mensagem_tween.kill()

	_hud_instrucao.text = mensagens[_hud_mensagem_index]
	_hud_instrucao.modulate.a = 0.0
	_hud_instrucao.position.x = _hud_instrucao_base_x + 18.0

	_hud_mensagem_tween = _criar_tween_seguro()
	if _hud_mensagem_tween == null:
		_hud_instrucao.modulate.a = 1.0
		_hud_instrucao.position.x = _hud_instrucao_base_x
		return
	_hud_mensagem_tween.set_parallel(true)
	_hud_mensagem_tween.set_trans(Tween.TRANS_QUINT)
	_hud_mensagem_tween.set_ease(Tween.EASE_OUT)
	_hud_mensagem_tween.tween_property(_hud_instrucao, "modulate:a", 1.0, 0.34)
	_hud_mensagem_tween.tween_property(_hud_instrucao, "position:x", _hud_instrucao_base_x, 0.42)


# ---------------------------------------------------------------
# TEXTO "APERTE START"
# ---------------------------------------------------------------
func _criar_texto_start(tam_tela: Vector2) -> void:
	# Menor e mais discreto -- só um "convite" sutil, sem competir com a arte de fundo.
	_config_start = LabelSettings.new()
	_config_start.font = _carregar_fonte(FONTE_TITULO)
	_config_start.font_size = int(tam_tela.x * 0.042)
	_config_start.outline_size = 2
	_config_start.outline_color = Color(0.01, 0.01, 0.03, 0.72)
	_config_start.font_color = Color.WHITE
	_config_start.shadow_size = 10
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
	_atualizar_hud_operacao(true)


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
	var cor_shadow_fraca := Color(COR_NEON_CIANO.r, COR_NEON_CIANO.g, COR_NEON_CIANO.b, 0.28)
	var cor_shadow_forte := Color(COR_NEON_ROSA.r, COR_NEON_ROSA.g, COR_NEON_ROSA.b, 0.68)

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
	_tween_start.parallel().tween_property(_config_start, "font_color", COR_NEON_ROSA.lerp(Color.WHITE, 0.42), 0.85)
	_tween_start.parallel().tween_property(_config_start, "shadow_color", cor_shadow_forte, 0.85)
	_tween_start.parallel().tween_property(_config_start, "shadow_size", 20.0, 0.85)

	# Repouso: volta ao rosa, halo mais fraco, leve transparência -- "respira" em vez de gritar.
	_tween_start.tween_property(_label_start, "scale", Vector2(1.0, 1.0), 0.85)
	_tween_start.parallel().tween_property(_label_start, "position:y", y_base, 0.85)
	_tween_start.parallel().tween_property(_label_start, "modulate:a", 0.85, 0.85)
	_tween_start.parallel().tween_property(_config_start, "font_color", Color.WHITE, 0.85)
	_tween_start.parallel().tween_property(_config_start, "shadow_color", cor_shadow_fraca, 0.85)
	_tween_start.parallel().tween_property(_config_start, "shadow_size", 12.0, 0.85)


# ---------------------------------------------------------------
# START pressionado
# ---------------------------------------------------------------
func _ao_apertar_start() -> void:
	if _ja_iniciando or _portal_entrada_em_andamento:
		return
	if modo_credito and creditos_maquina <= 0:
		_atualizar_hud_operacao(true)
		return
	_ja_iniciando = true
	if _tween_start:
		_tween_start.kill()
	if is_instance_valid(_sfx_start):
		_sfx_start.play()
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

	_posicionar_hud_superior(tam_tela)
	_posicionar_label_start()
