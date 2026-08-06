class_name HitMusicDifficultyConfig
extends Resource

@export_enum("FACIL", "DIFICIL")
var nome: String = "FACIL"

@export_file("*.json")
var chart_path: String = ""

@export_group("Jogabilidade")
@export_range(0.50, 2.00, 0.01)
var tempo_aproximacao: float = 1.10

@export_range(0.05, 0.40, 0.005)
var janela_acerto: float = 0.20

@export_range(0.02, 0.20, 0.005)
var janela_perfeito: float = 0.075

@export_range(1, 4, 1)
var max_notas_simultaneas: int = 2

@export_group("Visual")
@export_range(0.50, 1.50, 0.01)
var escala_tap: float = 1.0

@export_range(0.50, 1.50, 0.01)
var escala_estrela: float = 1.0

@export_range(0.50, 1.50, 0.01)
var largura_hold: float = 1.0

@export_range(0.50, 2.00, 0.01)
var velocidade_slide: float = 1.0

@export_range(0.0, 1.0, 0.01)
var intensidade_fundo: float = 0.18

@export_range(0.0, 2.0, 0.01)
var velocidade_fundo: float = 0.50

@export_group("Combinacoes")
@export var permitir_slides_cruzados: bool = false
@export var permitir_slides_curvos: bool = true
@export var permitir_duplas: bool = false
@export var permitir_hold_com_slide: bool = false