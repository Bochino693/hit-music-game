extends Node2D
## ============================================================
## PLAY — HIT MUSIC — PAPERMOON / SOUL EATER (mesa redonda / tela circular)
##
## Círculo físico calibrado para mesa/tela grande: 48 cm de RAIO.
## O círculo visual agora ocupa quase toda a largura no modo retrato.
## A cena roda em 3 estados, em sequência:
##
## 1. APRESENTACAO -- capa/imagem da fase com o nome por cima.
## 2. CONTAGEM -- vídeo soul.ogv com contagem regressiva por cima.
## 3. JOGANDO -- vídeo soul.ogv centralizado no círculo, com
##    os 8 pontos, HUD, música soul e beatmap musical aleatório/adaptativo.
##
## Dentro de JOGANDO:
## - 8 pontos ao redor do círculo, ligados aos inputs físicos
##   input_a..input_h ("toque").
## - BEATMAP com eventos "toque" e "arraste" (arraste segue um
##   CAMINHO de 2+ pontos em zigue-zague, detectado só por touch/
##   mouse, nunca pelos inputs_a..h).
## - Acerto = pontos + combo + volume da música sobe. Erro = sem
##   perda de pontos, zera o combo, volume cai ("Guitar Hero").
## - A duração da fase vem do próprio arquivo de áudio. Música e vídeo começam
##   na contagem 3, 2, 1; a jogabilidade termina somente após o fim audível.
##
## >>> PRECISA AJUSTAR ANTES DE RODAR DE VERDADE <<<
## - CAMINHO_MUSICA usa "res://songs/soul.mp3".
##   (ajuste a extensão/nome se o arquivo de áudio real tiver outro nome).
## - CAMINHO_IMAGEM_FASE usa "res://images/soul.jpeg".
## - CAMINHO_VIDEO_CONTAGEM usa "res://medias/soul.ogv".
## - CAMINHO_VIDEO_FUNDO usa "res://medias/soul.ogv".
## - CAMINHO_CENA_ABERTURA assume "res://scenes/abertura.tscn".
## - CAMINHO_SHADER_PULSO / CAMINHO_SHADER_MASCARA assumem uma
##   pasta "res://shaders/" -- salve os dois .gdshader que vieram
##   junto com o arquivo original da FASE 1 lá (ou ajuste o caminho).
## - NOME_FASE está como "SOUL EATER — PAPERMOON".
## - BEATMAP_SOUL pode ficar vazio: o motor multibanda escuta a música
##   em tempo real e cria toques/arrastes conforme pulsação, energia e timbre.
## - Esta cena usa o motor musical dinâmico da fase Soul / Soul Eater,
##   mantendo a mesma arquitetura reutilizável: assets e perfil definem a
##   personalidade da fase. Para outra música, duplique este
##   arquivo e troque os caminhos e PERFIL_JOGABILIDADE.
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
const CAMINHO_IMAGEM_FASE: String = "res://images/soul.jpeg"
const NOME_FASE: String = "SOUL EATER - PAPERMOON"
const DURACAO_APRESENTACAO_SEG: float = 4.0

# --- Contagem regressiva de início ---
const CAMINHO_VIDEO_CONTAGEM: String = "res://medias/soul.ogv"
# Contagem limpa: somente 3, 2 e 1, um número por segundo.
# Música e vídeo já estão rodando durante esta contagem.
const DURACAO_CONTAGEM_SEG: float = 3.0
const CONTAGEM_NUMERO_INICIAL: int = 3

# --- Vídeo de fundo do jogo em si ---
const CAMINHO_VIDEO_FUNDO: String = "res://medias/soul.ogv"

# Fallback automático: se você escreveu a pasta como medias em vez de mmedias,
# o script também tenta encontrar o vídeo em res://medias/soul.ogv.
const CAMINHO_VIDEO_FALLBACK_1: String = "res://medias/soul.ogv"

# --- Música ---
const CAMINHO_MUSICA: String = "res://songs/soul.mp3"
const BUS_MUSICA_HIT: String = "HitMusic"

# A duração real é lida diretamente do arquivo de áudio com get_length().
# Este valor só é usado se o importador não conseguir informar a duração.
const DURACAO_PARTIDA_FALLBACK_SEG: float = 115.0
# A fase termina exatamente na cauda audível da música, sem acrescentar tempo artificial.
const MARGEM_FINAL_MUSICA_SEG: float = 0.0

# Sincronia real: o analisador lê a música antes do atraso e o jogador ouve a
# mesma batida DETECCAO_ANTECIPACAO_SEG depois, exatamente quando o orbe chega.
const SINCRONIA_AUDIO_COM_ATRASO: bool = true

# --- Retorno ---
const CAMINHO_CENA_ABERTURA: String = "res://scenes/opening.tscn"

# --- Os 8 pontos ---
const NUM_PONTOS: int = 8
const LETRAS_PONTOS: Array[String] = ["A", "B", "C", "D", "E", "F", "G", "H"]
const INPUTS_PONTOS: Array[String] = [
	"input_a",
	"input_b",
	"input_c",
	"input_d",
	"input_e",
	"input_f",
	"input_g",
	"input_h",
]

# --- Timing (ajuste fino da jogabilidade) ---
const JANELA_ACERTO_SEG: float = 0.18  # +- tempo pra contar como acerto
const JANELA_PERFEITO_SEG: float = 0.075  # centro da batida: resposta precisa
const TEMPO_APROXIMACAO_SEG: float = 1.0  # quanto antes o ponto começa a "carregar"

# --- Pontuação ---
const PONTOS_POR_ACERTO_TOQUE: int = 150
const PONTOS_POR_ACERTO_BOM: int = 90
const PONTOS_POR_ACERTO_ARRASTE: int = 250

# Cores do julgamento visual. Elas não prolongam nem alteram o LED físico.
const COR_LED_PERFEITO: Color = Color(0.16, 1.0, 0.30, 1.0)
const COR_LED_BOM: Color = Color(1.0, 0.82, 0.12, 1.0)

# --- Volume dinâmico (efeito "Guitar Hero") ---
# O ganho é aplicado no BARRAMENTO, depois do analisador e do delay de sincronia.
# Assim, acerto e erro alteram o volume que já está chegando ao alto-falante,
# sem esperar DETECCAO_ANTECIPACAO_SEG para a mudança ficar audível.
const VOLUME_MAX_DB: float = 0.0
const VOLUME_MIN_DB: float = -16.0
const VOLUME_PASSO_ERRO_DB: float = -4.0
const VOLUME_PASSO_ACERTO_DB: float = 4.0

# Perfil reutilizável da fase. Para outras músicas/telas, normalmente basta trocar
# os caminhos dos assets e estes parâmetros; o motor continua lendo o áudio real.
const PERFIL_JOGABILIDADE: Dictionary = {
	# Soul usa um perfil de rock de abertura: bateria e ataques de guitarra
	# geram toques mais frequentes; arrastes ficam para transições melódicas e
	# tempos fortes do compasso, evitando tubos aleatórios em toda batida.
	"nome": "PAPERMOON_ROCK_DINAMICO",
	"sensibilidade": 1.08,
	"densidade": 0.90,
	"preferencia_arraste": 0.27,
	"complexidade_arraste": 0.62,
	"distancia_saltos": 0.86,
	"janela_toque_extra": 0.02,
}

# --- Cores neon Soul Eater: magenta, roxo, amarelo lunar e vermelho de erro. ---
const COR_NEON_VERDE: Color = Color(0.96, 0.06, 0.48)
const COR_NEON_CIANO: Color = Color(0.62, 0.22, 1.0)
const COR_ACERTO: Color = Color(1.0, 0.88, 0.18)
const COR_ERRO: Color = Color(1.0, 0.30, 0.36)

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
const BEATMAP_SOUL: Array = [
# {"tipo": "toque", "tempo": 1.20, "ponto": 0},
# {"tipo": "arraste", "tempo": 8.00, "tempo_fim": 8.90, "caminho": [2, 5, 1]},
]

## ------------------------------------------------------------
## DETECÇÃO DE BATIDA EM TEMPO REAL (grave/bumbo)
## Se BEATMAP_SOUL estiver vazio, o jogo não usa mais fases fixas por
## relógio/aleatórias -- ele "ouve" a música de verdade: um AudioEffectSpectrumAnalyzer
## no barramento Master mede a energia nas frequências graves (onde vive o bumbo/
## baixo) a cada frame, compara com a média recente, e considera "batida" sempre que
## a energia atual dá um pico bem acima da média. Cada batida detectada nasce um
## evento de toque (ou, de vez em quando, um arraste) praticamente na hora.
##
## Limitação física importante: como a detecção é ao vivo (ouvindo a música tocando
## de verdade), o jogo só "sabe" que a batida aconteceu no instante em que ela
## acontece -- diferente de um beatmap pré-escrito, não dá pra avisar o jogador com
## 1 segundo de antecedência (isso exigiria prever o futuro da música). Por isso os
## eventos nascidos de batida usam uma janela de acerto um pouco mais generosa
## (JANELA_ACERTO_BEAT_SEG) que o toque tradicional.
## ------------------------------------------------------------
const DETECCAO_BEAT_ATIVADA: bool = true
const DETECCAO_FREQ_MIN_HZ: float = 40.0
const DETECCAO_FREQ_MAX_HZ: float = 160.0
const DETECCAO_JANELA_MEDIA_SEG: float = 0.65  # quanto tempo de histórico usa pra calcular a "média" de grave
const DETECCAO_LIMIAR_MULTIPLICADOR: float = 1.42  # a energia atual precisa ser X vezes a média pra virar batida
const DETECCAO_LIMIAR_MINIMO: float = 0.0009  # piso absoluto, evita disparo falso em trechos quase silenciosos
const DETECCAO_COOLDOWN_SEG: float = 0.20  # tempo mínimo entre duas batidas, pra não disparar em dobro
const DETECCAO_ANTECIPACAO_SEG: float = 1.05  # tempo visual completo: a bola sai do centro e chega ao Tazo
const JANELA_ACERTO_BEAT_SEG: float = 0.26  # janela de acerto (toque) só pra eventos nascidos de batida
const DETECCAO_CHANCE_ARRASTE: float = 0.22  # a cada batida, chance de virar arraste em vez de toque simples
const DETECCAO_ARRASTE_DURACAO_SEG: float = 1.15  # tempo que o jogador tem pra completar um arraste nascido de batida

# Motor musical multibanda e adaptativo. Não usa fases fixas por relógio:
# grave identifica pulsação/bumbo, médios identificam corpo melódico e agudos
# ajudam a reconhecer ataques e transições. A média é exponencial, sem criar
# Arrays/Dictionaries a cada frame, reduzindo picos de CPU e coleta de memória.
const ANALISE_INTERVALO_SEG: float = 0.025
const ANALISE_GRAVE_MIN_HZ: float = 38.0
const ANALISE_GRAVE_MAX_HZ: float = 190.0
const ANALISE_MEDIO_MIN_HZ: float = 190.0
const ANALISE_MEDIO_MAX_HZ: float = 2200.0
const ANALISE_AGUDO_MIN_HZ: float = 2200.0
const ANALISE_AGUDO_MAX_HZ: float = 8200.0
const ANALISE_ALPHA_BASE: float = 0.045
const ANALISE_ALPHA_SECAO: float = 0.075
const ANALISE_LIMIAR_RAZAO_BASE: float = 1.28
const ANALISE_LIMIAR_ATAQUE: float = 0.055
const ANALISE_COOLDOWN_MIN_SEG: float = 0.16
const ANALISE_COOLDOWN_MAX_SEG: float = 0.38
const ANALISE_INTERVALO_BEAT_MIN_SEG: float = 0.24
const ANALISE_INTERVALO_BEAT_MAX_SEG: float = 1.10

# Layout enquadrado: nenhum efeito foi removido; posições e campos foram apenas contraídos para caber no círculo.
const RAIO_POS_PONTOS_RATIO: float = 0.720
const RAIO_VISUAL_PONTO_RATIO: float = 0.066
const RAIO_TOQUE_EXTRA_RATIO: float = 1.75
const RAIO_SEGURO_EFEITOS_RATIO: float = 0.948
const ESCALA_CAMPO_CENTRAL: float = 0.90
const ESCALA_ALCANCE_PARTICULAS: float = 0.76

# Ajuste vertical exclusivo da fase Soul.
# Valores negativos sobem os oito Tazos e o conjunto do HUD.
const DESLOCAMENTO_Y_PONTOS_RATIO: float = -0.032
const DESLOCAMENTO_Y_HUD_RATIO: float = -0.038

# Identidade visual Soul Eater: roxo/magenta e branco.
const COR_SOUL_VERMELHO: Color = Color(0.72, 0.035, 0.92, 1.0)
const COR_SOUL_BRANCO: Color = Color(1.0, 0.985, 1.0, 1.0)

# Tazo acertado permanece aceso só o suficiente para o jogador perceber o hit.
const TEMPO_TAZO_POS_ACERTO_SEG: float = 0.20
const TEMPO_TAZO_POS_CHECKPOINT_SEG: float = 0.16

# Arraste real por "tubo": não basta tocar o próximo Tazo. O caminho percorrido
# entre os dois checkpoints também precisa permanecer dentro do corredor.
const ARRASTE_RAIO_CHECKPOINT_EXTRA: float = 1.30
const ARRASTE_RAIO_CHECKPOINT_RATIO: float = 1.20

# Tubo mais tolerante:
# - RAIO_TUBO define a faixa principal aceita.
# - LIMITE_SAIDA cria uma segunda margem invisível para absorver pequenas imprecisões
#   do touchscreen sem transformar o arraste em um caminho livre.
# - o jogador ainda pode retornar ao tubo durante alguns milissegundos antes da falha.
const ARRASTE_RAIO_TUBO_RATIO: float = 0.92
const ARRASTE_LIMITE_SAIDA_TUBO_RATIO: float = 1.28
const ARRASTE_TEMPO_FORA_TUBO_TOLERADO_SEG: float = 0.24
const ARRASTE_PROGRESSO_MINIMO_SEGMENTO: float = 0.74
const ARRASTE_AMOSTRA_MIN_PX: float = 7.0
const ARRASTE_MAX_AMOSTRAS_MOVIMENTO: int = 20
const ARRASTE_TOLERANCIA_FINAL_SEG: float = 0.58

# Hover tecnológico que acompanha a projeção real do dedo sobre o tubo atual.
const ARRASTE_HOVER_TUBO_ATIVO: bool = true
const ARRASTE_HOVER_COMPRIMENTO_RATIO: float = 2.75
const ARRASTE_HOVER_PULSO_VELOCIDADE: float = 92.0

# Teste no PC: deixa o mouse visível para calibrar a moldura touch.
# IMPORTANTE: como o TOQUE agora só é resolvido pelos inputs físicos input_a..input_h,
# o touch/mouse continua reservado aos gestos de ARRASTE.
const MOUSE_VISIVEL_TESTE: bool = true

# Rastro completo preservado. A estabilidade vem do bloqueio de arrastes simultâneos e da validação contínua.
const ARRASTE_RASTRO_DURACAO_SEG: float = 0.68
const ARRASTE_RASTRO_MAX_PONTOS: int = 42
const ARRASTE_RASTRO_DIST_MIN_PX: float = 6.0
const ARRASTE_SETAS_ATIVAS_BRILHO: float = 1.35
const TEMPO_ORBE_SEG: float = 1.05

# Combo permanece visível por mais tempo depois de cada hit.
const TEMPO_COMBO_VISIVEL_SEG: float = 1.75
const TEMPO_FADE_COMBO_SEG: float = 0.28

# --- Desempenho ---
const FPS_ALVO: int = 60
# A lógica/input continua em 60 FPS. Apenas o redesenho dos efeitos Node2D é
# desacoplado e adaptativo, evitando que um trecho pesado do OGV congele o jogo.
const VISUAL_FPS_NORMAL: float = 45.0
const VISUAL_FPS_REDUZIDO: float = 28.0
const VISUAL_LIMIAR_REDUZIR_SEG: float = 1.0 / 43.0
const VISUAL_LIMIAR_RECUPERAR_SEG: float = 1.0 / 52.0
const VISUAL_TEMPO_REDUZIR_SEG: float = 0.55
const VISUAL_TEMPO_RECUPERAR_SEG: float = 2.20
const CAMINHO_TAZO_SCENE: String = "res://entities/tazo.tscn"
const TAZO_ANIM_IDLE: String = "idle"
const TAZO_ANIM_ACESO: String = "hig"  # nome que você criou no AnimatedSprite2D
const TAZO_DIAMETRO_RATIO: float = 0.290
const TAZO_IDLE_ANIMAR: bool = false
const TAZO_ACESO_USAR_FRAME_FINAL: bool = true
const TAZO_BRILHO_ATIVO: float = 1.55
const TAZO_VELOCIDADE_ACENDER: float = 8.5
const TAZO_VELOCIDADE_APAGAR: float = 5.8
const TAZO_ESCALA_ATIVA_EXTRA: float = 0.075
const TAZO_PULSO_ESCALA: float = 0.018
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
const VIDEO_FUNDO_ALPHA: float = 0.43

# Equalizador circular puramente visual. Ele apenas lê o analisador de áudio e
# desenha na borda; não participa da fila, duração ou comunicação dos LEDs.
const ONDA_BORDA_ATIVA: bool = true
const ONDA_BORDA_RAIO_INTERNO_RATIO: float = 0.875
const ONDA_BORDA_RAIO_BASE_RATIO: float = 0.892
const ONDA_BORDA_AMPLITUDE_REPOUSO_RATIO: float = 0.006
const ONDA_BORDA_AMPLITUDE_MAX_RATIO: float = 0.044
const ONDA_BORDA_ESPESSURA_RATIO: float = 0.0038
const ONDA_BORDA_SEGMENTOS_NORMAL: int = 72
const ONDA_BORDA_SEGMENTOS_REDUZIDO: int = 48
const ONDA_ACERTO_INCREMENTO: float = 0.060
const ONDA_ACERTO_DECAIMENTO_SEG: float = 0.030
const ONDA_PULSO_DECAIMENTO_SEG: float = 2.55
const ONDA_PULSO_TOQUE: float = 0.34
const ONDA_PULSO_ARRASTE: float = 0.38

# Proporção real do vídeo (largura / altura) -- AJUSTE pra bater com o soul.ogv
# de verdade (16:9 = 1.777, 4:3 = 1.333, quadrado = 1.0, retrato 9:16 = 0.5625 etc.).
# O vídeo é sempre mostrado por INTEIRO dentro do círculo, sem cortar nem esticar
# ("sem zoom"): se a proporção não for quadrada, sobra uma faixa preta dentro do
# círculo (o fundo por trás do vídeo) em vez de cortar pedaço da imagem.
const VIDEO_FUNDO_PROPORCAO_LARGURA_ALTURA: float = 16.0 / 9.0

# Modal final: tempo para inserir crédito/continuar antes de voltar à abertura.
const TEMPO_MODAL_CONTINUAR_SEG: float = 10.0
const CAMINHO_RECORDES: String = "user://hit_music_records.json"
const CAMINHO_IMAGEM_MODAL: String = "res://images/soul.jpeg"
const DURACAO_TRANSICAO_FINAL_SEG: float = 0.62
const DURACAO_ABRIR_MODAL_SEG: float = 0.48
const DURACAO_FECHAR_MODAL_SEG: float = 0.32

# Cada ponto recebe uma cor diferente para a bola/orbe que sai do centro.
const CORES_ORBE_POR_PONTO: Array = [
	Color(1.0, 0.18, 0.82, 1.0),  # A rosa
	Color(0.15, 0.88, 1.0, 1.0),  # B ciano
	Color(1.0, 0.78, 0.08, 1.0),  # C amarelo
	Color(0.32, 1.0, 0.35, 1.0),  # D verde
	Color(0.62, 0.25, 1.0, 1.0),  # E roxo
	Color(1.0, 0.32, 0.12, 1.0),  # F laranja
	Color(0.1, 0.45, 1.0, 1.0),  # G azul
	Color(1.0, 0.08, 0.22, 1.0),  # H vermelho
]

const COR_TOQUE_ORBE: Color = Color(1.0, 0.18, 0.82, 1.0)
const COR_SLIDE_AMARELO: Color = Color(1.0, 0.82, 0.06, 1.0)
const COR_SLIDE_PRETO: Color = Color(0.02, 0.015, 0.005, 1.0)
const COR_SLIDE_COMPLETO: Color = Color(0.25, 1.0, 0.45, 1.0)

# --- Comunicação persistente dos LEDs: COM5 / 9600 ---
# A abertura e o jogo usam exatamente os mesmos caminhos em user://.
# Assim, a ponte PowerShell continua aberta durante change_scene_to_file().
const SERIAL_ATIVADO: bool = true
const SERIAL_PORTA: String = "COM5"
const SERIAL_BAUD: int = 9600
const SERIAL_HEARTBEAT_INTERVALO_MS: int = 500
const SERIAL_VERIFICACAO_INTERVALO_MS: int = 700
const SERIAL_HEARTBEAT_TIMEOUT_SEG: float = 8.0
const SERIAL_ALIVE_TIMEOUT_SEG: float = 2.5
const SERIAL_STARTING_TIMEOUT_SEG: float = 6.0
const SERIAL_INTERVALO_ENTRE_COMANDOS_MS: int = 18

var _serial_base_dir: String = ""
var _serial_spool_dir: String = ""
var _serial_heartbeat_path: String = ""
var _serial_alive_path: String = ""
var _serial_ready_path: String = ""
var _serial_starting_path: String = ""
var _serial_ultimo_heartbeat_msec: int = -999999
var _serial_ultima_verificacao_msec: int = -999999
var _serial_sequencia: int = 0
var _serial_inicializado: bool = false
var _serial_spawn_solicitado: bool = false
var _serial_pendentes: Array[String] = []
var _serial_aviso_mostrado: bool = false
var _serial_pronta_anunciada: bool = false
var _serial_conexao_aviso_mostrado: bool = false
var _serial_tentativa_inicio_msec: int = -1

var _led_assinatura_atual: String = ""
# Oito canais físicos independentes. O contador representa quantos discos vivos
# possuem cada Tazo; o LED só apaga quando o último proprietário termina.
var _led_assinaturas_por_ponto: Array[String] = ["", "", "", "", "", "", "", ""]
var _led_donos_por_ponto: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0]
var _shader_tazo_cache: Shader = null

# --- Nodes internos ---
var _video_fundo: VideoStreamPlayer
var _mascara_layer: CanvasLayer
var _mascara_rect: ColorRect
var _mascara_mat: ShaderMaterial
var _musica_player: AudioStreamPlayer
var _musica_inicio_msec: int = -1
var _duracao_musica_seg: float = DURACAO_PARTIDA_FALLBACK_SEG
var _duracao_total_jogo_seg: float = DURACAO_PARTIDA_FALLBACK_SEG
var _musica_fonte_finalizada: bool = false
var _musica_fim_fonte_msec: int = -1
var _ultimo_tempo_musica_seg: float = 0.0
var _indice_bus_musica: int = -1

var _pontos: Array = []  # Array[Node2D] — instâncias de entities/tazo.tscn
var _ponto_raios: Array = []
var _ponto_sprites: Array = []
var _ponto_estados: Array = []
var _ponto_posicoes_fixas: Array[Vector2] = []
var _ponto_niveis_visuais: Array[float] = []
var _ponto_flash_inicio_msec: Array[int] = []
var _ponto_flash_fim_msec: Array[int] = []
var _ponto_flash_cores: Array[Color] = []
var _ponto_apagar_em_msec: Array[int] = []
var _beatmap: Array = []
var _indice_beatmap: int = 0
var _eventos_ativos: Array = []

# Detecção de batida em tempo real (grave/bumbo) -- ver bloco de constantes DETECCAO_*.
var _usando_deteccao_beat: bool = false
var _spectrum_instance: AudioEffectSpectrumAnalyzerInstance = null
var _ultimo_beat_msec: int = -999999
var _ultimo_ponto_beat: int = 0

# Estado do motor musical. A análise só produz descritores/eventos e coloca tudo
# em uma fila; a jogabilidade consome a fila separadamente no relógio do áudio.
var _fila_eventos_musicais: Array = []
var _analise_acumulador: float = 0.0
var _analise_aquecida: bool = false
var _media_grave: float = 0.0001
var _media_medio: float = 0.0001
var _media_agudo: float = 0.0001
var _media_total: float = 0.0001
var _energia_total_anterior: float = 0.0
var _energia_secao: float = 1.0
var _intervalos_beat: Array[float] = []
var _intervalo_beat_estimado: float = 0.50
var _bpm_estimado: float = 120.0
var _ultimo_beat_tempo_musica: float = -999.0
var _contador_batidas: int = 0
var _direcao_musical: int = 1
var _ultimo_evento_musical_seg: float = -999.0
var _ultimo_tipo_evento_musical: String = ""

# Estado contínuo do equalizador visual da borda.
var _onda_energia: float = 0.0
var _onda_grave: float = 0.0
var _onda_medio: float = 0.0
var _onda_agudo: float = 0.0
var _onda_media_grave: float = 0.0001
var _onda_media_medio: float = 0.0001
var _onda_media_agudo: float = 0.0001
var _onda_media_total: float = 0.0001
var _onda_visual_aquecida: bool = false
var _onda_acerto_nivel: float = 0.0
var _onda_pulso_hit: float = 0.0
var _onda_fase: float = 0.0

var _pontuacao: int = 0
var _combo_atual: int = 0
var _combo_maximo: int = 0
var _combo_visivel_ate_msec: int = 0
var _combo_fade_em_andamento: bool = false
var _label_pontuacao: Label
var _label_combo: Label
var _tween_combo: Tween

var _volume_musica_db: float = VOLUME_MAX_DB

# Governador visual: mede delta médio e reduz somente a frequência dos desenhos
# decorativos. Áudio, input, hit windows, LEDs e geração de eventos não mudam.
var _visual_acumulador: float = 0.0
var _frame_delta_medio: float = 1.0 / 60.0
var _visual_sobrecarga_acumulada: float = 0.0
var _visual_recuperacao_acumulada: float = 0.0
var _visual_reduzido: bool = false
var _qualidade_visual: float = 1.0

var _tempo_restante: float = DURACAO_PARTIDA_FALLBACK_SEG
var _partida_encerrada: bool = false
var _finalizacao_em_andamento: bool = false
var _finalizacao_layer: CanvasLayer
var _finalizacao_overlay: ColorRect
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
var _arraste_progresso_segmento: float = 0.0
var _arraste_fora_tubo_desde_msec: int = -1
var _efeitos_passagem_tubo: Array = []
var _ultimo_touch_msec: int = -999999
var _touch_ativo_id: int = -1

# Destaque de hover/clique: qual Tazo está mais perto do dedo/mouse agora, em tempo
# real -- independente de estar certo, errado ou fazer parte de algum evento do beatmap.
var _hover_indice_atual: int = -1

# Estado da cena e assets da apresentação/contagem.
var _estado_jogo: int = EstadoJogo.APRESENTACAO
var _sprite_apresentacao: Sprite2D
var _label_nome_fase: Label
var _label_contagem: Label
var _contagem_restante: float = DURACAO_CONTAGEM_SEG
var _contagem_ultimo_numero_led: int = -1
var _contagem_etapa_visual: int = -1
var _tween_contagem: Tween

# Modal final de crédito/continuação.
var _modal_continuar_ativo: bool = false
var _modal_countdown_restante: float = TEMPO_MODAL_CONTINUAR_SEG
var _modal_layer: CanvasLayer
var _modal_label_titulo: Label
var _modal_label_score: Label
var _modal_label_countdown: Label
var _modal_label_acao: Label
var _modal_ultimo_numero_led: int = -1
var _modal_fundo_escuro: ColorRect
var _modal_painel: Panel
var _modal_imagem_fundo: TextureRect
var _modal_overlay_imagem: ColorRect
var _modal_barra_tempo: ProgressBar
var _modal_em_transicao: bool = false
var _modal_acao_apos_fechar: Callable = Callable()
var _recorde_tela: int = 0
var _recorde_geral: int = 0
var _novo_recorde_tela: bool = false
var _novo_recorde_geral: bool = false


# ---------------------------------------------------------------
# CICLO DE VIDA
# ---------------------------------------------------------------
func _ready() -> void:
	Engine.max_fps = FPS_ALVO
	Input.set_mouse_mode(
		Input.MOUSE_MODE_VISIBLE if MOUSE_VISIVEL_TESTE else Input.MOUSE_MODE_HIDDEN
	)  # visível no teste; depois pode trocar MOUSE_VISIVEL_TESTE para false
	_rng.randomize()
	_validar_inputs_pontos()
	_arduino_inicializar()
	_configurar_deteccao_beat()
	_preparar_duracao_musica()

	# Todo beatmap usa o tempo real da música. Os primeiros três segundos pertencem
	# à contagem 3, 2, 1; depois a tela é liberada sem reiniciar áudio ou vídeo.
	_beatmap = BEATMAP_SOUL.duplicate(true)
	if not _beatmap.is_empty():
		push_warning(
			"Usando o BEATMAP_SOUL escrito à mão -- a detecção de batida em tempo real fica desligada nesta partida."
		)
	elif DETECCAO_BEAT_ATIVADA and _spectrum_instance != null:
		# Sem beatmap manual: em vez de simular fases fixas por relógio, o jogo escuta
		# a música de verdade e nasce os eventos ao vivo (ver _atualizar_deteccao_beat).
		# _beatmap fica vazio de propósito -- não tem como pré-calcular o futuro real da música.
		_usando_deteccao_beat = true
		push_warning(
			"BEATMAP_SOUL vazio -- usando detecção de batida em tempo real (grave/bumbo) da música soul."
		)
	else:
		# Não cria mais uma sequência aleatória sem relação com o áudio. Se o analisador
		# não estiver disponível, a fase permanece segura e informa o problema.
		push_error(
			"Sem beatmap manual e sem analisador de áudio. Nenhum Tazo será gerado até o barramento musical ser corrigido."
		)
		_beatmap = []
	_beatmap.sort_custom(func(a, b): return a["tempo"] < b["tempo"])
	_configurar_atraso_bus_musica()
	_aplicar_volume_musica_imediato(VOLUME_MAX_DB)
	_recalcular_duracao_total_jogo()

	_preparar_base_circular()
	_iniciar_apresentacao_fase()


func _process(delta: float) -> void:
	# Atualização exclusivamente visual: a música move a onda e cada acerto injeta
	# um pulso curto. Nenhum estado físico ou comando serial é alterado aqui.
	var velocidade_onda: float = lerp(
		1.25,
		3.20,
		clamp((_bpm_estimado - 70.0) / 120.0, 0.0, 1.0)
	)
	_onda_fase = fmod(_onda_fase + delta * velocidade_onda, TAU * 1024.0)
	_onda_acerto_nivel = move_toward(
		_onda_acerto_nivel, 0.0, delta * ONDA_ACERTO_DECAIMENTO_SEG
	)
	_onda_pulso_hit = move_toward(
		_onda_pulso_hit, 0.0, delta * ONDA_PULSO_DECAIMENTO_SEG
	)
	_atualizar_onda_espectro_visual()

	_arduino_tick_serial()
	_atualizar_apagamentos_tazos()
	_atualizar_transicoes_tazos(delta)
	_manter_tazos_fixos()
	_limpar_rastro_arraste_vencido()
	_limpar_efeitos_passagem_tubo()
	_atualizar_tolerancia_saida_tubo()
	_atualizar_visibilidade_combo()
	_atualizar_deteccao_beat(delta)
	_atualizar_governador_visual(delta)

	if _modal_continuar_ativo:
		_processar_modal_continuar(delta)
		return

	match _estado_jogo:
		EstadoJogo.CONTAGEM:
			_atualizar_contagem(delta)
		EstadoJogo.JOGANDO:
			_processar_frame_jogo(delta)


func _atualizar_governador_visual(delta: float) -> void:
	# Média exponencial evita reagir a um frame isolado. A troca de qualidade possui
	# histerese para não ficar alternando quando o vídeo muda de cena/cor.
	_frame_delta_medio = lerp(_frame_delta_medio, clamp(delta, 0.0, 0.10), 0.06)

	if _frame_delta_medio > VISUAL_LIMIAR_REDUZIR_SEG:
		_visual_sobrecarga_acumulada += delta
		_visual_recuperacao_acumulada = 0.0
	elif _frame_delta_medio < VISUAL_LIMIAR_RECUPERAR_SEG:
		_visual_recuperacao_acumulada += delta
		_visual_sobrecarga_acumulada = max(_visual_sobrecarga_acumulada - delta, 0.0)
	else:
		_visual_sobrecarga_acumulada = max(_visual_sobrecarga_acumulada - delta * 0.35, 0.0)
		_visual_recuperacao_acumulada = max(_visual_recuperacao_acumulada - delta * 0.35, 0.0)

	if not _visual_reduzido and _visual_sobrecarga_acumulada >= VISUAL_TEMPO_REDUZIR_SEG:
		_visual_reduzido = true
		_qualidade_visual = 0.72
		_visual_sobrecarga_acumulada = 0.0
	elif _visual_reduzido and _visual_recuperacao_acumulada >= VISUAL_TEMPO_RECUPERAR_SEG:
		_visual_reduzido = false
		_qualidade_visual = 1.0
		_visual_recuperacao_acumulada = 0.0

	if _estado_jogo != EstadoJogo.JOGANDO:
		return

	var fps_visual: float = VISUAL_FPS_REDUZIDO if _visual_reduzido else VISUAL_FPS_NORMAL
	_visual_acumulador += delta
	var passo: float = 1.0 / max(fps_visual, 1.0)
	if _visual_acumulador >= passo:
		_visual_acumulador = fmod(_visual_acumulador, passo)
		queue_redraw()


func _draw() -> void:
	if _estado_jogo != EstadoJogo.JOGANDO:
		return

	_desenhar_area_dedicada_central()
	_desenhar_nucleo_central()
	_desenhar_efeitos_tazos_modernos()
	_desenhar_anel_volume()
	_desenhar_onda_borda_musical()

	var tempo_musica: float = _tempo_atual_musica()

	# Todos os caminhos continuam visíveis. O caminho em foco recebe o brilho completo
	# e os demais mantêm o efeito secundário original, sem serem removidos.
	var evento_foco_arraste: Dictionary = (
		_arraste_evento_atual if _arraste_evento_atual != null else _obter_proximo_arraste_foco()
	)

	for evento in _eventos_ativos:
		if evento.get("resolvido", false):
			continue
		if evento["tipo"] == "arraste":
			var em_foco: bool = (
				(not evento_foco_arraste.is_empty()) and evento == evento_foco_arraste
			)
			_desenhar_linha_arraste(evento, em_foco)

	# Hover do tubo vem por cima do caminho, mas por baixo do rastro do dedo.
	# Assim ele mostra exatamente onde o jogador está sem esconder os efeitos existentes.
	_desenhar_hover_tubo_atual()
	_desenhar_rastro_arraste()
	_desenhar_efeitos_passagem_tubo()

	for evento in _eventos_ativos:
		if evento.get("resolvido", false):
			continue
		if evento["tipo"] == "toque":
			_desenhar_orbe_toque(evento, tempo_musica)

	_desenhar_hover_destaque()


func _desenhar_area_dedicada_central() -> void:
	# Centro maior e mais vivo: o raio do meio agora ocupa mais área,
	# deixando a tela com aparência de arcade japonês/chinês moderno.
	var tempo: float = Time.get_ticks_msec() / 1000.0
	var pulso: float = sin(tempo * 2.2) * 0.5 + 0.5
	var giro: float = fmod(tempo * 0.55, TAU)
	var escala_campo: float = ESCALA_CAMPO_CENTRAL

	# Base escura maior, para segurar melhor os efeitos que nascem no centro.
	draw_circle(_centro_tela, _raio_circulo_px * escala_campo * 0.72, Color(0, 0, 0, 0.070))
	draw_circle(
		_centro_tela,
		_raio_circulo_px * escala_campo * 0.58,
		Color(COR_NEON_CIANO.r, COR_NEON_CIANO.g, COR_NEON_CIANO.b, 0.018 + pulso * 0.012)
	)

	# Anéis internos com mais leitura visual.
	draw_arc(
		_centro_tela,
		_raio_circulo_px * escala_campo * 0.54,
		0.0,
		TAU,
		72,
		Color(1, 1, 1, 0.040),
		1.4,
		true
	)
	draw_arc(
		_centro_tela,
		_raio_circulo_px * escala_campo * 0.67,
		giro,
		giro + PI * 1.38,
		72,
		Color(COR_NEON_CIANO.r, COR_NEON_CIANO.g, COR_NEON_CIANO.b, 0.105 + pulso * 0.035),
		2.7,
		true
	)
	draw_arc(
		_centro_tela,
		_raio_circulo_px * escala_campo * 0.79,
		-giro * 0.82 + PI * 0.18,
		-giro * 0.82 + PI * 1.72,
		72,
		Color(COR_NEON_VERDE.r, COR_NEON_VERDE.g, COR_NEON_VERDE.b, 0.092 + pulso * 0.032),
		2.8,
		true
	)
	draw_arc(
		_centro_tela,
		_raio_circulo_px * escala_campo * 0.90,
		giro * 0.56 - PI * 0.15,
		giro * 0.56 + PI * 1.10,
		72,
		Color(1.0, 0.78, 0.08, 0.055 + pulso * 0.025),
		2.0,
		true
	)
	draw_arc(
		_centro_tela,
		_raio_circulo_px * escala_campo * 0.965,
		0.0,
		TAU,
		80,
		Color(1, 1, 1, 0.033),
		1.2,
		true
	)

	# Pequenas marcas digitais no raio do meio, para dar vida sem poluir.
	for i in range(16 if not _visual_reduzido else 10):
		var a: float = giro + float(i) * TAU / 16.0
		var r1: float = (
			_raio_circulo_px * escala_campo * (0.60 + 0.025 * sin(float(i) * 1.7 + tempo * 3.2))
		)
		var r2: float = r1 + _raio_circulo_px * escala_campo * 0.018
		var p1: Vector2 = _centro_tela + Vector2(cos(a), sin(a)) * r1
		var p2: Vector2 = _centro_tela + Vector2(cos(a), sin(a)) * r2
		var cor: Color = COR_NEON_CIANO.lerp(
			COR_NEON_VERDE, 0.5 + 0.5 * sin(float(i) * 0.9 + tempo * 2.0)
		)
		draw_line(p1, p2, Color(cor.r, cor.g, cor.b, 0.10 + pulso * 0.05), 1.2, true)


func _ease_out_cubic(t: float) -> float:
	t = clamp(t, 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 3.0)


func _ease_in_out_cubic(t: float) -> float:
	t = clamp(t, 0.0, 1.0)
	if t < 0.5:
		return 4.0 * t * t * t
	return 1.0 - pow(-2.0 * t + 2.0, 3.0) / 2.0


func _raio_maximo_efeito_no_ponto(indice: int, desejado: float) -> float:
	if indice < 0 or indice >= _pontos.size():
		return desejado
	var distancia_centro: float = _centro_tela.distance_to(_pontos[indice].position)
	var disponivel: float = _raio_circulo_px * RAIO_SEGURO_EFEITOS_RATIO - distancia_centro
	return clamp(min(desejado, disponivel), 3.0, desejado)


func _limitar_pos_efeito_no_circulo(pos: Vector2, margem: float) -> Vector2:
	var deslocamento: Vector2 = pos - _centro_tela
	var limite: float = max(_raio_circulo_px * RAIO_SEGURO_EFEITOS_RATIO - margem, 1.0)
	if deslocamento.length() <= limite:
		return pos
	return _centro_tela + deslocamento.normalized() * limite


func _cor_orbe_por_ponto(indice: int) -> Color:
	if CORES_ORBE_POR_PONTO.is_empty():
		return COR_TOQUE_ORBE
	return CORES_ORBE_POR_PONTO[abs(indice) % CORES_ORBE_POR_PONTO.size()]


func _cor_caminho_evento(evento: Dictionary) -> Color:
	# Um caminho de arraste inteiro usa UMA cor só (a do primeiro Tazo), em vez de ir
	# misturando a cor de cada ponto por trecho. Assim, com o olhar, dá pra saber na
	# hora quais Tazos pertencem ao mesmo caminho -- principalmente quando dois
	# arrastes aparecem perto um do outro.
	if evento.is_empty():
		return COR_NEON_CIANO
	var caminho: Array = evento.get("caminho", [])
	if caminho.is_empty():
		return COR_NEON_CIANO
	return _cor_orbe_por_ponto(int(caminho[0]))


func _obter_proximo_arraste_foco() -> Dictionary:
	# Entre os arrastes ativos (ainda não resolvidos), acha o que está mais perto de
	# vencer agora -- é ele que recebe o efeito completo enquanto o jogador ainda não
	# começou a arrastar o dedo.
	var tempo_musica: float = _tempo_atual_musica()
	var melhor: Dictionary = {}
	var melhor_distancia: float = 999999.0

	for evento in _eventos_ativos:
		if evento.get("resolvido", false):
			continue
		if evento.get("tipo", "") != "arraste":
			continue
		var distancia: float = abs(float(evento["tempo"]) - tempo_musica)
		if distancia < melhor_distancia:
			melhor_distancia = distancia
			melhor = evento

	return melhor


func _atualizar_hover(pos: Vector2) -> void:
	if _estado_jogo != EstadoJogo.JOGANDO:
		_hover_indice_atual = -1
		return
	_hover_indice_atual = _indice_ponto_mais_proximo(pos, ARRASTE_RAIO_CHECKPOINT_EXTRA)


func _desenhar_hover_destaque() -> void:
	# A mira tecnológica original foi preservada por completo: dois anéis,
	# quatro cantos em L, rotação, pulso e núcleo pressionado. Somente o campo
	# ao redor do Tazo foi contraído para permanecer na margem segura do círculo.
	if _hover_indice_atual < 0 or _hover_indice_atual >= _pontos.size():
		return

	var ponto: Node2D = _pontos[_hover_indice_atual]
	var raio_base: float = _ponto_raio(_hover_indice_atual)
	var cor: Color = _cor_orbe_por_ponto(_hover_indice_atual)
	var pulso: float = sin(Time.get_ticks_msec() / 140.0) * 0.5 + 0.5
	var pressionado: bool = _arraste_gesto_ativo

	var raio_anel: float = raio_base * (1.14 if pressionado else 1.22)
	var alpha_base: float = 0.90 if pressionado else 0.40
	var espessura: float = raio_base * (0.090 if pressionado else 0.055)

	draw_arc(
		ponto.position,
		raio_anel,
		0.0,
		TAU,
		48,
		Color(cor.r, cor.g, cor.b, alpha_base * (0.55 + pulso * 0.45)),
		espessura,
		true
	)
	draw_arc(
		ponto.position,
		raio_anel * 1.10,
		0.0,
		TAU,
		48,
		Color(1, 1, 1, alpha_base * 0.28),
		max(1.0, espessura * 0.4),
		true
	)

	# Mesmos quatro cantos em L e a mesma rotação lenta, agora em um campo menor.
	var meia_diag: float = raio_anel * 1.10
	var giro_lento: float = Time.get_ticks_msec() / 900.0
	var tam_canto: float = raio_base * 0.22
	for i in range(4):
		var ang_base: float = giro_lento + PI / 4.0 + i * (PI / 2.0)
		var dir_radial: Vector2 = Vector2(cos(ang_base), sin(ang_base))
		var dir_tang: Vector2 = Vector2(-dir_radial.y, dir_radial.x)
		var centro_canto: Vector2 = ponto.position + dir_radial * meia_diag
		var p1: Vector2 = centro_canto - dir_radial * tam_canto
		var p3: Vector2 = centro_canto - dir_tang * tam_canto
		draw_line(
			p1,
			centro_canto,
			Color(cor.r, cor.g, cor.b, alpha_base * 0.85),
			max(1.4, espessura * 0.55),
			true
		)
		draw_line(
			centro_canto,
			p3,
			Color(cor.r, cor.g, cor.b, alpha_base * 0.85),
			max(1.4, espessura * 0.55),
			true
		)

	if pressionado:
		draw_circle(
			ponto.position, raio_base * (0.28 + pulso * 0.10), Color(1, 1, 1, 0.30 + pulso * 0.20)
		)


func _desenhar_orbe_toque(evento: Dictionary, tempo_musica: float) -> void:
	var indice_ponto: int = int(evento["ponto"])
	if indice_ponto < 0 or indice_ponto >= _pontos.size():
		return

	var cor_orbe: Color = _cor_orbe_por_ponto(indice_ponto)
	var alvo: Vector2 = _pontos[indice_ponto].position
	var direcao: Vector2 = (alvo - _centro_tela).normalized()
	# A bola volta a percorrer o caminho inteiro: nasce no núcleo e termina no Tazo.
	var origem: Vector2 = _centro_tela + direcao * (_raio_circulo_px * 0.14)

	var inicio: float = float(
		evento.get("tempo_visual_inicio", float(evento["tempo"]) - TEMPO_ORBE_SEG)
	)
	var fim: float = float(evento["tempo"])
	var t: float = clamp((tempo_musica - inicio) / max(fim - inicio, 0.001), 0.0, 1.0)
	var e: float = _ease_in_out_cubic(t)
	var pos: Vector2 = origem.lerp(alvo, e)
	var raio_base: float = _ponto_raio(indice_ponto)
	var raio: float = raio_base * lerp(0.42, 0.78, e)
	var tempo: float = Time.get_ticks_msec() / 1000.0
	var pulso: float = sin(Time.get_ticks_msec() / 72.0) * 0.5 + 0.5

	# Trilho mais vivo: neon duplo + fagulhas pequenas que acompanham a bola.
	draw_line(
		origem, pos, Color(cor_orbe.r, cor_orbe.g, cor_orbe.b, 0.070), max(1.0, raio * 0.42), true
	)
	draw_line(origem, pos, Color(1, 1, 1, 0.125), max(1.0, raio * 0.105), true)

	var comprimento: float = origem.distance_to(alvo)
	var qtd_fagulhas: int = int(
		clamp(int(comprimento / max(raio_base * 0.55, 18.0)), 4, 10 if not _visual_reduzido else 6)
	)
	var anim_fagulha: float = fmod(tempo * 1.55, 1.0)
	for s in range(qtd_fagulhas):
		var ts: float = fmod((float(s) / float(qtd_fagulhas)) + anim_fagulha, 1.0)
		if ts > e:
			continue
		var lateral: Vector2 = (
			Vector2(-direcao.y, direcao.x) * sin(float(s) * 2.31 + tempo * 7.0) * raio * 0.30
		)
		var p_spark: Vector2 = origem.lerp(pos, ts) + lateral
		var alpha_spark: float = clamp(0.38 * (1.0 - abs(e - ts)), 0.0, 0.38)
		var cor_spark: Color = cor_orbe.lerp(Color.WHITE, 0.35 + 0.28 * sin(float(s) + tempo * 2.0))
		draw_circle(
			p_spark,
			max(1.4, raio * 0.070),
			Color(cor_spark.r, cor_spark.g, cor_spark.b, alpha_spark)
		)

	# Ondas um pouco mais presentes, mas ainda controladas pelo tamanho do Tazo.
	var onda_tempo: float = fmod(Time.get_ticks_msec() / 500.0, 1.0)
	for k in range(2):
		var atraso: float = float(k) * 0.18
		var t_onda: float = clamp(e - atraso + onda_tempo * 0.08, 0.0, 1.0)
		var pos_onda: Vector2 = origem.lerp(pos, t_onda)
		var raio_onda: float = raio * (0.70 + onda_tempo * 0.72 + float(k) * 0.12)
		var alpha_onda: float = clamp((1.0 - abs(t_onda - e)) * 0.31, 0.0, 0.31)
		draw_arc(
			pos_onda,
			raio_onda,
			0.0,
			TAU,
			24,
			Color(cor_orbe.r, cor_orbe.g, cor_orbe.b, alpha_onda),
			1.65,
			true
		)
		draw_arc(
			pos_onda, raio_onda * 0.55, 0.0, TAU, 18, Color(1, 1, 1, alpha_onda * 0.56), 1.10, true
		)

	# Bola principal agora conversa com o Tazo: viva, mas sem virar um disco gigante.
	draw_circle(pos, raio * 1.18, Color(cor_orbe.r, cor_orbe.g, cor_orbe.b, 0.13 + pulso * 0.10))
	draw_circle(pos, raio * 0.96, Color(cor_orbe.r, cor_orbe.g, cor_orbe.b, 0.90))
	draw_circle(pos, raio * 0.43, Color(1.0, 1.0, 1.0, 0.94))
	draw_arc(pos, raio * (1.02 + pulso * 0.10), 0.0, TAU, 28, Color(1, 1, 1, 0.80), 2.0, true)
	draw_arc(
		pos,
		raio * (1.18 + pulso * 0.14),
		-PI * 0.25,
		PI * 1.15,
		24,
		Color(cor_orbe.r, cor_orbe.g, cor_orbe.b, 0.62),
		1.85,
		true
	)

	if MOSTRAR_LETRA_ORBE:
		var fonte: Font = ThemeDB.fallback_font
		var tam_fonte: int = int(raio * 0.72)
		var texto: String = LETRAS_PONTOS[indice_ponto]
		var largura: float = (
			fonte.get_string_size(texto, HORIZONTAL_ALIGNMENT_CENTER, -1, tam_fonte).x
		)
		draw_string(
			fonte,
			Vector2(pos.x - largura / 2.0, pos.y + tam_fonte * 0.32),
			texto,
			HORIZONTAL_ALIGNMENT_CENTER,
			-1,
			tam_fonte,
			Color(0, 0, 0, 0.65)
		)
		draw_string(
			fonte,
			Vector2(pos.x - largura / 2.0, pos.y + tam_fonte * 0.32 - 1.0),
			texto,
			HORIZONTAL_ALIGNMENT_CENTER,
			-1,
			tam_fonte,
			Color.WHITE
		)


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
	var raio_nucleo: float = _raio_circulo_px * 0.125
	var giro: float = fmod(tempo * 1.2, TAU)

	draw_circle(
		_centro_tela,
		raio_nucleo * 2.15,
		Color(COR_NEON_VERDE.r, COR_NEON_VERDE.g, COR_NEON_VERDE.b, 0.050 + pulso * 0.050)
	)
	draw_circle(
		_centro_tela,
		raio_nucleo * 1.35,
		Color(COR_NEON_CIANO.r, COR_NEON_CIANO.g, COR_NEON_CIANO.b, 0.035 + pulso * 0.035)
	)
	draw_arc(
		_centro_tela,
		raio_nucleo * 1.82,
		giro,
		giro + PI * 1.25,
		52,
		Color(1, 1, 1, 0.26),
		2.1,
		true
	)
	draw_arc(
		_centro_tela,
		raio_nucleo * 1.28,
		-giro,
		-giro + PI * 1.35,
		48,
		Color(COR_NEON_VERDE.r, COR_NEON_VERDE.g, COR_NEON_VERDE.b, 0.68 + pulso * 0.22),
		3.1,
		true
	)
	draw_arc(
		_centro_tela,
		raio_nucleo * 0.82,
		giro * 1.45,
		giro * 1.45 + PI * 1.65,
		48,
		Color(COR_NEON_CIANO.r, COR_NEON_CIANO.g, COR_NEON_CIANO.b, 0.70 + pulso * 0.20),
		2.7,
		true
	)
	draw_circle(_centro_tela, raio_nucleo * 0.32, Color(1, 1, 1, 0.55 + pulso * 0.40))


func _atualizar_onda_espectro_visual() -> void:
	if _spectrum_instance == null or _estado_jogo != EstadoJogo.JOGANDO:
		return

	var grave: float = _spectrum_instance.get_magnitude_for_frequency_range(
		ANALISE_GRAVE_MIN_HZ, ANALISE_GRAVE_MAX_HZ
	).length()
	var medio: float = _spectrum_instance.get_magnitude_for_frequency_range(
		ANALISE_MEDIO_MIN_HZ, ANALISE_MEDIO_MAX_HZ
	).length()
	var agudo: float = _spectrum_instance.get_magnitude_for_frequency_range(
		ANALISE_AGUDO_MIN_HZ, ANALISE_AGUDO_MAX_HZ
	).length()
	var total: float = grave * 0.56 + medio * 0.29 + agudo * 0.15

	if not _onda_visual_aquecida:
		_onda_media_grave = max(grave, 0.0001)
		_onda_media_medio = max(medio, 0.0001)
		_onda_media_agudo = max(agudo, 0.0001)
		_onda_media_total = max(total, 0.0001)
		_onda_visual_aquecida = true
		return

	var razao_grave: float = grave / max(_onda_media_grave, 0.000001)
	var razao_medio: float = medio / max(_onda_media_medio, 0.000001)
	var razao_agudo: float = agudo / max(_onda_media_agudo, 0.000001)
	var razao_total: float = total / max(_onda_media_total, 0.000001)

	_onda_media_grave = lerp(_onda_media_grave, max(grave, 0.000001), 0.055)
	_onda_media_medio = lerp(_onda_media_medio, max(medio, 0.000001), 0.055)
	_onda_media_agudo = lerp(_onda_media_agudo, max(agudo, 0.000001), 0.055)
	_onda_media_total = lerp(_onda_media_total, max(total, 0.000001), 0.055)
	_onda_energia = lerp(
		_onda_energia,
		clamp((razao_total - 0.65) / 1.55, 0.0, 1.0),
		0.24
	)
	_onda_grave = lerp(_onda_grave, clamp(razao_grave / 2.4, 0.0, 1.0), 0.20)
	_onda_medio = lerp(_onda_medio, clamp(razao_medio / 2.4, 0.0, 1.0), 0.20)
	_onda_agudo = lerp(_onda_agudo, clamp(razao_agudo / 2.4, 0.0, 1.0), 0.20)


func _desenhar_onda_borda_musical() -> void:
	if not ONDA_BORDA_ATIVA or _estado_jogo != EstadoJogo.JOGANDO:
		return

	var segmentos: int = (
		ONDA_BORDA_SEGMENTOS_REDUZIDO
		if _visual_reduzido
		else ONDA_BORDA_SEGMENTOS_NORMAL
	)
	var energia: float = clamp(_onda_energia, 0.0, 1.0)
	var combo_normalizado: float = clamp(float(_combo_atual) / 18.0, 0.0, 1.0)
	var nivel_acertos: float = clamp(
		_onda_acerto_nivel * 0.70 + combo_normalizado * 0.30, 0.0, 1.0
	)
	var pulso_hit: float = clamp(_onda_pulso_hit, 0.0, 1.0)
	var intensidade: float = clamp(
		0.10 + energia * 0.18 + nivel_acertos * 0.46 + pulso_hit * 0.56,
		0.0,
		1.0
	)
	var amplitude: float = _raio_circulo_px * lerp(
		ONDA_BORDA_AMPLITUDE_REPOUSO_RATIO,
		ONDA_BORDA_AMPLITUDE_MAX_RATIO,
		intensidade
	)
	var raio_base: float = _raio_circulo_px * ONDA_BORDA_RAIO_BASE_RATIO
	var raio_interno: float = _raio_circulo_px * ONDA_BORDA_RAIO_INTERNO_RATIO
	var soma_faixas: float = max(_onda_grave + _onda_medio + _onda_agudo, 0.0001)
	var peso_grave: float = _onda_grave / soma_faixas
	var peso_medio: float = _onda_medio / soma_faixas
	var peso_agudo: float = _onda_agudo / soma_faixas

	# Identidade Soul: carmim nos graves, azul-mar nos médios e ouro/branco
	# nos ataques agudos e nos acertos mais fortes.
	var cor_onda: Color = COR_NEON_VERDE.lerp(
		COR_NEON_CIANO, clamp(peso_medio * 0.72 + peso_agudo, 0.0, 1.0)
	)
	cor_onda = cor_onda.lerp(
		Color(1.0, 0.78, 0.08, 1.0),
		clamp(peso_agudo * 0.22 + pulso_hit * 0.24, 0.0, 0.42)
	)
	var frequencia_barras: float = lerp(
		5.0, 9.0, clamp(peso_medio * 0.55 + peso_agudo * 0.90, 0.0, 1.0)
	)
	var linhas: PackedVector2Array = PackedVector2Array()

	for i in range(segmentos):
		var t: float = float(i) / float(segmentos)
		var angulo: float = t * TAU
		var forma_1: float = sin(angulo * frequencia_barras + _onda_fase)
		var forma_2: float = sin(angulo * (frequencia_barras * 1.73) - _onda_fase * 1.31)
		var forma_3: float = sin(angulo * 3.0 + _onda_fase * 0.57)
		var forma: float = clamp(
			0.40 + abs(forma_1) * 0.38 + abs(forma_2) * 0.15 + abs(forma_3) * 0.07,
			0.0,
			1.0
		)
		var variacao_frequencia: float = clamp(
			peso_grave * (0.78 + abs(forma_3) * 0.22)
			+ peso_medio * (0.68 + abs(forma_1) * 0.32)
			+ peso_agudo * (0.58 + abs(forma_2) * 0.42),
			0.45,
			1.0
		)
		var direcao: Vector2 = Vector2(cos(angulo), sin(angulo))
		linhas.append(_centro_tela + direcao * raio_interno)
		linhas.append(_centro_tela + direcao * (raio_base + amplitude * forma * variacao_frequencia))

	var alpha: float = clamp(
		0.35 + energia * 0.16 + nivel_acertos * 0.24 + pulso_hit * 0.28,
		0.32,
		0.92
	)
	var espessura: float = max(1.6, _raio_circulo_px * ONDA_BORDA_ESPESSURA_RATIO)
	draw_multiline(
		linhas,
		Color(cor_onda.r, cor_onda.g, cor_onda.b, alpha * 0.20),
		espessura * 3.0,
		true
	)
	draw_multiline(
		linhas,
		Color(cor_onda.r, cor_onda.g, cor_onda.b, alpha),
		espessura,
		true
	)
	var raio_pulso: float = raio_base + amplitude * (0.18 + pulso_hit * 0.50)
	draw_arc(
		_centro_tela,
		raio_pulso,
		0.0,
		TAU,
		segmentos,
		Color(cor_onda.r, cor_onda.g, cor_onda.b, 0.10 + pulso_hit * 0.34),
		max(1.2, espessura * (0.55 + pulso_hit * 0.35)),
		true
	)
	draw_arc(
		_centro_tela,
		raio_interno,
		0.0,
		TAU,
		segmentos,
		Color(1.0, 1.0, 1.0, 0.07 + pulso_hit * 0.16),
		max(1.0, espessura * 0.42),
		true
	)


func _desenhar_anel_volume() -> void:
	# Medidor de volume como um anel completo colado na borda interna do círculo --
	# usa a própria forma da mesa como HUD, em vez de uma barra retangular solta.
	if _musica_player == null:
		return

	var volume_atual: float = _obter_volume_musica_db()
	var proporcao: float = clamp(
		(volume_atual - VOLUME_MIN_DB) / (VOLUME_MAX_DB - VOLUME_MIN_DB), 0.0, 1.0
	)
	var raio_anel: float = _raio_circulo_px * 0.918
	var espessura: float = _raio_circulo_px * 0.022
	var inicio_ang: float = -PI / 2.0

	draw_arc(_centro_tela, raio_anel, 0.0, TAU, 64, Color(1, 1, 1, 0.08), espessura, true)

	if proporcao > 0.001:
		var cor_nivel: Color = COR_NEON_CIANO.lerp(COR_ERRO, 1.0 - proporcao)
		draw_arc(
			_centro_tela,
			raio_anel,
			inicio_ang,
			inicio_ang + TAU * proporcao,
			64,
			cor_nivel,
			espessura,
			true
		)


func _desenhar_linha_arraste(evento: Dictionary, em_foco: bool = true) -> void:
	var caminho: Array = evento["caminho"]
	if caminho.size() < 2:
		return

	var em_andamento: bool = _arraste_evento_atual != null and _arraste_evento_atual == evento
	var indice_progresso: int = _arraste_indice_atual if em_andamento else 0
	var cor_caminho: Color = _cor_caminho_evento(evento)

	var comprimentos: Array = []
	var comprimento_total: float = 0.0
	for i in range(caminho.size() - 1):
		var a: Vector2 = _pontos[int(caminho[i])].position
		var b: Vector2 = _pontos[int(caminho[i + 1])].position
		var d: float = a.distance_to(b)
		comprimentos.append(d)
		comprimento_total += d

	var progresso_fluxo: float = fmod(Time.get_ticks_msec() / 620.0, 1.0)
	var pulso: float = sin(Time.get_ticks_msec() / 105.0) * 0.5 + 0.5
	var distancia_alvo: float = progresso_fluxo * comprimento_total
	var acumulado: float = 0.0

	for i in range(caminho.size() - 1):
		var completo: bool = i < indice_progresso
		# A seta atual fica destacada: é a próxima que o jogador precisa seguir.
		var ativo: bool = (
			em_foco and ((em_andamento and i == indice_progresso) or (not em_andamento and i == 0))
		)
		_desenhar_segmento_arraste(
			int(caminho[i]), int(caminho[i + 1]), pulso, completo, ativo, cor_caminho, em_foco
		)

		# A bolinha "correndo" ao longo do caminho só aparece no caminho em foco --
		# é só um reforço visual extra, não precisa competir em caminhos secundários.
		if (
			em_foco
			and distancia_alvo >= acumulado
			and distancia_alvo <= acumulado + float(comprimentos[i])
		):
			var t_local: float = (distancia_alvo - acumulado) / max(float(comprimentos[i]), 0.001)
			var pos_orbe: Vector2 = _pontos[int(caminho[i])].position.lerp(
				_pontos[int(caminho[i + 1])].position, t_local
			)
			var raio_base: float = _ponto_raio(int(caminho[i]))
			draw_circle(
				pos_orbe, raio_base * 0.46, Color(cor_caminho.r, cor_caminho.g, cor_caminho.b, 0.28)
			)
			draw_circle(
				pos_orbe, raio_base * 0.24, Color(cor_caminho.r, cor_caminho.g, cor_caminho.b, 0.92)
			)
			draw_circle(pos_orbe, raio_base * 0.10, Color.WHITE)

		acumulado += float(comprimentos[i])


func _dados_hover_tubo_atual() -> Dictionary:
	if not ARRASTE_HOVER_TUBO_ATIVO:
		return {}
	if not _arraste_gesto_ativo or _arraste_evento_atual == null:
		return {}

	var caminho: Array = _arraste_evento_atual.get("caminho", [])
	if caminho.size() < 2:
		return {}
	if _arraste_indice_atual < 0 or _arraste_indice_atual >= caminho.size() - 1:
		return {}

	var indice_origem: int = int(caminho[_arraste_indice_atual])
	var indice_destino: int = int(caminho[_arraste_indice_atual + 1])
	if indice_origem < 0 or indice_origem >= _pontos.size():
		return {}
	if indice_destino < 0 or indice_destino >= _pontos.size():
		return {}

	var origem: Vector2 = _pontos[indice_origem].position
	var destino: Vector2 = _pontos[indice_destino].position
	var segmento: Vector2 = destino - origem
	if segmento.length_squared() <= 0.001:
		return {}

	var progresso: float = _projecao_no_segmento(_arraste_pos_atual, origem, destino)
	var pos_tubo: Vector2 = origem.lerp(destino, progresso)
	var raio_tubo: float = _raio_tubo_arraste(indice_origem, indice_destino)
	var raio_limite: float = raio_tubo * ARRASTE_LIMITE_SAIDA_TUBO_RATIO
	var distancia: float = _arraste_pos_atual.distance_to(pos_tubo)

	return {
		"origem": origem,
		"destino": destino,
		"direcao": segmento.normalized(),
		"pos_tubo": pos_tubo,
		"progresso": progresso,
		"raio_tubo": raio_tubo,
		"raio_limite": raio_limite,
		"distancia": distancia,
		"dentro_ideal": distancia <= raio_tubo,
		"dentro_limite": distancia <= raio_limite,
	}


func _desenhar_hover_tubo_atual() -> void:
	var dados: Dictionary = _dados_hover_tubo_atual()
	if dados.is_empty():
		return

	var cor_base: Color = _cor_caminho_evento(_arraste_evento_atual)
	var dentro_ideal: bool = bool(dados["dentro_ideal"])
	var dentro_limite: bool = bool(dados["dentro_limite"])
	var distancia: float = float(dados["distancia"])
	var raio_tubo: float = float(dados["raio_tubo"])
	var raio_limite: float = float(dados["raio_limite"])
	var pos_tubo: Vector2 = dados["pos_tubo"]
	var direcao: Vector2 = dados["direcao"]
	var perpendicular: Vector2 = Vector2(-direcao.y, direcao.x)
	var progresso: float = float(dados["progresso"])

	# A cor continua seguindo o caminho. Só aproxima do amarelo na margem de segurança
	# e do vermelho quando realmente passa do limite tolerado.
	var cor_hover: Color = cor_base
	if not dentro_limite:
		cor_hover = COR_ERRO
	elif not dentro_ideal:
		var faixa: float = clamp(
			(distancia - raio_tubo) / max(raio_limite - raio_tubo, 0.001), 0.0, 1.0
		)
		cor_hover = cor_base.lerp(Color(1.0, 0.78, 0.08, 1.0), 0.35 + faixa * 0.45)

	var pulso: float = sin(Time.get_ticks_msec() / ARRASTE_HOVER_PULSO_VELOCIDADE) * 0.5 + 0.5
	var giro: float = fmod(Time.get_ticks_msec() / 720.0, TAU)
	var comprimento: float = max(
		raio_tubo * ARRASTE_HOVER_COMPRIMENTO_RATIO, _raio_circulo_px * 0.065
	)
	var metade: float = comprimento * 0.5
	var inicio_hover: Vector2 = pos_tubo - direcao * metade
	var fim_hover: Vector2 = pos_tubo + direcao * metade

	# Faixa luminosa localizada: mostra a parte do tubo onde o dedo está agora.
	draw_line(
		inicio_hover,
		fim_hover,
		Color(cor_hover.r, cor_hover.g, cor_hover.b, 0.08 + pulso * 0.04),
		raio_tubo * 2.15,
		true
	)
	draw_line(
		inicio_hover,
		fim_hover,
		Color(cor_hover.r, cor_hover.g, cor_hover.b, 0.18 + pulso * 0.08),
		raio_tubo * 1.18,
		true
	)
	draw_line(inicio_hover, fim_hover, Color(0.0, 0.0, 0.0, 0.34), max(2.0, raio_tubo * 0.36), true)
	draw_line(
		inicio_hover,
		fim_hover,
		Color(1.0, 1.0, 1.0, 0.72 + pulso * 0.18),
		max(1.2, raio_tubo * 0.095),
		true
	)

	# Limites laterais curtos, como um scanner de corredor.
	for lado in [-1.0, 1.0]:
		var deslocamento: Vector2 = perpendicular * raio_tubo * 0.82 * float(lado)
		var lado_inicio: Vector2 = inicio_hover + deslocamento
		var lado_fim: Vector2 = fim_hover + deslocamento
		draw_line(
			lado_inicio,
			lado_fim,
			Color(cor_hover.r, cor_hover.g, cor_hover.b, 0.24 + pulso * 0.16),
			max(1.0, raio_tubo * 0.07),
			true
		)

	# Leitor circular moderno sobre a projeção real no tubo.
	draw_circle(
		pos_tubo,
		raio_tubo * (1.05 + pulso * 0.10),
		Color(cor_hover.r, cor_hover.g, cor_hover.b, 0.075 + pulso * 0.035)
	)
	draw_arc(
		pos_tubo,
		raio_tubo * (0.82 + pulso * 0.08),
		giro,
		giro + PI * 1.42,
		32,
		Color(cor_hover.r, cor_hover.g, cor_hover.b, 0.86),
		max(1.4, raio_tubo * 0.105),
		true
	)
	draw_arc(
		pos_tubo,
		raio_tubo * 0.56,
		-giro,
		-giro + PI * 1.28,
		28,
		Color(1, 1, 1, 0.82),
		max(1.1, raio_tubo * 0.075),
		true
	)
	draw_circle(pos_tubo, max(2.0, raio_tubo * 0.16), Color(1, 1, 1, 0.90))

	# Arco de progresso do trecho atual.
	if progresso > 0.001:
		draw_arc(
			pos_tubo,
			raio_tubo * 1.16,
			-PI / 2.0,
			-PI / 2.0 + TAU * progresso,
			36,
			Color(cor_hover.r, cor_hover.g, cor_hover.b, 0.72),
			max(1.2, raio_tubo * 0.08),
			true
		)

	# Quando o dedo se afasta do eixo, uma ligação discreta mostra para onde retornar.
	if distancia > 2.0:
		var pos_dedo: Vector2 = _limitar_pos_efeito_no_circulo(_arraste_pos_atual, raio_tubo * 0.45)
		draw_line(
			pos_tubo,
			pos_dedo,
			Color(cor_hover.r, cor_hover.g, cor_hover.b, 0.20 + pulso * 0.10),
			max(1.0, raio_tubo * 0.055),
			true
		)
		draw_circle(
			pos_dedo,
			raio_tubo * 0.24,
			Color(cor_hover.r, cor_hover.g, cor_hover.b, 0.18 + pulso * 0.08)
		)
		draw_arc(
			pos_dedo,
			raio_tubo * 0.34,
			0.0,
			TAU,
			24,
			Color(1, 1, 1, 0.54),
			max(1.0, raio_tubo * 0.055),
			true
		)


func _atualizar_tolerancia_saida_tubo() -> void:
	if not _arraste_gesto_ativo or _arraste_evento_atual == null:
		_arraste_fora_tubo_desde_msec = -1
		return

	var dados: Dictionary = _dados_hover_tubo_atual()
	if dados.is_empty():
		_arraste_fora_tubo_desde_msec = -1
		return

	if bool(dados["dentro_limite"]):
		_arraste_fora_tubo_desde_msec = -1
		return

	var agora_msec: int = Time.get_ticks_msec()
	if _arraste_fora_tubo_desde_msec < 0:
		_arraste_fora_tubo_desde_msec = agora_msec
		return

	var tempo_fora: float = float(agora_msec - _arraste_fora_tubo_desde_msec) / 1000.0
	if tempo_fora >= ARRASTE_TEMPO_FORA_TUBO_TOLERADO_SEG:
		_falhar_arraste_atual("SAIU DO TUBO")


func _desenhar_segmento_arraste(
	indice_origem: int,
	indice_destino: int,
	pulso: float,
	completo: bool,
	ativo: bool,
	cor_caminho: Color,
	em_foco: bool = true
) -> void:
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

	# Cor única pro caminho inteiro (a mesma em todos os trechos), pra ficar óbvio
	# quais Tazos pertencem ao mesmo arraste. Trechos já concluídos viram verde-completo.
	var cor: Color = COR_SLIDE_COMPLETO if completo else cor_caminho
	# Caminhos que não estão em foco (raro, mas pode acontecer dois arrastes visíveis
	# ao mesmo tempo) ficam bem mais discretos, pra não brigar visualmente com o principal.
	var atenuacao: float = 1.0 if em_foco else 0.38
	var largura: float = max(3.0, raio_origem * (0.42 if ativo else 0.28))
	var boost: float = ARRASTE_SETAS_ATIVAS_BRILHO if ativo else 1.0

	# Camada única de glow + núcleo nítido -- sem trilhos duplicados nas laterais,
	# leitura mais limpa e mais rápida de entender de relance.
	draw_line(
		inicio,
		fim,
		Color(cor.r, cor.g, cor.b, (0.11 + pulso * 0.05) * boost * atenuacao),
		largura * (2.6 if ativo else 2.0),
		true
	)
	draw_line(
		inicio,
		fim,
		Color(0.0, 0.0, 0.0, 0.28 * atenuacao),
		largura * (1.15 if ativo else 1.02),
		true
	)
	draw_line(
		inicio,
		fim,
		Color(cor.r, cor.g, cor.b, (0.88 + pulso * 0.12) * atenuacao),
		max(1.4, largura * (0.34 if ativo else 0.22)),
		true
	)

	if em_foco:
		# Luz móvel só no trecho ativo, mostrando a direção correta do arraste.
		if ativo:
			var fase_luz: float = fmod(Time.get_ticks_msec() / 520.0, 1.0)
			var pos_luz: Vector2 = inicio.lerp(fim, fase_luz)
			draw_circle(pos_luz, largura * 0.60, Color(1, 1, 1, 0.40))
			draw_circle(pos_luz, largura * 0.28, Color(cor.r, cor.g, cor.b, 0.85))

		# Poucas setas, grandes e claras -- em vez de várias repetindo em cima uma da
		# outra, o que só poluía a leitura quando tinha mais de um trecho na tela.
		var passo: float = max(raio_origem * 1.05, 26.0)
		var qtd: int = clamp(int(distancia / passo), 2, 4)
		var anim: float = fmod(Time.get_ticks_msec() / 480.0, 1.0)
		for j in range(qtd):
			var t: float = (float(j) + anim) / float(qtd)
			if t < 0.08 or t > 0.92:
				continue
			var centro: Vector2 = inicio.lerp(fim, t)
			var alpha_seta: float = 0.90 if ativo else 0.55
			_desenhar_chevron_espacado(
				centro, direcao, perpendicular, largura * (1.05 if ativo else 0.85), cor, alpha_seta
			)

	var ponta_centro: Vector2 = fim - direcao * (largura * 0.12)
	_desenhar_chevron_espacado(
		ponta_centro,
		direcao,
		perpendicular,
		largura * 1.10,
		cor.lerp(Color.WHITE, 0.2),
		0.9 * atenuacao
	)


func _desenhar_chevron_espacado(
	centro: Vector2,
	direcao: Vector2,
	perpendicular: Vector2,
	largura: float,
	cor: Color,
	alpha: float
) -> void:
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

	_atualizar_hover(pos)

	if not _arraste_rastro.is_empty():
		var ultimo: Dictionary = _arraste_rastro[_arraste_rastro.size() - 1]
		var ultimo_pos: Vector2 = ultimo["pos"]
		if ultimo_pos.distance_to(pos) < ARRASTE_RASTRO_DIST_MIN_PX:
			return

	var cor: Color = COR_NEON_CIANO
	if _arraste_evento_atual != null:
		cor = _cor_caminho_evento(_arraste_evento_atual)
	else:
		var indice_perto: int = _indice_ponto_mais_proximo(pos, ARRASTE_RAIO_CHECKPOINT_EXTRA)
		if indice_perto >= 0:
			cor = _cor_orbe_por_ponto(indice_perto)

	_arraste_rastro.append({"pos": pos, "tempo": Time.get_ticks_msec() / 1000.0, "cor": cor})

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
	# Efeito de toque novo: em vez de desenhar uma linha conectando os pontos por onde
	# o dedo passou, cada posição registrada vira uma marca de área (um "ripple" que
	# nasce pequeno, cresce e apaga) -- demarca por onde o gesto passou de um jeito mais
	# tecnológico/moderno, sem parecer um risco de caneta.
	if _arraste_rastro.is_empty() and not _arraste_gesto_ativo:
		return

	var agora: float = Time.get_ticks_msec() / 1000.0
	var raio_base: float = _raio_circulo_px * 0.050

	for item in _arraste_rastro:
		var pos: Vector2 = _limitar_pos_efeito_no_circulo(item["pos"], raio_base * 1.55)
		var cor: Color = item["cor"]
		var idade: float = agora - float(item["tempo"])
		var vida: float = clamp(1.0 - idade / ARRASTE_RASTRO_DURACAO_SEG, 0.0, 1.0)
		if vida <= 0.0:
			continue

		var expansao: float = 1.0 - vida
		var raio_ripple: float = raio_base * (0.55 + expansao * 0.95)

		draw_circle(pos, raio_ripple * 1.5, Color(cor.r, cor.g, cor.b, 0.05 * vida))
		draw_arc(
			pos,
			raio_ripple,
			0.0,
			TAU,
			28,
			Color(cor.r, cor.g, cor.b, 0.55 * vida),
			max(1.2, raio_base * 0.16 * vida),
			true
		)
		draw_arc(
			pos,
			raio_ripple * 0.55,
			0.0,
			TAU,
			22,
			Color(1, 1, 1, 0.35 * vida),
			max(1.0, raio_base * 0.10 * vida),
			true
		)

	# Marcador tech contínuo embaixo do dedo/mouse enquanto o gesto está ativo: um halo
	# suave pulsando + pequenas marcas de mira nos 4 cantos, tipo leitor de área.
	if _arraste_gesto_ativo:
		var cor_cursor: Color = COR_NEON_CIANO
		if _arraste_evento_atual != null:
			cor_cursor = _cor_caminho_evento(_arraste_evento_atual)
		var pulso_cursor: float = sin(Time.get_ticks_msec() / 95.0) * 0.5 + 0.5
		var raio_glow: float = _raio_circulo_px * (0.068 + pulso_cursor * 0.012)
		var pos_cursor: Vector2 = _limitar_pos_efeito_no_circulo(
			_arraste_pos_atual, raio_glow * 1.55
		)

		draw_circle(
			pos_cursor,
			raio_glow * 1.55,
			Color(cor_cursor.r, cor_cursor.g, cor_cursor.b, 0.085 + pulso_cursor * 0.035)
		)
		draw_circle(
			pos_cursor,
			raio_glow,
			Color(cor_cursor.r, cor_cursor.g, cor_cursor.b, 0.16 + pulso_cursor * 0.06)
		)
		draw_arc(
			pos_cursor,
			raio_glow * 0.92,
			0.0,
			TAU,
			40,
			Color(1, 1, 1, 0.55 + pulso_cursor * 0.25),
			2.0,
			true
		)
		draw_circle(pos_cursor, raio_glow * 0.28, Color(1, 1, 1, 0.85))

		for i in range(4):
			var ang: float = (PI / 2.0) * i + PI / 4.0
			var p_ext: Vector2 = pos_cursor + Vector2(cos(ang), sin(ang)) * raio_glow * 1.35
			var p_int: Vector2 = pos_cursor + Vector2(cos(ang), sin(ang)) * raio_glow * 1.05
			draw_line(
				p_int,
				p_ext,
				Color(cor_cursor.r, cor_cursor.g, cor_cursor.b, 0.5 + pulso_cursor * 0.3),
				2.0,
				true
			)


func _registrar_efeito_passagem_tubo(pos: Vector2, cor: Color, intensidade: float = 1.0) -> void:
	var agora: float = Time.get_ticks_msec() / 1000.0
	(
		_efeitos_passagem_tubo
		. append(
			{
				"pos": _limitar_pos_efeito_no_circulo(pos, _raio_circulo_px * 0.09),
				"cor": cor,
				"inicio": agora,
				"duracao": 0.46,
				"intensidade": intensidade,
			}
		)
	)
	while _efeitos_passagem_tubo.size() > 10:
		_efeitos_passagem_tubo.remove_at(0)


func _limpar_efeitos_passagem_tubo() -> void:
	if _efeitos_passagem_tubo.is_empty():
		return
	var agora: float = Time.get_ticks_msec() / 1000.0
	for i in range(_efeitos_passagem_tubo.size() - 1, -1, -1):
		var efeito: Dictionary = _efeitos_passagem_tubo[i]
		if agora - float(efeito["inicio"]) >= float(efeito["duracao"]):
			_efeitos_passagem_tubo.remove_at(i)


func _desenhar_efeitos_passagem_tubo() -> void:
	if _efeitos_passagem_tubo.is_empty():
		return
	var agora: float = Time.get_ticks_msec() / 1000.0
	for efeito in _efeitos_passagem_tubo:
		var duracao: float = max(float(efeito["duracao"]), 0.001)
		var t: float = clamp((agora - float(efeito["inicio"])) / duracao, 0.0, 1.0)
		var vida: float = 1.0 - t
		var pos: Vector2 = _limitar_pos_efeito_no_circulo(efeito["pos"], _raio_circulo_px * 0.11)
		var cor: Color = efeito["cor"]
		var intensidade: float = float(efeito["intensidade"])
		var raio: float = _raio_circulo_px * (0.022 + t * 0.052) * intensidade
		draw_circle(pos, raio * 1.45, Color(cor.r, cor.g, cor.b, 0.055 * vida))
		draw_arc(
			pos,
			raio,
			0.0,
			TAU,
			24,
			Color(cor.r, cor.g, cor.b, 0.78 * vida),
			max(1.0, _raio_circulo_px * 0.0035),
			true
		)
		draw_arc(
			pos, raio * 0.58, -PI * 0.25, PI * 1.20, 18, Color(1, 1, 1, 0.68 * vida), 1.2, true
		)
		for k in range(4):
			var ang: float = float(k) * PI / 2.0 + t * 0.8
			var p1: Vector2 = pos + Vector2(cos(ang), sin(ang)) * raio * 0.75
			var p2: Vector2 = pos + Vector2(cos(ang), sin(ang)) * raio * 1.18
			draw_line(p1, p2, Color(cor.r, cor.g, cor.b, 0.55 * vida), 1.2, true)


func _input(event: InputEvent) -> void:
	if _modal_continuar_ativo:
		if _modal_em_transicao:
			return
		if event is InputEventScreenTouch and event.pressed:
			_ultimo_touch_msec = Time.get_ticks_msec()
			_continuar_partida_com_credito()
			get_viewport().set_input_as_handled()
		elif (
			event is InputEventMouseButton
			and event.button_index == MOUSE_BUTTON_LEFT
			and event.pressed
		):
			if Time.get_ticks_msec() - _ultimo_touch_msec > 180:
				_continuar_partida_com_credito()
		return

	if _estado_jogo != EstadoJogo.JOGANDO:
		return

	if event is InputEventScreenTouch:
		_ultimo_touch_msec = Time.get_ticks_msec()
		if event.pressed:
			if _touch_ativo_id >= 0 and _touch_ativo_id != event.index:
				return
			_touch_ativo_id = event.index
			_arraste_gesto_ativo = true
			_arraste_ultimo_pos = event.position
			_arraste_pos_atual = event.position
			_registrar_ponto_rastro_arraste(event.position)
			_iniciar_arraste(event.position)
		else:
			if _touch_ativo_id == event.index:
				_finalizar_arraste()
				_touch_ativo_id = -1
		get_viewport().set_input_as_handled()

	elif event is InputEventScreenDrag:
		_ultimo_touch_msec = Time.get_ticks_msec()
		if _touch_ativo_id < 0 or _touch_ativo_id == event.index:
			_touch_ativo_id = event.index
			_atualizar_arraste(event.position)
		get_viewport().set_input_as_handled()

	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		# Em touchscreen, o sistema pode gerar um mouse artificial logo após o touch.
		# Ignorá-lo evita começar/finalizar o arraste duas vezes e elimina engasgos.
		if Time.get_ticks_msec() - _ultimo_touch_msec <= 180:
			return
		if event.pressed:
			_arraste_gesto_ativo = true
			_arraste_ultimo_pos = event.position
			_arraste_pos_atual = event.position
			_registrar_ponto_rastro_arraste(event.position)
			_iniciar_arraste(event.position)
		else:
			_finalizar_arraste()

	elif event is InputEventMouseMotion and _arraste_gesto_ativo:
		if Time.get_ticks_msec() - _ultimo_touch_msec > 180:
			_atualizar_arraste(event.position)

	elif event is InputEventMouseMotion:
		_atualizar_hover(event.position)


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
		_mostrar_debug_video(
			"VÍDEO NÃO ENCONTRADO:\n" + caminho + "\nTambém tentei:\n" + CAMINHO_VIDEO_FALLBACK_1
		)
		return

	_limpar_debug_video()

	_video_fundo = VideoStreamPlayer.new()
	_video_fundo.name = "VideoFundoCircular"
	_video_fundo.stream = stream
	_video_fundo.autoplay = false
	_video_fundo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_video_fundo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

	# Importante: o som do vídeo fica mudo.
	# O áudio oficial do jogo vem do AudioStreamPlayer usando soul.mp3.
	_video_fundo.volume_db = -80.0

	# O vídeo precisa ficar atrás dos pontos, HUD e desenhos do jogo.
	# O fundo preto fica ainda mais atrás.
	_video_fundo.z_index = -5

	# Vídeo mostrado por INTEIRO, sem forçar um recorte quadrado (sem "zoom"/crop):
	# calcula o tamanho preservando VIDEO_FUNDO_PROPORCAO_LARGURA_ALTURA e encaixa o
	# vídeo inteiro dentro do círculo (contain). Se a proporção não for quadrada, sobra
	# uma faixa do fundo preto dentro do círculo -- em vez de cortar ou esticar o vídeo.
	var diametro: float = _raio_circulo_px * 2.0
	var tamanho_video: Vector2
	if VIDEO_FUNDO_PROPORCAO_LARGURA_ALTURA >= 1.0:
		tamanho_video = Vector2(diametro, diametro / VIDEO_FUNDO_PROPORCAO_LARGURA_ALTURA)
	else:
		tamanho_video = Vector2(diametro * VIDEO_FUNDO_PROPORCAO_LARGURA_ALTURA, diametro)
	_video_fundo.expand = true
	_video_fundo.size = tamanho_video
	_video_fundo.position = _centro_tela - (_video_fundo.size / 2.0)
	_video_fundo.pivot_offset = _video_fundo.size / 2.0
	_video_fundo.modulate = Color(1, 1, 1, VIDEO_FUNDO_ALPHA)

	# Não uso shader no VideoStreamPlayer aqui.
	# Em alguns projetos o material no vídeo pode impedir a exibição dependendo da versão/importação.
	add_child(_video_fundo)
	_video_fundo.show()
	_video_fundo.play()

	print(
		"HIT MUSIC - vídeo iniciado: ",
		caminho,
		" | tamanho: ",
		_video_fundo.size,
		" | posição: ",
		_video_fundo.position
	)

	if loop:
		_video_fundo.finished.connect(
			func():
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
# 1) APRESENTAÇÃO -- soul.jpeg + nome da fase
# ---------------------------------------------------------------
func _nome_fase_formatado_para_intro() -> String:
	var nome: String = NOME_FASE.strip_edges()
	if "\n" in nome or nome.length() <= 18:
		return nome

	var meio: int = int(nome.length() / 2)
	var melhor_espaco: int = -1
	var melhor_distancia: int = 999999
	for i in range(1, nome.length() - 1):
		if nome.substr(i, 1) != " ":
			continue
		var distancia: int = abs(i - meio)
		if distancia < melhor_distancia:
			melhor_distancia = distancia
			melhor_espaco = i

	if melhor_espaco < 0:
		return nome

	var linha_1: String = nome.substr(0, melhor_espaco).strip_edges()
	var linha_2: String = nome.substr(melhor_espaco + 1).strip_edges()
	linha_1 = linha_1.trim_suffix("-").trim_suffix("—").strip_edges()
	linha_2 = linha_2.trim_prefix("-").trim_prefix("—").strip_edges()
	return linha_1 + "\n" + linha_2


func _iniciar_apresentacao_fase() -> void:
	_estado_jogo = EstadoJogo.APRESENTACAO
	var nome_intro: String = _nome_fase_formatado_para_intro()
	var nome_em_duas_linhas: bool = "\n" in nome_intro

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
	config_nome.font_size = int(_raio_circulo_px * (0.125 if nome_em_duas_linhas else 0.16))
	config_nome.font_color = Color.WHITE
	config_nome.outline_size = 6
	config_nome.outline_color = Color(0.02, 0.0, 0.05, 0.95)
	config_nome.shadow_size = 20
	config_nome.shadow_color = Color(COR_NEON_VERDE.r, COR_NEON_VERDE.g, COR_NEON_VERDE.b, 0.6)

	_label_nome_fase = Label.new()
	_label_nome_fase.label_settings = config_nome
	_label_nome_fase.text = nome_intro
	_label_nome_fase.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label_nome_fase.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label_nome_fase.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label_nome_fase.max_lines_visible = 2
	_label_nome_fase.size = Vector2(
		_raio_circulo_px * 1.62,
		_raio_circulo_px * (0.62 if nome_em_duas_linhas else 0.4)
	)
	_label_nome_fase.position = _centro_tela - _label_nome_fase.size / 2.0
	_label_nome_fase.z_index = 5
	add_child(_label_nome_fase)

	# Quando há atraso de áudio para sincronizar os orbes com a batida, iniciamos a
	# fonte silenciosamente antes da contagem. O delay do barramento faz o som se tornar
	# audível exatamente quando o número 3 aparece, sem tocar durante a apresentação.
	var pre_roll: float = _atraso_saida_musica_seg()
	if pre_roll > 0.001:
		var espera_pre_roll: float = max(DURACAO_APRESENTACAO_SEG - pre_roll, 0.0)
		get_tree().create_timer(espera_pre_roll).timeout.connect(_pre_iniciar_musica_para_contagem)

	get_tree().create_timer(DURACAO_APRESENTACAO_SEG).timeout.connect(_iniciar_contagem)


func _pre_iniciar_musica_para_contagem() -> void:
	if _estado_jogo != EstadoJogo.APRESENTACAO:
		return
	if _musica_player != null and is_instance_valid(_musica_player):
		return
	_tocar_musica()


# ---------------------------------------------------------------
# 2) CONTAGEM -- vídeo e música já rodando + números 3, 2 e 1
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
	_contagem_etapa_visual = -1
	_led_assinatura_atual = ""
	_arduino_enviar_unico("BLINKALL")

	# O vídeo nasce aqui e continua sendo o mesmo durante toda a fase.
	# Não é recriado ao terminar a contagem, portanto não volta ao início.
	_criar_video_generico(CAMINHO_VIDEO_CONTAGEM, false)

	# Sem delay de sincronização, a música começa exatamente aqui. Quando existe delay,
	# o pré-roll acima já iniciou a fonte e o som se torna audível neste instante.
	if _musica_player == null or not is_instance_valid(_musica_player):
		_tocar_musica()

	var config_contagem := LabelSettings.new()
	config_contagem.font_size = int(_raio_circulo_px * 0.5)
	config_contagem.font_color = Color.WHITE
	config_contagem.outline_size = 8
	config_contagem.outline_color = Color(0.02, 0.0, 0.05, 0.95)
	config_contagem.shadow_size = 24
	config_contagem.shadow_color = Color(COR_NEON_CIANO.r, COR_NEON_CIANO.g, COR_NEON_CIANO.b, 0.7)

	_label_contagem = Label.new()
	_label_contagem.label_settings = config_contagem
	_label_contagem.text = str(CONTAGEM_NUMERO_INICIAL)
	_label_contagem.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label_contagem.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label_contagem.size = Vector2(_raio_circulo_px * 0.8, _raio_circulo_px * 0.8)
	_label_contagem.position = _centro_tela - _label_contagem.size / 2.0
	_label_contagem.pivot_offset = _label_contagem.size / 2.0
	_label_contagem.z_index = 5
	add_child(_label_contagem)


func _atualizar_contagem(delta: float) -> void:
	_contagem_restante = max(_contagem_restante - delta, 0.0)
	var decorrido: float = DURACAO_CONTAGEM_SEG - _contagem_restante
	var etapa: int = clamp(int(floor(decorrido)), 0, CONTAGEM_NUMERO_INICIAL - 1)
	var numero: int = CONTAGEM_NUMERO_INICIAL - etapa

	if etapa != _contagem_etapa_visual:
		_contagem_etapa_visual = etapa
		_animar_etapa_contagem(str(numero))

	if numero != _contagem_ultimo_numero_led:
		_contagem_ultimo_numero_led = numero
		_arduino_enviar_unico("COUNT " + str(numero))

	if _contagem_restante <= 0.0:
		_iniciar_jogo_real()


func _animar_etapa_contagem(texto: String) -> void:
	if _label_contagem == null:
		return
	if _tween_contagem:
		_tween_contagem.kill()

	_label_contagem.text = texto
	_label_contagem.scale = Vector2(0.92, 0.92)
	_label_contagem.modulate = Color(1, 1, 1, 0.0)

	_tween_contagem = create_tween()
	_tween_contagem.set_parallel(true)
	(
		_tween_contagem
		. tween_property(_label_contagem, "scale", Vector2.ONE, 0.22)
		. set_trans(Tween.TRANS_QUINT)
		. set_ease(Tween.EASE_OUT)
	)
	(
		_tween_contagem
		. tween_property(_label_contagem, "modulate", Color.WHITE, 0.18)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)


# ---------------------------------------------------------------
# 3) JOGANDO -- continua o mesmo vídeo e a mesma música iniciados na contagem
# ---------------------------------------------------------------
func _iniciar_jogo_real() -> void:
	if _label_contagem:
		_label_contagem.queue_free()
		_label_contagem = null

	_estado_jogo = EstadoJogo.JOGANDO
	_led_assinatura_atual = ""
	_arduino_enviar_unico("READY")

	# O mesmo vídeo e a mesma música iniciados na contagem continuam daqui em diante.
	# Só recria em caso de falha de carregamento; nunca reinicia uma mídia válida.
	if _video_fundo == null or not is_instance_valid(_video_fundo):
		_criar_video_generico(CAMINHO_VIDEO_FUNDO, false)
	if _musica_player == null or not is_instance_valid(_musica_player):
		_tocar_musica()

	_criar_pontos()
	_descartar_eventos_beatmap_ja_vencidos(_tempo_atual_musica())

	var tempo_audivel: float = max(_tempo_atual_musica() - _atraso_saida_musica_seg(), 0.0)
	_tempo_restante = max(_duracao_musica_seg - tempo_audivel, 0.0)
	_criar_hud()
	_atualizar_label_tempo()


func _descartar_eventos_beatmap_ja_vencidos(tempo_musica: float) -> void:
	# Como os primeiros três segundos da faixa pertencem à contagem, eventos manuais
	# que já terminaram nesse período são ignorados. Os próximos permanecem sincronizados.
	while _indice_beatmap < _beatmap.size():
		var evento: Dictionary = _beatmap[_indice_beatmap]
		var limite: float
		if evento.get("tipo", "") == "arraste":
			limite = (
				float(evento.get("tempo_fim", evento.get("tempo", 0.0)))
				+ ARRASTE_TOLERANCIA_FINAL_SEG
			)
		else:
			limite = float(evento.get("tempo", 0.0)) + _janela_acerto_evento(evento)
		if limite >= tempo_musica:
			break
		_indice_beatmap += 1


func _processar_frame_jogo(_delta: float) -> void:
	if _partida_encerrada or _finalizacao_em_andamento:
		return

	# O cronômetro é derivado do mesmo relógio monotônico da música.
	# Durante o pequeno pré-roll de sincronia ele permanece na duração real da faixa;
	# depois acompanha exatamente o tempo audível, sem acumular diferença de FPS.
	var tempo_musica: float = _tempo_atual_musica()
	var tempo_audivel: float = max(tempo_musica - _atraso_saida_musica_seg(), 0.0)
	_tempo_restante = max(_duracao_musica_seg - tempo_audivel, 0.0)
	_atualizar_label_tempo()

	# Nunca encerra apenas porque um número estimado chegou a zero. Primeiro espera o
	# sinal finished da própria música e depois aguarda toda a cauda audível do delay.
	var fim_audio_confirmado: bool = (
		_musica_fonte_finalizada and tempo_musica >= _duracao_total_jogo_seg
	)
	var sem_player_usando_fallback: bool = (
		(_musica_player == null or not is_instance_valid(_musica_player))
		and tempo_musica >= _duracao_total_jogo_seg
	)
	if fim_audio_confirmado or sem_player_usando_fallback:
		_encerrar_partida()
		return

	_despachar_fila_eventos_musicais(tempo_musica)
	_ativar_eventos_pendentes(tempo_musica)
	_atualizar_eventos_ativos(tempo_musica)
	_processar_inputs_toque(tempo_musica)
	_led_sincronizar_com_discos_vivos(tempo_musica)


func _cor_led_guia(ponto: int) -> Color:
	# Clareia levemente as cores da tela para continuarem fortes na fita física.
	var cor: Color = _cor_orbe_por_ponto(ponto).lerp(Color.WHITE, 0.16)
	var maior: float = max(cor.r, max(cor.g, cor.b))
	if maior > 0.001 and maior < 0.88:
		cor *= 0.88 / maior
	cor.a = 1.0
	return cor


func _led_enviar_cor_independente(ponto: int, cor: Color) -> void:
	if ponto < 0 or ponto >= NUM_PONTOS:
		return
	var comando: String = (
		"LED %d %d %d %d"
		% [
			ponto,
			int(clamp(cor.r * 255.0, 0.0, 255.0)),
			int(clamp(cor.g * 255.0, 0.0, 255.0)),
			int(clamp(cor.b * 255.0, 0.0, 255.0)),
		]
	)
	if _led_assinaturas_por_ponto[ponto] == comando:
		return
	_led_assinaturas_por_ponto[ponto] = comando
	_arduino_enviar_forcado(comando)


func _led_evento_adquirir(evento: Dictionary) -> void:
	if evento.get("tipo", "") != "toque" or evento.get("resolvido", false):
		return
	if evento.get("led_posse_ativa", false):
		return
	var ponto: int = int(evento.get("ponto", -1))
	if ponto < 0 or ponto >= NUM_PONTOS:
		return
	evento["led_posse_ativa"] = true
	# Prazo imutável e individual: do nascimento da bola até o último instante em
	# que este evento pode pontuar. Outros eventos nunca alteram este relógio.
	evento["led_fim_tempo_musica"] = (
		float(evento.get("tempo", 0.0)) + _janela_acerto_evento(evento)
	)


func _led_evento_liberar(evento: Dictionary) -> void:
	if evento.get("tipo", "") != "toque":
		return
	if not evento.get("led_posse_ativa", false):
		return
	evento["led_posse_ativa"] = false


func _led_sincronizar_com_discos_vivos(tempo_musica: float) -> void:
	# Fonte única de verdade: os próprios discos vivos. Não acumula contadores entre
	# frames, portanto não deriva nem se perde depois de muitos eventos/reconexões.
	var vivos_por_ponto: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0]

	for evento in _eventos_ativos:
		if evento.get("tipo", "") != "toque" or evento.get("resolvido", false):
			continue
		var ponto: int = int(evento.get("ponto", -1))
		if ponto < 0 or ponto >= NUM_PONTOS:
			continue

		var tempo_alvo: float = float(evento.get("tempo", 0.0))
		var inicio: float = float(
			evento.get("tempo_visual_inicio", tempo_alvo - TEMPO_ORBE_SEG)
		)
		var fim: float = float(
			evento.get("led_fim_tempo_musica", tempo_alvo + _janela_acerto_evento(evento))
		)
		if tempo_musica >= inicio and tempo_musica <= fim:
			vivos_por_ponto[ponto] += 1

	for ponto in range(NUM_PONTOS):
		_led_donos_por_ponto[ponto] = vivos_por_ponto[ponto]
		var cor_desejada: Color = (
			_cor_led_guia(ponto) if vivos_por_ponto[ponto] > 0 else Color.BLACK
		)
		_led_enviar_cor_independente(ponto, cor_desejada)


# ---------------------------------------------------------------
# COM5 PERSISTENTE ENTRE AS DUAS CENAS
# ---------------------------------------------------------------
func _arduino_enviar_unico(linha: String) -> void:
	var comando: String = linha.strip_edges()
	if comando.is_empty() or comando == _led_assinatura_atual:
		return
	if _arduino_enviar_linha(comando):
		_led_assinatura_atual = comando


func _arduino_enviar_forcado(linha: String) -> void:
	var comando: String = linha.strip_edges()
	if comando.is_empty():
		return
	_led_assinatura_atual = ""
	_arduino_enviar_linha(comando)


func _powershell_literal(valor: String) -> String:
	return "'" + valor.replace("'", "''") + "'"


func _serial_configurar_caminhos() -> void:
	if not _serial_base_dir.is_empty():
		return

	_serial_base_dir = ProjectSettings.globalize_path("user://hit_music_serial")
	_serial_spool_dir = _serial_base_dir.path_join("spool")
	_serial_heartbeat_path = _serial_base_dir.path_join("godot_heartbeat.txt")
	_serial_alive_path = _serial_base_dir.path_join("bridge_alive.txt")
	_serial_ready_path = _serial_base_dir.path_join("bridge_ready.txt")
	_serial_starting_path = _serial_base_dir.path_join("bridge_starting.txt")

	DirAccess.make_dir_recursive_absolute(_serial_spool_dir)


func _serial_escrever_atomico(caminho_final: String, conteudo: String) -> bool:
	var temporario: String = (
		caminho_final + ".tmp_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	)

	var arquivo := FileAccess.open(temporario, FileAccess.WRITE)
	if arquivo == null:
		return false

	arquivo.store_string(conteudo)
	arquivo.flush()
	arquivo.close()

	if FileAccess.file_exists(caminho_final):
		DirAccess.remove_absolute(caminho_final)

	var erro: int = DirAccess.rename_absolute(temporario, caminho_final)
	if erro != OK:
		if FileAccess.file_exists(temporario):
			DirAccess.remove_absolute(temporario)
		return false
	return true


func _serial_arquivo_recente(caminho: String, idade_maxima_seg: float) -> bool:
	if not FileAccess.file_exists(caminho):
		return false

	var modificado: int = FileAccess.get_modified_time(caminho)
	if modificado <= 0:
		return false

	var idade: float = Time.get_unix_time_from_system() - float(modificado)
	return idade >= -1.0 and idade <= idade_maxima_seg


func _serial_bridge_viva() -> bool:
	return _serial_arquivo_recente(_serial_alive_path, SERIAL_ALIVE_TIMEOUT_SEG)


func _serial_bridge_iniciando() -> bool:
	return _serial_arquivo_recente(_serial_starting_path, SERIAL_STARTING_TIMEOUT_SEG)


func _serial_limpar_spool_antigo() -> void:
	var pasta := DirAccess.open(_serial_spool_dir)
	if pasta == null:
		return

	for nome in pasta.get_files():
		if nome.ends_with(".cmd") or nome.contains(".tmp_"):
			pasta.remove(nome)


func _arduino_montar_script_shell() -> String:
	var spool_ps: String = _powershell_literal(_serial_spool_dir)
	var heartbeat_ps: String = _powershell_literal(_serial_heartbeat_path)
	var alive_ps: String = _powershell_literal(_serial_alive_path)
	var ready_ps: String = _powershell_literal(_serial_ready_path)
	var starting_ps: String = _powershell_literal(_serial_starting_path)
	var porta_ps: String = _powershell_literal(SERIAL_PORTA)

	return (
		"""
$ErrorActionPreference = 'Stop'
$spool = %s
$heartbeat = %s
$alive = %s
$ready = %s
$starting = %s
$portaNome = %s
$baud = %d
$timeoutHb = %s
$gapComandoMs = %d
$serial = $null
$ultimoAlive = [DateTime]::MinValue
$semHeartbeatDesde = $null

function Touch-File([string]$path) {
	[System.IO.File]::WriteAllText($path, [DateTime]::UtcNow.Ticks.ToString())
}

New-Item -ItemType Directory -Path $spool -Force | Out-Null

try {
	while ($true) {
		$agoraUtc = [DateTime]::UtcNow
		if (($agoraUtc - $ultimoAlive).TotalMilliseconds -ge 250) {
			Touch-File $alive
			$ultimoAlive = $agoraUtc
		}

		if (-not (Test-Path -LiteralPath $heartbeat)) {
			if ($null -eq $semHeartbeatDesde) {
				$semHeartbeatDesde = $agoraUtc
			}
			elseif (($agoraUtc - $semHeartbeatDesde).TotalSeconds -gt $timeoutHb) {
				break
			}
			Start-Sleep -Milliseconds 100
			continue
		}

		$semHeartbeatDesde = $null
		$idadeHb = ($agoraUtc - (Get-Item -LiteralPath $heartbeat).LastWriteTimeUtc).TotalSeconds
		if ($idadeHb -gt $timeoutHb) {
			break
		}

		if ($null -eq $serial -or -not $serial.IsOpen) {
			Remove-Item -LiteralPath $ready -Force -ErrorAction SilentlyContinue

			try {
				$serial = [System.IO.Ports.SerialPort]::new(
					$portaNome,
					$baud,
					[System.IO.Ports.Parity]::None,
					8,
					[System.IO.Ports.StopBits]::One
				)
				$serial.Handshake = [System.IO.Ports.Handshake]::None
				$serial.NewLine = "`n"
				$serial.Encoding = [System.Text.Encoding]::ASCII
				$serial.DtrEnable = $false
				$serial.RtsEnable = $false
				$serial.WriteTimeout = 250
				$serial.ReadTimeout = 90
				$serial.Open()

				# O Nano pode reiniciar quando a porta abre. Esperamos o boot terminar.
				Start-Sleep -Milliseconds 1900
				$serial.DiscardOutBuffer()
				$serial.DiscardInBuffer()

				# Handshake: só considera a COM5 pronta se estiver com o sketch correto.
				$serial.Write("HELLO`n")
				$confirmado = $false
				$limiteHandshake = [DateTime]::UtcNow.AddMilliseconds(1400)

				while (-not $confirmado -and [DateTime]::UtcNow -lt $limiteHandshake) {
					try {
						$resposta = $serial.ReadLine().Trim()
						if ($resposta -eq 'HITMUSIC_OK') {
							$confirmado = $true
						}
					}
					catch [System.TimeoutException] {}
				}

				if (-not $confirmado) {
					throw 'A COM5 abriu, mas o Arduino não respondeu HITMUSIC_OK.'
				}

				$serial.Write("CLEAR`n")
				Touch-File $ready
				Remove-Item -LiteralPath $starting -Force -ErrorAction SilentlyContinue
			}
			catch {
				try {
					if ($null -ne $serial) {
						$serial.Close()
						$serial.Dispose()
					}
				} catch {}
				$serial = $null
				Start-Sleep -Milliseconds 500
				continue
			}
		}

		$arquivos = Get-ChildItem -LiteralPath $spool -Filter '*.cmd' -File |
			Sort-Object -Property Name

		foreach ($arquivoCmd in $arquivos) {
			try {
				$cmd = [System.IO.File]::ReadAllText($arquivoCmd.FullName).Trim()
				if ($cmd.Length -gt 0) {
					$serial.Write($cmd + "`n")
					$serial.BaseStream.Flush()
					Start-Sleep -Milliseconds $gapComandoMs
				}
				Remove-Item -LiteralPath $arquivoCmd.FullName -Force
			}
			catch {
				try {
					if ($null -ne $serial) {
						$serial.Close()
						$serial.Dispose()
					}
				} catch {}
				$serial = $null
				Remove-Item -LiteralPath $ready -Force -ErrorAction SilentlyContinue
				break
			}
		}

		Start-Sleep -Milliseconds 8
	}
}
finally {
	try {
		if ($null -ne $serial -and $serial.IsOpen) {
			$serial.Write("CLEAR`n")
			$serial.Close()
		}
		if ($null -ne $serial) {
			$serial.Dispose()
		}
	} catch {}

	Remove-Item -LiteralPath $ready -Force -ErrorAction SilentlyContinue
	Remove-Item -LiteralPath $alive -Force -ErrorAction SilentlyContinue
	Remove-Item -LiteralPath $starting -Force -ErrorAction SilentlyContinue
}
"""
		% [
			spool_ps,
			heartbeat_ps,
			alive_ps,
			ready_ps,
			starting_ps,
			porta_ps,
			SERIAL_BAUD,
			str(SERIAL_HEARTBEAT_TIMEOUT_SEG).replace(",", "."),
			SERIAL_INTERVALO_ENTRE_COMANDOS_MS
		]
	)


func _serial_gravar_heartbeat() -> void:
	_serial_configurar_caminhos()
	var arquivo := FileAccess.open(_serial_heartbeat_path, FileAccess.WRITE)
	if arquivo == null:
		return
	arquivo.store_string(str(Time.get_unix_time_from_system()))
	arquivo.flush()
	arquivo.close()


func _arduino_inicializar() -> void:
	if not SERIAL_ATIVADO:
		return

	_serial_configurar_caminhos()
	_serial_inicializado = true
	if _serial_tentativa_inicio_msec < 0:
		_serial_tentativa_inicio_msec = Time.get_ticks_msec()
	_serial_gravar_heartbeat()

	if OS.get_name() != "Windows":
		if not _serial_aviso_mostrado:
			_serial_aviso_mostrado = true
			push_warning("A comunicação COM5 deste jogo foi preparada para Windows.")
		return

	if _serial_bridge_viva() or _serial_bridge_iniciando():
		return

	# Só limpamos comandos antigos quando realmente será criada uma ponte nova.
	_serial_limpar_spool_antigo()
	_serial_escrever_atomico(_serial_starting_path, str(Time.get_unix_time_from_system()))

	var script_shell: String = _arduino_montar_script_shell()
	var script_codificado: String = Marshalls.raw_to_base64(script_shell.to_utf16_buffer())
	var argumentos := PackedStringArray(
		[
			"-NoLogo",
			"-NoProfile",
			"-NonInteractive",
			"-ExecutionPolicy",
			"Bypass",
			"-WindowStyle",
			"Hidden",
			"-EncodedCommand",
			script_codificado
		]
	)

	var pid: int = OS.create_process("powershell.exe", argumentos, false)
	if pid <= 0:
		if FileAccess.file_exists(_serial_starting_path):
			DirAccess.remove_absolute(_serial_starting_path)
		if not _serial_aviso_mostrado:
			_serial_aviso_mostrado = true
			push_warning("Não consegui iniciar a ponte invisível da COM5.")
		return

	_serial_spawn_solicitado = true
	_serial_aviso_mostrado = false
	_serial_tentativa_inicio_msec = Time.get_ticks_msec()
	_serial_conexao_aviso_mostrado = false
	print("HIT MUSIC: ponte persistente solicitada em COM5 / 9600. PID: ", pid)


func _serial_criar_comando_atomico(comando: String) -> bool:
	_serial_configurar_caminhos()
	_serial_sequencia += 1

	var nome_base: String = (
		"cmd_%020d_%06d_%d" % [Time.get_ticks_usec(), _serial_sequencia, OS.get_process_id()]
	)
	var caminho_final: String = _serial_spool_dir.path_join(nome_base + ".cmd")
	return _serial_escrever_atomico(caminho_final, comando + "\n")


func _serial_reduzir_pendentes(comando: String) -> void:
	var prefixo: String = comando.get_slice(" ", 0).to_upper()

	if prefixo == "ATTRACT" or prefixo == "BLINKALL" or prefixo == "READY":
		_serial_pendentes.clear()
	elif prefixo == "COUNT":
		for i in range(_serial_pendentes.size() - 1, -1, -1):
			if _serial_pendentes[i].begins_with("COUNT "):
				_serial_pendentes.remove_at(i)
	elif prefixo == "CLEAR":
		for i in range(_serial_pendentes.size() - 1, -1, -1):
			var antigo: String = _serial_pendentes[i]
			if antigo.begins_with("LED ") or antigo == "CLEAR":
				_serial_pendentes.remove_at(i)
	elif prefixo == "LED":
		# Nunca comprime transições LED. Mesmo se a ponte estiver momentaneamente
		# ocupada, o LIGAR precisa chegar antes do DESLIGAR daquele mesmo evento.
		pass

	_serial_pendentes.append(comando)
	# Não descarta comandos por tamanho de fila. Perder o comando mais antigo aqui
	# poderia eliminar justamente o LIGAR de um alvo que ainda vai aparecer.


func _serial_drenar_pendentes() -> void:
	if _serial_pendentes.is_empty():
		return

	# Drena tudo que estiver pendente. Cada LED é um canal independente; uma leva
	# anterior não pode obrigar os próximos alvos a esperar outro tick do jogo.
	while not _serial_pendentes.is_empty():
		var comando: String = _serial_pendentes[0]
		if not _serial_criar_comando_atomico(comando):
			break
		_serial_pendentes.pop_front()


func _arduino_tick_serial() -> void:
	if not SERIAL_ATIVADO:
		return

	if not _serial_inicializado:
		_arduino_inicializar()

	var agora: int = Time.get_ticks_msec()

	if agora - _serial_ultimo_heartbeat_msec >= SERIAL_HEARTBEAT_INTERVALO_MS:
		_serial_ultimo_heartbeat_msec = agora
		_serial_gravar_heartbeat()

	var ponte_pronta: bool = _serial_bridge_viva() and FileAccess.file_exists(_serial_ready_path)
	if ponte_pronta:
		if not _serial_pronta_anunciada:
			_serial_pronta_anunciada = true
			_serial_conexao_aviso_mostrado = false
			# A placa pode ter reiniciado enquanto a ponte reconectava. Força uma
			# reconstrução imediata dos oito estados, sem depender do cache.
			for i in range(_led_assinaturas_por_ponto.size()):
				_led_assinaturas_por_ponto[i] = ""
				var cor_restaurada: Color = (
					_cor_led_guia(i) if _led_donos_por_ponto[i] > 0 else Color.BLACK
				)
				_led_enviar_cor_independente(i, cor_restaurada)
			print("HIT MUSIC: Arduino confirmado na COM5 (HITMUSIC_OK).")
	else:
		if _serial_pronta_anunciada:
			_serial_pronta_anunciada = false
			_serial_tentativa_inicio_msec = agora
		if (
			_serial_tentativa_inicio_msec >= 0
			and agora - _serial_tentativa_inicio_msec > 7000
			and not _serial_conexao_aviso_mostrado
		):
			_serial_conexao_aviso_mostrado = true
			push_warning(
				"COM5 ainda não confirmou HITMUSIC_OK. Feche o Monitor Serial e confira o sketch e a alimentação."
			)

	_serial_drenar_pendentes()

	if agora - _serial_ultima_verificacao_msec < SERIAL_VERIFICACAO_INTERVALO_MS:
		return

	_serial_ultima_verificacao_msec = agora
	if not _serial_bridge_viva() and not _serial_bridge_iniciando():
		_serial_spawn_solicitado = false
		_arduino_inicializar()


func _arduino_enviar_linha(linha: String) -> bool:
	if not SERIAL_ATIVADO:
		return false

	var comando: String = linha.strip_edges()
	if comando.is_empty():
		return false

	if not _serial_inicializado:
		_arduino_inicializar()

	if _serial_criar_comando_atomico(comando):
		return true

	_serial_reduzir_pendentes(comando)
	return false


func _serial_encerrar_aplicativo() -> void:
	if not SERIAL_ATIVADO:
		return

	# O comando é gravado antes do processo fechar. Depois, sem novos heartbeats,
	# a ponte encerra sozinha e também envia CLEAR no bloco finally.
	_arduino_enviar_forcado("CLEAR")
	_serial_drenar_pendentes()


func _notification(what: int) -> void:
	# IMPORTANTE: não encerra no PREDELETE, porque PREDELETE também acontece
	# durante a troca abertura -> jogo e jogo -> abertura.
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_serial_encerrar_aplicativo()


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

	float alpha_fora = smoothstep(
		raio_px - suavizacao_px,
		raio_px + suavizacao_px,
		dist
	);

	float pulso = sin(TIME * 1.85) * 0.5 + 0.5;
	vec3 vermelho = vec3(0.72, 0.035, 0.92);
	vec3 branco = vec3(1.0, 0.98, 0.98);

	// Duas bordas Soul Eater: roxo/magenta externo e branco interno.
	float anel_externo = 1.0 - smoothstep(
		0.0,
		suavizacao_px * 5.8,
		abs(dist - raio_px)
	);
	float anel_interno = 1.0 - smoothstep(
		0.0,
		suavizacao_px * 3.2,
		abs(dist - (raio_px - suavizacao_px * 4.8))
	);
	float halo = 1.0 - smoothstep(
		0.0,
		suavizacao_px * 11.0,
		abs(dist - (raio_px - suavizacao_px * 1.6))
	);

	vec3 cor_externa = mix(vermelho * 0.82, vermelho, pulso);
	vec3 cor_interna = mix(branco, vermelho * 0.92, pulso * 0.18);
	vec3 cor_final = (
		cor_externa * anel_externo * 1.12
		+ cor_interna * anel_interno * 0.98
		+ vermelho * halo * 0.12
	);
	float alpha_final = max(
		alpha_fora,
		max(anel_externo * 0.96, anel_interno * 0.90 + halo * 0.12)
	);

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
	_ponto_niveis_visuais.clear()
	_ponto_flash_inicio_msec.clear()
	_ponto_flash_fim_msec.clear()
	_ponto_flash_cores.clear()
	_ponto_apagar_em_msec.clear()

	var textura_tazo_fixa: Texture2D = null
	if TAZO_USAR_SHEET_FIXO and ResourceLoader.exists(CAMINHO_TAZO_SHEET_FIXO):
		textura_tazo_fixa = load(CAMINHO_TAZO_SHEET_FIXO)

	var cena_tazo: PackedScene = null
	if textura_tazo_fixa == null:
		if ResourceLoader.exists(CAMINHO_TAZO_SCENE):
			cena_tazo = load(CAMINHO_TAZO_SCENE)
		else:
			push_warning(
				(
					"Não encontrei "
					+ CAMINHO_TAZO_SCENE
					+ " nem "
					+ CAMINHO_TAZO_SHEET_FIXO
					+ " — usando bolinha fallback."
				)
			)

	var raio_posicionamento: float = _raio_circulo_px * RAIO_POS_PONTOS_RATIO
	var raio_visual_ponto: float = (_raio_circulo_px * TAZO_DIAMETRO_RATIO) * 0.5
	var centro_pontos: Vector2 = (
		_centro_tela + Vector2(0.0, _raio_circulo_px * DESLOCAMENTO_Y_PONTOS_RATIO)
	)
	_raio_toque_ponto_px = raio_visual_ponto * RAIO_TOQUE_EXTRA_RATIO

	for i in range(NUM_PONTOS):
		var angulo: float = -PI / 2.0 + i * (TAU / NUM_PONTOS)
		var pos: Vector2 = centro_pontos + Vector2(cos(angulo), sin(angulo)) * raio_posicionamento

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
				push_warning(
					(
						"A raiz do tazo.tscn precisa ser Node2D/Area2D. Usando fallback no ponto "
						+ str(i)
					)
				)
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
		_ponto_niveis_visuais.append(0.0)
		_ponto_flash_inicio_msec.append(0)
		_ponto_flash_fim_msec.append(0)
		_ponto_flash_cores.append(Color.WHITE)
		_ponto_apagar_em_msec.append(0)

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


func _ponto_set_estado(
	indice: int, estado: String, flash_tempo: float = 0.0, flash_cor: Color = Color.WHITE
) -> void:
	if indice < 0 or indice >= _pontos.size():
		return

	var estado_anterior: String = (
		str(_ponto_estados[indice]) if indice < _ponto_estados.size() else ""
	)
	var mudou_estado: bool = estado_anterior != estado
	if indice < _ponto_estados.size():
		_ponto_estados[indice] = estado
	if estado != "idle" and indice < _ponto_apagar_em_msec.size():
		_ponto_apagar_em_msec[indice] = 0

	var ponto: Node2D = _pontos[indice]
	if ponto is PontoRitmo:
		var ponto_fallback: PontoRitmo = ponto
		ponto_fallback.estado = estado
		ponto_fallback.flash_tempo = flash_tempo
		ponto_fallback.flash_cor = flash_cor

	# A troca do frame acontece uma vez; brilho, escala e apagamento são interpolados por frame.
	if mudou_estado:
		_tazo_tocar_animacao(indice, estado != "idle")

	if flash_tempo > 0.0:
		_tazo_flash(indice, flash_cor, flash_tempo)


func _agendar_apagamento_tazo(indice: int, atraso_seg: float) -> void:
	if indice < 0 or indice >= _pontos.size():
		return
	if indice >= _ponto_apagar_em_msec.size():
		return
	_ponto_apagar_em_msec[indice] = Time.get_ticks_msec() + max(1, int(atraso_seg * 1000.0))


func _atualizar_apagamentos_tazos() -> void:
	if _ponto_apagar_em_msec.is_empty():
		return
	var agora: int = Time.get_ticks_msec()
	for i in range(_ponto_apagar_em_msec.size()):
		var prazo: int = _ponto_apagar_em_msec[i]
		if prazo > 0 and agora >= prazo:
			_ponto_apagar_em_msec[i] = 0
			_ponto_set_estado(i, "idle")


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
		spr.region_rect = _tazo_region_rect(
			TAZO_ACESO_FRAME_INDEX if aceso else TAZO_IDLE_FRAME_INDEX
		)
		return

	# Fallback para AnimatedSprite2D da sua tazo.tscn.
	if sprite_node is AnimatedSprite2D:
		var sprite: AnimatedSprite2D = sprite_node
		if sprite.sprite_frames == null:
			return
		var anim: String = _tazo_animacao_existente(
			sprite, TAZO_ANIM_ACESO if aceso else TAZO_ANIM_IDLE, aceso
		)
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
	return Rect2(
		Vector2(float(idx * TAZO_SHEET_FRAME_SIZE.x), 0.0),
		Vector2(float(TAZO_SHEET_FRAME_SIZE.x), float(TAZO_SHEET_FRAME_SIZE.y))
	)


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
	var agora: int = Time.get_ticks_msec()
	var duracao_ms: int = max(1, int(tempo * 1000.0))
	_ponto_flash_inicio_msec[indice] = agora
	_ponto_flash_fim_msec[indice] = agora + duracao_ms
	_ponto_flash_cores[indice] = cor


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
	_tazo_shader_set_nivel(indice, 1.0 if ativo else 0.0, cor, forca)


func _tazo_shader_set_nivel(indice: int, nivel: float, cor: Color, forca: float) -> void:
	if indice < 0 or indice >= _ponto_sprites.size():
		return
	var sprite_node: Node2D = _ponto_sprites[indice]
	if (
		sprite_node == null
		or not is_instance_valid(sprite_node)
		or not (sprite_node.material is ShaderMaterial)
	):
		return
	var mat: ShaderMaterial = sprite_node.material
	mat.set_shader_parameter("ativo", clamp(nivel, 0.0, 1.0))
	mat.set_shader_parameter("cor_brilho", cor)
	mat.set_shader_parameter("forca", max(forca, 0.0))


func _atualizar_transicoes_tazos(delta: float) -> void:
	if _pontos.is_empty():
		return

	var agora: int = Time.get_ticks_msec()
	var tempo: float = float(agora) / 1000.0
	var limite: int = min(_pontos.size(), _ponto_niveis_visuais.size())

	for i in range(limite):
		var ativo_estado: bool = i < _ponto_estados.size() and str(_ponto_estados[i]) != "idle"
		var alvo: float = 1.0 if ativo_estado else 0.0
		var velocidade: float = TAZO_VELOCIDADE_ACENDER if ativo_estado else TAZO_VELOCIDADE_APAGAR
		_ponto_niveis_visuais[i] = move_toward(_ponto_niveis_visuais[i], alvo, velocidade * delta)

		var nivel: float = _ponto_niveis_visuais[i]
		var flash_nivel: float = 0.0
		var flash_cor: Color = _cor_orbe_por_ponto(i)
		if i < _ponto_flash_fim_msec.size() and agora < _ponto_flash_fim_msec[i]:
			var inicio: int = _ponto_flash_inicio_msec[i]
			var fim: int = _ponto_flash_fim_msec[i]
			var duracao: float = max(float(fim - inicio), 1.0)
			flash_nivel = 1.0 - clamp(float(agora - inicio) / duracao, 0.0, 1.0)
			flash_cor = _ponto_flash_cores[i]

		var sprite_node: Node2D = _ponto_sprites[i] if i < _ponto_sprites.size() else null
		if sprite_node != null and is_instance_valid(sprite_node):
			var pulso: float = sin(tempo * 7.0 + float(i) * 0.85) * 0.5 + 0.5
			var escala_extra: float = nivel * (TAZO_ESCALA_ATIVA_EXTRA + pulso * TAZO_PULSO_ESCALA)
			var impacto: float = sin((1.0 - flash_nivel) * PI) * 0.12 if flash_nivel > 0.0 else 0.0
			sprite_node.scale = Vector2.ONE * (1.0 + escala_extra + impacto)
			sprite_node.modulate = Color.WHITE.lerp(flash_cor, flash_nivel * 0.42)

		var nivel_shader: float = max(nivel, flash_nivel)
		var cor_shader: Color = flash_cor if flash_nivel > 0.0 else _cor_orbe_por_ponto(i)
		var forca_shader: float = lerp(0.35, TAZO_BRILHO_ATIVO, nivel) + flash_nivel * 0.85
		_tazo_shader_set_nivel(i, nivel_shader, cor_shader, forca_shader)


func _desenhar_efeitos_tazos_modernos() -> void:
	# O efeito principal agora fica no shader dos próprios Tazos.
	# Aqui desenhamos apenas a ligação e um anel simples para manter o visual moderno
	# sem dezenas de arcos e círculos sendo recalculados em cada frame.
	if _pontos.is_empty():
		return

	var tempo: float = Time.get_ticks_msec() / 1000.0
	for i in range(_pontos.size()):
		var ponto: Node2D = _pontos[i]
		if ponto == null or not is_instance_valid(ponto):
			continue

		var nivel: float = _ponto_niveis_visuais[i] if i < _ponto_niveis_visuais.size() else 0.0
		var cor: Color = _cor_orbe_por_ponto(i)
		var raio: float = _ponto_raio(i)
		var pulso: float = sin(tempo * 5.2 + float(i) * 0.8) * 0.5 + 0.5

		draw_line(
			_centro_tela,
			ponto.position,
			Color(cor.r, cor.g, cor.b, 0.018 + nivel * 0.12),
			1.0 + nivel * 1.7,
			true
		)

		if nivel > 0.01:
			draw_arc(
				ponto.position,
				raio * (1.25 + pulso * 0.04),
				tempo * 0.9 + float(i) * 0.35,
				tempo * 0.9 + float(i) * 0.35 + PI * 1.35,
				24,
				Color(cor.r, cor.g, cor.b, nivel * 0.74),
				2.0 + nivel * 1.8,
				true
			)


func _criar_shader_tazo_brilho() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;

uniform float ativo = 0.0;
uniform vec4 cor_brilho : source_color = vec4(1.0, 0.2, 0.9, 1.0);
uniform float forca : hint_range(0.0, 3.0) = 1.15;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec2 px = TEXTURE_PIXEL_SIZE * 2.2;

	float a1 = texture(TEXTURE, UV + vec2(px.x, 0.0)).a;
	float a2 = texture(TEXTURE, UV - vec2(px.x, 0.0)).a;
	float a3 = texture(TEXTURE, UV + vec2(0.0, px.y)).a;
	float a4 = texture(TEXTURE, UV - vec2(0.0, px.y)).a;
	float vizinho = max(max(a1, a2), max(a3, a4));
	float contorno = max(vizinho - tex.a, 0.0);

	float pulso = sin(TIME * 7.2) * 0.5 + 0.5;
	float varredura = smoothstep(0.72, 1.0, sin((UV.y + UV.x * 0.35) * 16.0 - TIME * 5.0) * 0.5 + 0.5);
	float brilho_base = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	float mascara = smoothstep(0.16, 0.88, brilho_base);

	vec3 neon_interno = cor_brilho.rgb
		* (0.10 + pulso * 0.22 + varredura * 0.16)
		* mascara
		* forca
		* ativo;

	float halo = contorno * ativo * (0.45 + pulso * 0.45) * min(forca, 2.2);
	vec3 cor_final = tex.rgb + neon_interno + cor_brilho.rgb * halo;
	float alpha_final = max(tex.a, halo * 0.72);

	COLOR = vec4(cor_final, alpha_final);
}
"""
	return sh


func _criar_hud() -> void:
	var camada := CanvasLayer.new()
	camada.layer = 5
	add_child(camada)

	var largura_painel: float = _raio_circulo_px * 0.56
	var altura_painel: float = _raio_circulo_px * 0.20
	var largura_tempo: float = largura_painel * 0.56
	var altura_tempo: float = altura_painel * 0.62
	var vao_entre_paineis: float = _raio_circulo_px * 0.025

	# O placar/cronômetro não pode nunca ficar em cima do sprite do Tazo do topo
	# (ponto A, índice 0, que fica bem no topo do círculo -- ângulo -90°). Calculamos
	# até onde esse Tazo (e o anel de destaque/flash que passa um pouco do seu raio
	# visual) desce, e só então decidimos onde o HUD começa: se a posição "padrão"
	# (mais colada no topo) já tem folga, ela é mantida; se não tem, o HUD desce o
	# suficiente pra sempre sobrar um respiro entre os dois.
	var centro_ponto_topo_y: float = (
		_centro_tela.y
		+ _raio_circulo_px * DESLOCAMENTO_Y_PONTOS_RATIO
		- _raio_circulo_px * RAIO_POS_PONTOS_RATIO
	)
	var raio_visual_ponto_topo: float = (_raio_circulo_px * TAZO_DIAMETRO_RATIO) * 0.5
	var borda_inferior_ponto_topo: float = centro_ponto_topo_y + raio_visual_ponto_topo * 1.8
	var folga_seguranca: float = _raio_circulo_px * 0.025

	var topo_padrao_tempo_y: float = (
		(_centro_tela.y - _raio_circulo_px * 0.60)
		- altura_tempo
		- vao_entre_paineis
		+ _raio_circulo_px * DESLOCAMENTO_Y_HUD_RATIO
	)
	var topo_tempo_y: float = max(topo_padrao_tempo_y, borda_inferior_ponto_topo + folga_seguranca)
	var topo_painel_y: float = topo_tempo_y + altura_tempo + vao_entre_paineis

	var painel := Panel.new()
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0.03, 0.0, 0.07, 0.72)
	estilo.set_border_width_all(2)
	estilo.border_color = Color(COR_SOUL_BRANCO.r, COR_SOUL_BRANCO.g, COR_SOUL_BRANCO.b, 0.86)
	estilo.set_corner_radius_all(int(altura_painel * 0.5))
	estilo.shadow_color = Color(COR_SOUL_VERMELHO.r, COR_SOUL_VERMELHO.g, COR_SOUL_VERMELHO.b, 0.42)
	estilo.shadow_size = 16
	painel.add_theme_stylebox_override("panel", estilo)
	painel.size = Vector2(largura_painel, altura_painel)
	painel.position = Vector2(_centro_tela.x - largura_painel / 2.0, topo_painel_y)
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
	config_pontuacao.outline_color = Color(
		COR_SOUL_VERMELHO.r, COR_SOUL_VERMELHO.g, COR_SOUL_VERMELHO.b, 0.86
	)

	_label_pontuacao = Label.new()
	_label_pontuacao.label_settings = config_pontuacao
	_label_pontuacao.text = "0"
	_label_pontuacao.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label_pontuacao.size = Vector2(largura_painel, altura_painel * 0.6)
	_label_pontuacao.position = Vector2(0, altura_painel * 0.40)
	painel.add_child(_label_pontuacao)

	# Painelzinho de tempo, encaixado logo acima do placar, no mesmo vão do topo.
	var painel_tempo := Panel.new()
	var estilo_tempo := StyleBoxFlat.new()
	estilo_tempo.bg_color = Color(0.03, 0.0, 0.07, 0.75)
	estilo_tempo.set_border_width_all(2)
	estilo_tempo.border_color = Color(COR_SOUL_VERMELHO.r, COR_SOUL_VERMELHO.g, COR_SOUL_VERMELHO.b, 0.94)
	estilo_tempo.set_corner_radius_all(int(altura_tempo * 0.5))
	estilo_tempo.shadow_color = Color(COR_SOUL_BRANCO.r, COR_SOUL_BRANCO.g, COR_SOUL_BRANCO.b, 0.24)
	estilo_tempo.shadow_size = 12
	painel_tempo.add_theme_stylebox_override("panel", estilo_tempo)
	painel_tempo.size = Vector2(largura_tempo, altura_tempo)
	painel_tempo.position = Vector2(_centro_tela.x - largura_tempo / 2.0, topo_tempo_y)
	camada.add_child(painel_tempo)

	var config_tempo := LabelSettings.new()
	config_tempo.font_size = int(altura_tempo * 0.5)
	config_tempo.font_color = Color.WHITE
	config_tempo.outline_size = 2
	config_tempo.outline_color = Color(
		COR_SOUL_VERMELHO.r, COR_SOUL_VERMELHO.g, COR_SOUL_VERMELHO.b, 0.88
	)

	_label_tempo = Label.new()
	_label_tempo.label_settings = config_tempo
	_label_tempo.text = "1:35"
	_label_tempo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label_tempo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label_tempo.size = Vector2(largura_tempo, altura_tempo)
	painel_tempo.add_child(_label_tempo)

	# Combo, logo abaixo do placar -- some quando o combo é 0 ou 1.
	var config_combo := LabelSettings.new()
	config_combo.font_size = int(altura_painel * 0.34)
	config_combo.font_color = COR_NEON_VERDE
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
func _preparar_duracao_musica() -> void:
	var stream: AudioStream = load(CAMINHO_MUSICA)
	if stream == null:
		_duracao_musica_seg = DURACAO_PARTIDA_FALLBACK_SEG
		push_warning(
			(
				"Não foi possível ler a duração da música. Usando fallback de %.2f s."
				% _duracao_musica_seg
			)
		)
		return

	var duracao_lida: float = stream.get_length()
	if duracao_lida > 1.0:
		_duracao_musica_seg = duracao_lida
	else:
		_duracao_musica_seg = DURACAO_PARTIDA_FALLBACK_SEG
		push_warning(
			(
				"O importador retornou duração inválida. Usando fallback de %.2f s."
				% _duracao_musica_seg
			)
		)

	print("HIT MUSIC - duração real da faixa: %.3f s" % _duracao_musica_seg)


func _atraso_saida_musica_seg() -> float:
	if SINCRONIA_AUDIO_COM_ATRASO and _usando_deteccao_beat:
		return DETECCAO_ANTECIPACAO_SEG
	return 0.0


func _recalcular_duracao_total_jogo() -> void:
	# Inclui o atraso audível e uma margem mínima para o último transient terminar.
	_duracao_total_jogo_seg = (
		_duracao_musica_seg + _atraso_saida_musica_seg() + MARGEM_FINAL_MUSICA_SEG
	)
	_tempo_restante = _duracao_total_jogo_seg


func _configurar_atraso_bus_musica() -> void:
	if _indice_bus_musica < 0:
		_indice_bus_musica = AudioServer.get_bus_index(BUS_MUSICA_HIT)
	if _indice_bus_musica < 0:
		return

	# O analisador fica no efeito 0 e o delay no efeito 1.
	if AudioServer.get_bus_effect_count(_indice_bus_musica) < 2:
		return

	var efeito: AudioEffect = AudioServer.get_bus_effect(_indice_bus_musica, 1)
	if not (efeito is AudioEffectDelay):
		return

	var delay := efeito as AudioEffectDelay
	var usar_atraso: bool = SINCRONIA_AUDIO_COM_ATRASO and _usando_deteccao_beat
	delay.dry = 0.0 if usar_atraso else 1.0
	delay.tap1_active = usar_atraso
	delay.tap1_delay_ms = DETECCAO_ANTECIPACAO_SEG * 1000.0
	delay.tap1_level_db = 0.0
	delay.tap1_pan = 0.0
	delay.tap2_active = false
	delay.feedback_active = false


func _obter_volume_musica_db() -> float:
	if _indice_bus_musica >= 0 and _indice_bus_musica < AudioServer.get_bus_count():
		_volume_musica_db = AudioServer.get_bus_volume_db(_indice_bus_musica)
	return clamp(_volume_musica_db, VOLUME_MIN_DB, VOLUME_MAX_DB)


func _aplicar_volume_musica_imediato(novo_db: float) -> void:
	_volume_musica_db = clamp(novo_db, VOLUME_MIN_DB, VOLUME_MAX_DB)
	if _indice_bus_musica < 0:
		_indice_bus_musica = AudioServer.get_bus_index(BUS_MUSICA_HIT)
	if _indice_bus_musica >= 0:
		# O volume do barramento é aplicado depois da cadeia analisador/delay. Por isso
		# afeta imediatamente inclusive o áudio que já estava armazenado no delay.
		AudioServer.set_bus_volume_db(_indice_bus_musica, _volume_musica_db)


func _alterar_volume_musica_imediato(delta_db: float) -> void:
	_aplicar_volume_musica_imediato(_obter_volume_musica_db() + delta_db)


func _tocar_musica() -> void:
	if _musica_player != null and is_instance_valid(_musica_player):
		if _musica_player.playing or _musica_fonte_finalizada:
			return
		_musica_player.queue_free()
		_musica_player = null

	var stream_original: AudioStream = load(CAMINHO_MUSICA)
	_musica_inicio_msec = Time.get_ticks_msec()
	_musica_fonte_finalizada = false
	_musica_fim_fonte_msec = -1
	_ultimo_tempo_musica_seg = 0.0

	if stream_original == null:
		push_warning("Música não encontrada em: " + CAMINHO_MUSICA)
		return

	# Garante execução única da faixa. O jogo termina pela duração real do arquivo,
	# nunca mais por um cronômetro fixo ou por loop.
	var stream: AudioStream = stream_original.duplicate() as AudioStream
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = false
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = false
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_DISABLED

	_musica_player = AudioStreamPlayer.new()
	_musica_player.stream = stream
	_musica_player.bus = (
		BUS_MUSICA_HIT if AudioServer.get_bus_index(BUS_MUSICA_HIT) >= 0 else "Master"
	)
	_musica_player.volume_db = 0.0
	_aplicar_volume_musica_imediato(_volume_musica_db)
	_musica_player.finished.connect(_ao_musica_terminar)
	add_child(_musica_player)
	_musica_player.play()


func _ao_musica_terminar() -> void:
	# O próprio player confirmou o fim da fonte. Usamos o tempo realmente transcorrido
	# como duração final, evitando confiar cegamente em um valor incorreto do importador.
	_musica_fonte_finalizada = true
	_musica_fim_fonte_msec = Time.get_ticks_msec()
	var duracao_real_fonte: float = max(
		_ultimo_tempo_musica_seg, float(_musica_fim_fonte_msec - _musica_inicio_msec) / 1000.0
	)
	_duracao_musica_seg = max(duracao_real_fonte, 0.01)
	_ultimo_tempo_musica_seg = _duracao_musica_seg
	_recalcular_duracao_total_jogo()


func _encerrar_partida() -> void:
	if _partida_encerrada or _finalizacao_em_andamento:
		return

	_partida_encerrada = true
	_finalizacao_em_andamento = true
	for i in range(NUM_PONTOS):
		_led_donos_por_ponto[i] = 0
		_led_assinaturas_por_ponto[i] = ""
	_eventos_ativos.clear()
	_fila_eventos_musicais.clear()
	_arraste_evento_atual = null
	_arraste_gesto_ativo = false
	_arduino_enviar_unico("CLEAR")
	_iniciar_finalizacao_suave()


func _iniciar_finalizacao_suave() -> void:
	_finalizacao_layer = CanvasLayer.new()
	_finalizacao_layer.layer = 35
	add_child(_finalizacao_layer)

	_finalizacao_overlay = ColorRect.new()
	_finalizacao_overlay.size = get_viewport_rect().size
	_finalizacao_overlay.color = Color(0.005, 0.008, 0.018, 1.0)
	_finalizacao_overlay.modulate = Color(1, 1, 1, 0.0)
	_finalizacao_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_finalizacao_layer.add_child(_finalizacao_overlay)

	var tw: Tween = create_tween()
	tw.set_parallel(true)
	(
		tw
		. tween_property(
			_finalizacao_overlay, "modulate", Color(1, 1, 1, 0.64), DURACAO_TRANSICAO_FINAL_SEG
		)
		. set_trans(Tween.TRANS_QUINT)
		. set_ease(Tween.EASE_IN_OUT)
	)
	if _video_fundo and is_instance_valid(_video_fundo):
		(
			tw
			. tween_property(
				_video_fundo,
				"modulate",
				Color(1, 1, 1, VIDEO_FUNDO_ALPHA * 0.32),
				DURACAO_TRANSICAO_FINAL_SEG
			)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_IN_OUT)
		)
	tw.finished.connect(_concluir_finalizacao_e_abrir_modal)


func _concluir_finalizacao_e_abrir_modal() -> void:
	# Não chama stop(): a música já terminou naturalmente e não deve ser cortada.
	if _video_fundo and is_instance_valid(_video_fundo):
		_video_fundo.paused = true

	_carregar_e_atualizar_recordes()
	musica_concluida.emit()
	_arduino_enviar_unico("COUNT " + str(int(TEMPO_MODAL_CONTINUAR_SEG)))
	_finalizacao_em_andamento = false
	_mostrar_modal_continuar()


func _mostrar_modal_continuar() -> void:
	if _modal_continuar_ativo:
		return

	_modal_continuar_ativo = true
	_modal_em_transicao = true
	_modal_countdown_restante = TEMPO_MODAL_CONTINUAR_SEG
	_modal_ultimo_numero_led = -1

	_modal_layer = CanvasLayer.new()
	_modal_layer.layer = 40
	add_child(_modal_layer)

	var tam_tela: Vector2 = get_viewport_rect().size
	_modal_fundo_escuro = ColorRect.new()
	_modal_fundo_escuro.color = Color(0.015, 0.0, 0.005, 0.78)
	_modal_fundo_escuro.size = tam_tela
	_modal_fundo_escuro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal_fundo_escuro.modulate = Color(1, 1, 1, 0.0)
	_modal_layer.add_child(_modal_fundo_escuro)

	var largura: float = _raio_circulo_px * 1.50
	var altura: float = _raio_circulo_px * 1.24
	_modal_painel = Panel.new()
	_modal_painel.size = Vector2(largura, altura)
	_modal_painel.position = _centro_tela - _modal_painel.size / 2.0
	_modal_painel.pivot_offset = _modal_painel.size / 2.0
	_modal_painel.scale = Vector2(0.94, 0.94)
	_modal_painel.modulate = Color(1, 1, 1, 0.0)
	_modal_painel.clip_contents = true

	var estilo := StyleBoxFlat.new()
	# A imagem fornece o fundo; esta camada só dá profundidade e acabamento.
	estilo.bg_color = Color(0.028, 0.003, 0.010, 0.60)
	estilo.set_border_width_all(4)
	estilo.border_color = Color(
		COR_SOUL_VERMELHO.r, COR_SOUL_VERMELHO.g, COR_SOUL_VERMELHO.b, 0.98
	)
	estilo.set_corner_radius_all(int(_raio_circulo_px * 0.050))
	estilo.shadow_color = Color(
		COR_SOUL_BRANCO.r, COR_SOUL_BRANCO.g, COR_SOUL_BRANCO.b, 0.24
	)
	estilo.shadow_size = 26
	_modal_painel.add_theme_stylebox_override("panel", estilo)
	_modal_layer.add_child(_modal_painel)

	# Fundo temático do resultado. Usa exatamente soul.jpeg e mantém a
	# imagem da apresentação como fallback para não quebrar a tela.
	var textura_modal: Texture2D = load(CAMINHO_IMAGEM_MODAL)
	if textura_modal == null:
		textura_modal = load(CAMINHO_IMAGEM_FASE)
		if textura_modal == null:
			push_warning("Imagem do modal não encontrada: " + CAMINHO_IMAGEM_MODAL)

	if textura_modal != null:
		_modal_imagem_fundo = TextureRect.new()
		_modal_imagem_fundo.texture = textura_modal
		_modal_imagem_fundo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_modal_imagem_fundo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_modal_imagem_fundo.size = _modal_painel.size
		_modal_imagem_fundo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_modal_imagem_fundo.modulate = Color(1, 1, 1, 0.76)
		_modal_painel.add_child(_modal_imagem_fundo)

	_modal_overlay_imagem = ColorRect.new()
	_modal_overlay_imagem.size = _modal_painel.size
	_modal_overlay_imagem.color = Color(0.030, 0.002, 0.008, 0.48)
	_modal_overlay_imagem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal_painel.add_child(_modal_overlay_imagem)

	# Moldura interna branca sobre a borda vermelha.
	var moldura_interna := Panel.new()
	moldura_interna.position = Vector2(largura * 0.018, altura * 0.018)
	moldura_interna.size = Vector2(largura * 0.964, altura * 0.964)
	moldura_interna.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var estilo_moldura := StyleBoxFlat.new()
	estilo_moldura.bg_color = Color(0, 0, 0, 0)
	estilo_moldura.set_border_width_all(2)
	estilo_moldura.border_color = Color(
		COR_SOUL_BRANCO.r, COR_SOUL_BRANCO.g, COR_SOUL_BRANCO.b, 0.74
	)
	estilo_moldura.set_corner_radius_all(int(_raio_circulo_px * 0.038))
	moldura_interna.add_theme_stylebox_override("panel", estilo_moldura)
	_modal_painel.add_child(moldura_interna)

	# Cabeçalho Soul em vidro vermelho.
	var faixa_titulo := Panel.new()
	faixa_titulo.position = Vector2(largura * 0.055, altura * 0.040)
	faixa_titulo.size = Vector2(largura * 0.890, altura * 0.145)
	faixa_titulo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var estilo_faixa := StyleBoxFlat.new()
	estilo_faixa.bg_color = Color(
		COR_SOUL_VERMELHO.r * 0.24,
		COR_SOUL_VERMELHO.g * 0.24,
		COR_SOUL_VERMELHO.b * 0.24,
		0.82
	)
	estilo_faixa.set_border_width_all(2)
	estilo_faixa.border_color = Color(
		COR_SOUL_BRANCO.r, COR_SOUL_BRANCO.g, COR_SOUL_BRANCO.b, 0.82
	)
	estilo_faixa.set_corner_radius_all(int(altura * 0.055))
	estilo_faixa.shadow_color = Color(
		COR_SOUL_VERMELHO.r, COR_SOUL_VERMELHO.g, COR_SOUL_VERMELHO.b, 0.42
	)
	estilo_faixa.shadow_size = 14
	faixa_titulo.add_theme_stylebox_override("panel", estilo_faixa)
	_modal_painel.add_child(faixa_titulo)

	var cfg_titulo := LabelSettings.new()
	cfg_titulo.font_size = int(_raio_circulo_px * 0.062)
	cfg_titulo.font_color = COR_SOUL_BRANCO
	cfg_titulo.outline_size = 5
	cfg_titulo.outline_color = Color(0.16, 0.0, 0.015, 0.96)
	cfg_titulo.shadow_size = 15
	cfg_titulo.shadow_color = Color(
		COR_SOUL_VERMELHO.r, COR_SOUL_VERMELHO.g, COR_SOUL_VERMELHO.b, 0.64
	)

	_modal_label_titulo = Label.new()
	_modal_label_titulo.label_settings = cfg_titulo
	_modal_label_titulo.text = "PAPERMOON - SOUL EATER"
	_modal_label_titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_modal_label_titulo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_modal_label_titulo.size = Vector2(largura * 0.88, altura * 0.10)
	_modal_label_titulo.position = Vector2(largura * 0.06, altura * 0.055)
	_modal_painel.add_child(_modal_label_titulo)

	var cfg_subtitulo := LabelSettings.new()
	cfg_subtitulo.font_size = int(_raio_circulo_px * 0.030)
	cfg_subtitulo.font_color = Color(1.0, 0.90, 0.91, 1.0)
	cfg_subtitulo.outline_size = 2
	cfg_subtitulo.outline_color = Color(0, 0, 0, 0.90)
	var label_subtitulo := Label.new()
	label_subtitulo.label_settings = cfg_subtitulo
	label_subtitulo.text = "RESULTADO FINAL"
	label_subtitulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_subtitulo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label_subtitulo.size = Vector2(largura, altura * 0.055)
	label_subtitulo.position = Vector2(0, altura * 0.142)
	_modal_painel.add_child(label_subtitulo)

	var cfg_score := LabelSettings.new()
	cfg_score.font_size = int(_raio_circulo_px * 0.105)
	cfg_score.font_color = COR_SOUL_BRANCO
	cfg_score.outline_size = 6
	cfg_score.outline_color = Color(
		COR_SOUL_VERMELHO.r, COR_SOUL_VERMELHO.g, COR_SOUL_VERMELHO.b, 0.96
	)
	cfg_score.shadow_size = 18
	cfg_score.shadow_color = Color(
		COR_SOUL_VERMELHO.r, COR_SOUL_VERMELHO.g, COR_SOUL_VERMELHO.b, 0.52
	)

	_modal_label_score = Label.new()
	_modal_label_score.label_settings = cfg_score
	_modal_label_score.text = str(_pontuacao) + " PONTOS"
	_modal_label_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_modal_label_score.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_modal_label_score.size = Vector2(largura, altura * 0.18)
	_modal_label_score.position = Vector2(0, altura * 0.190)
	_modal_painel.add_child(_modal_label_score)

	var margem_h: float = largura * 0.055
	var espaco: float = largura * 0.025
	var largura_card: float = (largura - margem_h * 2.0 - espaco * 2.0) / 3.0
	var altura_card: float = altura * 0.245
	var y_cards: float = altura * 0.405

	_criar_card_estatistica(
		_modal_painel,
		Vector2(margem_h, y_cards),
		Vector2(largura_card, altura_card),
		"COMBO MÁXIMO",
		"x" + str(_combo_maximo),
		COR_SOUL_VERMELHO
	)
	_criar_card_estatistica(
		_modal_painel,
		Vector2(margem_h + largura_card + espaco, y_cards),
		Vector2(largura_card, altura_card),
		"RECORDE DA TELA",
		str(_recorde_tela),
		COR_SOUL_BRANCO
	)
	_criar_card_estatistica(
		_modal_painel,
		Vector2(margem_h + (largura_card + espaco) * 2.0, y_cards),
		Vector2(largura_card, altura_card),
		"RECORDE GERAL",
		str(_recorde_geral),
		Color(1.0, 0.48, 0.92, 1.0)
	)

	if _novo_recorde_tela or _novo_recorde_geral:
		var cfg_recorde := LabelSettings.new()
		cfg_recorde.font_size = int(_raio_circulo_px * 0.040)
		cfg_recorde.font_color = COR_SLIDE_AMARELO
		cfg_recorde.outline_size = 3
		cfg_recorde.outline_color = Color(0, 0, 0, 0.9)
		var label_recorde := Label.new()
		label_recorde.label_settings = cfg_recorde
		label_recorde.text = (
			"NOVO RECORDE GERAL!" if _novo_recorde_geral else "NOVO RECORDE DESTA TELA!"
		)
		label_recorde.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label_recorde.size = Vector2(largura, altura * 0.08)
		label_recorde.position = Vector2(0, altura * 0.655)
		_modal_painel.add_child(label_recorde)

	var cfg_count := LabelSettings.new()
	cfg_count.font_size = int(_raio_circulo_px * 0.052)
	cfg_count.font_color = Color.WHITE
	cfg_count.outline_size = 3
	cfg_count.outline_color = Color(0.0, 0.0, 0.0, 0.92)
	cfg_count.shadow_size = 8
	cfg_count.shadow_color = Color(
		COR_SOUL_VERMELHO.r, COR_SOUL_VERMELHO.g, COR_SOUL_VERMELHO.b, 0.52
	)

	_modal_label_countdown = Label.new()
	_modal_label_countdown.label_settings = cfg_count
	_modal_label_countdown.text = "RETORNO EM %02d s" % int(ceil(_modal_countdown_restante))
	_modal_label_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_modal_label_countdown.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_modal_label_countdown.size = Vector2(largura, altura * 0.10)
	_modal_label_countdown.position = Vector2(0, altura * 0.72)
	_modal_painel.add_child(_modal_label_countdown)

	_modal_barra_tempo = ProgressBar.new()
	_modal_barra_tempo.min_value = 0.0
	_modal_barra_tempo.max_value = TEMPO_MODAL_CONTINUAR_SEG
	_modal_barra_tempo.value = TEMPO_MODAL_CONTINUAR_SEG
	_modal_barra_tempo.show_percentage = false
	_modal_barra_tempo.size = Vector2(largura * 0.66, max(8.0, altura * 0.018))
	_modal_barra_tempo.position = Vector2(largura * 0.17, altura * 0.815)
	_modal_barra_tempo.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var barra_fundo := StyleBoxFlat.new()
	barra_fundo.bg_color = Color(1, 1, 1, 0.12)
	barra_fundo.set_corner_radius_all(int(_modal_barra_tempo.size.y * 0.5))
	var barra_cheia := StyleBoxFlat.new()
	barra_cheia.bg_color = Color(
		COR_SOUL_VERMELHO.r, COR_SOUL_VERMELHO.g, COR_SOUL_VERMELHO.b, 0.96
	)
	barra_cheia.set_corner_radius_all(int(_modal_barra_tempo.size.y * 0.5))
	barra_cheia.shadow_color = Color(
		COR_SOUL_BRANCO.r, COR_SOUL_BRANCO.g, COR_SOUL_BRANCO.b, 0.34
	)
	barra_cheia.shadow_size = 7
	_modal_barra_tempo.add_theme_stylebox_override("background", barra_fundo)
	_modal_barra_tempo.add_theme_stylebox_override("fill", barra_cheia)
	_modal_painel.add_child(_modal_barra_tempo)

	var cfg_acao := LabelSettings.new()
	cfg_acao.font_size = int(_raio_circulo_px * 0.038)
	cfg_acao.font_color = COR_SOUL_BRANCO
	cfg_acao.outline_size = 2
	cfg_acao.outline_color = Color(0, 0, 0, 0.90)

	_modal_label_acao = Label.new()
	_modal_label_acao.label_settings = cfg_acao
	_modal_label_acao.text = "INSIRA CRÉDITO OU APERTE START PARA JOGAR NOVAMENTE"
	_modal_label_acao.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_modal_label_acao.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_modal_label_acao.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_modal_label_acao.size = Vector2(largura * 0.88, altura * 0.12)
	_modal_label_acao.position = Vector2(largura * 0.06, altura * 0.865)
	_modal_painel.add_child(_modal_label_acao)

	var pos_final_modal: Vector2 = _modal_painel.position
	_modal_painel.position = pos_final_modal + Vector2(0, _raio_circulo_px * 0.035)

	var tw: Tween = create_tween()
	tw.set_parallel(true)
	(
		tw
		. tween_property(
			_modal_fundo_escuro, "modulate", Color(1, 1, 1, 1.0), DURACAO_ABRIR_MODAL_SEG
		)
		. set_trans(Tween.TRANS_QUINT)
		. set_ease(Tween.EASE_OUT)
	)
	(
		tw
		. tween_property(_modal_painel, "scale", Vector2.ONE, DURACAO_ABRIR_MODAL_SEG)
		. set_trans(Tween.TRANS_QUINT)
		. set_ease(Tween.EASE_OUT)
	)
	(
		tw
		. tween_property(_modal_painel, "position", pos_final_modal, DURACAO_ABRIR_MODAL_SEG)
		. set_trans(Tween.TRANS_QUINT)
		. set_ease(Tween.EASE_OUT)
	)
	(
		tw
		. tween_property(
			_modal_painel, "modulate", Color(1, 1, 1, 1.0), DURACAO_ABRIR_MODAL_SEG * 0.82
		)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	tw.finished.connect(func(): _modal_em_transicao = false)


func _criar_card_estatistica(
	pai: Control, pos: Vector2, tamanho: Vector2, titulo: String, valor: String, cor: Color
) -> void:
	var card := Panel.new()
	card.position = pos
	card.size = tamanho
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(cor.r * 0.10, cor.g * 0.10, cor.b * 0.10, 0.70)
	estilo.set_border_width_all(2)
	estilo.border_color = Color(cor.r, cor.g, cor.b, 0.88)
	estilo.set_corner_radius_all(int(tamanho.y * 0.16))
	estilo.shadow_color = Color(cor.r, cor.g, cor.b, 0.30)
	estilo.shadow_size = 12
	card.add_theme_stylebox_override("panel", estilo)
	pai.add_child(card)

	var cfg_titulo := LabelSettings.new()
	cfg_titulo.font_size = int(_raio_circulo_px * 0.028)
	cfg_titulo.font_color = Color(0.82, 0.90, 0.98, 1.0)
	cfg_titulo.outline_size = 2
	cfg_titulo.outline_color = Color(0, 0, 0, 0.85)
	var label_titulo := Label.new()
	label_titulo.label_settings = cfg_titulo
	label_titulo.text = titulo
	label_titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_titulo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label_titulo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label_titulo.size = Vector2(tamanho.x, tamanho.y * 0.42)
	label_titulo.position = Vector2(0, tamanho.y * 0.06)
	card.add_child(label_titulo)

	var cfg_valor := LabelSettings.new()
	cfg_valor.font_size = int(_raio_circulo_px * 0.058)
	cfg_valor.font_color = cor
	cfg_valor.outline_size = 3
	cfg_valor.outline_color = Color(0, 0, 0, 0.90)
	var label_valor := Label.new()
	label_valor.label_settings = cfg_valor
	label_valor.text = valor
	label_valor.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_valor.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label_valor.size = Vector2(tamanho.x, tamanho.y * 0.48)
	label_valor.position = Vector2(0, tamanho.y * 0.46)
	card.add_child(label_valor)


func _carregar_e_atualizar_recordes() -> void:
	var dados: Dictionary = {"recorde_geral": 0, "telas": {}}
	if FileAccess.file_exists(CAMINHO_RECORDES):
		var arquivo_leitura := FileAccess.open(CAMINHO_RECORDES, FileAccess.READ)
		if arquivo_leitura != null:
			var convertido: Variant = JSON.parse_string(arquivo_leitura.get_as_text())
			if convertido is Dictionary:
				dados = convertido as Dictionary

	var telas: Dictionary = {}
	var telas_salvas: Variant = dados.get("telas", {})
	if telas_salvas is Dictionary:
		telas = telas_salvas as Dictionary

	var anterior_tela: int = int(telas.get(NOME_FASE, 0))
	var anterior_geral: int = int(dados.get("recorde_geral", 0))
	_recorde_tela = max(anterior_tela, _pontuacao)
	_recorde_geral = max(anterior_geral, _pontuacao)
	_novo_recorde_tela = _pontuacao > anterior_tela
	_novo_recorde_geral = _pontuacao > anterior_geral

	telas[NOME_FASE] = _recorde_tela
	dados["telas"] = telas
	dados["recorde_geral"] = _recorde_geral

	if _novo_recorde_tela or _novo_recorde_geral or not FileAccess.file_exists(CAMINHO_RECORDES):
		var arquivo_escrita := FileAccess.open(CAMINHO_RECORDES, FileAccess.WRITE)
		if arquivo_escrita != null:
			arquivo_escrita.store_string(JSON.stringify(dados, "	"))


func _fechar_modal_e_executar(acao: Callable) -> void:
	if not _modal_continuar_ativo or _modal_em_transicao:
		return
	_modal_em_transicao = true
	_modal_acao_apos_fechar = acao

	var tw: Tween = create_tween()
	tw.set_parallel(true)
	if _modal_painel and is_instance_valid(_modal_painel):
		(
			tw
			. tween_property(_modal_painel, "scale", Vector2(0.84, 0.84), DURACAO_FECHAR_MODAL_SEG)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_IN)
		)
		tw.tween_property(_modal_painel, "modulate", Color(1, 1, 1, 0.0), DURACAO_FECHAR_MODAL_SEG)
	if _modal_fundo_escuro and is_instance_valid(_modal_fundo_escuro):
		tw.tween_property(
			_modal_fundo_escuro, "modulate", Color(1, 1, 1, 0.0), DURACAO_FECHAR_MODAL_SEG
		)
	tw.finished.connect(
		func():
			if _modal_layer and is_instance_valid(_modal_layer):
				_modal_layer.queue_free()
			_modal_continuar_ativo = false
			_modal_em_transicao = false
			var executar: Callable = _modal_acao_apos_fechar
			_modal_acao_apos_fechar = Callable()
			if executar.is_valid():
				executar.call()
	)


func _processar_modal_continuar(delta: float) -> void:
	if _modal_em_transicao:
		return

	_modal_countdown_restante = max(_modal_countdown_restante - delta, 0.0)

	if _modal_label_countdown:
		var numero: int = int(ceil(_modal_countdown_restante))
		_modal_label_countdown.text = "RETORNO EM %02d s" % numero

		if _modal_barra_tempo:
			_modal_barra_tempo.value = _modal_countdown_restante

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
	_fechar_modal_e_executar(Callable(self, "_recarregar_cena_agora"))


func _voltar_para_abertura() -> void:
	_fechar_modal_e_executar(Callable(self, "_voltar_para_abertura_agora"))


func _recarregar_cena_agora() -> void:
	_arduino_enviar_unico("READY")
	get_tree().reload_current_scene()


func _voltar_para_abertura_agora() -> void:
	_arduino_enviar_unico("CLEAR")
	get_tree().change_scene_to_file(CAMINHO_CENA_ABERTURA)


func _tempo_atual_musica() -> float:
	if _musica_inicio_msec < 0:
		return 0.0

	# Enquanto o arquivo está tocando, usa a posição real do AudioStreamPlayer corrigida
	# pelo mix e pela latência de saída. Isso mantém HUD, eventos e batidas no mesmo tempo.
	if _musica_player != null and is_instance_valid(_musica_player) and _musica_player.playing:
		var posicao: float = _musica_player.get_playback_position()
		posicao += AudioServer.get_time_since_last_mix()
		posicao -= AudioServer.get_output_latency()
		posicao = clamp(posicao, 0.0, _duracao_musica_seg)
		_ultimo_tempo_musica_seg = max(_ultimo_tempo_musica_seg, posicao)
		return _ultimo_tempo_musica_seg

	# Depois que a fonte termina, continua apenas pelo tempo do delay audível. Assim o
	# modal só começa quando o último som realmente saiu, sem cortar e sem reiniciar.
	if _musica_fonte_finalizada and _musica_fim_fonte_msec >= 0:
		var cauda: float = max(float(Time.get_ticks_msec() - _musica_fim_fonte_msec) / 1000.0, 0.0)
		return max(_ultimo_tempo_musica_seg, _duracao_musica_seg + cauda)

	# Fallback monotônico para casos em que o player ainda está sendo preparado.
	return max(
		_ultimo_tempo_musica_seg, float(Time.get_ticks_msec() - _musica_inicio_msec) / 1000.0
	)


# ---------------------------------------------------------------
# DETECÇÃO DE BATIDA EM TEMPO REAL (grave/bumbo) -- ver DETECCAO_* no topo do arquivo
# ---------------------------------------------------------------
func _configurar_deteccao_beat() -> void:
	if not DETECCAO_BEAT_ATIVADA:
		return

	_indice_bus_musica = AudioServer.get_bus_index(BUS_MUSICA_HIT)
	if _indice_bus_musica < 0:
		AudioServer.add_bus()
		_indice_bus_musica = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(_indice_bus_musica, BUS_MUSICA_HIT)
		AudioServer.set_bus_send(_indice_bus_musica, "Master")

	if _indice_bus_musica < 0:
		push_warning("Não foi possível criar o barramento exclusivo da música.")
		return

	while AudioServer.get_bus_effect_count(_indice_bus_musica) > 0:
		AudioServer.remove_bus_effect(
			_indice_bus_musica, AudioServer.get_bus_effect_count(_indice_bus_musica) - 1
		)

	var analisador := AudioEffectSpectrumAnalyzer.new()
	# Um buffer um pouco maior estabiliza a leitura em máquinas com vídeo pesado,
	# mas o motor ainda amostra em intervalos curtos e reage aos ataques.
	analisador.buffer_length = 0.25
	AudioServer.add_bus_effect(_indice_bus_musica, analisador, 0)

	var delay := AudioEffectDelay.new()
	delay.dry = 1.0
	delay.tap1_active = false
	delay.tap2_active = false
	delay.feedback_active = false
	AudioServer.add_bus_effect(_indice_bus_musica, delay, 1)

	_spectrum_instance = AudioServer.get_bus_effect_instance(_indice_bus_musica, 0)
	_aplicar_volume_musica_imediato(VOLUME_MAX_DB)


func _atualizar_deteccao_beat(delta: float) -> void:
	if not _usando_deteccao_beat or _spectrum_instance == null:
		return
	if (
		_musica_player == null
		or not is_instance_valid(_musica_player)
		or not _musica_player.playing
	):
		return

	_analise_acumulador += delta
	if _analise_acumulador < ANALISE_INTERVALO_SEG:
		return
	var passo_analise: float = _analise_acumulador
	_analise_acumulador = fmod(_analise_acumulador, ANALISE_INTERVALO_SEG)

	var grave: float = (
		_spectrum_instance
		. get_magnitude_for_frequency_range(ANALISE_GRAVE_MIN_HZ, ANALISE_GRAVE_MAX_HZ)
		. length()
	)
	var medio: float = (
		_spectrum_instance
		. get_magnitude_for_frequency_range(ANALISE_MEDIO_MIN_HZ, ANALISE_MEDIO_MAX_HZ)
		. length()
	)
	var agudo: float = (
		_spectrum_instance
		. get_magnitude_for_frequency_range(ANALISE_AGUDO_MIN_HZ, ANALISE_AGUDO_MAX_HZ)
		. length()
	)
	var total: float = grave * 0.56 + medio * 0.29 + agudo * 0.15

	if not _analise_aquecida:
		_media_grave = max(grave, 0.0001)
		_media_medio = max(medio, 0.0001)
		_media_agudo = max(agudo, 0.0001)
		_media_total = max(total, 0.0001)
		_energia_total_anterior = total
		_analise_aquecida = true
		return

	var sensibilidade: float = clamp(
		float(PERFIL_JOGABILIDADE.get("sensibilidade", 1.0)), 0.55, 1.65
	)
	var razao_grave: float = grave / max(_media_grave, 0.000001)
	var razao_medio: float = medio / max(_media_medio, 0.000001)
	var razao_agudo: float = agudo / max(_media_agudo, 0.000001)
	var razao_total: float = total / max(_media_total, 0.000001)
	var ataque: float = max(total - _energia_total_anterior, 0.0) / max(_media_total, 0.000001)

	var limiar_razao: float = ANALISE_LIMIAR_RAZAO_BASE / sensibilidade
	var pico_pulsacao: bool = razao_grave >= limiar_razao
	var pico_transiente: bool = (
		razao_total >= limiar_razao * 0.97 and ataque >= ANALISE_LIMIAR_ATAQUE / sensibilidade
	)
	var pico_melodico: bool = (
		max(razao_medio, razao_agudo) >= limiar_razao * 1.05
		and ataque >= ANALISE_LIMIAR_ATAQUE * 0.72
	)

	var tempo_musica: float = _tempo_atual_musica()
	var cooldown: float = clamp(
		_intervalo_beat_estimado * 0.42, ANALISE_COOLDOWN_MIN_SEG, ANALISE_COOLDOWN_MAX_SEG
	)
	var passou_cooldown: bool = tempo_musica - _ultimo_beat_tempo_musica >= cooldown

	# Atualiza a linha de base mais devagar durante picos para não "engolir" o ataque.
	var alpha_base: float = (
		1.0 - pow(1.0 - ANALISE_ALPHA_BASE, passo_analise / ANALISE_INTERVALO_SEG)
	)
	var alpha_pico: float = (
		alpha_base * 0.25 if (pico_pulsacao or pico_transiente or pico_melodico) else alpha_base
	)
	_media_grave = lerp(_media_grave, max(grave, 0.000001), alpha_pico)
	_media_medio = lerp(_media_medio, max(medio, 0.000001), alpha_pico)
	_media_agudo = lerp(_media_agudo, max(agudo, 0.000001), alpha_pico)
	_media_total = lerp(_media_total, max(total, 0.000001), alpha_pico)
	_energia_total_anterior = total
	_energia_secao = lerp(_energia_secao, clamp(razao_total, 0.45, 2.8), ANALISE_ALPHA_SECAO)

	if not passou_cooldown or not (pico_pulsacao or pico_transiente or pico_melodico):
		return

	_registrar_pulso_musical(tempo_musica)
	if _estado_jogo != EstadoJogo.JOGANDO or _partida_encerrada:
		return

	_criar_evento_musical_dinamico(
		{
			"tempo_detectado": tempo_musica,
			"grave": grave,
			"medio": medio,
			"agudo": agudo,
			"razao_grave": razao_grave,
			"razao_medio": razao_medio,
			"razao_agudo": razao_agudo,
			"razao_total": razao_total,
			"ataque": ataque,
			"pico_pulsacao": pico_pulsacao,
			"pico_melodico": pico_melodico,
		}
	)


func _disparar_evento_por_beat(energia: float, media: float) -> void:
	# Compatibilidade com chamadas antigas: converte o pico simples em um descritor
	# multibanda. O caminho normal usa _criar_evento_musical_dinamico diretamente.
	var razao: float = clamp(energia / max(media, 0.0001), 1.0, 4.0)
	_criar_evento_musical_dinamico(
		{
			"tempo_detectado": _tempo_atual_musica(),
			"grave": energia,
			"medio": energia * 0.45,
			"agudo": energia * 0.22,
			"razao_grave": razao,
			"razao_medio": razao * 0.82,
			"razao_agudo": razao * 0.68,
			"razao_total": razao,
			"ataque": razao - 1.0,
			"pico_pulsacao": true,
			"pico_melodico": false,
		}
	)


func _registrar_pulso_musical(tempo_musica: float) -> void:
	if _ultimo_beat_tempo_musica > -100.0:
		var intervalo: float = tempo_musica - _ultimo_beat_tempo_musica
		if (
			intervalo >= ANALISE_INTERVALO_BEAT_MIN_SEG
			and intervalo <= ANALISE_INTERVALO_BEAT_MAX_SEG
		):
			# Normaliza meia/dobra de tempo para estabilizar BPM entre estilos diferentes.
			while intervalo < 0.30:
				intervalo *= 2.0
			while intervalo > 0.78:
				intervalo *= 0.5
			_intervalos_beat.append(intervalo)
			while _intervalos_beat.size() > 9:
				_intervalos_beat.pop_front()
			var ordenados: Array[float] = _intervalos_beat.duplicate()
			ordenados.sort()
			var mediana: float = ordenados[int(ordenados.size() / 2)]
			_intervalo_beat_estimado = lerp(_intervalo_beat_estimado, mediana, 0.34)
			_bpm_estimado = 60.0 / max(_intervalo_beat_estimado, 0.001)

	_ultimo_beat_tempo_musica = tempo_musica
	_ultimo_beat_msec = Time.get_ticks_msec()
	_contador_batidas += 1


func _criar_evento_musical_dinamico(dados: Dictionary) -> void:
	var tempo_detectado: float = float(dados.get("tempo_detectado", _tempo_atual_musica()))
	var densidade: float = clamp(float(PERFIL_JOGABILIDADE.get("densidade", 0.82)), 0.25, 1.0)
	var intensidade: float = clamp(float(dados.get("razao_total", 1.0)), 0.6, 3.5)
	var secao: float = clamp(_energia_secao, 0.55, 2.4)

	# Em trechos calmos, respeita a música e não inventa uma chuva de alvos.
	var intervalo_min_evento: float = lerp(
		_intervalo_beat_estimado * 1.55, _intervalo_beat_estimado * 0.58, densidade
	)
	intervalo_min_evento /= clamp(0.82 + secao * 0.20, 0.82, 1.28)
	if tempo_detectado - _ultimo_evento_musical_seg < max(intervalo_min_evento, 0.16):
		return

	var grave: float = float(dados.get("grave", 0.0))
	var medio: float = float(dados.get("medio", 0.0))
	var agudo: float = float(dados.get("agudo", 0.0))
	var corpo_melodico: float = (medio + agudo * 0.72) / max(grave, 0.000001)
	var preferencia_arraste: float = clamp(
		float(PERFIL_JOGABILIDADE.get("preferencia_arraste", 0.34)), 0.0, 1.0
	)
	var compasso_forte: bool = _contador_batidas % 4 == 0
	var transicao_melodica: bool = (
		bool(dados.get("pico_melodico", false))
		and corpo_melodico > lerp(1.55, 0.82, preferencia_arraste)
	)
	var usar_arraste: bool = (
		not _existe_arraste_ativo()
		and _ultimo_tipo_evento_musical != "arraste"
		and (
			transicao_melodica or (compasso_forte and corpo_melodico > 0.88 and intensidade > 1.18)
		)
	)

	var tempo_alvo: float = tempo_detectado + _atraso_saida_musica_seg()
	if usar_arraste:
		var complexidade: float = clamp(
			float(PERFIL_JOGABILIDADE.get("complexidade_arraste", 0.68)), 0.0, 1.0
		)
		var tamanho: int = 2
		if intensidade > 1.55 and complexidade > 0.42:
			tamanho = 3
		if intensidade > 2.05 and complexidade > 0.78:
			tamanho = 4
		var inicio: int = _escolher_proximo_ponto_dinamico(intensidade, corpo_melodico)
		var caminho: Array = _montar_caminho_arraste_dinamico(
			inicio, tamanho, intensidade, corpo_melodico
		)
		var duracao: float = clamp(
			_intervalo_beat_estimado * (2.15 + float(tamanho - 2) * 0.55), 0.92, 2.25
		)
		(
			_fila_eventos_musicais
			. append(
				{
					"tipo": "arraste",
					"tempo": tempo_alvo,
					"tempo_visual_inicio": tempo_detectado,
					"tempo_fim": tempo_alvo + duracao,
					"caminho": caminho,
					"resolvido": false,
					"via_beat": true,
					"bpm": _bpm_estimado,
				}
			)
		)
		_ultimo_ponto_beat = int(caminho[caminho.size() - 1])
		_ultimo_tipo_evento_musical = "arraste"
	else:
		var ponto: int = _escolher_proximo_ponto_dinamico(intensidade, corpo_melodico)
		(
			_fila_eventos_musicais
			. append(
				{
					"tipo": "toque",
					"tempo": tempo_alvo,
					"tempo_visual_inicio": tempo_detectado,
					"ponto": ponto,
					"resolvido": false,
					"via_beat": true,
					"bpm": _bpm_estimado,
				}
			)
		)
		_ultimo_ponto_beat = ponto
		_ultimo_tipo_evento_musical = "toque"

	_ultimo_evento_musical_seg = tempo_detectado


func _escolher_proximo_ponto_dinamico(intensidade: float, corpo_melodico: float) -> int:
	var distancia_perfil: float = clamp(
		float(PERFIL_JOGABILIDADE.get("distancia_saltos", 0.72)), 0.0, 1.0
	)
	var salto: int = clamp(
		int(round(1.0 + distancia_perfil * 2.0 + (intensidade - 1.0) * 0.65)), 1, 4
	)
	if corpo_melodico > 1.35:
		_direcao_musical *= -1
	elif _contador_batidas % 3 == 0:
		_direcao_musical *= -1
	var ponto: int = posmod(_ultimo_ponto_beat + _direcao_musical * salto, NUM_PONTOS)
	if ponto == _ultimo_ponto_beat:
		ponto = posmod(ponto + _direcao_musical, NUM_PONTOS)
	return ponto


func _montar_caminho_arraste_dinamico(
	inicio: int, tamanho: int, intensidade: float, corpo_melodico: float
) -> Array:
	var caminho: Array = [inicio]
	var atual: int = inicio
	var direcao: int = _direcao_musical
	for passo in range(1, tamanho):
		if passo % 2 == 0 or corpo_melodico > 1.45:
			direcao *= -1
		var salto: int = clamp(
			int(round(2.0 + (intensidade - 1.0) * 0.55 + float(passo % 2))), 2, 4
		)
		var proximo: int = posmod(atual + direcao * salto, NUM_PONTOS)
		var tentativas: int = 0
		while proximo in caminho and tentativas < NUM_PONTOS:
			proximo = posmod(proximo + direcao, NUM_PONTOS)
			tentativas += 1
		caminho.append(proximo)
		atual = proximo
	return caminho


func _despachar_fila_eventos_musicais(tempo_musica: float) -> void:
	if _fila_eventos_musicais.is_empty():
		return

	for i in range(_fila_eventos_musicais.size() - 1, -1, -1):
		var evento: Dictionary = _fila_eventos_musicais[i]
		var limite_expiracao: float = (
			float(evento.get("tempo_fim", evento.get("tempo", 0.0))) + ARRASTE_TOLERANCIA_FINAL_SEG
		)
		if tempo_musica > limite_expiracao:
			_fila_eventos_musicais.remove_at(i)

	# Sem limite global: todos os eventos cujo relógio já começou entram imediatamente.
	while not _fila_eventos_musicais.is_empty():
		var evento: Dictionary = _fila_eventos_musicais.pop_front()
		_eventos_ativos.append(evento)
		# Eventos detectados ao vivo entram na lista exatamente quando o disco nasce.
		_led_evento_adquirir(evento)


func _janela_acerto_evento(evento: Dictionary) -> float:
	# Eventos nascidos de uma batida detectada ao vivo usam uma janela um pouco mais
	# larga que os de um beatmap pré-escrito, já que aqui não existe telegraph real.
	var base: float = JANELA_ACERTO_BEAT_SEG if evento.get("via_beat", false) else JANELA_ACERTO_SEG
	return base + max(float(PERFIL_JOGABILIDADE.get("janela_toque_extra", 0.0)), 0.0)


# ---------------------------------------------------------------
# BEATMAP / EVENTOS
# ---------------------------------------------------------------
func _ativar_eventos_pendentes(tempo_musica: float) -> void:
	# Beatmap manual também não disputa vagas. Cada evento possui seu próprio tempo,
	# sua própria bola e sua própria posse do LED físico.
	while _indice_beatmap < _beatmap.size():
		var proximo: Dictionary = _beatmap[_indice_beatmap]
		# Usa o mesmo início empregado pelo desenho do orbe. LED e bola nascem juntos.
		if (float(proximo["tempo"]) - TEMPO_ORBE_SEG) > tempo_musica:
			break

		var evento: Dictionary = proximo.duplicate()
		evento["resolvido"] = false
		_eventos_ativos.append(evento)
		_led_evento_adquirir(evento)
		_indice_beatmap += 1


func _atualizar_eventos_ativos(tempo_musica: float) -> void:
	for i in range(_eventos_ativos.size() - 1, -1, -1):
		var evento: Dictionary = _eventos_ativos[i]

		if evento["tipo"] == "toque":
			_atualizar_visual_toque(evento, tempo_musica)
			var fim_led_evento: float = float(
				evento.get(
					"led_fim_tempo_musica",
					float(evento["tempo"]) + _janela_acerto_evento(evento)
				)
			)
			var venceu_janela: bool = tempo_musica > fim_led_evento
			# Acertar contabiliza o ponto, mas não encerra antecipadamente a jogada.
			# A bola e o LED permanecem até passar completamente a janela do alvo.
			if venceu_janela:
				if not evento.get("acerto_registrado", false):
					_registrar_erro(evento)
					var idx_toque: int = int(evento["ponto"])
					_ponto_set_estado(idx_toque, "hig", 0.14, COR_ERRO)
					_agendar_apagamento_tazo(idx_toque, TEMPO_TAZO_POS_ACERTO_SEG)
				evento["resolvido"] = true
				_led_evento_liberar(evento)
				_eventos_ativos.remove_at(i)

		elif evento["tipo"] == "arraste":
			_atualizar_visual_arraste(evento, tempo_musica)
			var venceu_janela_arraste: bool = (
				tempo_musica > float(evento["tempo_fim"]) + ARRASTE_TOLERANCIA_FINAL_SEG
			)
			if evento.get("resolvido", false) or venceu_janela_arraste:
				if not evento.get("resolvido", false):
					_registrar_erro(evento)
				for indice_p in evento["caminho"]:
					var idx_arraste: int = int(indice_p)
					var cor_fim_arraste: Color = (
						COR_SLIDE_COMPLETO if evento.get("sucesso", false) else COR_ERRO
					)
					_ponto_set_estado(idx_arraste, "hig", 0.10, cor_fim_arraste)
					_agendar_apagamento_tazo(idx_arraste, TEMPO_TAZO_POS_ACERTO_SEG)
				if _arraste_evento_atual == evento:
					_arraste_evento_atual = null
					_arraste_indice_atual = 0
					_arraste_gesto_ativo = false
				_eventos_ativos.remove_at(i)


func _atualizar_visual_toque(evento: Dictionary, tempo_musica: float) -> void:
	var indice: int = int(evento["ponto"])
	var t: float = float(evento["tempo"])
	var janela: float = _janela_acerto_evento(evento)
	if tempo_musica < t - janela:
		var restante: float = t - janela - tempo_musica
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
func _validar_inputs_pontos() -> void:
	var ausentes: Array[String] = []
	for acao in INPUTS_PONTOS:
		if not InputMap.has_action(acao):
			ausentes.append(acao)
	if not ausentes.is_empty():
		push_error(
			(
				"Ações físicas ausentes no Input Map: "
				+ ", ".join(ausentes)
				+ ". Sem elas os Tazos não responderão aos botões."
			)
		)


func _processar_inputs_toque(tempo_musica: float) -> void:
	for i in range(NUM_PONTOS):
		var acao: String = INPUTS_PONTOS[i]
		if not InputMap.has_action(acao):
			continue
		if Input.is_action_just_pressed(acao):
			# O próprio resultado do julgamento controla o LED. Não enviamos PULSE,
			# porque esse comando podia interromper outros alvos simultâneos.
			var estado_atual: String = (
				str(_ponto_estados[i]) if i < _ponto_estados.size() else "idle"
			)
			_ponto_set_estado(i, estado_atual, 0.12, Color.WHITE)
			_tentar_resolver_toque(i, tempo_musica)


func _tentar_resolver_toque(indice_ponto: int, tempo_musica: float) -> void:
	# Se houver mais de um disco associado ao mesmo ponto, julga sempre o mais
	# próximo da batida. Isso torna sequências rápidas justas e previsíveis.
	var melhor_evento: Dictionary = {}
	var melhor_diferenca: float = 999999.0
	for evento in _eventos_ativos:
		if (
			evento["tipo"] == "toque"
			and evento["ponto"] == indice_ponto
			and not evento.get("resolvido", false)
			and not evento.get("acerto_registrado", false)
		):
			var diferenca: float = abs(tempo_musica - float(evento["tempo"]))
			if diferenca <= _janela_acerto_evento(evento) and diferenca < melhor_diferenca:
				melhor_diferenca = diferenca
				melhor_evento = evento

	if melhor_evento.is_empty():
		return

	# A pontuação é consumida uma única vez, porém o evento não é encerrado aqui.
	# O LED e a bola continuam até o relógio ultrapassar o fim da janela válida.
	melhor_evento["acerto_registrado"] = true
	var perfeito: bool = melhor_diferenca <= JANELA_PERFEITO_SEG
	var pontos_ganhos: int = PONTOS_POR_ACERTO_TOQUE if perfeito else PONTOS_POR_ACERTO_BOM
	var cor_resultado: Color = COR_LED_PERFEITO if perfeito else COR_LED_BOM
	var texto_resultado: String = "PERFEITO!" if perfeito else "BOM!"

	_registrar_acerto(pontos_ganhos)
	var ponto_node: Node2D = _pontos[indice_ponto]
	_ponto_set_estado(indice_ponto, "hig", 0.16, cor_resultado)
	_agendar_apagamento_tazo(indice_ponto, TEMPO_TAZO_POS_ACERTO_SEG)
	_explosao_particulas(ponto_node.position, cor_resultado)
	_efeito_texto_flutuante(texto_resultado, ponto_node.position, cor_resultado)


func _indice_ponto_mais_proximo(pos_tela: Vector2, multiplicador_raio: float = 1.0) -> int:
	for i in range(_pontos.size()):
		if _pontos[i].position.distance_to(pos_tela) <= _raio_toque_ponto_px * multiplicador_raio:
			return i
	return -1


func _raio_arraste_checkpoint(indice: int = -1) -> float:
	var idx: int = indice if indice >= 0 else 0
	return _ponto_raio(idx) * ARRASTE_RAIO_CHECKPOINT_RATIO


func _raio_tubo_arraste(indice_origem: int, indice_destino: int) -> float:
	var raio_medio: float = (_ponto_raio(indice_origem) + _ponto_raio(indice_destino)) * 0.5
	return max(raio_medio * ARRASTE_RAIO_TUBO_RATIO, 8.0)


func _segmento_passou_no_ponto(a: Vector2, b: Vector2, ponto: Vector2, raio: float) -> bool:
	var ab: Vector2 = b - a
	var ab_len2: float = ab.length_squared()
	if ab_len2 <= 0.001:
		return ponto.distance_to(b) <= raio

	var t: float = clamp((ponto - a).dot(ab) / ab_len2, 0.0, 1.0)
	var mais_perto: Vector2 = a + ab * t
	return mais_perto.distance_to(ponto) <= raio


func _projecao_no_segmento(pos: Vector2, origem: Vector2, destino: Vector2) -> float:
	var segmento: Vector2 = destino - origem
	var comprimento2: float = segmento.length_squared()
	if comprimento2 <= 0.001:
		return 0.0
	return clamp((pos - origem).dot(segmento) / comprimento2, 0.0, 1.0)


func _distancia_ao_segmento(pos: Vector2, origem: Vector2, destino: Vector2) -> float:
	var t: float = _projecao_no_segmento(pos, origem, destino)
	return pos.distance_to(origem.lerp(destino, t))


func _validar_movimento_dentro_tubo(
	a: Vector2,
	b: Vector2,
	origem: Vector2,
	destino: Vector2,
	raio_tubo: float,
	raio_checkpoint: float
) -> Dictionary:
	var distancia_movimento: float = a.distance_to(b)
	var passo: float = max(ARRASTE_AMOSTRA_MIN_PX, raio_tubo * 0.32)
	var amostras: int = clamp(
		int(ceil(distancia_movimento / passo)), 1, ARRASTE_MAX_AMOSTRAS_MOVIMENTO
	)
	var progresso_max: float = _arraste_progresso_segmento
	var valido: bool = true
	var dentro_faixa_ideal: bool = true
	var distancia_maxima: float = 0.0
	var raio_limite: float = raio_tubo * ARRASTE_LIMITE_SAIDA_TUBO_RATIO

	for s in range(amostras + 1):
		var fracao: float = float(s) / float(amostras)
		var amostra: Vector2 = a.lerp(b, fracao)
		var progresso: float = _projecao_no_segmento(amostra, origem, destino)
		progresso_max = max(progresso_max, progresso)

		var dentro_checkpoint_inicio: bool = amostra.distance_to(origem) <= raio_checkpoint
		var dentro_checkpoint_fim: bool = amostra.distance_to(destino) <= raio_checkpoint
		var distancia_tubo: float = _distancia_ao_segmento(amostra, origem, destino)
		distancia_maxima = max(distancia_maxima, distancia_tubo)

		if (
			distancia_tubo > raio_tubo
			and not dentro_checkpoint_inicio
			and not dentro_checkpoint_fim
		):
			dentro_faixa_ideal = false

		# A falha só é sinalizada quando ultrapassa também a margem externa.
		if (
			distancia_tubo > raio_limite
			and not dentro_checkpoint_inicio
			and not dentro_checkpoint_fim
		):
			valido = false
			break

	var chegou_destino: bool = (
		b.distance_to(destino) <= raio_checkpoint
		or _segmento_passou_no_ponto(a, b, destino, raio_checkpoint)
	)
	return {
		"valido": valido,
		"dentro_faixa_ideal": dentro_faixa_ideal,
		"distancia_maxima": distancia_maxima,
		"progresso_max": progresso_max,
		"chegou_destino": chegou_destino,
	}


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


func _existe_arraste_ativo() -> bool:
	for evento in _eventos_ativos:
		if evento.get("tipo", "") == "arraste" and not evento.get("resolvido", false):
			return true
	return false


func _iniciar_arraste(pos: Vector2) -> void:
	_arraste_gesto_ativo = true
	_arraste_ultimo_pos = pos
	_arraste_pos_atual = pos
	_arraste_evento_atual = null
	_arraste_indice_atual = 0
	_arraste_progresso_segmento = 0.0
	_arraste_fora_tubo_desde_msec = -1
	_tentar_iniciar_arraste_por_pos(pos)


func _tentar_iniciar_arraste_por_pos(pos: Vector2) -> bool:
	if _arraste_evento_atual != null:
		return true

	var tempo_musica: float = _tempo_atual_musica()
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
		var raio_checkpoint: float = _raio_arraste_checkpoint(primeiro_indice)
		var distancia: float = primeiro_ponto.position.distance_to(pos)
		var cruzou_primeiro: bool = _segmento_passou_no_ponto(
			_arraste_ultimo_pos, pos, primeiro_ponto.position, raio_checkpoint
		)
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
	_arraste_progresso_segmento = 0.0
	_arraste_fora_tubo_desde_msec = -1

	_ponto_set_estado(idx_inicio, "hig", 0.12, _cor_orbe_por_ponto(idx_inicio))
	_registrar_efeito_passagem_tubo(
		_pontos[idx_inicio].position, _cor_caminho_evento(melhor_evento), 0.75
	)
	return true


func _atualizar_arraste(pos: Vector2) -> void:
	if not _arraste_gesto_ativo:
		return

	var pos_anterior: Vector2 = _arraste_pos_atual
	_arraste_ultimo_pos = pos_anterior
	_arraste_pos_atual = pos
	_registrar_ponto_rastro_arraste(pos)

	if _arraste_evento_atual == null:
		_tentar_iniciar_arraste_por_pos(pos)
		if _arraste_evento_atual == null:
			return

	var caminho: Array = _arraste_evento_atual["caminho"]
	var inicio_movimento: Vector2 = pos_anterior

	while _arraste_indice_atual < caminho.size() - 1:
		var indice_origem: int = int(caminho[_arraste_indice_atual])
		var indice_destino: int = int(caminho[_arraste_indice_atual + 1])
		if (
			indice_origem < 0
			or indice_origem >= _pontos.size()
			or indice_destino < 0
			or indice_destino >= _pontos.size()
		):
			_falhar_arraste_atual("CAMINHO INVÁLIDO")
			return

		var origem: Vector2 = _pontos[indice_origem].position
		var destino: Vector2 = _pontos[indice_destino].position
		var raio_checkpoint: float = _raio_arraste_checkpoint(indice_destino)
		var raio_tubo: float = _raio_tubo_arraste(indice_origem, indice_destino)
		var validacao: Dictionary = _validar_movimento_dentro_tubo(
			inicio_movimento, pos, origem, destino, raio_tubo, raio_checkpoint
		)

		if not bool(validacao["valido"]):
			# Não falha na primeira escapada. Inicia a janela de retorno ao tubo.
			var agora_msec: int = Time.get_ticks_msec()
			if _arraste_fora_tubo_desde_msec < 0:
				_arraste_fora_tubo_desde_msec = agora_msec
			var tempo_fora: float = float(agora_msec - _arraste_fora_tubo_desde_msec) / 1000.0
			if tempo_fora >= ARRASTE_TEMPO_FORA_TUBO_TOLERADO_SEG:
				_falhar_arraste_atual("SAIU DO TUBO")
			return

		# Voltou para a área tolerada: cancela a contagem de saída.
		_arraste_fora_tubo_desde_msec = -1
		_arraste_progresso_segmento = max(
			_arraste_progresso_segmento, float(validacao["progresso_max"])
		)
		if not bool(validacao["chegou_destino"]):
			break

		# O destino só vale quando o movimento realmente percorreu a maior parte do tubo.
		if _arraste_progresso_segmento < ARRASTE_PROGRESSO_MINIMO_SEGMENTO:
			_falhar_arraste_atual("NÃO PASSOU PELO TUBO")
			return

		_arraste_indice_atual += 1
		_arraste_progresso_segmento = 0.0
		_arraste_fora_tubo_desde_msec = -1
		_ponto_set_estado(indice_destino, "hig", 0.14, _cor_orbe_por_ponto(indice_destino))
		_agendar_apagamento_tazo(indice_origem, TEMPO_TAZO_POS_CHECKPOINT_SEG)
		_registrar_efeito_passagem_tubo(destino, _cor_caminho_evento(_arraste_evento_atual), 1.0)

		if _arraste_indice_atual >= caminho.size() - 1:
			_resolver_arraste_completo()
			return

		# Se um único evento de touch atravessou mais de um trecho, a próxima validação
		# parte exatamente do checkpoint alcançado, sem aceitar atalhos diagonais.
		inicio_movimento = destino


func _falhar_arraste_atual(mensagem: String) -> void:
	if _arraste_evento_atual == null:
		_arraste_gesto_ativo = false
		return

	var evento: Dictionary = _arraste_evento_atual
	if not evento.get("resolvido", false):
		evento["resolvido"] = true
		evento["sucesso"] = false
		_registrar_erro(evento)
		var caminho: Array = evento.get("caminho", [])
		for indice_p in caminho:
			var idx: int = int(indice_p)
			_ponto_set_estado(idx, "hig", 0.12, COR_ERRO)
			_agendar_apagamento_tazo(idx, TEMPO_TAZO_POS_ACERTO_SEG)
		_efeito_texto_flutuante(mensagem, _centro_caminho(caminho), COR_ERRO)

	_arraste_evento_atual = null
	_arraste_indice_atual = 0
	_arraste_progresso_segmento = 0.0
	_arraste_fora_tubo_desde_msec = -1
	_arraste_gesto_ativo = false
	_hover_indice_atual = -1


func _resolver_arraste_completo() -> void:
	if _arraste_evento_atual == null:
		return

	var evento: Dictionary = _arraste_evento_atual
	if evento.get("resolvido", false):
		return

	var caminho: Array = evento["caminho"]
	var tempo_musica: float = _tempo_atual_musica()
	var dentro_do_tempo: bool = (
		tempo_musica <= float(evento["tempo_fim"]) + ARRASTE_TOLERANCIA_FINAL_SEG
	)

	if not dentro_do_tempo:
		_falhar_arraste_atual("ARRASTE FORA DO TEMPO")
		return

	evento["resolvido"] = true
	evento["sucesso"] = true
	_registrar_acerto(PONTOS_POR_ACERTO_ARRASTE)
	for indice_p in caminho:
		var idx_ok: int = int(indice_p)
		_ponto_set_estado(idx_ok, "hig", 0.16, COR_SLIDE_COMPLETO)
		_agendar_apagamento_tazo(idx_ok, TEMPO_TAZO_POS_ACERTO_SEG)
	_registrar_efeito_passagem_tubo(
		_pontos[int(caminho[caminho.size() - 1])].position, COR_SLIDE_COMPLETO, 1.35
	)
	_efeito_texto_flutuante("ARRASTE COMPLETO!", _centro_caminho(caminho), COR_SLIDE_COMPLETO)

	_arraste_evento_atual = null
	_arraste_indice_atual = 0
	_arraste_progresso_segmento = 0.0
	_arraste_fora_tubo_desde_msec = -1
	_arraste_gesto_ativo = false


func _finalizar_arraste() -> void:
	if _arraste_evento_atual != null:
		var evento: Dictionary = _arraste_evento_atual
		var caminho: Array = evento["caminho"]
		var completou_caminho: bool = _arraste_indice_atual >= caminho.size() - 1

		if completou_caminho:
			_resolver_arraste_completo()
		else:
			_falhar_arraste_atual("ARRASTE INCOMPLETO")

	_arraste_evento_atual = null
	_arraste_indice_atual = 0
	_arraste_progresso_segmento = 0.0
	_arraste_fora_tubo_desde_msec = -1
	_arraste_gesto_ativo = false
	_hover_indice_atual = -1


func _registrar_acerto(pontos: int) -> void:
	var bonus_combo: float = 1.0 + min(float(_combo_atual), 10.0) * 0.05
	var pontos_finais: int = int(round(float(pontos) * bonus_combo))
	_pontuacao += pontos_finais
	_combo_atual += 1
	_combo_maximo = max(_combo_maximo, _combo_atual)
	# Impacto apenas visual no equalizador circular. A lógica física abaixo e as
	# rotinas de LED permanecem exatamente com o comportamento original do Soul.
	_onda_acerto_nivel = clamp(
		_onda_acerto_nivel + ONDA_ACERTO_INCREMENTO, 0.0, 1.0
	)
	_onda_pulso_hit = max(
		_onda_pulso_hit,
		ONDA_PULSO_ARRASTE if pontos == PONTOS_POR_ACERTO_ARRASTE else ONDA_PULSO_TOQUE
	)
	_alterar_volume_musica_imediato(VOLUME_PASSO_ACERTO_DB)
	_atualizar_hud()
	_mostrar_combo()


func _registrar_erro(_evento: Dictionary) -> void:
	# Sem perda de pontos -- só zera o combo e o volume da música cai (efeito "Guitar Hero").
	_combo_atual = 0
	_alterar_volume_musica_imediato(VOLUME_PASSO_ERRO_DB)
	_atualizar_hud()

	# Feedback físico de erro somente para eventos de clique.
	# Arrastes nunca acendem nem alteram as fitas conectadas em D2..D9.
	if _evento.get("tipo", "") == "toque":
		var indice_led: int = int(_evento.get("ponto", -1))
		if indice_led >= 0:
			if indice_led < _pontos.size():
				_explosao_particulas(_pontos[indice_led].position, COR_ERRO)
				_efeito_texto_flutuante("ERROU!", _pontos[indice_led].position, COR_ERRO)


func _indice_led_do_evento(evento: Dictionary) -> int:
	if evento.is_empty() or evento.get("tipo", "") != "toque":
		return -1
	return int(evento.get("ponto", -1))


func _centro_caminho(caminho: Array) -> Vector2:
	if caminho.is_empty():
		return _centro_tela
	var soma: Vector2 = Vector2.ZERO
	for indice in caminho:
		if int(indice) >= 0 and int(indice) < _pontos.size():
			soma += _pontos[int(indice)].position
	return soma / float(caminho.size())


func _efeito_texto_flutuante(texto: String, pos: Vector2, cor: Color) -> void:
	pos = _limitar_pos_efeito_no_circulo(pos, _raio_circulo_px * 0.20)
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

	# Mede o texto de verdade -- tanto o Label quanto o card usam exatamente essa
	# medida (mais uma folga vertical pequena pra acentos/cedilha não cortar), em vez
	# de uma caixa genérica grande. Assim nada fica sobrando pros lados ou em cima/baixo.
	var fonte: Font = ThemeDB.fallback_font
	var largura_texto: float = (
		fonte.get_string_size(texto, HORIZONTAL_ALIGNMENT_CENTER, -1, cfg.font_size).x
	)
	var altura_texto: float = cfg.font_size * 1.18

	var label := Label.new()
	label.label_settings = cfg
	label.text = texto
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = Vector2(largura_texto, altura_texto)
	label.position = pos - label.size / 2.0
	label.pivot_offset = label.size / 2.0  # escala/gira sempre a partir do centro real do texto
	label.scale = Vector2(0.62, 0.62)
	label.modulate = Color(1, 1, 1, 0.0)
	layer.add_child(label)

	# Card "vidro" moderno atrás do texto, com padding fixo e igual nos 4 lados --
	# cantos arredondados tipo chip de HUD tecnológico, sempre do tamanho exato do
	# texto (+ padding), nunca maior nem descentralizado.
	var padding_h: float = cfg.font_size * 0.55
	var padding_v: float = cfg.font_size * 0.30
	var largura_card: float = largura_texto + padding_h * 2.0
	var altura_card: float = altura_texto + padding_v * 2.0

	var brilho := Panel.new()
	var estilo_brilho := StyleBoxFlat.new()
	estilo_brilho.bg_color = Color(cor.r, cor.g, cor.b, 0.16)
	estilo_brilho.set_border_width_all(2)
	estilo_brilho.border_color = Color(cor.r, cor.g, cor.b, 0.62)
	estilo_brilho.set_corner_radius_all(int(altura_card * 0.5))
	estilo_brilho.shadow_color = Color(cor.r, cor.g, cor.b, 0.42)
	estilo_brilho.shadow_size = int(altura_card * 0.30)
	brilho.add_theme_stylebox_override("panel", estilo_brilho)
	brilho.size = Vector2(largura_card, altura_card)
	brilho.position = pos - brilho.size / 2.0
	brilho.pivot_offset = brilho.size / 2.0
	brilho.scale = Vector2(0.62, 0.62)
	brilho.mouse_filter = Control.MOUSE_FILTER_IGNORE
	brilho.modulate = Color(1, 1, 1, 0.0)
	layer.add_child(brilho)
	layer.move_child(brilho, 0)  # o card fica atrás do texto, não na frente

	# Ambos os pivots ficam no centro exato (pos), e ambos assentam em escala 1.0 --
	# o "TRANS_BACK" só dá aquele leve estouro durante o movimento, não deixa o texto
	# maior que o card no final (era esse o bug: antes o texto ia até 1.18 e o card
	# só até 1.06, então o texto vazava pros lados).
	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "scale", Vector2(1.0, 1.0), 0.18).set_trans(Tween.TRANS_BACK).set_ease(
		Tween.EASE_OUT
	)
	tw.tween_property(label, "modulate", Color(1, 1, 1, 1.0), 0.10)
	(
		tw
		. tween_property(brilho, "scale", Vector2(1.0, 1.0), 0.18)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	tw.tween_property(brilho, "modulate", Color(1, 1, 1, 0.92), 0.10)
	tw.set_parallel(false)
	tw.tween_interval(0.46)
	tw.set_parallel(true)
	(
		tw
		. tween_property(
			label, "position", label.position + Vector2(0, -_raio_circulo_px * 0.085), 0.42
		)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	(
		tw
		. tween_property(
			brilho, "position", brilho.position + Vector2(0, -_raio_circulo_px * 0.085), 0.42
		)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	tw.tween_property(label, "modulate", Color(1, 1, 1, 0.0), 0.42)
	tw.tween_property(brilho, "modulate", Color(1, 1, 1, 0.0), 0.32)
	tw.finished.connect(
		func():
			if layer and is_instance_valid(layer):
				layer.queue_free()
	)


func _atualizar_hud() -> void:
	if _label_pontuacao:
		_label_pontuacao.text = str(_pontuacao)
	if _label_combo and _combo_atual >= 2:
		_label_combo.visible = true
		_label_combo.modulate = Color.WHITE
		_label_combo.text = "HIT COMBO x%d" % _combo_atual


func _mostrar_combo() -> void:
	if _label_combo == null or _combo_atual < 2:
		return

	_combo_visivel_ate_msec = Time.get_ticks_msec() + int(TEMPO_COMBO_VISIVEL_SEG * 1000.0)
	_combo_fade_em_andamento = false
	_label_combo.visible = true
	_label_combo.modulate = Color.WHITE
	_label_combo.text = "HIT COMBO x%d" % _combo_atual
	if _tween_combo:
		_tween_combo.kill()
	_label_combo.scale = Vector2(1.42, 1.42)
	_tween_combo = create_tween()
	_tween_combo.set_trans(Tween.TRANS_BACK)
	_tween_combo.set_ease(Tween.EASE_OUT)
	_tween_combo.tween_property(_label_combo, "scale", Vector2(1.0, 1.0), 0.30)


func _atualizar_visibilidade_combo() -> void:
	if _label_combo == null or not _label_combo.visible:
		return
	if _combo_visivel_ate_msec <= 0 or Time.get_ticks_msec() < _combo_visivel_ate_msec:
		return
	if _combo_fade_em_andamento:
		return

	_combo_fade_em_andamento = true
	var prazo_encerrado: int = _combo_visivel_ate_msec
	var tw: Tween = create_tween()
	tw.tween_property(_label_combo, "modulate", Color(1, 1, 1, 0.0), TEMPO_FADE_COMBO_SEG)
	tw.finished.connect(
		func():
			if _combo_visivel_ate_msec == prazo_encerrado:
				_label_combo.visible = false
				_label_combo.modulate = Color.WHITE
				_combo_visivel_ate_msec = 0
			_combo_fade_em_andamento = false
	)


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
	grad.colors = PackedColorArray(
		[
			Color(1.0, 1.0, 1.0, 1.0),
			Color(cor_base.r, cor_base.g, cor_base.b, 0.9),
			Color(cor_base.r, cor_base.g, cor_base.b, 0.0),
		]
	)
	grad.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	return grad


func _explosao_particulas(pos: Vector2, cor: Color) -> void:
	# Explosão menor e mais sofisticada: brilho principal + pequenas fagulhas coloridas.
	_criar_particulas_neon(
		pos, cor, 14 if not _visual_reduzido else 9, 0.40, 38.0, 105.0, 0.20, 0.40, 24
	)

	if not _visual_reduzido:
		var cor_extra: Color = cor.lerp(Color(1.0, 0.35, 1.0, 1.0), 0.38)
		_criar_particulas_neon(pos, cor_extra, 6, 0.28, 24.0, 72.0, 0.10, 0.23, 25)


func _criar_particulas_neon(
	pos: Vector2,
	cor: Color,
	quantidade: int,
	vida: float,
	vel_min: float,
	vel_max: float,
	escala_min: float,
	escala_max: float,
	z: int
) -> void:
	var particulas := CPUParticles2D.new()
	particulas.position = _limitar_pos_efeito_no_circulo(pos, _raio_circulo_px * 0.10)
	particulas.z_index = z
	particulas.texture = _obter_textura_particula()
	particulas.emitting = true
	particulas.one_shot = true
	particulas.amount = quantidade
	particulas.lifetime = vida
	particulas.explosiveness = 1.0
	particulas.spread = 180.0
	particulas.initial_velocity_min = vel_min * ESCALA_ALCANCE_PARTICULAS
	particulas.initial_velocity_max = vel_max * ESCALA_ALCANCE_PARTICULAS
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
# BEATMAP DE TESTE (usado só se BEATMAP_SOUL estiver vazio)
# ---------------------------------------------------------------


func _gerar_beatmap_soul_por_fases(duracao_seg: float) -> Array:
	var eventos: Array = []

	# Este beatmap não fica mais A-B-C-D em sequência.
	# Ele cria uma sequência musical "aleatória controlada":
	# - Intro: poucos toques e quase nenhum arraste.
	# - Verso: alterna pontos distantes para dar movimento.
	# - Refrão: mais hits e mais velocidade.
	# - Ponte: arrastes maiores conectando pontos distantes.
	# - Final: mistura toque duplo visual + arraste curto, mais intenso.
	#
	# A música real desta fase é soul.mp3.
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
			var caminho: Array = _montar_caminho_arraste_musical(
				inicio, tamanho_caminho, intensidade
			)

			(
				eventos
				. append(
					{
						"tipo": "arraste",
						"tempo": tempo_evento,
						"tempo_fim": tempo_evento + intervalo * (1.5 + intensidade * 0.22),
						"caminho": caminho,
					}
				)
			)

			ultimo_ponto = caminho[caminho.size() - 1]
			tempo += intervalo * (1.8 + intensidade * 0.18)

		else:
			var ponto_a: int = _sortear_ponto_musical(ultimo_ponto, intensidade)

			(
				eventos
				. append(
					{
						"tipo": "toque",
						"tempo": tempo_evento,
						"ponto": ponto_a,
					}
				)
			)

			ultimo_ponto = ponto_a

			# Hit duplo: dois pontos próximos no tempo, comum em batidas fortes.
			# Não é exatamente simultâneo para o jogador conseguir reagir.
			if _rng.randf() < chance_hit_duplo and tempo_evento + 0.12 < duracao_seg:
				var ponto_b: int = _sortear_ponto_musical(ponto_a, intensidade + 1)

				(
					eventos
					. append(
						{
							"tipo": "toque",
							"tempo": tempo_evento + _rng.randf_range(0.10, 0.16),
							"ponto": ponto_b,
						}
					)
				)

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
		draw_circle(
			Vector2.ZERO, raio_ponto * 1.4, Color(0.25, 0.85, 1.0, 0.035 + pulso_idle * 0.03)
		)

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
			draw_line(
				dir_marca * r_ini,
				dir_marca * r_fim,
				Color(1, 1, 1, alpha_marca),
				espessura_marca,
				true
			)

		draw_arc(Vector2.ZERO, raio_ponto * 1.18, 0.0, TAU, 48, Color(1, 1, 1, 0.12), 1.0, true)
		draw_arc(Vector2.ZERO, raio_ponto, 0.0, TAU, 48, Color(1, 1, 1, 0.30), 2.5, true)

		if estado == "aproximando":
			# Anel de contagem regressiva encolhendo, com "cauda" tipo cometa girando.
			var raio_aprox: float = lerp(raio_ponto * 1.7, raio_ponto * 1.05, progresso_aproximacao)
			var inicio_arco: float = _rotacao_interna * 3.0
			draw_arc(
				Vector2.ZERO,
				raio_aprox,
				inicio_arco,
				inicio_arco + TAU * 0.72,
				40,
				Color(0.25, 0.85, 1.0, 0.95),
				5.0,
				true
			)
			draw_arc(
				Vector2.ZERO,
				raio_aprox,
				inicio_arco,
				inicio_arco + TAU * 0.72,
				40,
				Color(0.25, 0.85, 1.0, 0.28),
				11.0,
				true
			)

		if estado == "ativo" or estado == "ativo_arraste":
			var pulso_ativo: float = sin(Time.get_ticks_msec() / 90.0) * 0.5 + 0.5
			draw_circle(
				Vector2.ZERO, raio_ponto * 1.35, Color(1.0, 0.15, 0.85, 0.10 + pulso_ativo * 0.08)
			)
			draw_circle(
				Vector2.ZERO, raio_ponto * 1.15, Color(1.0, 0.15, 0.85, 0.20 + pulso_ativo * 0.14)
			)
			draw_circle(
				Vector2.ZERO, raio_ponto * (0.82 + pulso_ativo * 0.08), Color(1.0, 0.15, 0.85, 0.9)
			)

		if flash_tempo > 0.0:
			var alpha: float = clamp(flash_tempo / 0.25, 0.0, 1.0)
			var expansao: float = 1.0 - alpha
			draw_circle(
				Vector2.ZERO,
				raio_ponto * (1.3 + expansao * 0.4),
				Color(flash_cor.r, flash_cor.g, flash_cor.b, alpha * 0.45)
			)
			draw_arc(
				Vector2.ZERO,
				raio_ponto * (1.3 + expansao * 0.4),
				0.0,
				TAU,
				32,
				Color(flash_cor.r, flash_cor.g, flash_cor.b, alpha * 0.65),
				3.5,
				true
			)

		# Núcleo com degradê em camadas + friso interno.
		draw_circle(Vector2.ZERO, raio_ponto * 0.62, Color(0.06, 0.0, 0.10, 0.94))
		draw_circle(Vector2.ZERO, raio_ponto * 0.53, Color(0.11, 0.02, 0.16, 0.9))
		draw_arc(Vector2.ZERO, raio_ponto * 0.53, 0.0, TAU, 32, Color(1, 1, 1, 0.10), 1.5, true)

		# Letra com sombra por trás -- legibilidade e acabamento.
		var largura_texto: float = (
			fonte.get_string_size(letra, HORIZONTAL_ALIGNMENT_CENTER, -1, tam_fonte).x
		)
		draw_string(
			fonte,
			Vector2(-largura_texto / 2.0 + 1.5, tam_fonte * 0.31 + 1.5),
			letra,
			HORIZONTAL_ALIGNMENT_CENTER,
			-1,
			tam_fonte,
			Color(0, 0, 0, 0.6)
		)
		draw_string(
			fonte,
			Vector2(-largura_texto / 2.0, tam_fonte * 0.31),
			letra,
			HORIZONTAL_ALIGNMENT_CENTER,
			-1,
			tam_fonte,
			Color.WHITE
		)
