extends Node2D
## ============================================================
## PLAY — HIT MUSIC (mesa redonda / tela circular)
##
## Círculo físico calibrado para mesa/tela grande: 48 cm de RAIO.
## O círculo visual agora ocupa quase toda a largura no modo retrato.
## A cena roda em 3 estados, em sequência:
##
## 1. APRESENTACAO -- capa/imagem da fase com o nome por cima.
## 2. CONTAGEM -- vídeo media1.ogv com contagem regressiva por cima.
## 3. JOGANDO -- vídeo media1.ogv centralizado no círculo, com
##    os 8 pontos, HUD, música song1 e beatmap musical aleatório/adaptativo.
##
## Dentro de JOGANDO:
## - 8 pontos ao redor do círculo, ligados aos inputs físicos
##   input_a..input_h ("toque").
## - BEATMAP com eventos "toque" e "arraste" (arraste segue um
##   CAMINHO de 2+ pontos em zigue-zague, detectado só por touch/
##   mouse, nunca pelos inputs_a..h).
## - Acerto = pontos + combo + volume da música sobe. Erro = sem
##   perda de pontos, zera o combo, volume cai ("Guitar Hero").
## - Partida dura 1 minuto e 20 segundos (DURACAO_PARTIDA_SEG).
##   Ao zerar o tempo (ou a música terminar sozinha), encerra e
##   volta pra tela de abertura.
##
## >>> PRECISA AJUSTAR ANTES DE RODAR DE VERDADE <<<
## - CAMINHO_MUSICA usa "res://songs/song1.mp3".
## - CAMINHO_IMAGEM_FASE usa "res://images/hit_music_sinta_a_batida.png".
## - CAMINHO_VIDEO_CONTAGEM usa "res://mmedias/media1.ogv".
## - CAMINHO_VIDEO_FUNDO usa "res://mmedias/media1.ogv".
## - CAMINHO_CENA_ABERTURA assume "res://scenes/abertura.tscn".
## - CAMINHO_SHADER_PULSO / CAMINHO_SHADER_MASCARA assumem uma
##   pasta "res://shaders/" -- salve os dois .gdshader que vieram
##   junto com este arquivo lá (ou ajuste o caminho).
## - NOME_FASE está como FASE 1.
## - BEATMAP_CHINA_SONG pode ficar vazio: o script gera um beatmap
##   automático por fases da música song1.
## - Se quiser fases futuras (2, 3...) com outra imagem/vídeos/
##   música, é só repetir esse mesmo padrão de constantes por fase
##   mais pra frente -- não implementei isso ainda porque só os
##   arquivos da fase 1 existem por enquanto.
## ============================================================

signal musica_concluida

enum EstadoJogo { APRESENTACAO, CONTAGEM, JOGANDO }

# --- Constantes físicas da mesa redonda / tela gigante ---
# A referência física agora é RAIO de 48 cm.
# 48 cm = 18.90 polegadas de raio / 96 cm = 37.80 polegadas de diâmetro.
const RAIO_FISICO_CM: float = 48.0
const DIAMETRO_FISICO_CM: float = RAIO_FISICO_CM * 2.0
const CIRCUNFERENCIA_FISICA_CM: float = DIAMETRO_FISICO_CM * PI
const RAIO_FISICO_POL: float = RAIO_FISICO_CM / 2.54
const DIAMETRO_FISICO_POL: float = DIAMETRO_FISICO_CM / 2.54

# AGIGANTAMENTO REAL DO JOGO:
# antes era 0.80, então o círculo ocupava só 80% da largura menor.
# agora usa 98.5% da largura no modo retrato, ficando quase colado nas bordas.
const PORCENTAGEM_TELA_CIRCULO: float = 0.985
const SUAVIZACAO_MASCARA_PX: float = 3.0

# --- Shaders (arquivos .gdshader -- veja o cabeçalho do arquivo) ---
const CAMINHO_SHADER_PULSO: String = "res://shaders/pulso_neon.gdshader"
const CAMINHO_SHADER_MASCARA: String = "res://shaders/mascara_circular.gdshader"

# --- Apresentação da fase ---
const CAMINHO_IMAGEM_FASE: String = "res://images/hit_music_sinta_a_batida.png"
const NOME_FASE: String = "FASE 1"
const DURACAO_APRESENTACAO_SEG: float = 2.5

# --- Contagem regressiva de início ---
const CAMINHO_VIDEO_CONTAGEM: String = "res://mmedias/media1.ogv"
const DURACAO_CONTAGEM_SEG: float = 5.0

# --- Vídeo de fundo do jogo em si ---
const CAMINHO_VIDEO_FUNDO: String = "res://mmedias/media1.ogv"

# Fallback automático: se você escreveu a pasta como medias em vez de mmedias,
# o script também tenta encontrar o vídeo em res://medias/media1.ogv.
const CAMINHO_VIDEO_FALLBACK_1: String = "res://medias/media1.ogv"

# --- Música ---
const CAMINHO_MUSICA: String = "res://songs/song1.mp3"

# --- Duração da partida e retorno ---
const DURACAO_PARTIDA_SEG: float = 80.0  # 1 minuto e 20 segundos
const CAMINHO_CENA_ABERTURA: String = "res://scenes/abertura.tscn"

# --- Os 8 pontos ---
const NUM_PONTOS: int = 8
const LETRAS_PONTOS: Array[String] = ["A", "B", "C", "D", "E", "F", "G", "H"]
const INPUTS_PONTOS: Array[String] = [
	"input_a", "input_b", "input_c", "input_d",
	"input_e", "input_f", "input_g", "input_h",
]

# --- Timing (ajuste fino da jogabilidade) ---
const JANELA_ACERTO_SEG: float = 0.18       # +- tempo pra contar como acerto
const TEMPO_APROXIMACAO_SEG: float = 1.0    # apenas VISUAL da tela; não controla o LED físico


# --- Pontuação ---
const PONTOS_POR_ACERTO_TOQUE: int = 100
const PONTOS_POR_ACERTO_ARRASTE: int = 150

# --- Volume dinâmico (efeito "Guitar Hero") ---
const VOLUME_MAX_DB: float = 0.0
const VOLUME_MIN_DB: float = -40.0
const VOLUME_PASSO_ERRO_DB: float = -6.0
const VOLUME_PASSO_ACERTO_DB: float = 4.0

# --- Cores neon ---
const COR_NEON_ROSA: Color = Color(1.0, 0.15, 0.85)
const COR_NEON_CIANO: Color = Color(0.25, 0.85, 1.0)
const COR_ACERTO: Color = Color(0.3, 1.0, 0.55)
const COR_ERRO: Color = Color(1.0, 0.2, 0.2)


## ------------------------------------------------------------
## BEATMAP -- preencha ouvindo a música. Tempos em segundos.
## "toque":   {"tipo": "toque", "tempo": 1.20, "ponto": 0}
## "arraste": {"tipo": "arraste", "tempo": 8.00, "tempo_fim": 8.90,
##             "caminho": [2, 5, 1, 6]}
##             -- "caminho" é a sequência de pontos que o dedo
##             precisa visitar em ordem, num arrasto contínuo.
##             2 pontos = arrasto reto. 3+ pontos = zigue-zague
##             (o dedo muda de direção no meio do gesto).
## ------------------------------------------------------------
const BEATMAP_CHINA_SONG: Array = [
	# {"tipo": "toque", "tempo": 1.20, "ponto": 0},
	# {"tipo": "arraste", "tempo": 8.00, "tempo_fim": 8.90, "caminho": [2, 5, 1]},
]

const RAIO_POS_PONTOS_RATIO: float = 0.86
const RAIO_VISUAL_PONTO_RATIO: float = 0.070
const RAIO_TOQUE_EXTRA_RATIO: float = 1.75
# Moldura touch / frame touch:
# aumenta um pouco a área de leitura do arraste para compensar pequenas falhas
# de calibração e deixar o dedo passar pela sequência dos Tazos sem "perder" o checkpoint.
const ARRASTE_RAIO_CHECKPOINT_EXTRA: float = 2.15
const ARRASTE_TOLERANCIA_FINAL_SEG: float = 0.58
# Teste no PC: deixa o mouse visível para calibrar a moldura touch.
const MOUSE_VISIVEL_TESTE: bool = true
# Rastro luminoso do dedo/mouse durante o arraste.
const ARRASTE_RASTRO_DURACAO_SEG: float = 0.95
const ARRASTE_RASTRO_MAX_PONTOS: int = 96
const ARRASTE_RASTRO_DIST_MIN_PX: float = 2.0
const ARRASTE_SETAS_ATIVAS_BRILHO: float = 1.35
const TEMPO_ORBE_SEG: float = 1.05

const CAMINHO_TAZO_SCENE: String = "res://entities/tazo.tscn"
const TAZO_ANIM_IDLE: String = "idle"
const TAZO_ANIM_ACESO: String = "hig" # nome que você criou no AnimatedSprite2D
const TAZO_DIAMETRO_RATIO: float = 0.36
const TAZO_IDLE_ANIMAR: bool = false
const TAZO_ACESO_USAR_FRAME_FINAL: bool = true
const TAZO_BRILHO_ATIVO: float = 1.55
const MOSTRAR_LETRA_ORBE: bool = false

# Sprite sheet corrigido: todos os frames têm o mesmo canvas e o Tazo fica exatamente no centro.
# Coloque o arquivo em: res://entities/tazos_fixos_sheet.png
const TAZO_USAR_SHEET_FIXO: bool = true
const CAMINHO_TAZO_SHEET_FIXO: String = "res://entities/tazos_fixos_sheet.png"
const TAZO_SHEET_FRAME_SIZE: Vector2i = Vector2i(160, 160)
const TAZO_IDLE_FRAME_INDEX: int = 0
const TAZO_ACESO_FRAME_INDEX: int = 7


# Transparência do vídeo de fundo.
# 1.0 = normal / 0.45 = bem mais leve e transparente.
const VIDEO_FUNDO_ALPHA: float = 0.50

# Modal final: tempo para inserir crédito/continuar antes de voltar à abertura.
const TEMPO_MODAL_CONTINUAR_SEG: float = 10.0

# Cada ponto recebe uma cor diferente para a bola/orbe que sai do centro.
const CORES_ORBE_POR_PONTO: Array = [
	Color(1.0, 0.18, 0.82, 1.0),  # A rosa
	Color(0.15, 0.88, 1.0, 1.0),  # B ciano
	Color(1.0, 0.78, 0.08, 1.0),  # C amarelo
	Color(0.32, 1.0, 0.35, 1.0),  # D verde
	Color(0.62, 0.25, 1.0, 1.0),  # E roxo
	Color(1.0, 0.32, 0.12, 1.0),  # F laranja
	Color(0.1, 0.45, 1.0, 1.0),   # G azul
	Color(1.0, 0.08, 0.22, 1.0),  # H vermelho
]

const COR_TOQUE_ORBE: Color = Color(1.0, 0.18, 0.82, 1.0)
const COR_SLIDE_AMARELO: Color = Color(1.0, 0.82, 0.06, 1.0)
const COR_SLIDE_PRETO: Color = Color(0.02, 0.015, 0.005, 1.0)
const COR_SLIDE_COMPLETO: Color = Color(0.25, 1.0, 0.45, 1.0)

# Comunicação de LEDs centralizada.
# IMPORTANTE: o Godot NUNCA abre COM5 diretamente.
# Toda comunicação passa pelo Autoload led_client.gd -> spool -> BRIDGE_R14.ps1 -> Arduino.
var _led_assinatura_atual: String = ""
var _led_feedback_bloqueio_ate_msec: int = 0
var _shader_tazo_cache: Shader = null

# --- Nodes internos ---
var _video_fundo: VideoStreamPlayer
var _mascara_layer: CanvasLayer
var _mascara_rect: ColorRect
var _mascara_mat: ShaderMaterial
var _musica_player: AudioStreamPlayer

var _pontos: Array = []  # Array[Node2D] — instâncias de entities/tazo.tscn
var _ponto_raios: Array = []
var _ponto_sprites: Array = []
var _ponto_estados: Array = []
var _ponto_posicoes_fixas: Array[Vector2] = []
var _beatmap: Array = []
var _indice_beatmap: int = 0
var _eventos_ativos: Array = []

var _pontuacao: int = 0
var _combo_atual: int = 0
var _label_pontuacao: Label
var _label_combo: Label
var _tween_combo: Tween

var _tempo_restante: float = DURACAO_PARTIDA_SEG
var _partida_encerrada: bool = false
var _label_tempo: Label

var _raio_circulo_px: float = 0.0
var _raio_toque_ponto_px: float = 0.0
var _centro_tela: Vector2 = Vector2.ZERO
var _textura_particula_cache: ImageTexture
var _label_debug_video: Label
var _rng := RandomNumberGenerator.new()

# Arrasto contínuo (touch) -- segue um "caminho" de pontos em sequência.
var _arraste_evento_atual = null  # Dictionary ou null
var _arraste_indice_atual: int = 0
var _arraste_gesto_ativo: bool = false
var _arraste_ultimo_pos: Vector2 = Vector2.ZERO
var _arraste_pos_atual: Vector2 = Vector2.ZERO
var _arraste_rastro: Array = []

# Estado da cena e assets da apresentação/contagem.
var _estado_jogo: int = EstadoJogo.APRESENTACAO
var _sprite_apresentacao: Sprite2D
var _label_nome_fase: Label
var _label_contagem: Label
var _contagem_restante: float = DURACAO_CONTAGEM_SEG
var _contagem_ultimo_numero_led: int = -1

# Modal final de crédito/continuação.
var _modal_continuar_ativo: bool = false
var _modal_countdown_restante: float = TEMPO_MODAL_CONTINUAR_SEG
var _modal_layer: CanvasLayer
var _modal_label_titulo: Label
var _modal_label_score: Label
var _modal_label_countdown: Label
var _modal_label_acao: Label
var _modal_ultimo_numero_led: int = -1


# ---------------------------------------------------------------
# CICLO DE VIDA
# ---------------------------------------------------------------
func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if MOUSE_VISIVEL_TESTE else Input.MOUSE_MODE_HIDDEN)  # visível no teste; depois pode trocar MOUSE_VISIVEL_TESTE para false
	_rng.randomize()
	_arduino_inicializar()

	_beatmap = BEATMAP_CHINA_SONG.duplicate(true)
	if _beatmap.is_empty():
		push_warning("BEATMAP_CHINA_SONG está vazio -- usando beatmap automático por fases da música song1.")
		_beatmap = _gerar_beatmap_song1_por_fases(DURACAO_PARTIDA_SEG)
	_beatmap.sort_custom(func(a, b): return a["tempo"] < b["tempo"])

	_preparar_base_circular()
	_iniciar_apresentacao_fase()

func _process(delta: float) -> void:
	_arduino_tick_serial()
	_manter_tazos_fixos()
	_limpar_rastro_arraste_vencido()
	if _modal_continuar_ativo:
		_processar_modal_continuar(delta)
		queue_redraw()
		return

	match _estado_jogo:
		EstadoJogo.CONTAGEM:
			_atualizar_contagem(delta)
		EstadoJogo.JOGANDO:
			_processar_frame_jogo(delta)
	queue_redraw()

func _draw() -> void:
	if _estado_jogo != EstadoJogo.JOGANDO:
		return

	_desenhar_area_dedicada_central()
	_desenhar_scanner_radar()
	_desenhar_nucleo_central()
	_desenhar_anel_volume()

	var tempo_musica: float = _tempo_atual_musica()

	# Primeiro os caminhos de arraste, depois o rastro real do dedo/mouse e os orbes por cima.
	for evento in _eventos_ativos:
		if evento.get("resolvido", false):
			continue
		if evento["tipo"] == "arraste":
			_desenhar_linha_arraste(evento)

	_desenhar_rastro_arraste()

	for evento in _eventos_ativos:
		if evento.get("resolvido", false):
			continue
		if evento["tipo"] == "toque":
			_desenhar_orbe_toque(evento, tempo_musica)



func _desenhar_area_dedicada_central() -> void:
	# Centro maior e mais vivo: o raio do meio agora ocupa mais área,
	# deixando a tela com aparência de arcade japonês/chinês moderno.
	var tempo: float = Time.get_ticks_msec() / 1000.0
	var pulso: float = sin(tempo * 2.2) * 0.5 + 0.5
	var giro: float = fmod(tempo * 0.55, TAU)

	# Base escura maior, para segurar melhor os efeitos que nascem no centro.
	draw_circle(_centro_tela, _raio_circulo_px * 0.72, Color(0, 0, 0, 0.070))
	draw_circle(_centro_tela, _raio_circulo_px * 0.58, Color(COR_NEON_CIANO.r, COR_NEON_CIANO.g, COR_NEON_CIANO.b, 0.018 + pulso * 0.012))

	# Anéis internos com mais leitura visual.
	draw_arc(_centro_tela, _raio_circulo_px * 0.54, 0.0, TAU, 160, Color(1, 1, 1, 0.040), 1.4, true)
	draw_arc(_centro_tela, _raio_circulo_px * 0.67, giro, giro + PI * 1.38, 160, Color(COR_NEON_CIANO.r, COR_NEON_CIANO.g, COR_NEON_CIANO.b, 0.105 + pulso * 0.035), 2.7, true)
	draw_arc(_centro_tela, _raio_circulo_px * 0.79, -giro * 0.82 + PI * 0.18, -giro * 0.82 + PI * 1.72, 160, Color(COR_NEON_ROSA.r, COR_NEON_ROSA.g, COR_NEON_ROSA.b, 0.092 + pulso * 0.032), 2.8, true)
	draw_arc(_centro_tela, _raio_circulo_px * 0.90, giro * 0.56 - PI * 0.15, giro * 0.56 + PI * 1.10, 160, Color(1.0, 0.78, 0.08, 0.055 + pulso * 0.025), 2.0, true)
	draw_arc(_centro_tela, _raio_circulo_px * 0.965, 0.0, TAU, 180, Color(1, 1, 1, 0.033), 1.2, true)

	# Pequenas marcas digitais no raio do meio, para dar vida sem poluir.
	for i in range(32):
		var a: float = giro + float(i) * TAU / 32.0
		var r1: float = _raio_circulo_px * (0.60 + 0.025 * sin(float(i) * 1.7 + tempo * 3.2))
		var r2: float = r1 + _raio_circulo_px * 0.018
		var p1: Vector2 = _centro_tela + Vector2(cos(a), sin(a)) * r1
		var p2: Vector2 = _centro_tela + Vector2(cos(a), sin(a)) * r2
		var cor: Color = COR_NEON_CIANO.lerp(COR_NEON_ROSA, 0.5 + 0.5 * sin(float(i) * 0.9 + tempo * 2.0))
		draw_line(p1, p2, Color(cor.r, cor.g, cor.b, 0.10 + pulso * 0.05), 1.2, true)

func _ease_out_cubic(t: float) -> float:
	t = clamp(t, 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 3.0)


func _cor_orbe_por_ponto(indice: int) -> Color:
	if CORES_ORBE_POR_PONTO.is_empty():
		return COR_TOQUE_ORBE
	return CORES_ORBE_POR_PONTO[abs(indice) % CORES_ORBE_POR_PONTO.size()]


func _desenhar_orbe_toque(evento: Dictionary, tempo_musica: float) -> void:
	var indice_ponto: int = int(evento["ponto"])
	if indice_ponto < 0 or indice_ponto >= _pontos.size():
		return

	var cor_orbe: Color = _cor_orbe_por_ponto(indice_ponto)
	var alvo: Vector2 = _pontos[indice_ponto].position
	var direcao: Vector2 = (alvo - _centro_tela).normalized()
	# Como o raio do meio subiu, a bola nasce mais para fora do centro.
	var origem: Vector2 = _centro_tela + direcao * (_raio_circulo_px * 0.32)

	var inicio: float = float(evento["tempo"]) - TEMPO_ORBE_SEG
	var fim: float = float(evento["tempo"])
	var t: float = clamp((tempo_musica - inicio) / max(fim - inicio, 0.001), 0.0, 1.0)
	var e: float = _ease_out_cubic(t)
	var pos: Vector2 = origem.lerp(alvo, e)
	var raio_base: float = _ponto_raio(indice_ponto)
	var raio: float = raio_base * lerp(0.42, 0.78, e)
	var tempo: float = Time.get_ticks_msec() / 1000.0
	var pulso: float = sin(Time.get_ticks_msec() / 72.0) * 0.5 + 0.5

	# Trilho mais vivo: neon duplo + fagulhas pequenas que acompanham a bola.
	draw_line(origem, pos, Color(cor_orbe.r, cor_orbe.g, cor_orbe.b, 0.070), max(1.0, raio * 0.42), true)
	draw_line(origem, pos, Color(1, 1, 1, 0.125), max(1.0, raio * 0.105), true)

	var comprimento: float = origem.distance_to(alvo)
	var qtd_fagulhas: int = int(clamp(int(comprimento / max(raio_base * 0.26, 8.0)), 6, 24))
	var anim_fagulha: float = fmod(tempo * 1.55, 1.0)
	for s in range(qtd_fagulhas):
		var ts: float = fmod((float(s) / float(qtd_fagulhas)) + anim_fagulha, 1.0)
		if ts > e:
			continue
		var lateral: Vector2 = Vector2(-direcao.y, direcao.x) * sin(float(s) * 2.31 + tempo * 7.0) * raio * 0.30
		var p_spark: Vector2 = origem.lerp(pos, ts) + lateral
		var alpha_spark: float = clamp(0.38 * (1.0 - abs(e - ts)), 0.0, 0.38)
		var cor_spark: Color = cor_orbe.lerp(Color.WHITE, 0.35 + 0.28 * sin(float(s) + tempo * 2.0))
		draw_circle(p_spark, max(1.4, raio * 0.070), Color(cor_spark.r, cor_spark.g, cor_spark.b, alpha_spark))

	# Ondas um pouco mais presentes, mas ainda controladas pelo tamanho do Tazo.
	var onda_tempo: float = fmod(Time.get_ticks_msec() / 500.0, 1.0)
	for k in range(4):
		var atraso: float = float(k) * 0.18
		var t_onda: float = clamp(e - atraso + onda_tempo * 0.08, 0.0, 1.0)
		var pos_onda: Vector2 = origem.lerp(pos, t_onda)
		var raio_onda: float = raio * (0.70 + onda_tempo * 0.72 + float(k) * 0.12)
		var alpha_onda: float = clamp((1.0 - abs(t_onda - e)) * 0.31, 0.0, 0.31)
		draw_arc(pos_onda, raio_onda, 0.0, TAU, 44, Color(cor_orbe.r, cor_orbe.g, cor_orbe.b, alpha_onda), 1.65, true)
		draw_arc(pos_onda, raio_onda * 0.55, 0.0, TAU, 34, Color(1, 1, 1, alpha_onda * 0.56), 1.10, true)

	# Bola principal agora conversa com o Tazo: viva, mas sem virar um disco gigante.
	draw_circle(pos, raio * 1.18, Color(cor_orbe.r, cor_orbe.g, cor_orbe.b, 0.13 + pulso * 0.10))
	draw_circle(pos, raio * 0.96, Color(cor_orbe.r, cor_orbe.g, cor_orbe.b, 0.90))
	draw_circle(pos, raio * 0.43, Color(1.0, 1.0, 1.0, 0.94))
	draw_arc(pos, raio * (1.02 + pulso * 0.10), 0.0, TAU, 56, Color(1, 1, 1, 0.80), 2.0, true)
	draw_arc(pos, raio * (1.18 + pulso * 0.14), -PI * 0.25, PI * 1.15, 42, Color(cor_orbe.r, cor_orbe.g, cor_orbe.b, 0.62), 1.85, true)

	if MOSTRAR_LETRA_ORBE:
		var fonte: Font = ThemeDB.fallback_font
		var tam_fonte: int = int(raio * 0.72)
		var texto: String = LETRAS_PONTOS[indice_ponto]
		var largura: float = fonte.get_string_size(texto, HORIZONTAL_ALIGNMENT_CENTER, -1, tam_fonte).x
		draw_string(fonte, Vector2(pos.x - largura / 2.0, pos.y + tam_fonte * 0.32), texto, HORIZONTAL_ALIGNMENT_CENTER, -1, tam_fonte, Color(0, 0, 0, 0.65))
		draw_string(fonte, Vector2(pos.x - largura / 2.0, pos.y + tam_fonte * 0.32 - 1.0), texto, HORIZONTAL_ALIGNMENT_CENTER, -1, tam_fonte, Color.WHITE)

func _desenhar_scanner_radar() -> void:
	# Leque giratório sutil de fundo, tipo radar -- dá vida ao círculo mesmo sem eventos ativos.
	var angulo_atual: float = fmod(Time.get_ticks_msec() / 1000.0, TAU)
	var num_segmentos: int = 24
	var abertura: float = 0.55

	var pontos := PackedVector2Array()
	var cores := PackedColorArray()

	pontos.append(_centro_tela)
	cores.append(Color(COR_NEON_CIANO.r, COR_NEON_CIANO.g, COR_NEON_CIANO.b, 0.12))

	for k in range(num_segmentos + 1):
		var a: float = angulo_atual - abertura + (abertura * 2.0) * (float(k) / num_segmentos)
		pontos.append(_centro_tela + Vector2(cos(a), sin(a)) * _raio_circulo_px)
		cores.append(Color(COR_NEON_CIANO.r, COR_NEON_CIANO.g, COR_NEON_CIANO.b, 0.0))

	draw_polygon(pontos, cores)

	# Borda frontal da varredura, mais nítida -- reforça a sensação de "scan" real.
	var ponta_frente: Vector2 = _centro_tela + Vector2(cos(angulo_atual), sin(angulo_atual)) * _raio_circulo_px
	draw_line(_centro_tela, ponta_frente, Color(COR_NEON_CIANO.r, COR_NEON_CIANO.g, COR_NEON_CIANO.b, 0.35), 2.0, true)


func _desenhar_nucleo_central() -> void:
	# Raios estruturais mais presentes, agora acompanhando o raio central maior.
	var tempo: float = Time.get_ticks_msec() / 1000.0
	for i in range(_pontos.size()):
		var ponto: Node2D = _pontos[i]
		var cor: Color = _cor_orbe_por_ponto(i)
		var alpha: float = 0.050 + 0.030 * (sin(tempo * 2.4 + float(i)) * 0.5 + 0.5)
		draw_line(_centro_tela, ponto.position, Color(cor.r, cor.g, cor.b, alpha), 1.55, true)

	# Medalhão central maior: ele conversa com o novo raio de saída das bolas.
	var pulso: float = sin(Time.get_ticks_msec() / 760.0) * 0.5 + 0.5
	var raio_nucleo: float = _raio_circulo_px * 0.145
	var giro: float = fmod(tempo * 1.2, TAU)

	draw_circle(_centro_tela, raio_nucleo * 2.15, Color(COR_NEON_ROSA.r, COR_NEON_ROSA.g, COR_NEON_ROSA.b, 0.050 + pulso * 0.050))
	draw_circle(_centro_tela, raio_nucleo * 1.35, Color(COR_NEON_CIANO.r, COR_NEON_CIANO.g, COR_NEON_CIANO.b, 0.035 + pulso * 0.035))
	draw_arc(_centro_tela, raio_nucleo * 1.82, giro, giro + PI * 1.25, 52, Color(1, 1, 1, 0.26), 2.1, true)
	draw_arc(_centro_tela, raio_nucleo * 1.28, -giro, -giro + PI * 1.35, 48, Color(COR_NEON_ROSA.r, COR_NEON_ROSA.g, COR_NEON_ROSA.b, 0.68 + pulso * 0.22), 3.1, true)
	draw_arc(_centro_tela, raio_nucleo * 0.82, giro * 1.45, giro * 1.45 + PI * 1.65, 48, Color(COR_NEON_CIANO.r, COR_NEON_CIANO.g, COR_NEON_CIANO.b, 0.70 + pulso * 0.20), 2.7, true)
	draw_circle(_centro_tela, raio_nucleo * 0.32, Color(1, 1, 1, 0.55 + pulso * 0.40))

func _desenhar_anel_volume() -> void:
	# Medidor de volume como um anel completo colado na borda interna do círculo --
	# usa a própria forma da mesa como HUD, em vez de uma barra retangular solta.
	if _musica_player == null:
		return

	var proporcao: float = clamp((_musica_player.volume_db - VOLUME_MIN_DB) / (VOLUME_MAX_DB - VOLUME_MIN_DB), 0.0, 1.0)
	var raio_anel: float = _raio_circulo_px * 0.965
	var espessura: float = _raio_circulo_px * 0.028
	var inicio_ang: float = -PI / 2.0

	draw_arc(_centro_tela, raio_anel, 0.0, TAU, 96, Color(1, 1, 1, 0.08), espessura, true)

	if proporcao > 0.001:
		var cor_nivel: Color = COR_NEON_CIANO.lerp(COR_ERRO, 1.0 - proporcao)
		draw_arc(_centro_tela, raio_anel, inicio_ang, inicio_ang + TAU * proporcao, 96, cor_nivel, espessura, true)


func _desenhar_linha_arraste(evento: Dictionary) -> void:
	var caminho: Array = evento["caminho"]
	if caminho.size() < 2:
		return

	var em_andamento: bool = _arraste_evento_atual != null and _arraste_evento_atual == evento
	var indice_progresso: int = _arraste_indice_atual if em_andamento else 0

	var comprimentos: Array = []
	var comprimento_total: float = 0.0
	for i in range(caminho.size() - 1):
		var a: Vector2 = _pontos[int(caminho[i])].position
		var b: Vector2 = _pontos[int(caminho[i + 1])].position
		var d: float = a.distance_to(b)
		comprimentos.append(d)
		comprimento_total += d

	var progresso_fluxo: float = fmod(Time.get_ticks_msec() / 500.0, 1.0)
	var pulso: float = sin(Time.get_ticks_msec() / 105.0) * 0.5 + 0.5
	var distancia_alvo: float = progresso_fluxo * comprimento_total
	var acumulado: float = 0.0

	for i in range(caminho.size() - 1):
		var completo: bool = i < indice_progresso
		# A seta atual fica destacada: é a próxima que o jogador precisa seguir.
		var ativo: bool = (em_andamento and i == indice_progresso) or (not em_andamento and i == 0)
		_desenhar_segmento_arraste(int(caminho[i]), int(caminho[i + 1]), pulso, completo, ativo)

		if distancia_alvo >= acumulado and distancia_alvo <= acumulado + float(comprimentos[i]):
			var t_local: float = (distancia_alvo - acumulado) / max(float(comprimentos[i]), 0.001)
			var pos_orbe: Vector2 = _pontos[int(caminho[i])].position.lerp(_pontos[int(caminho[i + 1])].position, t_local)
			var raio_base: float = _ponto_raio(int(caminho[i]))
			var cor_a: Color = _cor_orbe_por_ponto(int(caminho[i]))
			var cor_b: Color = _cor_orbe_por_ponto(int(caminho[i + 1]))
			var cor_slide: Color = cor_a.lerp(cor_b, t_local)
			draw_circle(pos_orbe, raio_base * 0.50, Color(cor_slide.r, cor_slide.g, cor_slide.b, 0.28))
			draw_circle(pos_orbe, raio_base * 0.28, Color(cor_slide.r, cor_slide.g, cor_slide.b, 0.92))
			draw_circle(pos_orbe, raio_base * 0.12, Color.WHITE)

		acumulado += float(comprimentos[i])

func _desenhar_segmento_arraste(indice_origem: int, indice_destino: int, pulso: float, completo: bool, ativo: bool = false) -> void:
	var origem: Node2D = _pontos[indice_origem]
	var destino: Node2D = _pontos[indice_destino]
	var p1: Vector2 = origem.position
	var p2: Vector2 = destino.position
	var direcao: Vector2 = (p2 - p1).normalized()
	var perpendicular: Vector2 = Vector2(-direcao.y, direcao.x)

	var raio_origem: float = _ponto_raio(indice_origem)
	var recuo: float = raio_origem * 0.92
	var inicio: Vector2 = p1 + direcao * recuo
	var fim: Vector2 = p2 - direcao * recuo
	var distancia: float = inicio.distance_to(fim)

	var cor_a: Color = _cor_orbe_por_ponto(indice_origem)
	var cor_b: Color = _cor_orbe_por_ponto(indice_destino)
	var cor_principal: Color = COR_SLIDE_COMPLETO if completo else cor_a.lerp(cor_b, 0.42)
	var cor_secundaria: Color = cor_b if not completo else Color(0.85, 1.0, 0.70, 1.0)
	var largura: float = max(3.0, raio_origem * (0.44 if ativo else 0.32))

	# Linha de arraste mais viva. A seta ativa recebe glow maior e leitura clara.
	var boost: float = ARRASTE_SETAS_ATIVAS_BRILHO if ativo else 1.0
	draw_line(inicio, fim, Color(cor_principal.r, cor_principal.g, cor_principal.b, (0.070 + pulso * 0.035) * boost), largura * (3.20 if ativo else 2.70), true)
	draw_line(inicio, fim, Color(0.0, 0.0, 0.0, 0.26), largura * (1.42 if ativo else 1.35), true)
	draw_line(inicio, fim, Color(1.0, 1.0, 1.0, (0.14 + pulso * 0.06) * boost), max(1.2, largura * (0.24 if ativo else 0.18)), true)

	var offset_trilho: Vector2 = perpendicular * largura * (0.70 if ativo else 0.62)
	draw_line(inicio + offset_trilho, fim + offset_trilho, Color(cor_a.r, cor_a.g, cor_a.b, (0.34 + pulso * 0.12) * boost), max(1.3, largura * 0.25), true)
	draw_line(inicio - offset_trilho, fim - offset_trilho, Color(cor_b.r, cor_b.g, cor_b.b, (0.34 + pulso * 0.12) * boost), max(1.3, largura * 0.25), true)

	# Luz móvel somente no trecho ativo, mostrando a direção correta do arraste.
	if ativo:
		for luz_i in range(3):
			var fase_luz: float = fmod(Time.get_ticks_msec() / 520.0 + float(luz_i) * 0.18, 1.0)
			var pos_luz: Vector2 = inicio.lerp(fim, fase_luz)
			var cor_luz: Color = cor_a.lerp(cor_b, fase_luz).lerp(Color.WHITE, 0.22)
			draw_circle(pos_luz, largura * (0.72 - float(luz_i) * 0.10), Color(cor_luz.r, cor_luz.g, cor_luz.b, 0.22 - float(luz_i) * 0.045))
			draw_circle(pos_luz, largura * (0.24 - float(luz_i) * 0.025), Color(1, 1, 1, 0.52 - float(luz_i) * 0.08))

	# Micro pontos no trilho com mais brilho e movimento.
	var qtd_pontos: int = int(clamp(int(distancia / max(raio_origem * 0.24, 8.0)), 5, 28))
	var anim_ponto: float = fmod(Time.get_ticks_msec() / 560.0, 1.0)
	for d in range(qtd_pontos):
		var td: float = fmod(float(d) / float(qtd_pontos) + anim_ponto, 1.0)
		if td < 0.06 or td > 0.94:
			continue
		var lateral: Vector2 = perpendicular * sin(float(d) * 1.53 + Time.get_ticks_msec() / 180.0) * largura * 0.52
		var centro_dot: Vector2 = inicio.lerp(fim, td) + lateral
		var cor_dot: Color = cor_a.lerp(cor_b, td).lerp(Color.WHITE, 0.18 + pulso * 0.12)
		draw_circle(centro_dot, max(1.2, largura * 0.19), Color(cor_dot.r, cor_dot.g, cor_dot.b, 0.42))

	# Setinhas com mais vida: >>>   >>>   >>>, um pouco mais grossas e brilhantes.
	var passo: float = max(raio_origem * 0.68, 17.0)
	var qtd: int = max(3, int(distancia / passo))
	var anim: float = fmod(Time.get_ticks_msec() / 430.0, 1.0)
	for j in range(qtd + 1):
		var t: float = (float(j) + anim) / float(qtd + 1)
		if t < 0.08 or t > 0.92:
			continue
		var centro: Vector2 = inicio.lerp(fim, t)
		var cor_chev: Color = cor_principal.lerp(cor_secundaria, 0.5 + sin(float(j) * 1.7 + Time.get_ticks_msec() / 230.0) * 0.25)
		cor_chev = cor_chev.lerp(Color.WHITE, 0.08 + pulso * 0.08)
		var alpha: float = (0.82 + pulso * 0.18) if ativo else (0.66 + pulso * 0.26)
		_desenhar_chevron_espacado(centro, direcao, perpendicular, largura * (1.16 if ativo else 1.0), cor_chev, alpha)

	var ponta_centro: Vector2 = fim - direcao * (largura * 0.12)
	_desenhar_chevron_espacado(ponta_centro, direcao, perpendicular, largura * 1.24, cor_secundaria.lerp(Color.WHITE, 0.15), 0.96)

func _desenhar_chevron_espacado(centro: Vector2, direcao: Vector2, perpendicular: Vector2, largura: float, cor: Color, alpha: float) -> void:
	var comprimento: float = largura * 1.08
	var abertura: float = largura * 0.58
	var ponta: Vector2 = centro + direcao * comprimento * 0.50
	var base: Vector2 = centro - direcao * comprimento * 0.42
	var a: Vector2 = base - perpendicular * abertura
	var b: Vector2 = base + perpendicular * abertura
	var espessura_glow: float = max(1.6, largura * 0.38)
	var espessura_sombra: float = max(1.2, largura * 0.28)
	var espessura_cor: float = max(1.2, largura * 0.18)

	# Glow por trás para a seta parecer acesa.
	draw_line(a, ponta, Color(cor.r, cor.g, cor.b, alpha * 0.22), espessura_glow, true)
	draw_line(b, ponta, Color(cor.r, cor.g, cor.b, alpha * 0.22), espessura_glow, true)
	draw_line(a, ponta, Color(0, 0, 0, 0.56), espessura_sombra, true)
	draw_line(b, ponta, Color(0, 0, 0, 0.56), espessura_sombra, true)
	draw_line(a, ponta, Color(cor.r, cor.g, cor.b, alpha), espessura_cor, true)
	draw_line(b, ponta, Color(cor.r, cor.g, cor.b, alpha), espessura_cor, true)
	draw_circle(ponta, max(1.25, largura * 0.105), Color(1, 1, 1, alpha * 0.82))


func _registrar_ponto_rastro_arraste(pos: Vector2) -> void:
	if _estado_jogo != EstadoJogo.JOGANDO:
		return

	if not _arraste_rastro.is_empty():
		var ultimo: Dictionary = _arraste_rastro[_arraste_rastro.size() - 1]
		var ultimo_pos: Vector2 = ultimo["pos"]
		if ultimo_pos.distance_to(pos) < ARRASTE_RASTRO_DIST_MIN_PX:
			return

	var cor: Color = COR_NEON_CIANO
	if _arraste_evento_atual != null:
		var caminho: Array = _arraste_evento_atual.get("caminho", [])
		if not caminho.is_empty():
			var idx_caminho: int = int(clamp(_arraste_indice_atual, 0, caminho.size() - 1))
			cor = _cor_orbe_por_ponto(int(caminho[idx_caminho]))
	else:
		var indice_perto: int = _indice_ponto_mais_proximo(pos, ARRASTE_RAIO_CHECKPOINT_EXTRA)
		if indice_perto >= 0:
			cor = _cor_orbe_por_ponto(indice_perto)

	_arraste_rastro.append({
		"pos": pos,
		"tempo": Time.get_ticks_msec() / 1000.0,
		"cor": cor
	})

	while _arraste_rastro.size() > ARRASTE_RASTRO_MAX_PONTOS:
		_arraste_rastro.remove_at(0)


func _limpar_rastro_arraste_vencido() -> void:
	if _arraste_rastro.is_empty():
		return

	var agora: float = Time.get_ticks_msec() / 1000.0
	for i in range(_arraste_rastro.size() - 1, -1, -1):
		var item: Dictionary = _arraste_rastro[i]
		if agora - float(item["tempo"]) > ARRASTE_RASTRO_DURACAO_SEG:
			_arraste_rastro.remove_at(i)


func _desenhar_rastro_arraste() -> void:
	if _arraste_rastro.is_empty():
		return

	var agora: float = Time.get_ticks_msec() / 1000.0

	for i in range(1, _arraste_rastro.size()):
		var item_a: Dictionary = _arraste_rastro[i - 1]
		var item_b: Dictionary = _arraste_rastro[i]
		var p1: Vector2 = item_a["pos"]
		var p2: Vector2 = item_b["pos"]
		var cor: Color = item_b["cor"]
		var idade: float = agora - float(item_b["tempo"])
		var vida: float = clamp(1.0 - idade / ARRASTE_RASTRO_DURACAO_SEG, 0.0, 1.0)
		if vida <= 0.0:
			continue

		var largura: float = max(2.0, _raio_circulo_px * 0.013 * vida)
		draw_line(p1, p2, Color(cor.r, cor.g, cor.b, 0.24 * vida), largura * 4.4, true)
		draw_line(p1, p2, Color(cor.r, cor.g, cor.b, 0.56 * vida), largura * 1.35, true)
		draw_line(p1, p2, Color(1, 1, 1, 0.42 * vida), max(1.0, largura * 0.34), true)

	# Cursor luminoso atual para teste com mouse e para dar retorno ao touch.
	if _arraste_gesto_ativo:
		var cor_cursor: Color = COR_NEON_CIANO
		if _arraste_evento_atual != null:
			var caminho_cursor: Array = _arraste_evento_atual.get("caminho", [])
			if not caminho_cursor.is_empty():
				var idx_caminho_cursor: int = int(clamp(_arraste_indice_atual, 0, caminho_cursor.size() - 1))
				cor_cursor = _cor_orbe_por_ponto(int(caminho_cursor[idx_caminho_cursor]))
		var pulso_cursor: float = sin(Time.get_ticks_msec() / 70.0) * 0.5 + 0.5
		draw_circle(_arraste_pos_atual, _raio_circulo_px * (0.036 + pulso_cursor * 0.006), Color(cor_cursor.r, cor_cursor.g, cor_cursor.b, 0.20))
		draw_circle(_arraste_pos_atual, _raio_circulo_px * 0.012, Color(1, 1, 1, 0.75))


func _input(event: InputEvent) -> void:
	if _modal_continuar_ativo:
		if event is InputEventScreenTouch and event.pressed:
			_continuar_partida_com_credito()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_continuar_partida_com_credito()
		return

	if _estado_jogo != EstadoJogo.JOGANDO:
		return

	# Moldura touch:
	# - tocar rápido em um Tazo continua valendo como TOQUE;
	# - segurar e arrastar pela sequência das setas ativa o ARRASTE;
	# - se o dedo começar fora do primeiro Tazo, o arraste fica "armado" e só começa
	#   quando o dedo entrar no primeiro Tazo correto do caminho.
	if event is InputEventScreenTouch:
		if event.pressed:
			_arraste_gesto_ativo = true
			_arraste_ultimo_pos = event.position
			_arraste_pos_atual = event.position
			_registrar_ponto_rastro_arraste(event.position)
			_processar_toque_na_tela(event.position)
			_iniciar_arraste(event.position)
		else:
			_finalizar_arraste()

	elif event is InputEventScreenDrag:
		_atualizar_arraste(event.position)

	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_arraste_gesto_ativo = true
			_arraste_ultimo_pos = event.position
			_arraste_pos_atual = event.position
			_registrar_ponto_rastro_arraste(event.position)
			_processar_toque_na_tela(event.position)
			_iniciar_arraste(event.position)
		else:
			_finalizar_arraste()

	elif event is InputEventMouseMotion and _arraste_gesto_ativo:
		_atualizar_arraste(event.position)

func _processar_toque_na_tela(pos: Vector2) -> void:
	var indice_ponto: int = _indice_ponto_mais_proximo(pos)
	if indice_ponto == -1:
		return

	var tempo_musica: float = _tempo_atual_musica()
	_tentar_resolver_toque(indice_ponto, tempo_musica)

# ---------------------------------------------------------------
# MONTAGEM DA CENA
# ---------------------------------------------------------------
func _preparar_base_circular() -> void:
	var tam_tela: Vector2 = get_viewport_rect().size
	_centro_tela = tam_tela / 2.0

	# Círculo gigante em modo retrato:
	# usa quase toda a largura disponível, pois em tela retrato a largura é o limitador.
	# Exemplo: 1080 px de largura -> diâmetro aproximado de 1064 px.
	var menor_lado: float = min(tam_tela.x, tam_tela.y)
	_raio_circulo_px = (menor_lado * PORCENTAGEM_TELA_CIRCULO) / 2.0

	# Proteção para não passar totalmente da tela em resoluções diferentes.
	# Mantém uma margem visual pequena de segurança.
	var margem_px: float = 4.0
	_raio_circulo_px = min(_raio_circulo_px, (menor_lado / 2.0) - margem_px)

	# Fundo preto total por baixo de tudo -- evita flash branco antes de montar.
	var fundo_preto := ColorRect.new()
	fundo_preto.color = Color.BLACK
	fundo_preto.size = tam_tela
	fundo_preto.position = Vector2.ZERO
	fundo_preto.z_index = -10
	add_child(fundo_preto)

	_criar_mascara_circular(tam_tela)


func _criar_video_generico(caminho: String, loop: bool) -> void:
	# Remove qualquer vídeo anterior antes de criar outro.
	if _video_fundo and is_instance_valid(_video_fundo):
		_video_fundo.stop()
		_video_fundo.queue_free()
		_video_fundo = null

	var stream: VideoStream = _carregar_video_com_fallback(caminho)

	if stream == null:
		_mostrar_debug_video("VÍDEO NÃO ENCONTRADO:\n" + caminho + "\nTambém tentei:\n" + CAMINHO_VIDEO_FALLBACK_1)
		return

	_limpar_debug_video()

	_video_fundo = VideoStreamPlayer.new()
	_video_fundo.name = "VideoFundoCircular"
	_video_fundo.stream = stream
	_video_fundo.autoplay = false
	_video_fundo.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Importante: o som do vídeo fica mudo.
	# O áudio oficial do jogo vem do AudioStreamPlayer usando song1.
	_video_fundo.volume_db = -80.0

	# O vídeo precisa ficar atrás dos pontos, HUD e desenhos do jogo.
	# O fundo preto fica ainda mais atrás.
	_video_fundo.z_index = -5

	# Deixa o vídeo sempre quadrado, centralizado e encaixado exatamente no círculo.
	# Se o vídeo original é quadrado, ele entra perfeito.
	# Se não for quadrado, o Control ainda fica quadrado e a máscara circular esconde as quinas.
	var diametro: float = _raio_circulo_px * 2.0
	_video_fundo.size = Vector2(diametro, diametro)
	_video_fundo.position = _centro_tela - (_video_fundo.size / 2.0)
	_video_fundo.pivot_offset = _video_fundo.size / 2.0
	_video_fundo.modulate = Color(1, 1, 1, VIDEO_FUNDO_ALPHA)

	# Não uso shader no VideoStreamPlayer aqui.
	# Em alguns projetos o material no vídeo pode impedir a exibição dependendo da versão/importação.
	add_child(_video_fundo)
	_video_fundo.show()
	_video_fundo.play()

	print("HIT MUSIC - vídeo iniciado: ", caminho, " | tamanho: ", _video_fundo.size, " | posição: ", _video_fundo.position)

	if loop:
		_video_fundo.finished.connect(func():
			if _video_fundo and is_instance_valid(_video_fundo):
				_video_fundo.play()
		)


func _carregar_video_com_fallback(caminho_principal: String) -> VideoStream:
	var caminhos: Array[String] = []

	caminhos.append(caminho_principal)

	if caminho_principal != CAMINHO_VIDEO_FALLBACK_1:
		caminhos.append(CAMINHO_VIDEO_FALLBACK_1)

	var alternativo_1: String = caminho_principal.replace("mmedias", "medias")
	var alternativo_2: String = caminho_principal.replace("medias", "mmedias")

	if alternativo_1 not in caminhos:
		caminhos.append(alternativo_1)

	if alternativo_2 not in caminhos:
		caminhos.append(alternativo_2)

	for caminho in caminhos:
		if ResourceLoader.exists(caminho):
			var stream: VideoStream = load(caminho)
			if stream != null:
				print("HIT MUSIC - carregou vídeo em: ", caminho)
				return stream

	for caminho in caminhos:
		push_warning("HIT MUSIC - vídeo não existe neste caminho: " + caminho)

	return null


func _mostrar_debug_video(texto: String) -> void:
	if _label_debug_video and is_instance_valid(_label_debug_video):
		_label_debug_video.queue_free()

	var config := LabelSettings.new()
	config.font_size = int(_raio_circulo_px * 0.055)
	config.font_color = Color(1, 0.25, 0.25, 1)
	config.outline_size = 4
	config.outline_color = Color.BLACK

	_label_debug_video = Label.new()
	_label_debug_video.label_settings = config
	_label_debug_video.text = texto
	_label_debug_video.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label_debug_video.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label_debug_video.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label_debug_video.size = Vector2(_raio_circulo_px * 1.6, _raio_circulo_px * 0.55)
	_label_debug_video.position = _centro_tela - _label_debug_video.size / 2.0
	_label_debug_video.z_index = 50
	add_child(_label_debug_video)


func _limpar_debug_video() -> void:
	if _label_debug_video and is_instance_valid(_label_debug_video):
		_label_debug_video.queue_free()
		_label_debug_video = null


# ---------------------------------------------------------------
# 1) APRESENTAÇÃO -- samurai.jpeg + nome da fase
# ---------------------------------------------------------------
func _iniciar_apresentacao_fase() -> void:
	_estado_jogo = EstadoJogo.APRESENTACAO

	var textura: Texture2D = load(CAMINHO_IMAGEM_FASE)
	if textura == null:
		push_warning("Imagem de apresentação não encontrada em: " + CAMINHO_IMAGEM_FASE)
	else:
		_sprite_apresentacao = Sprite2D.new()
		_sprite_apresentacao.texture = textura
		_sprite_apresentacao.position = _centro_tela
		_sprite_apresentacao.z_index = 0

		var diametro: float = _raio_circulo_px * 2.0 * 1.05
		var lado_menor_textura: float = min(textura.get_width(), textura.get_height())
		var escala: float = diametro / lado_menor_textura
		_sprite_apresentacao.scale = Vector2(escala, escala)
		add_child(_sprite_apresentacao)

	var config_nome := LabelSettings.new()
	config_nome.font_size = int(_raio_circulo_px * 0.16)
	config_nome.font_color = Color.WHITE
	config_nome.outline_size = 6
	config_nome.outline_color = Color(0.02, 0.0, 0.05, 0.95)
	config_nome.shadow_size = 20
	config_nome.shadow_color = Color(COR_NEON_ROSA.r, COR_NEON_ROSA.g, COR_NEON_ROSA.b, 0.6)

	_label_nome_fase = Label.new()
	_label_nome_fase.label_settings = config_nome
	_label_nome_fase.text = NOME_FASE
	_label_nome_fase.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label_nome_fase.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label_nome_fase.size = Vector2(_raio_circulo_px * 1.5, _raio_circulo_px * 0.4)
	_label_nome_fase.position = _centro_tela - _label_nome_fase.size / 2.0
	_label_nome_fase.z_index = 5
	add_child(_label_nome_fase)

	get_tree().create_timer(DURACAO_APRESENTACAO_SEG).timeout.connect(_iniciar_contagem)


# ---------------------------------------------------------------
# 2) CONTAGEM -- media_china1.ogv (5s) + número grande
# ---------------------------------------------------------------
func _iniciar_contagem() -> void:
	if _sprite_apresentacao:
		_sprite_apresentacao.queue_free()
		_sprite_apresentacao = null
	if _label_nome_fase:
		_label_nome_fase.queue_free()
		_label_nome_fase = null

	_estado_jogo = EstadoJogo.CONTAGEM
	_contagem_restante = DURACAO_CONTAGEM_SEG
	_contagem_ultimo_numero_led = -1
	_led_assinatura_atual = ""
	_arduino_enviar_unico("BLINKALL")

	_criar_video_generico(CAMINHO_VIDEO_CONTAGEM, false)

	var config_contagem := LabelSettings.new()
	config_contagem.font_size = int(_raio_circulo_px * 0.5)
	config_contagem.font_color = Color.WHITE
	config_contagem.outline_size = 8
	config_contagem.outline_color = Color(0.02, 0.0, 0.05, 0.95)
	config_contagem.shadow_size = 24
	config_contagem.shadow_color = Color(COR_NEON_CIANO.r, COR_NEON_CIANO.g, COR_NEON_CIANO.b, 0.7)

	_label_contagem = Label.new()
	_label_contagem.label_settings = config_contagem
	_label_contagem.text = str(int(ceil(DURACAO_CONTAGEM_SEG)))
	_label_contagem.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label_contagem.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label_contagem.size = Vector2(_raio_circulo_px * 0.8, _raio_circulo_px * 0.8)
	_label_contagem.position = _centro_tela - _label_contagem.size / 2.0
	_label_contagem.pivot_offset = _label_contagem.size / 2.0
	_label_contagem.z_index = 5
	add_child(_label_contagem)


func _atualizar_contagem(delta: float) -> void:
	_contagem_restante = max(_contagem_restante - delta, 0.0)
	var numero: int = int(ceil(_contagem_restante))

	if numero != _contagem_ultimo_numero_led:
		_contagem_ultimo_numero_led = numero
		_arduino_enviar_unico("COUNT " + str(numero))

	if _label_contagem:
		_label_contagem.text = "VAI!" if numero <= 0 else str(numero)
		# Pulso leve a cada fração de segundo -- só pra não ficar um número estático parado.
		var fracao: float = _contagem_restante - floor(_contagem_restante)
		_label_contagem.scale = Vector2.ONE * (1.0 + fracao * 0.15)

	if _contagem_restante <= 0.0:
		_iniciar_jogo_real()


# ---------------------------------------------------------------
# 3) JOGANDO -- media_china2.ogv em loop + pontos + HUD + música
# ---------------------------------------------------------------
func _iniciar_jogo_real() -> void:
	if _video_fundo:
		_video_fundo.queue_free()
		_video_fundo = null
	if _label_contagem:
		_label_contagem.queue_free()
		_label_contagem = null

	_estado_jogo = EstadoJogo.JOGANDO
	_led_assinatura_atual = ""

	# PARTIDA = hardware começa totalmente apagado.
	# CLEAR remove MENU/SCENE/guia deixados pela tela anterior e também zera
	# efeito_apos_ready no firmware. Assim READY não volta para o MENU antigo.
	_arduino_enviar_forcado("CLEAR")
	_arduino_enviar_forcado("READY")

	_criar_video_generico(CAMINHO_VIDEO_FUNDO, true)
	_criar_pontos()
	_criar_hud()
	_tocar_musica()



func _processar_frame_jogo(delta: float) -> void:
	if _partida_encerrada:
		return

	_tempo_restante = max(_tempo_restante - delta, 0.0)
	_atualizar_label_tempo()
	if _tempo_restante <= 0.0:
		_encerrar_partida()
		return

	var tempo_musica: float = _tempo_atual_musica()
	_ativar_eventos_pendentes(tempo_musica)
	_atualizar_eventos_ativos(tempo_musica)
	_atualizar_leds_guia(tempo_musica)
	_processar_inputs_toque(tempo_musica)

func _tipo_evento_acende_led(tipo_original: String) -> bool:
	var tipo := tipo_original.strip_edges().to_lower()

	# Gestos de arrasto são exclusivamente visuais/touch.
	if tipo in ["arraste", "drag", "slide", "swipe"]:
		return false

	# Somente jogadas ligadas a um input físico acendem a mesa.
	return tipo in [
		"toque", "click", "tap",
		"hold", "segurar", "press", "pressionar"
	]


func _indice_input_para_led(valor) -> int:
	# Aceita índice 0..7 ou nome input_a..input_h / A..H.
	if valor is int or valor is float:
		var idx := int(valor)
		return idx if idx >= 0 and idx < NUM_PONTOS else -1

	var texto := str(valor).strip_edges().to_lower()

	if texto.begins_with("input_"):
		texto = texto.substr(6)

	if texto.length() == 1:
		var letras := "abcdefgh"
		var idx := letras.find(texto)
		if idx >= 0 and idx < NUM_PONTOS:
			return idx

	return -1


func _indices_led_do_evento(evento: Dictionary) -> Array[int]:
	var resultado: Array[int] = []

	# Formato atual do jogo: "ponto": 0..7
	if evento.has("ponto"):
		var idx := _indice_input_para_led(evento["ponto"])
		if idx >= 0:
			resultado.append(idx)

	# Compatibilidade para hold/click futuros com mais de um alvo.
	if evento.has("pontos"):
		var pontos = evento["pontos"]
		if pontos is Array:
			for valor in pontos:
				var idx := _indice_input_para_led(valor)
				if idx >= 0 and not resultado.has(idx):
					resultado.append(idx)

	# Também aceita descrição explícita pelo input.
	if evento.has("input"):
		var idx := _indice_input_para_led(evento["input"])
		if idx >= 0 and not resultado.has(idx):
			resultado.append(idx)

	if evento.has("inputs"):
		var inputs = evento["inputs"]
		if inputs is Array:
			for valor in inputs:
				var idx := _indice_input_para_led(valor)
				if idx >= 0 and not resultado.has(idx):
					resultado.append(idx)

	return resultado


func _atualizar_leds_guia(_tempo_musica: float) -> void:
	# ================================================================
	# HARDWARE R17 — mesma filosofia do sistema antigo de 7 posições:
	#
	# 1) monta primeiro o ESTADO COMPLETO dos alvos;
	# 2) começa sempre com A..H apagados;
	# 3) só eventos CLICK/TOQUE/TAP/HOLD ativos entram no conjunto;
	# 4) ARRASTE/DRAG/SLIDE nunca acende LED físico;
	# 5) envia as 8 posições juntas em um único MULTI.
	#
	# Mapeamento:
	# input_a -> índice 0 -> D2
	# input_b -> índice 1 -> D3
	# input_c -> índice 2 -> D4
	# input_d -> índice 3 -> D5
	# input_e -> índice 4 -> D6
	# input_f -> índice 5 -> D7
	# input_g -> índice 6 -> D8
	# input_h -> índice 7 -> D9
	# ================================================================

	var cores: Array = []
	for _i in range(NUM_PONTOS):
		cores.append(Color.BLACK)

	# IMPORTANTE:
	# usa apenas os eventos que o jogo considera ATIVOS neste momento.
	# É o equivalente ao "leds_ativos" do seu sistema antigo.
	for evento_variant in _eventos_ativos:
		if not (evento_variant is Dictionary):
			continue

		var evento: Dictionary = evento_variant

		if bool(evento.get("resolvido", false)):
			continue

		var tipo := str(evento.get("tipo", ""))
		if not _tipo_evento_acende_led(tipo):
			continue

		var indices := _indices_led_do_evento(evento)

		for idx in indices:
			if idx < 0 or idx >= NUM_PONTOS:
				continue

			# A cor é a mesma cor associada ao tazo/input.
			# A fita inteira daquele tazo recebe essa cor pelo firmware.
			cores[idx] = _cor_orbe_por_ponto(idx)

	# Um único quadro contém o estado das oito posições.
	# Tudo que não foi selecionado permanece 000000 (apagado).
	_arduino_enviar_unico(_cmd_multi_cores(cores))


func _cor_para_hex(cor: Color, escala: float = 1.0) -> String:
	var r: int = clampi(roundi(cor.r * 255.0 * escala), 0, 255)
	var g: int = clampi(roundi(cor.g * 255.0 * escala), 0, 255)
	var b: int = clampi(roundi(cor.b * 255.0 * escala), 0, 255)
	return "%02X%02X%02X" % [r, g, b]


func _cmd_multi_cores(cores: Array) -> String:
	var hex: String = ""
	for i in range(NUM_PONTOS):
		var cor := Color.BLACK
		if i < cores.size() and cores[i] is Color:
			cor = cores[i]
		hex += _cor_para_hex(cor)
	return "MULTI " + hex


func _cmd_led_path(caminho: Array) -> String:
	# Mostra o caminho completo. Firmware R13/R14 entende MULTI.
	var cores: Array = []
	for _i in range(NUM_PONTOS):
		cores.append(Color.BLACK)

	for indice in caminho:
		var idx: int = int(indice)
		if idx >= 0 and idx < NUM_PONTOS:
			cores[idx] = _cor_orbe_por_ponto(idx) * 0.72

	# Primeiro ponto fica mais forte para indicar onde iniciar o gesto.
	if not caminho.is_empty():
		var primeiro: int = int(caminho[0])
		if primeiro >= 0 and primeiro < NUM_PONTOS:
			cores[primeiro] = COR_SLIDE_AMARELO

	return _cmd_multi_cores(cores)


func _cmd_led_progresso(caminho: Array, passo_atual: int) -> String:
	# Verde = já percorrido; amarelo = checkpoint atual; cor suave = próximos.
	var cores: Array = []
	for _i in range(NUM_PONTOS):
		cores.append(Color.BLACK)

	for j in range(caminho.size()):
		var idx: int = int(caminho[j])
		if idx < 0 or idx >= NUM_PONTOS:
			continue

		if j < passo_atual:
			cores[idx] = COR_SLIDE_COMPLETO
		elif j == passo_atual:
			cores[idx] = COR_SLIDE_AMARELO
		else:
			cores[idx] = _cor_orbe_por_ponto(idx) * 0.45

	return _cmd_multi_cores(cores)


func _cmd_led_slide_ok(caminho: Array) -> String:
	# Acendimento verde do caminho concluído. O feedback seguinte do jogo
	# volta a desenhar as guias normalmente.
	var cores: Array = []
	for _i in range(NUM_PONTOS):
		cores.append(Color.BLACK)

	for indice in caminho:
		var idx: int = int(indice)
		if idx >= 0 and idx < NUM_PONTOS:
			cores[idx] = COR_SLIDE_COMPLETO

	return _cmd_multi_cores(cores)


func _arduino_enviar_unico(linha: String) -> void:
	# Evita gravar a mesma coisa todo frame.
	if linha == _led_assinatura_atual:
		return
	_led_assinatura_atual = linha
	_arduino_enviar_linha(linha)




func _arduino_enviar_forcado(linha: String) -> void:
	# Envia mesmo que seja igual ao último comando. Usado nos inputs físicos para D2..D9 responderem sempre.
	_led_assinatura_atual = ""
	_arduino_enviar_linha(linha)

func _obter_led_client() -> Node:
	# Aceita os nomes mais comuns de Autoload, para não depender de maiúsculas.
	for caminho in [
		"/root/LedClient",
		"/root/led_client",
		"/root/LEDClient",
		"/root/HitMusicSerial",
	]:
		var node := get_node_or_null(caminho)
		if node != null:
			return node
	return null


func _arduino_inicializar() -> void:
	var cliente := _obter_led_client()
	if cliente == null:
		push_error("HIT MUSIC: Autoload led_client.gd não encontrado. Adicione-o em Project Settings > Globals/Autoload.")
		return

	if cliente.has_method("ensure_bridge"):
		cliente.call("ensure_bridge")


func _arduino_tick_serial() -> void:
	# A bridge é persistente e o Autoload cuida da saúde dela.
	# Não existe mais COM5 aberta por esta cena.
	var cliente := _obter_led_client()
	if cliente != null and cliente.has_method("tick"):
		cliente.call("tick")


func _arduino_enviar_linha(linha: String) -> void:
	var comando := linha.strip_edges()
	if comando.is_empty():
		return

	var cliente := _obter_led_client()
	if cliente == null:
		push_error("HIT MUSIC: led_client.gd não está carregado; comando perdido: " + comando)
		return

	if cliente.has_method("send"):
		cliente.call("send", comando)
	elif cliente.has_method("enviar"):
		cliente.call("enviar", comando)
	else:
		push_error("HIT MUSIC: led_client.gd não possui send()/enviar().")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		# Fecha hardware de forma limpa antes do processo do Godot terminar:
		# LedClient -> bridge_stop -> CLEAR -> fecha COM5.
		var cliente := _obter_led_client()
		if cliente != null and cliente.has_method("shutdown"):
			cliente.call("shutdown")


func _criar_shader_pulso_neon() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;

uniform float velocidade_pulso : hint_range(0.1, 5.0) = 1.3;
uniform float intensidade_pulso : hint_range(0.0, 1.0) = 0.4;
uniform float limiar_brilho : hint_range(0.0, 1.0) = 0.55;

void fragment() {
	vec4 cor = texture(TEXTURE, UV);

	float brilho = dot(cor.rgb, vec3(0.299, 0.587, 0.114));
	float mascara_neon = smoothstep(limiar_brilho - 0.15, limiar_brilho + 0.25, brilho);

	float pulso = sin(TIME * velocidade_pulso * 6.283185) * 0.5 + 0.5;
	vec3 cor_realcada = cor.rgb + (cor.rgb * pulso * intensidade_pulso * mascara_neon);

	COLOR = vec4(cor_realcada, cor.a);
}
"""
	return sh


func _criar_mascara_circular(tam_tela: Vector2) -> void:
	_mascara_layer = CanvasLayer.new()
	_mascara_layer.layer = 10
	add_child(_mascara_layer)

	_mascara_rect = ColorRect.new()
	_mascara_rect.color = Color.BLACK
	_mascara_rect.size = tam_tela
	_mascara_rect.position = Vector2.ZERO
	_mascara_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_mascara_mat = ShaderMaterial.new()
	_mascara_mat.shader = _criar_shader_mascara()
	_mascara_mat.set_shader_parameter("centro_px", _centro_tela)
	_mascara_mat.set_shader_parameter("raio_px", _raio_circulo_px)
	_mascara_mat.set_shader_parameter("suavizacao_px", SUAVIZACAO_MASCARA_PX)
	_mascara_mat.set_shader_parameter("tamanho_rect", tam_tela)
	_mascara_rect.material = _mascara_mat

	_mascara_layer.add_child(_mascara_rect)


func _criar_shader_mascara() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;

uniform vec2 centro_px;
uniform float raio_px;
uniform float suavizacao_px;
uniform vec2 tamanho_rect;

void fragment() {
	vec2 pos_px = UV * tamanho_rect;
	float dist = distance(pos_px, centro_px);

	float alpha_fora = smoothstep(raio_px - suavizacao_px, raio_px + suavizacao_px, dist);

	float largura_anel = suavizacao_px * 5.0;
	float anel = 1.0 - smoothstep(0.0, largura_anel, abs(dist - raio_px));
	float pulso_cor = sin(TIME * 1.6) * 0.5 + 0.5;
	vec3 cor_anel = mix(vec3(1.0, 0.1, 0.85), vec3(0.25, 0.85, 1.0), pulso_cor);

	vec3 cor_final = cor_anel * anel * 0.9;
	float alpha_final = max(alpha_fora, anel * 0.85);

	COLOR = vec4(cor_final, alpha_final);
}
"""
	return sh


func _criar_pontos() -> void:
	# Limpa pontos antigos caso a cena reinicie sem descarregar tudo.
	for p in _pontos:
		if p != null and is_instance_valid(p):
			p.queue_free()
	_pontos.clear()
	_ponto_raios.clear()
	_ponto_sprites.clear()
	_ponto_estados.clear()
	_ponto_posicoes_fixas.clear()

	var textura_tazo_fixa: Texture2D = null
	if TAZO_USAR_SHEET_FIXO and ResourceLoader.exists(CAMINHO_TAZO_SHEET_FIXO):
		textura_tazo_fixa = load(CAMINHO_TAZO_SHEET_FIXO)

	var cena_tazo: PackedScene = null
	if textura_tazo_fixa == null:
		if ResourceLoader.exists(CAMINHO_TAZO_SCENE):
			cena_tazo = load(CAMINHO_TAZO_SCENE)
		else:
			push_warning("Não encontrei " + CAMINHO_TAZO_SCENE + " nem " + CAMINHO_TAZO_SHEET_FIXO + " — usando bolinha fallback.")

	var raio_posicionamento: float = _raio_circulo_px * RAIO_POS_PONTOS_RATIO
	var raio_visual_ponto: float = (_raio_circulo_px * TAZO_DIAMETRO_RATIO) * 0.5
	_raio_toque_ponto_px = raio_visual_ponto * RAIO_TOQUE_EXTRA_RATIO

	for i in range(NUM_PONTOS):
		var angulo: float = -PI / 2.0 + i * (TAU / NUM_PONTOS)
		var pos: Vector2 = _centro_tela + Vector2(cos(angulo), sin(angulo)) * raio_posicionamento

		var ponto: Node2D = null
		var sprite_node: Node2D = null

		# Melhor opção: Tazo já recortado em sprite sheet fixo, sem deslocamento entre frames.
		if textura_tazo_fixa != null:
			ponto = Node2D.new()
			var spr := Sprite2D.new()
			spr.name = "SpriteTazoFixo"
			spr.texture = textura_tazo_fixa
			spr.centered = true
			spr.position = Vector2.ZERO
			spr.rotation = 0.0
			spr.region_enabled = true
			spr.region_rect = _tazo_region_rect(TAZO_IDLE_FRAME_INDEX)
			ponto.add_child(spr)
			sprite_node = spr

		# Fallback: usa sua entities/tazo.tscn, mas ainda tenta travar no centro.
		if ponto == null and cena_tazo != null:
			var inst: Node = cena_tazo.instantiate()
			if inst is Node2D:
				ponto = inst
				sprite_node = _tazo_obter_sprite(ponto)
			else:
				push_warning("A raiz do tazo.tscn precisa ser Node2D/Area2D. Usando fallback no ponto " + str(i))
				inst.queue_free()

		if ponto == null:
			ponto = PontoRitmo.new()

		ponto.name = "Tazo_%s" % LETRAS_PONTOS[i]
		ponto.position = pos
		ponto.rotation = 0.0
		ponto.z_index = 18

		if ponto is PontoRitmo:
			var ponto_fallback: PontoRitmo = ponto
			ponto_fallback.indice = i
			ponto_fallback.letra = LETRAS_PONTOS[i]
			ponto_fallback.raio_ponto = raio_visual_ponto

		ponto.set_meta("indice", i)
		ponto.set_meta("letra", LETRAS_PONTOS[i])
		add_child(ponto)

		_pontos.append(ponto)
		_ponto_raios.append(raio_visual_ponto)
		_ponto_estados.append("idle")
		_ponto_posicoes_fixas.append(pos)

		if sprite_node == null:
			sprite_node = _tazo_obter_sprite(ponto)
		_ponto_sprites.append(sprite_node)
		_tazo_ajustar_tamanho(ponto, raio_visual_ponto)
		_ponto_set_estado(i, "idle")

func _manter_tazos_fixos() -> void:
	# Trava cada Tazo exatamente na posição calculada em _criar_pontos().
	# Isso impede que troca de estado, animação, shader ou flash arraste o sprite para fora do lugar.
	if _pontos.is_empty() or _ponto_posicoes_fixas.is_empty():
		return

	var limite: int = min(_pontos.size(), _ponto_posicoes_fixas.size())
	for i in range(limite):
		var ponto: Node2D = _pontos[i]
		if ponto == null or not is_instance_valid(ponto):
			continue

		ponto.position = _ponto_posicoes_fixas[i]
		ponto.rotation = 0.0

		if i < _ponto_sprites.size():
			var sprite_node: Node2D = _ponto_sprites[i]
			if sprite_node != null and is_instance_valid(sprite_node):
				sprite_node.position = Vector2.ZERO
				sprite_node.rotation = 0.0

				if sprite_node is Sprite2D:
					var spr: Sprite2D = sprite_node
					spr.centered = true
					spr.offset = Vector2.ZERO
				elif sprite_node is AnimatedSprite2D:
					var anim: AnimatedSprite2D = sprite_node
					anim.centered = true
					anim.offset = Vector2.ZERO


func _ponto_raio(indice: int) -> float:
	if indice >= 0 and indice < _ponto_raios.size():
		return float(_ponto_raios[indice])
	return _raio_circulo_px * RAIO_VISUAL_PONTO_RATIO


func _ponto_set_estado(indice: int, estado: String, flash_tempo: float = 0.0, flash_cor: Color = Color.WHITE) -> void:
	if indice < 0 or indice >= _pontos.size():
		return

	var estado_anterior: String = ""
	if indice < _ponto_estados.size():
		estado_anterior = str(_ponto_estados[indice])

	var mudou_estado: bool = estado_anterior != estado
	if indice < _ponto_estados.size():
		_ponto_estados[indice] = estado

	var ponto: Node2D = _pontos[indice]
	var aceso: bool = estado != "idle"

	if ponto is PontoRitmo:
		var ponto_fallback: PontoRitmo = ponto
		ponto_fallback.estado = estado
		ponto_fallback.flash_tempo = flash_tempo
		ponto_fallback.flash_cor = flash_cor

	# Importante: não reinicia a animação todo frame. Isso era uma das causas do Tazo parecer tremendo.
	if mudou_estado:
		_tazo_tocar_animacao(indice, aceso)

	var cor_ativa: Color = flash_cor if flash_tempo > 0.0 else _cor_orbe_por_ponto(indice)
	_tazo_shader_set(indice, aceso or flash_tempo > 0.0, cor_ativa, TAZO_BRILHO_ATIVO if aceso else 1.15)

	if flash_tempo > 0.0:
		_tazo_flash(indice, flash_cor, flash_tempo)
	else:
		ponto.modulate = Color(1, 1, 1, 1)


func _tazo_obter_sprite(node: Node) -> Node2D:
	if node is Sprite2D:
		return node
	if node is AnimatedSprite2D:
		return node
	for child in node.get_children():
		var achou: Node2D = _tazo_obter_sprite(child)
		if achou != null:
			return achou
	return null

func _tazo_tocar_animacao(indice: int, aceso: bool) -> void:
	if indice < 0 or indice >= _ponto_sprites.size():
		return

	var sprite_node: Node2D = _ponto_sprites[indice]
	if sprite_node == null:
		return

	# Sprite sheet fixo: não anima, não desloca. Só troca o recorte da textura.
	if sprite_node is Sprite2D:
		var spr: Sprite2D = sprite_node
		spr.centered = true
		spr.position = Vector2.ZERO
		spr.offset = Vector2.ZERO
		spr.rotation = 0.0
		spr.region_enabled = true
		spr.region_rect = _tazo_region_rect(TAZO_ACESO_FRAME_INDEX if aceso else TAZO_IDLE_FRAME_INDEX)
		return

	# Fallback para AnimatedSprite2D da sua tazo.tscn.
	if sprite_node is AnimatedSprite2D:
		var sprite: AnimatedSprite2D = sprite_node
		if sprite.sprite_frames == null:
			return
		var anim: String = _tazo_animacao_existente(sprite, TAZO_ANIM_ACESO if aceso else TAZO_ANIM_IDLE, aceso)
		if anim == "":
			return

		sprite.centered = true
		sprite.position = Vector2.ZERO
		sprite.offset = Vector2.ZERO
		sprite.rotation = 0.0
		sprite.animation = anim

		var frames: int = sprite.sprite_frames.get_frame_count(anim)
		if aceso and TAZO_ACESO_USAR_FRAME_FINAL:
			sprite.frame = max(frames - 1, 0)
			sprite.pause()
		elif not aceso and not TAZO_IDLE_ANIMAR:
			sprite.frame = 0
			sprite.pause()
		else:
			sprite.play(anim)


func _tazo_region_rect(frame_index: int) -> Rect2:
	var idx: int = max(frame_index, 0)
	return Rect2(Vector2(float(idx * TAZO_SHEET_FRAME_SIZE.x), 0.0), Vector2(float(TAZO_SHEET_FRAME_SIZE.x), float(TAZO_SHEET_FRAME_SIZE.y)))

func _tazo_animacao_existente(sprite: AnimatedSprite2D, preferida: String, aceso: bool) -> String:
	if sprite == null or sprite.sprite_frames == null:
		return ""
	var tentativas: Array[String] = []
	tentativas.append(preferida)
	if aceso:
		tentativas.append("hig")
		tentativas.append("high")
		tentativas.append("hit")
		tentativas.append("aceso")
	else:
		tentativas.append("idle")
		tentativas.append("parado")

	for nome in tentativas:
		if sprite.sprite_frames.has_animation(nome):
			return nome

	var nomes: PackedStringArray = sprite.sprite_frames.get_animation_names()
	return nomes[0] if nomes.size() > 0 else ""


func _tazo_flash(indice: int, cor: Color, tempo: float) -> void:
	if indice < 0 or indice >= _pontos.size():
		return

	var ponto: Node2D = _pontos[indice]
	ponto.position = ponto.position # mantém a raiz fixa; o flash mexe só em brilho/modulate.
	ponto.modulate = Color(1, 1, 1, 1).lerp(cor, 0.42)
	_tazo_shader_set(indice, true, cor, 2.05)
	var tw: Tween = create_tween()
	tw.tween_property(ponto, "modulate", Color(1, 1, 1, 1), tempo).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.finished.connect(func():
		var ativo: bool = false
		if indice >= 0 and indice < _ponto_estados.size():
			ativo = str(_ponto_estados[indice]) != "idle"
		_tazo_shader_set(indice, ativo, _cor_orbe_por_ponto(indice), TAZO_BRILHO_ATIVO if ativo else 0.0)
	)


func _tazo_maior_lado_de_todos_frames(sprite: AnimatedSprite2D) -> float:
	var maior: float = 0.0
	if sprite == null or sprite.sprite_frames == null:
		return maior
	for anim in sprite.sprite_frames.get_animation_names():
		var qtd: int = sprite.sprite_frames.get_frame_count(anim)
		for f in range(qtd):
			var tex: Texture2D = sprite.sprite_frames.get_frame_texture(anim, f)
			if tex != null:
				maior = max(maior, max(float(tex.get_width()), float(tex.get_height())))
	return maior

func _tazo_ajustar_tamanho(ponto: Node2D, raio_visual: float) -> void:
	var sprite_node: Node2D = _tazo_obter_sprite(ponto)
	if sprite_node == null:
		return

	# Trava o sprite no centro do ponto. O Tazo não deve andar quando troca idle/hig.
	sprite_node.position = Vector2.ZERO
	sprite_node.rotation = 0.0

	var maior_lado: float = 0.0
	if sprite_node is Sprite2D:
		var spr: Sprite2D = sprite_node
		spr.centered = true
		spr.offset = Vector2.ZERO
		spr.region_enabled = true
		maior_lado = float(max(TAZO_SHEET_FRAME_SIZE.x, TAZO_SHEET_FRAME_SIZE.y))
	elif sprite_node is AnimatedSprite2D:
		var animspr: AnimatedSprite2D = sprite_node
		animspr.centered = true
		animspr.offset = Vector2.ZERO
		maior_lado = _tazo_maior_lado_de_todos_frames(animspr)

	if maior_lado <= 0.0:
		return

	var diametro_desejado: float = raio_visual * 2.0
	var escala: float = diametro_desejado / maior_lado
	ponto.scale = Vector2.ONE * escala

	# Shader próprio para brilho. A posição não muda; só muda luminosidade/cor.
	if _shader_tazo_cache == null:
		_shader_tazo_cache = _criar_shader_tazo_brilho()
	var mat := ShaderMaterial.new()
	mat.shader = _shader_tazo_cache
	mat.set_shader_parameter("ativo", 0.0)
	mat.set_shader_parameter("cor_brilho", Color(1, 1, 1, 1))
	mat.set_shader_parameter("forca", 0.0)
	sprite_node.material = mat


func _tazo_shader_set(indice: int, ativo: bool, cor: Color, forca: float) -> void:
	if indice < 0 or indice >= _ponto_sprites.size():
		return
	var sprite_node: Node2D = _ponto_sprites[indice]
	if sprite_node == null or not (sprite_node.material is ShaderMaterial):
		return
	var mat: ShaderMaterial = sprite_node.material
	mat.set_shader_parameter("ativo", 1.0 if ativo else 0.0)
	mat.set_shader_parameter("cor_brilho", cor)
	mat.set_shader_parameter("forca", forca if ativo else 0.0)

func _criar_shader_tazo_brilho() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;

uniform float ativo = 0.0;
uniform vec4 cor_brilho : source_color = vec4(1.0, 0.2, 0.9, 1.0);
uniform float forca : hint_range(0.0, 3.0) = 1.15;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float brilho_base = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	float borda_luz = smoothstep(0.18, 0.95, brilho_base);
	float pulso = sin(TIME * 8.0) * 0.5 + 0.5;
	vec3 brilho = cor_brilho.rgb * (0.12 + pulso * 0.26) * borda_luz * forca * ativo;
	vec3 cor_final = tex.rgb + brilho;
	COLOR = vec4(cor_final, tex.a);
}
"""
	return sh


func _criar_hud() -> void:
	var camada := CanvasLayer.new()
	camada.layer = 5
	add_child(camada)

	var largura_painel: float = _raio_circulo_px * 0.56
	var altura_painel: float = _raio_circulo_px * 0.20

	var painel := Panel.new()
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0.03, 0.0, 0.07, 0.72)
	estilo.set_border_width_all(2)
	estilo.border_color = Color(COR_NEON_CIANO.r, COR_NEON_CIANO.g, COR_NEON_CIANO.b, 0.6)
	estilo.set_corner_radius_all(int(altura_painel * 0.5))
	estilo.shadow_color = Color(COR_NEON_CIANO.r, COR_NEON_CIANO.g, COR_NEON_CIANO.b, 0.30)
	estilo.shadow_size = 16
	painel.add_theme_stylebox_override("panel", estilo)
	painel.size = Vector2(largura_painel, altura_painel)
	painel.position = Vector2(
		_centro_tela.x - largura_painel / 2.0,
		_centro_tela.y - _raio_circulo_px * 0.60
	)
	camada.add_child(painel)

	var config_rotulo := LabelSettings.new()
	config_rotulo.font_size = int(altura_painel * 0.26)
	config_rotulo.font_color = Color(1, 1, 1, 0.55)

	var rotulo := Label.new()
	rotulo.label_settings = config_rotulo
	rotulo.text = "PONTOS"
	rotulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rotulo.size = Vector2(largura_painel, altura_painel * 0.34)
	rotulo.position = Vector2(0, altura_painel * 0.08)
	painel.add_child(rotulo)

	var config_pontuacao := LabelSettings.new()
	config_pontuacao.font_size = int(altura_painel * 0.46)
	config_pontuacao.font_color = Color.WHITE
	config_pontuacao.outline_size = 3
	config_pontuacao.outline_color = Color(COR_NEON_CIANO.r, COR_NEON_CIANO.g, COR_NEON_CIANO.b, 0.6)

	_label_pontuacao = Label.new()
	_label_pontuacao.label_settings = config_pontuacao
	_label_pontuacao.text = "0"
	_label_pontuacao.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label_pontuacao.size = Vector2(largura_painel, altura_painel * 0.6)
	_label_pontuacao.position = Vector2(0, altura_painel * 0.40)
	painel.add_child(_label_pontuacao)

	# Painelzinho de tempo, encaixado logo acima do placar, no mesmo vão do topo.
	var largura_tempo: float = largura_painel * 0.56
	var altura_tempo: float = altura_painel * 0.62

	var painel_tempo := Panel.new()
	var estilo_tempo := StyleBoxFlat.new()
	estilo_tempo.bg_color = Color(0.03, 0.0, 0.07, 0.75)
	estilo_tempo.set_border_width_all(2)
	estilo_tempo.border_color = Color(COR_NEON_ROSA.r, COR_NEON_ROSA.g, COR_NEON_ROSA.b, 0.6)
	estilo_tempo.set_corner_radius_all(int(altura_tempo * 0.5))
	estilo_tempo.shadow_color = Color(COR_NEON_ROSA.r, COR_NEON_ROSA.g, COR_NEON_ROSA.b, 0.28)
	estilo_tempo.shadow_size = 12
	painel_tempo.add_theme_stylebox_override("panel", estilo_tempo)
	painel_tempo.size = Vector2(largura_tempo, altura_tempo)
	painel_tempo.position = Vector2(
		_centro_tela.x - largura_tempo / 2.0,
		painel.position.y - altura_tempo - _raio_circulo_px * 0.025
	)
	camada.add_child(painel_tempo)

	var config_tempo := LabelSettings.new()
	config_tempo.font_size = int(altura_tempo * 0.5)
	config_tempo.font_color = Color.WHITE
	config_tempo.outline_size = 2
	config_tempo.outline_color = Color(COR_NEON_ROSA.r, COR_NEON_ROSA.g, COR_NEON_ROSA.b, 0.6)

	_label_tempo = Label.new()
	_label_tempo.label_settings = config_tempo
	_label_tempo.text = "1:20"
	_label_tempo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label_tempo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label_tempo.size = Vector2(largura_tempo, altura_tempo)
	painel_tempo.add_child(_label_tempo)

	# Combo, logo abaixo do placar -- some quando o combo é 0 ou 1.
	var config_combo := LabelSettings.new()
	config_combo.font_size = int(altura_painel * 0.34)
	config_combo.font_color = COR_NEON_ROSA
	config_combo.outline_size = 4
	config_combo.outline_color = Color(0, 0, 0, 0.85)

	_label_combo = Label.new()
	_label_combo.label_settings = config_combo
	_label_combo.text = ""
	_label_combo.visible = false
	_label_combo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label_combo.size = Vector2(largura_painel * 1.2, altura_painel * 0.5)
	_label_combo.pivot_offset = _label_combo.size / 2.0
	_label_combo.position = Vector2(
		_centro_tela.x - _label_combo.size.x / 2.0,
		painel.position.y + altura_painel + _raio_circulo_px * 0.02
	)
	camada.add_child(_label_combo)

	_atualizar_hud()


# ---------------------------------------------------------------
# MÚSICA
# ---------------------------------------------------------------
func _tocar_musica() -> void:
	var stream: AudioStream = load(CAMINHO_MUSICA)
	if stream == null:
		push_warning("Música não encontrada em: " + CAMINHO_MUSICA)
		return

	_musica_player = AudioStreamPlayer.new()
	_musica_player.stream = stream
	_musica_player.volume_db = VOLUME_MAX_DB
	_musica_player.finished.connect(_ao_musica_terminar)
	add_child(_musica_player)
	_musica_player.play()


func _ao_musica_terminar() -> void:
	musica_concluida.emit()
	_encerrar_partida()


func _encerrar_partida() -> void:
	if _partida_encerrada:
		return
	_partida_encerrada = true

	if _musica_player:
		_musica_player.stop()
	if _video_fundo:
		# Mantém o vídeo aparecendo no fundo do modal, porém mais apagado.
		_video_fundo.paused = true
		_video_fundo.modulate = Color(1, 1, 1, VIDEO_FUNDO_ALPHA * 0.62)

	_eventos_ativos.clear()
	_arduino_enviar_unico("COUNT " + str(int(TEMPO_MODAL_CONTINUAR_SEG)))
	_mostrar_modal_continuar()


func _mostrar_modal_continuar() -> void:
	if _modal_continuar_ativo:
		return

	_modal_continuar_ativo = true
	_modal_countdown_restante = TEMPO_MODAL_CONTINUAR_SEG
	_modal_ultimo_numero_led = -1

	_modal_layer = CanvasLayer.new()
	_modal_layer.layer = 40
	add_child(_modal_layer)

	var tam_tela: Vector2 = get_viewport_rect().size

	var escurecer := ColorRect.new()
	escurecer.color = Color(0, 0, 0, 0.52)
	escurecer.size = tam_tela
	escurecer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal_layer.add_child(escurecer)

	var largura: float = _raio_circulo_px * 1.28
	var altura: float = _raio_circulo_px * 0.62
	var painel := Panel.new()
	painel.size = Vector2(largura, altura)
	painel.position = _centro_tela - painel.size / 2.0

	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0.025, 0.0, 0.07, 0.90)
	estilo.set_border_width_all(4)
	estilo.border_color = Color(COR_NEON_CIANO.r, COR_NEON_CIANO.g, COR_NEON_CIANO.b, 0.92)
	estilo.set_corner_radius_all(int(_raio_circulo_px * 0.045))
	estilo.shadow_color = Color(COR_NEON_ROSA.r, COR_NEON_ROSA.g, COR_NEON_ROSA.b, 0.40)
	estilo.shadow_size = 28
	painel.add_theme_stylebox_override("panel", estilo)
	_modal_layer.add_child(painel)

	var cfg_titulo := LabelSettings.new()
	cfg_titulo.font_size = int(_raio_circulo_px * 0.085)
	cfg_titulo.font_color = Color.WHITE
	cfg_titulo.outline_size = 5
	cfg_titulo.outline_color = Color(0, 0, 0, 0.9)
	cfg_titulo.shadow_size = 16
	cfg_titulo.shadow_color = Color(COR_NEON_CIANO.r, COR_NEON_CIANO.g, COR_NEON_CIANO.b, 0.55)

	_modal_label_titulo = Label.new()
	_modal_label_titulo.label_settings = cfg_titulo
	_modal_label_titulo.text = "FIM DA PARTIDA"
	_modal_label_titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_modal_label_titulo.size = Vector2(largura, altura * 0.22)
	_modal_label_titulo.position = Vector2(0, altura * 0.08)
	painel.add_child(_modal_label_titulo)

	var cfg_score := LabelSettings.new()
	cfg_score.font_size = int(_raio_circulo_px * 0.075)
	cfg_score.font_color = COR_SLIDE_AMARELO
	cfg_score.outline_size = 4
	cfg_score.outline_color = Color(0, 0, 0, 0.9)

	_modal_label_score = Label.new()
	_modal_label_score.label_settings = cfg_score
	_modal_label_score.text = "PONTOS: " + str(_pontuacao)
	_modal_label_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_modal_label_score.size = Vector2(largura, altura * 0.18)
	_modal_label_score.position = Vector2(0, altura * 0.29)
	painel.add_child(_modal_label_score)

	var cfg_count := LabelSettings.new()
	cfg_count.font_size = int(_raio_circulo_px * 0.14)
	cfg_count.font_color = Color.WHITE
	cfg_count.outline_size = 6
	cfg_count.outline_color = Color(COR_NEON_ROSA.r, 0, COR_NEON_ROSA.b, 0.78)

	_modal_label_countdown = Label.new()
	_modal_label_countdown.label_settings = cfg_count
	_modal_label_countdown.text = str(int(ceil(_modal_countdown_restante)))
	_modal_label_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_modal_label_countdown.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_modal_label_countdown.size = Vector2(largura, altura * 0.24)
	_modal_label_countdown.position = Vector2(0, altura * 0.45)
	painel.add_child(_modal_label_countdown)

	var cfg_acao := LabelSettings.new()
	cfg_acao.font_size = int(_raio_circulo_px * 0.050)
	cfg_acao.font_color = Color(0.78, 0.95, 1.0, 1.0)
	cfg_acao.outline_size = 3
	cfg_acao.outline_color = Color(0, 0, 0, 0.88)

	_modal_label_acao = Label.new()
	_modal_label_acao.label_settings = cfg_acao
	_modal_label_acao.text = "INSIRA MAIS CRÉDITO OU APERTE START PARA CONTINUAR"
	_modal_label_acao.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_modal_label_acao.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_modal_label_acao.size = Vector2(largura * 0.90, altura * 0.20)
	_modal_label_acao.position = Vector2(largura * 0.05, altura * 0.73)
	painel.add_child(_modal_label_acao)


func _processar_modal_continuar(delta: float) -> void:
	_modal_countdown_restante = max(_modal_countdown_restante - delta, 0.0)

	if _modal_label_countdown:
		var numero: int = int(ceil(_modal_countdown_restante))
		_modal_label_countdown.text = str(numero)
		var fracao: float = _modal_countdown_restante - floor(_modal_countdown_restante)
		_modal_label_countdown.scale = Vector2.ONE * (1.0 + fracao * 0.12)

		if numero != _modal_ultimo_numero_led:
			_modal_ultimo_numero_led = numero
			_arduino_enviar_unico("COUNT " + str(numero))

	if _acao_just_pressed("input_credit") or _acao_just_pressed("input_start"):
		_continuar_partida_com_credito()
		return

	if _modal_countdown_restante <= 0.0:
		_voltar_para_abertura()


func _acao_just_pressed(nome_acao: String) -> bool:
	return InputMap.has_action(nome_acao) and Input.is_action_just_pressed(nome_acao)


func _continuar_partida_com_credito() -> void:
	_arduino_enviar_unico("READY")
	get_tree().reload_current_scene()


func _voltar_para_abertura() -> void:
	_arduino_enviar_unico("CLEAR")
	get_tree().change_scene_to_file(CAMINHO_CENA_ABERTURA)


func _tempo_atual_musica() -> float:
	if _musica_player == null or not _musica_player.playing:
		return 0.0
	return _musica_player.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()


# ---------------------------------------------------------------
# BEATMAP / EVENTOS
# ---------------------------------------------------------------
func _ativar_eventos_pendentes(tempo_musica: float) -> void:
	while _indice_beatmap < _beatmap.size() and (_beatmap[_indice_beatmap]["tempo"] - TEMPO_APROXIMACAO_SEG) <= tempo_musica:
		var evento: Dictionary = _beatmap[_indice_beatmap].duplicate()
		evento["resolvido"] = false
		_eventos_ativos.append(evento)
		_indice_beatmap += 1


func _atualizar_eventos_ativos(tempo_musica: float) -> void:
	for i in range(_eventos_ativos.size() - 1, -1, -1):
		var evento: Dictionary = _eventos_ativos[i]

		if evento["tipo"] == "toque":
			_atualizar_visual_toque(evento, tempo_musica)
			var venceu_janela: bool = tempo_musica > evento["tempo"] + JANELA_ACERTO_SEG
			if evento.get("resolvido", false) or venceu_janela:
				if not evento.get("resolvido", false):
					_registrar_erro(evento)
					var idx_toque: int = int(evento["ponto"])
					_ponto_set_estado(idx_toque, "idle", 0.25, COR_ERRO)
				_eventos_ativos.remove_at(i)

		elif evento["tipo"] == "arraste":
			_atualizar_visual_arraste(evento, tempo_musica)
			var venceu_janela_arraste: bool = tempo_musica > float(evento["tempo_fim"]) + ARRASTE_TOLERANCIA_FINAL_SEG
			if evento.get("resolvido", false) or venceu_janela_arraste:
				if not evento.get("resolvido", false):
					_registrar_erro(evento)
				for indice_p in evento["caminho"]:
					_ponto_set_estado(int(indice_p), "idle")
				if _arraste_evento_atual == evento:
					_arraste_evento_atual = null
					_arraste_indice_atual = 0
					_arraste_gesto_ativo = false
				_eventos_ativos.remove_at(i)


func _atualizar_visual_toque(evento: Dictionary, tempo_musica: float) -> void:
	var indice: int = int(evento["ponto"])
	var t: float = float(evento["tempo"])
	if tempo_musica < t - JANELA_ACERTO_SEG:
		var restante: float = t - JANELA_ACERTO_SEG - tempo_musica
		var progresso: float = 1.0 - clamp(restante / TEMPO_APROXIMACAO_SEG, 0.0, 1.0)
		_ponto_set_estado(indice, "hig" if progresso > 0.18 else "idle")
	else:
		_ponto_set_estado(indice, "hig")


func _atualizar_visual_arraste(evento: Dictionary, tempo_musica: float) -> void:
	if tempo_musica < evento["tempo"] - TEMPO_APROXIMACAO_SEG:
		return
	for indice_p in evento["caminho"]:
		_ponto_set_estado(int(indice_p), "hig")


# ---------------------------------------------------------------
# INPUT -- TOQUE NOS BOTÕES (input_a..input_h)
# ---------------------------------------------------------------
func _processar_inputs_toque(tempo_musica: float) -> void:
	for i in range(NUM_PONTOS):
		if Input.is_action_just_pressed(INPUTS_PONTOS[i]):
			# O input não acende LED por conta própria.
			# O hardware reflete apenas o beatmap.
			_tentar_resolver_toque(i, tempo_musica)


func _tentar_resolver_toque(indice_ponto: int, tempo_musica: float) -> void:
	for evento in _eventos_ativos:
		if evento["tipo"] == "toque" and evento["ponto"] == indice_ponto and not evento.get("resolvido", false):
			if abs(tempo_musica - evento["tempo"]) <= JANELA_ACERTO_SEG:
				evento["resolvido"] = true
				_registrar_acerto(PONTOS_POR_ACERTO_TOQUE)
				var ponto: Node2D = _pontos[indice_ponto]
				_ponto_set_estado(indice_ponto, "idle", 0.25, COR_ACERTO)
				_explosao_particulas(ponto.position, COR_ACERTO)
				_efeito_texto_flutuante("PERFEITO!", ponto.position, COR_ACERTO)
				# Sem flash OK físico: mantém a duração real do evento.
				_led_assinatura_atual = ""
				return

func _indice_ponto_mais_proximo(pos_tela: Vector2, multiplicador_raio: float = 1.0) -> int:
	for i in range(_pontos.size()):
		if _pontos[i].position.distance_to(pos_tela) <= _raio_toque_ponto_px * multiplicador_raio:
			return i
	return -1


func _raio_arraste_checkpoint() -> float:
	return _raio_toque_ponto_px * ARRASTE_RAIO_CHECKPOINT_EXTRA


func _segmento_passou_no_ponto(a: Vector2, b: Vector2, ponto: Vector2, raio: float) -> bool:
	var ab: Vector2 = b - a
	var ab_len2: float = ab.length_squared()
	if ab_len2 <= 0.001:
		return ponto.distance_to(b) <= raio

	var t: float = clamp((ponto - a).dot(ab) / ab_len2, 0.0, 1.0)
	var mais_perto: Vector2 = a + ab * t
	return mais_perto.distance_to(ponto) <= raio


func _evento_arraste_pode_receber_input(evento: Dictionary, tempo_musica: float) -> bool:
	if evento.is_empty():
		return false
	if evento.get("tipo", "") != "arraste":
		return false
	if evento.get("resolvido", false):
		return false

	var inicio: float = float(evento["tempo"]) - TEMPO_APROXIMACAO_SEG
	var fim: float = float(evento["tempo_fim"]) + ARRASTE_TOLERANCIA_FINAL_SEG
	return tempo_musica >= inicio and tempo_musica <= fim


func _iniciar_arraste(pos: Vector2) -> void:
	_arraste_gesto_ativo = true
	_arraste_ultimo_pos = pos
	_arraste_pos_atual = pos
	_arraste_evento_atual = null
	_arraste_indice_atual = 0

	# Se apertou exatamente no primeiro Tazo do caminho, começa imediatamente.
	# Se apertou fora, o gesto fica ativo e _atualizar_arraste() tenta começar
	# quando o dedo entrar no primeiro Tazo da sequência.
	_tentar_iniciar_arraste_por_pos(pos)


func _tentar_iniciar_arraste_por_pos(pos: Vector2) -> bool:
	if _arraste_evento_atual != null:
		return true

	var tempo_musica: float = _tempo_atual_musica()
	var raio_checkpoint: float = _raio_arraste_checkpoint()

	var melhor_evento: Dictionary = {}
	var melhor_distancia: float = 999999.0

	for evento in _eventos_ativos:
		if not _evento_arraste_pode_receber_input(evento, tempo_musica):
			continue

		var caminho: Array = evento["caminho"]
		if caminho.size() < 2:
			continue

		var primeiro_indice: int = int(caminho[0])
		if primeiro_indice < 0 or primeiro_indice >= _pontos.size():
			continue

		var primeiro_ponto: Node2D = _pontos[primeiro_indice]
		var distancia: float = primeiro_ponto.position.distance_to(pos)

		# Aceita tanto entrar no primeiro Tazo quanto cruzar por cima dele entre um frame e outro.
		var cruzou_primeiro: bool = _segmento_passou_no_ponto(_arraste_ultimo_pos, pos, primeiro_ponto.position, raio_checkpoint)
		if distancia <= raio_checkpoint or cruzou_primeiro:
			if distancia < melhor_distancia:
				melhor_distancia = distancia
				melhor_evento = evento

	if melhor_evento.is_empty():
		return false

	var caminho_melhor: Array = melhor_evento["caminho"]
	var idx_inicio: int = int(caminho_melhor[0])
	_arraste_evento_atual = melhor_evento
	_arraste_indice_atual = 0

	_ponto_set_estado(idx_inicio, "hig", 0.18, _cor_orbe_por_ponto(idx_inicio))
	_led_feedback_bloqueio_ate_msec = Time.get_ticks_msec() + 180
	_arduino_enviar_unico(_cmd_led_progresso(caminho_melhor, _arraste_indice_atual))
	return true


func _atualizar_arraste(pos: Vector2) -> void:
	if not _arraste_gesto_ativo:
		return

	var pos_anterior: Vector2 = _arraste_pos_atual
	_arraste_ultimo_pos = pos_anterior
	_arraste_pos_atual = pos
	_registrar_ponto_rastro_arraste(pos)

	# Moldura touch: o jogador pode encostar fora do primeiro Tazo e entrar arrastando.
	if _arraste_evento_atual == null:
		_tentar_iniciar_arraste_por_pos(pos)
		if _arraste_evento_atual == null:
			return

	var caminho: Array = _arraste_evento_atual["caminho"]
	var raio_checkpoint: float = _raio_arraste_checkpoint()

	# Avança pelos checkpoints na ordem das setas.
	# O teste por segmento evita perder ponto quando a moldura touch manda poucos frames.
	while _arraste_indice_atual < caminho.size() - 1:
		var proximo_indice: int = int(caminho[_arraste_indice_atual + 1])
		if proximo_indice < 0 or proximo_indice >= _pontos.size():
			break

		var proximo_ponto: Node2D = _pontos[proximo_indice]
		var tocou_proximo: bool = proximo_ponto.position.distance_to(pos) <= raio_checkpoint
		var cruzou_proximo: bool = _segmento_passou_no_ponto(pos_anterior, pos, proximo_ponto.position, raio_checkpoint)

		if not tocou_proximo and not cruzou_proximo:
			break

		_arraste_indice_atual += 1
		_ponto_set_estado(proximo_indice, "hig", 0.18, _cor_orbe_por_ponto(proximo_indice))
		_explosao_particulas(proximo_ponto.position, _cor_orbe_por_ponto(proximo_indice))
		_arduino_enviar_unico(_cmd_led_progresso(caminho, _arraste_indice_atual))

		# Se chegou no último Tazo, soma na hora. Não precisa soltar o dedo.
		if _arraste_indice_atual >= caminho.size() - 1:
			_resolver_arraste_completo()
			return


func _resolver_arraste_completo() -> void:
	if _arraste_evento_atual == null:
		return

	var evento: Dictionary = _arraste_evento_atual
	if evento.get("resolvido", false):
		return

	var caminho: Array = evento["caminho"]
	var tempo_musica: float = _tempo_atual_musica()
	var dentro_do_tempo: bool = tempo_musica <= float(evento["tempo_fim"]) + ARRASTE_TOLERANCIA_FINAL_SEG

	if not dentro_do_tempo:
		_registrar_erro(evento)
		_efeito_texto_flutuante("ARRASTE FORA DO TEMPO", _centro_caminho(caminho), COR_ERRO)
		var idx_falha: int = clamp(_arraste_indice_atual, 0, caminho.size() - 1)
		# Sem flash ERR físico: o quadro do beatmap controla o LED.
		_led_assinatura_atual = ""
	else:
		evento["resolvido"] = true
		_registrar_acerto(PONTOS_POR_ACERTO_ARRASTE)
		for indice_p in caminho:
			var idx_ok: int = int(indice_p)
			var p: Node2D = _pontos[idx_ok]
			_ponto_set_estado(idx_ok, "idle", 0.35, COR_SLIDE_COMPLETO)
			_explosao_particulas(p.position, COR_SLIDE_COMPLETO)
		_efeito_texto_flutuante("ARRASTE COMPLETO!", _centro_caminho(caminho), COR_SLIDE_COMPLETO)
		_led_feedback_bloqueio_ate_msec = Time.get_ticks_msec() + 780
		# Sem flash verde extra no hardware.
		_led_assinatura_atual = ""

	_arraste_evento_atual = null
	_arraste_indice_atual = 0
	_arraste_gesto_ativo = false


func _finalizar_arraste() -> void:
	# Ao soltar sem completar todos os Tazos do caminho, falha.
	if _arraste_evento_atual != null:
		var evento: Dictionary = _arraste_evento_atual
		var caminho: Array = evento["caminho"]
		var completou_caminho: bool = _arraste_indice_atual >= caminho.size() - 1

		if completou_caminho:
			_resolver_arraste_completo()
		else:
			_registrar_erro(evento)
			for indice_p in caminho:
				var idx_erro: int = int(indice_p)
				_ponto_set_estado(idx_erro, "idle", 0.30, COR_ERRO)
			_efeito_texto_flutuante("ARRASTE FALHOU", _centro_caminho(caminho), COR_ERRO)
			_led_feedback_bloqueio_ate_msec = Time.get_ticks_msec() + 520

	_arraste_evento_atual = null
	_arraste_indice_atual = 0
	_arraste_gesto_ativo = false

func _registrar_acerto(pontos: int) -> void:
	_pontuacao += pontos
	_combo_atual += 1
	if _musica_player:
		_musica_player.volume_db = min(_musica_player.volume_db + VOLUME_PASSO_ACERTO_DB, VOLUME_MAX_DB)
	_atualizar_hud()
	_mostrar_combo()


func _registrar_erro(_evento: Dictionary) -> void:
	# Sem perda de pontos -- só zera o combo e o volume da música cai (efeito "Guitar Hero").
	_combo_atual = 0
	if _musica_player:
		_musica_player.volume_db = max(_musica_player.volume_db + VOLUME_PASSO_ERRO_DB, VOLUME_MIN_DB)
	_atualizar_hud()

	var indice_led: int = _indice_led_do_evento(_evento)
	if indice_led >= 0:
		# Sem flash ERR físico: não prolonga a luz além da janela do evento.
		_led_assinatura_atual = ""
		if indice_led < _pontos.size():
			_explosao_particulas(_pontos[indice_led].position, COR_ERRO)
			_efeito_texto_flutuante("ERROU!", _pontos[indice_led].position, COR_ERRO)


func _indice_led_do_evento(evento: Dictionary) -> int:
	if evento.is_empty():
		return -1
	if evento.get("tipo", "") == "toque":
		return int(evento.get("ponto", -1))
	if evento.get("tipo", "") == "arraste":
		var caminho: Array = evento.get("caminho", [])
		if caminho.is_empty():
			return -1
		var idx: int = clamp(_arraste_indice_atual, 0, caminho.size() - 1)
		return int(caminho[idx])
	return -1


func _centro_caminho(caminho: Array) -> Vector2:
	if caminho.is_empty():
		return _centro_tela
	var soma: Vector2 = Vector2.ZERO
	for indice in caminho:
		if int(indice) >= 0 and int(indice) < _pontos.size():
			soma += _pontos[int(indice)].position
	return soma / float(caminho.size())


func _efeito_texto_flutuante(texto: String, pos: Vector2, cor: Color) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 32
	add_child(layer)

	var cfg := LabelSettings.new()
	# Texto maior para PERFEITO / ERRO / ARRASTE, já que o raio central subiu.
	cfg.font_size = int(_raio_circulo_px * 0.072)
	cfg.font_color = cor.lerp(Color.WHITE, 0.10)
	cfg.outline_size = 7
	cfg.outline_color = Color(0, 0, 0, 0.94)
	cfg.shadow_size = 22
	cfg.shadow_color = Color(cor.r, cor.g, cor.b, 0.62)

	var label := Label.new()
	label.label_settings = cfg
	label.text = texto
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = Vector2(_raio_circulo_px * 1.28, _raio_circulo_px * 0.32)
	label.position = pos - label.size / 2.0
	label.scale = Vector2(0.62, 0.62)
	label.modulate = Color(1, 1, 1, 0.0)
	layer.add_child(label)

	# Uma lâmina de luz atrás do texto, bem arcade.
	var brilho := ColorRect.new()
	brilho.color = Color(cor.r, cor.g, cor.b, 0.18)
	brilho.size = Vector2(_raio_circulo_px * 0.88, _raio_circulo_px * 0.105)
	brilho.position = label.position + Vector2((label.size.x - brilho.size.x) * 0.5, label.size.y * 0.45)
	brilho.scale = Vector2(0.45, 1.0)
	brilho.modulate = Color(1, 1, 1, 0.0)
	layer.add_child(brilho)

	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "scale", Vector2(1.18, 1.18), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "modulate", Color(1, 1, 1, 1.0), 0.10)
	tw.tween_property(brilho, "scale", Vector2(1.18, 1.0), 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(brilho, "modulate", Color(1, 1, 1, 0.85), 0.10)
	tw.set_parallel(false)
	tw.tween_interval(0.24)
	tw.set_parallel(true)
	tw.tween_property(label, "position", label.position + Vector2(0, -_raio_circulo_px * 0.13), 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "modulate", Color(1, 1, 1, 0.0), 0.42)
	tw.tween_property(brilho, "modulate", Color(1, 1, 1, 0.0), 0.32)
	tw.finished.connect(func():
		if layer and is_instance_valid(layer):
			layer.queue_free()
	)

func _atualizar_hud() -> void:
	if _label_pontuacao:
		_label_pontuacao.text = str(_pontuacao)
	if _label_combo:
		if _combo_atual >= 2:
			_label_combo.visible = true
			_label_combo.text = "COMBO x%d" % _combo_atual
		else:
			_label_combo.visible = false


func _mostrar_combo() -> void:
	if _label_combo == null or _combo_atual < 2:
		return
	if _tween_combo:
		_tween_combo.kill()
	_label_combo.scale = Vector2(1.55, 1.55)
	_tween_combo = create_tween()
	_tween_combo.set_trans(Tween.TRANS_BACK)
	_tween_combo.set_ease(Tween.EASE_OUT)
	_tween_combo.tween_property(_label_combo, "scale", Vector2(1.0, 1.0), 0.28)


func _atualizar_label_tempo() -> void:
	if _label_tempo == null:
		return

	var total_segundos: int = int(_tempo_restante)
	var minutos: int = int(total_segundos / 60)
	var segundos: int = total_segundos % 60
	_label_tempo.text = "%d:%02d" % [minutos, segundos]

# ---------------------------------------------------------------
# PARTÍCULAS DE ACERTO
# ---------------------------------------------------------------
func _obter_textura_particula() -> ImageTexture:
	if _textura_particula_cache:
		return _textura_particula_cache

	var tamanho: int = 32
	var imagem := Image.create(tamanho, tamanho, false, Image.FORMAT_RGBA8)
	var centro: Vector2 = Vector2(tamanho, tamanho) / 2.0

	for x in range(tamanho):
		for y in range(tamanho):
			var dist: float = Vector2(x, y).distance_to(centro) / (tamanho / 2.0)
			var alpha: float = clamp(1.0 - dist, 0.0, 1.0)
			alpha = pow(alpha, 1.8)
			imagem.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))

	_textura_particula_cache = ImageTexture.create_from_image(imagem)
	return _textura_particula_cache


func _gerar_gradiente_particula(cor_base: Color) -> Gradient:
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(cor_base.r, cor_base.g, cor_base.b, 0.9),
		Color(cor_base.r, cor_base.g, cor_base.b, 0.0),
	])
	grad.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	return grad


func _explosao_particulas(pos: Vector2, cor: Color) -> void:
	# Explosão menor e mais sofisticada: brilho principal + pequenas fagulhas coloridas.
	_criar_particulas_neon(pos, cor, 24, 0.46, 42.0, 118.0, 0.22, 0.46, 24)

	var cor_extra: Color = cor.lerp(Color(1.0, 0.35, 1.0, 1.0), 0.38)
	_criar_particulas_neon(pos, cor_extra, 12, 0.32, 25.0, 82.0, 0.12, 0.28, 25)


func _criar_particulas_neon(pos: Vector2, cor: Color, quantidade: int, vida: float, vel_min: float, vel_max: float, escala_min: float, escala_max: float, z: int) -> void:
	var particulas := CPUParticles2D.new()
	particulas.position = pos
	particulas.z_index = z
	particulas.texture = _obter_textura_particula()
	particulas.emitting = true
	particulas.one_shot = true
	particulas.amount = quantidade
	particulas.lifetime = vida
	particulas.explosiveness = 1.0
	particulas.spread = 180.0
	particulas.initial_velocity_min = vel_min
	particulas.initial_velocity_max = vel_max
	particulas.gravity = Vector2.ZERO
	particulas.damping_min = 95.0
	particulas.damping_max = 165.0
	particulas.scale_amount_min = escala_min
	particulas.scale_amount_max = escala_max
	particulas.color_ramp = _gerar_gradiente_particula(cor)

	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	particulas.material = mat

	add_child(particulas)
	particulas.finished.connect(particulas.queue_free)


# ---------------------------------------------------------------
# BEATMAP DE TESTE (usado só se BEATMAP_CHINA_SONG estiver vazio)
# ---------------------------------------------------------------
func _gerar_beatmap_song1_por_fases(duracao_seg: float) -> Array:
	var eventos: Array = []

	# Este beatmap não fica mais A-B-C-D em sequência.
	# Ele cria uma sequência musical "aleatória controlada":
	# - Intro: poucos toques e quase nenhum arraste.
	# - Verso: alterna pontos distantes para dar movimento.
	# - Refrão: mais hits e mais velocidade.
	# - Ponte: arrastes maiores conectando pontos distantes.
	# - Final: mistura toque duplo visual + arraste curto, mais intenso.
	#
	# A música real continua sendo song1.
	# Para ficar 100% perfeito com a música, depois você pode trocar por um beatmap manual
	# com os tempos exatos. Enquanto isso, essa função cria uma jogabilidade musical boa
	# e sempre diferente.

	var tempo: float = 2.0
	var ultimo_ponto: int = _rng.randi_range(0, NUM_PONTOS - 1)

	while tempo < duracao_seg:
		var fase: Dictionary = _perfil_musical_por_tempo(tempo)
		var intervalo: float = fase["intervalo"]
		var intensidade: int = fase["intensidade"]
		var chance_arraste: float = fase["chance_arraste"]
		var chance_hit_duplo: float = fase["chance_hit_duplo"]

		# Pequena variação humana para não parecer metrônomo travado.
		var variacao: float = _rng.randf_range(-intervalo * 0.12, intervalo * 0.12)
		var tempo_evento: float = max(0.10, tempo + variacao)

		var usar_arraste: bool = _rng.randf() < chance_arraste

		if usar_arraste:
			var inicio: int = _sortear_ponto_musical(ultimo_ponto, intensidade)
			var tamanho_caminho: int = 2 + min(intensidade, 3)
			var caminho: Array = _montar_caminho_arraste_musical(inicio, tamanho_caminho, intensidade)

			eventos.append({
				"tipo": "arraste",
				"tempo": tempo_evento,
				"tempo_fim": tempo_evento + intervalo * (1.5 + intensidade * 0.22),
				"caminho": caminho,
			})

			ultimo_ponto = caminho[caminho.size() - 1]
			tempo += intervalo * (1.8 + intensidade * 0.18)

		else:
			var ponto_a: int = _sortear_ponto_musical(ultimo_ponto, intensidade)

			eventos.append({
				"tipo": "toque",
				"tempo": tempo_evento,
				"ponto": ponto_a,
			})

			ultimo_ponto = ponto_a

			# Hit duplo: dois pontos próximos no tempo, comum em batidas fortes.
			# Não é exatamente simultâneo para o jogador conseguir reagir.
			if _rng.randf() < chance_hit_duplo and tempo_evento + 0.12 < duracao_seg:
				var ponto_b: int = _sortear_ponto_musical(ponto_a, intensidade + 1)

				eventos.append({
					"tipo": "toque",
					"tempo": tempo_evento + _rng.randf_range(0.10, 0.16),
					"ponto": ponto_b,
				})

				ultimo_ponto = ponto_b

			tempo += intervalo

	return eventos


func _perfil_musical_por_tempo(tempo: float) -> Dictionary:
	# Quanto maior a intensidade:
	# - menor o intervalo entre eventos;
	# - maior chance de arraste;
	# - maior chance de hit duplo;
	# - maior distância entre pontos sorteados.

	if tempo < 10.0:
		return {
			"nome": "INTRO",
			"intervalo": _rng.randf_range(0.78, 0.95),
			"intensidade": 1,
			"chance_arraste": 0.04,
			"chance_hit_duplo": 0.02,
		}

	if tempo < 26.0:
		return {
			"nome": "VERSO",
			"intervalo": _rng.randf_range(0.55, 0.70),
			"intensidade": 2,
			"chance_arraste": 0.16,
			"chance_hit_duplo": 0.08,
		}

	if tempo < 48.0:
		return {
			"nome": "REFRAO",
			"intervalo": _rng.randf_range(0.34, 0.50),
			"intensidade": 4,
			"chance_arraste": 0.22,
			"chance_hit_duplo": 0.20,
		}

	if tempo < 62.0:
		return {
			"nome": "PONTE",
			"intervalo": _rng.randf_range(0.46, 0.64),
			"intensidade": 3,
			"chance_arraste": 0.42,
			"chance_hit_duplo": 0.10,
		}

	return {
		"nome": "FINAL",
		"intervalo": _rng.randf_range(0.30, 0.44),
		"intensidade": 5,
		"chance_arraste": 0.28,
		"chance_hit_duplo": 0.26,
	}


func _sortear_ponto_musical(ultimo_ponto: int, intensidade: int) -> int:
	var candidatos: Array[int] = []

	for i in range(NUM_PONTOS):
		if i == ultimo_ponto:
			continue

		var distancia_circular: int = abs(i - ultimo_ponto)
		distancia_circular = min(distancia_circular, NUM_PONTOS - distancia_circular)

		# Evita ficar sequencial demais.
		# Em intensidade baixa aceita vizinhos às vezes.
		# Em intensidade alta prefere saltos mais longos pelo círculo.
		if intensidade >= 3 and distancia_circular <= 1:
			continue

		candidatos.append(i)

	if candidatos.is_empty():
		for i in range(NUM_PONTOS):
			if i != ultimo_ponto:
				candidatos.append(i)

	return candidatos[_rng.randi_range(0, candidatos.size() - 1)]


func _montar_caminho_arraste_musical(inicio: int, tamanho: int, intensidade: int) -> Array:
	var caminho: Array = [inicio]
	var atual: int = inicio

	while caminho.size() < tamanho:
		var proximo: int = _sortear_ponto_musical(atual, intensidade)

		# Evita repetir ponto já usado no mesmo arraste quando possível.
		var tentativas: int = 0
		while proximo in caminho and tentativas < 12:
			proximo = _sortear_ponto_musical(atual, intensidade)
			tentativas += 1

		caminho.append(proximo)
		atual = proximo

	return caminho


# ---------------------------------------------------------------
# CLASSE INTERNA: visual de cada um dos 8 pontos
# ---------------------------------------------------------------
class PontoRitmo:
	extends Node2D

	var indice: int = 0
	var letra: String = ""
	var estado: String = "idle"  # idle | aproximando | ativo | ativo_arraste
	var progresso_aproximacao: float = 0.0
	var flash_tempo: float = 0.0
	var flash_cor: Color = Color.WHITE
	var raio_ponto: float = 40.0

	var _rotacao_interna: float = 0.0

	func _process(delta: float) -> void:
		if flash_tempo > 0.0:
			flash_tempo -= delta
		_rotacao_interna += delta
		queue_redraw()

	func _draw() -> void:
		var fonte: Font = ThemeDB.fallback_font
		var tam_fonte: int = int(raio_ponto * 0.8)

		# Sombra suave por baixo -- separa o ponto do vídeo de fundo (profundidade).
		draw_circle(Vector2(0, raio_ponto * 0.08), raio_ponto * 1.35, Color(0, 0, 0, 0.22))

		# Glow ambiente sutil -- o ponto "respira" mesmo parado, nunca fica morto.
		var pulso_idle: float = sin(Time.get_ticks_msec() / 900.0 + indice) * 0.5 + 0.5
		draw_circle(Vector2.ZERO, raio_ponto * 1.4, Color(0.25, 0.85, 1.0, 0.035 + pulso_idle * 0.03))

		# Bezel duplo tipo radar, com marcas maiores a cada 5 (posições cardeais).
		var num_marcas: int = 20
		for m in range(num_marcas):
			var ang: float = (TAU / num_marcas) * m + _rotacao_interna * 0.2
			var maior: bool = m % 5 == 0
			var r_ini: float = raio_ponto * (1.02 if maior else 1.05)
			var r_fim: float = raio_ponto * (1.20 if maior else 1.14)
			var alpha_marca: float = 0.32 if maior else 0.16
			var espessura_marca: float = 2.2 if maior else 1.5
			var dir_marca: Vector2 = Vector2(cos(ang), sin(ang))
			draw_line(dir_marca * r_ini, dir_marca * r_fim, Color(1, 1, 1, alpha_marca), espessura_marca, true)

		draw_arc(Vector2.ZERO, raio_ponto * 1.18, 0.0, TAU, 48, Color(1, 1, 1, 0.12), 1.0, true)
		draw_arc(Vector2.ZERO, raio_ponto, 0.0, TAU, 48, Color(1, 1, 1, 0.30), 2.5, true)

		if estado == "aproximando":
			# Anel de contagem regressiva encolhendo, com "cauda" tipo cometa girando.
			var raio_aprox: float = lerp(raio_ponto * 1.7, raio_ponto * 1.05, progresso_aproximacao)
			var inicio_arco: float = _rotacao_interna * 3.0
			draw_arc(Vector2.ZERO, raio_aprox, inicio_arco, inicio_arco + TAU * 0.72, 40, Color(0.25, 0.85, 1.0, 0.95), 5.0, true)
			draw_arc(Vector2.ZERO, raio_aprox, inicio_arco, inicio_arco + TAU * 0.72, 40, Color(0.25, 0.85, 1.0, 0.28), 11.0, true)

		if estado == "ativo" or estado == "ativo_arraste":
			var pulso_ativo: float = sin(Time.get_ticks_msec() / 90.0) * 0.5 + 0.5
			draw_circle(Vector2.ZERO, raio_ponto * 1.35, Color(1.0, 0.15, 0.85, 0.10 + pulso_ativo * 0.08))
			draw_circle(Vector2.ZERO, raio_ponto * 1.15, Color(1.0, 0.15, 0.85, 0.20 + pulso_ativo * 0.14))
			draw_circle(Vector2.ZERO, raio_ponto * (0.82 + pulso_ativo * 0.08), Color(1.0, 0.15, 0.85, 0.9))

		if flash_tempo > 0.0:
			var alpha: float = clamp(flash_tempo / 0.25, 0.0, 1.0)
			var expansao: float = 1.0 - alpha
			draw_circle(Vector2.ZERO, raio_ponto * (1.3 + expansao * 0.4), Color(flash_cor.r, flash_cor.g, flash_cor.b, alpha * 0.45))
			draw_arc(Vector2.ZERO, raio_ponto * (1.3 + expansao * 0.4), 0.0, TAU, 32, Color(flash_cor.r, flash_cor.g, flash_cor.b, alpha * 0.65), 3.5, true)

		# Núcleo com degradê em camadas + friso interno.
		draw_circle(Vector2.ZERO, raio_ponto * 0.62, Color(0.06, 0.0, 0.10, 0.94))
		draw_circle(Vector2.ZERO, raio_ponto * 0.53, Color(0.11, 0.02, 0.16, 0.9))
		draw_arc(Vector2.ZERO, raio_ponto * 0.53, 0.0, TAU, 32, Color(1, 1, 1, 0.10), 1.5, true)

		# Letra com sombra por trás -- legibilidade e acabamento.
		var largura_texto: float = fonte.get_string_size(letra, HORIZONTAL_ALIGNMENT_CENTER, -1, tam_fonte).x
		draw_string(fonte, Vector2(-largura_texto / 2.0 + 1.5, tam_fonte * 0.31 + 1.5), letra, HORIZONTAL_ALIGNMENT_CENTER, -1, tam_fonte, Color(0, 0, 0, 0.6))
		draw_string(fonte, Vector2(-largura_texto / 2.0, tam_fonte * 0.31), letra, HORIZONTAL_ALIGNMENT_CENTER, -1, tam_fonte, Color.WHITE)
