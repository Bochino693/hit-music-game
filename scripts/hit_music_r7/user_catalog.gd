extends RefCounted
## Musicas cadastradas pelo operador na tela de Configuracoes.
##
## Uma musica de fabrica mora em res:// e vem no executavel. Uma musica
## nova, cadastrada no gabinete, NAO pode morar la: depois de exportado
## o res:// e somente leitura. Entao os arquivos escolhidos sao copiados
## para user:// (a pasta de dados do jogo, que sobrevive a fechar e
## reabrir) e a ficha da musica e gravada num JSON separado.
##
## O catalogo junta as duas listas, entao para o resto do jogo nao
## existe diferenca: a musica nova aparece no seletor, entra no ranking
## e gera fase igual as outras — o ritmo dela sai do BPM informado, via
## rhythm_profile.gd.

const USER_SONGS_PATH: String = "user://hit_music_user_songs.json"
const AUDIO_DIR: String = "user://songs"
const VIDEO_DIR: String = "user://medias"
const COVER_DIR: String = "user://covers"
## Cena generica: nao da para gerar um .tscn novo em tempo de execucao,
## entao toda musica de operador usa a mesma cena, que descobre qual
## musica carregar pela meta da arvore (ver scripts/user_song.gd).
const USER_SCENE: String = "res://scenes/user_song.tscn"

const AUDIO_EXTENSIONS: Array[String] = ["mp3", "ogg", "wav"]
const COVER_EXTENSIONS: Array[String] = ["png", "jpg", "jpeg", "webp"]
const VIDEO_EXTENSIONS: Array[String] = ["ogv"]


static func all_user_songs() -> Array:
	if not FileAccess.file_exists(USER_SONGS_PATH):
		return []

	var file := FileAccess.open(USER_SONGS_PATH, FileAccess.READ)
	if file == null:
		return []

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return []

	var songs_value: Variant = (parsed as Dictionary).get("songs", [])
	if not songs_value is Array:
		return []

	var result: Array = []
	for value in (songs_value as Array):
		if value is Dictionary:
			result.append((value as Dictionary).duplicate(true))
	return result


static func save_user_songs(songs: Array) -> bool:
	var file := FileAccess.open(USER_SONGS_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Nao foi possivel gravar " + USER_SONGS_PATH)
		return false
	file.store_string(JSON.stringify({"songs": songs}, "\t"))
	return true


## Cadastra uma musica. Devolve {"ok": bool, "erro": String, "id": String}.
## O audio e obrigatorio; video e capa sao opcionais.
static func add_song(
	title: String,
	audio_source: String,
	video_source: String,
	cover_source: String,
	bpm: float
) -> Dictionary:
	var clean_title: String = title.strip_edges()
	if clean_title.is_empty():
		return {"ok": false, "erro": "Informe o nome da música.", "id": ""}
	if audio_source.strip_edges().is_empty():
		return {"ok": false, "erro": "Escolha o arquivo de áudio.", "id": ""}
	if not FileAccess.file_exists(audio_source):
		return {"ok": false, "erro": "Áudio não encontrado no caminho informado.", "id": ""}
	if not _extension_allowed(audio_source, AUDIO_EXTENSIONS):
		return {"ok": false, "erro": "Áudio precisa ser mp3, ogg ou wav.", "id": ""}

	var songs: Array = all_user_songs()
	var song_id: String = _unique_id(clean_title, songs)

	var audio_path: String = _copy_media(audio_source, AUDIO_DIR, song_id)
	if audio_path.is_empty():
		return {"ok": false, "erro": "Falha ao copiar o áudio.", "id": ""}

	var video_path: String = ""
	if not video_source.strip_edges().is_empty():
		if not _extension_allowed(video_source, VIDEO_EXTENSIONS):
			return {"ok": false, "erro": "O vídeo precisa ser .ogv.", "id": ""}
		video_path = _copy_media(video_source, VIDEO_DIR, song_id)

	var cover_path: String = ""
	if not cover_source.strip_edges().is_empty():
		if not _extension_allowed(cover_source, COVER_EXTENSIONS):
			return {"ok": false, "erro": "A capa precisa ser png, jpg ou webp.", "id": ""}
		cover_path = _copy_media(cover_source, COVER_DIR, song_id)

	var song: Dictionary = {
		"id": song_id,
		"title": clean_title.to_upper(),
		"scene": USER_SCENE,
		"audio": audio_path,
		"video": video_path,
		"cover": cover_path,
		"bpm": clampf(bpm, 40.0, 260.0),
		"chart_start": 4.0,
		"seed": _seed_from_text(song_id),
		"pattern": "diamonds",
		"colors": _colors_for(cover_path, song_id),
		"user_song": true,
	}

	songs.append(song)
	if not save_user_songs(songs):
		return {"ok": false, "erro": "Não foi possível gravar o catálogo.", "id": ""}
	return {"ok": true, "erro": "", "id": song_id}


static func remove_song(song_id: String) -> bool:
	var songs: Array = all_user_songs()
	var kept: Array = []
	var removed: bool = false
	for value in songs:
		if value is Dictionary and str((value as Dictionary).get("id", "")) == song_id:
			_delete_media(value as Dictionary)
			removed = true
			continue
		kept.append(value)
	if not removed:
		return false
	return save_user_songs(kept)


## Carrega um audio que pode estar em res:// (musica de fabrica) ou em
## user:// (musica do operador). Em user:// nao existe importacao do
## Godot, entao o arquivo e lido em bytes e o stream e montado na mao.
static func load_audio(path: String) -> AudioStream:
	if path.is_empty():
		return null

	if path.begins_with("res://"):
		if not ResourceLoader.exists(path):
			return null
		var resource: Resource = load(path)
		return resource as AudioStream if resource is AudioStream else null

	if not FileAccess.file_exists(path):
		return null

	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null

	match path.get_extension().to_lower():
		"mp3":
			var mp3 := AudioStreamMP3.new()
			mp3.data = bytes
			mp3.loop = false
			return mp3
		"ogg":
			return AudioStreamOggVorbis.load_from_buffer(bytes)
		"wav":
			# WAV sem importacao nao carrega por bytes de forma confiavel
			# (o cabecalho define formato, canais e taxa). Convertemos o
			# caminho num stream so quando o Godot souber ler.
			var wav_resource: Resource = ResourceLoader.load(path)
			return wav_resource as AudioStream if wav_resource is AudioStream else null
		_:
			return null


static func load_cover(path: String) -> Texture2D:
	if path.is_empty():
		return null

	if path.begins_with("res://"):
		if not ResourceLoader.exists(path):
			return null
		var resource: Resource = load(path)
		return resource as Texture2D if resource is Texture2D else null

	if not FileAccess.file_exists(path):
		return null

	var image := Image.new()
	if image.load(path) != OK:
		return null
	return ImageTexture.create_from_image(image)


## Video de user:// nao passa pelo importador, entao o stream aponta
## direto para o arquivo. Se a build nao conseguir abrir, o chamador
## simplesmente segue sem video — a musica continua jogavel.
static func load_video(path: String) -> VideoStream:
	if path.is_empty():
		return null

	if path.begins_with("res://"):
		if not ResourceLoader.exists(path):
			return null
		var resource: Resource = load(path)
		return resource as VideoStream if resource is VideoStream else null

	if not FileAccess.file_exists(path):
		return null

	var stream := VideoStreamTheora.new()
	stream.file = path
	return stream


static func _extension_allowed(path: String, allowed: Array[String]) -> bool:
	return path.get_extension().to_lower() in allowed


static func _copy_media(source: String, directory: String, song_id: String) -> String:
	if not DirAccess.dir_exists_absolute(directory):
		DirAccess.make_dir_recursive_absolute(directory)

	var target: String = "%s/%s.%s" % [
		directory,
		song_id,
		source.get_extension().to_lower()
	]

	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(source)
	if bytes.is_empty():
		return ""

	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_buffer(bytes)
	file.close()
	return target


static func _delete_media(song: Dictionary) -> void:
	for key in ["audio", "video", "cover"]:
		var path: String = str(song.get(key, ""))
		if path.begins_with("user://") and FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


static func _unique_id(title: String, songs: Array) -> String:
	var base: String = ""
	for character in title.to_lower():
		if character.is_valid_identifier() or character.is_valid_int():
			base += character
		elif character == " " or character == "-":
			base += "_"
	base = base.strip_edges()
	if base.is_empty():
		base = "musica"
	base = "user_" + base

	var taken: Dictionary = {}
	for value in songs:
		if value is Dictionary:
			taken[str((value as Dictionary).get("id", ""))] = true

	if not taken.has(base):
		return base
	var index: int = 2
	while taken.has("%s_%d" % [base, index]):
		index += 1
	return "%s_%d" % [base, index]


static func _seed_from_text(text: String) -> int:
	var value: int = 1013
	for index in range(text.length()):
		value = posmod(value * 31 + text.unicode_at(index), 100000)
	return value


## Paleta da musica nova. Se houver capa, a cor principal sai da propria
## imagem (media dos pixels mais saturados) — a tela nasce combinando
## com a arte. Sem capa, sai da semente do nome.
static func _colors_for(cover_path: String, song_id: String) -> Dictionary:
	var primary := Color(0.05, 0.92, 1.0, 1.0)

	var texture: Texture2D = load_cover(cover_path)
	if texture != null:
		var image: Image = texture.get_image()
		if image != null:
			primary = _dominant_color(image)
	else:
		var hue: float = float(_seed_from_text(song_id) % 360) / 360.0
		primary = Color.from_hsv(hue, 0.85, 1.0, 1.0)

	var accent: Color = Color.from_hsv(
		fposmod(primary.h + 0.12, 1.0),
		clampf(primary.s * 0.75, 0.35, 1.0),
		1.0,
		1.0
	)
	var dark: Color = Color.from_hsv(primary.h, clampf(primary.s * 0.8, 0.0, 1.0), 0.055, 1.0)

	return {
		"primary": "#" + primary.to_html(false),
		"secondary": "#FFFFFF",
		"accent": "#" + accent.to_html(false),
		"dark": "#" + dark.to_html(false),
	}


static func _dominant_color(image: Image) -> Color:
	var width: int = image.get_width()
	var height: int = image.get_height()
	if width <= 0 or height <= 0:
		return Color(0.05, 0.92, 1.0, 1.0)

	var step_x: int = maxi(width / 48, 1)
	var step_y: int = maxi(height / 48, 1)
	var total := Vector3.ZERO
	var count: int = 0

	for x in range(0, width, step_x):
		for y in range(0, height, step_y):
			var pixel: Color = image.get_pixel(x, y)
			if pixel.a < 0.5 or pixel.s < 0.35 or pixel.v < 0.30:
				continue
			total += Vector3(pixel.r, pixel.g, pixel.b)
			count += 1

	if count <= 0:
		return Color(0.05, 0.92, 1.0, 1.0)

	var average := Color(total.x / count, total.y / count, total.z / count, 1.0)
	# Sobe saturacao e brilho: a cor do cenario precisa aguentar fundo
	# escuro, e a media de uma capa costuma sair lavada.
	return Color.from_hsv(
		average.h,
		clampf(average.s * 1.25 + 0.10, 0.45, 1.0),
		clampf(maxf(average.v, 0.70) * 1.10, 0.0, 1.0),
		1.0
	)
