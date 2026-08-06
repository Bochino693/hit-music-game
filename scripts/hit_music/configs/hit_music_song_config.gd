class_name HitMusicSongConfig
extends Resource

@export_group("Identificacao")
@export var id: String = ""
@export var nome: String = ""
@export var artista: String = ""

@export_group("Arquivos")
@export_file var musica_path: String = ""
@export_file var imagem_capa_path: String = ""
@export_file var video_contagem_path: String = ""
@export_file var video_fundo_path: String = ""
@export_file var video_preview_path: String = ""

@export_group("Tema")
@export var cor_primaria: Color = Color.WHITE
@export var cor_secundaria: Color = Color.WHITE
@export var cor_slide: Color = Color(0.0, 0.95, 1.0, 1.0)
@export var cor_hold: Color = Color(1.0, 0.84, 0.05, 1.0)

@export_enum(
	"NENHUM",
	"LOSANGOS",
	"HEXAGONOS",
	"QUADRADOS",
	"LINHAS TECNICAS",
	"COLMEIA",
	"RADIAL"
)
var padrao_fundo_principal: String = "LOSANGOS"

@export_enum(
	"NENHUM",
	"LOSANGOS",
	"HEXAGONOS",
	"QUADRADOS",
	"LINHAS TECNICAS",
	"COLMEIA",
	"RADIAL"
)
var padrao_fundo_secundario: String = "HEXAGONOS"

@export_group("Dificuldades")
@export var facil: HitMusicDifficultyConfig
@export var dificil: HitMusicDifficultyConfig