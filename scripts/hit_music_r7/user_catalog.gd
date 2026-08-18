extends RefCounted
## Catálogo de músicas instaladas pelo operador.
##
## As músicas de fábrica continuam em res://. Pacotes vendidos à parte
## chegam por pendrive e são copiados para user://, que continua gravável
## depois que o jogo é exportado.
##
## FORMATO DO PACOTE NO PENDRIVE (uma pasta por música):
##   musica.mp3
##   musica.ogv
##   capa.png / capa.jpg / capa.jpeg / capa.webp
##   musica.txt
##
## Conteúdo mínimo do TXT:
##   name="NOME DA MUSICA"
##
## Opcionais:
##   category="POP"
##   bpm=128
##
## O BPM é procurado automaticamente nesta ordem:
## 1) TBPM embutido no MP3;
## 2) propriedade BPM do AudioStreamMP3;
## 3) bpm= no TXT;
## 4) se continuar zerado, config.gd faz análise de batidas em tempo real
##    com AudioEffectSpectrumAnalyzer antes de importar.

const USER_SONGS_PATH: String = "user://hit_music_user_songs.json"
const AUDIO_DIR: String = "user://songs"
const VIDEO_DIR: String = "user://medias"
const COVER_DIR: String = "user://covers"
const USER_SCENE: String = "res://scenes/user_song.tscn"

const AUDIO_EXTENSIONS: Array[String] = ["mp3", "ogg", "wav"]
const USB_AUDIO_EXTENSIONS: Array[String] = ["mp3"]
const COVER_EXTENSIONS: Array[String] = ["png", "jpg", "jpeg", "webp"]
const VIDEO_EXTENSIONS: Array[String] = ["ogv"]
const CATEGORIES: Array[String] = [
	"ANIME", "INFANTIL", "ROCK", "POP", "ELETRONICA",
	"FUNK", "HIP HOP", "SERTANEJO", "GOSPEL", "CLASSICA", "OUTROS",
]

const USB_CONTAINER_NAMES: Array[String] = [
	"HIT_MUSIC",
	"HITMUSIC",
	"MUSICAS",
	"MUSIC",
	"UPLOADS",
]


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
	file.close()
	return true


## Mantém a assinatura que o restante do jogo já usa.
## O áudio é obrigatório. Vídeo/capa continuam opcionais para compatibilidade
## com músicas antigas, mas o importador de PENDRIVE exige os quatro arquivos.
static func add_song(
	title: String,
	audio_source: String,
	video_source: String,
	cover_source: String,
	category: String,
	detected_bpm: float
) -> Dictionary:
	var clean_title: String = title.strip_edges()
	if clean_title.is_empty():
		return {"ok": false, "erro": "Informe o nome da música.", "id": ""}
	if audio_source.strip_edges().is_empty():
		return {"ok": false, "erro": "Escolha o arquivo de áudio.", "id": ""}
	if not FileAccess.file_exists(audio_source):
		return {"ok": false, "erro": "Áudio não encontrado.", "id": ""}
	if not _extension_allowed(audio_source, AUDIO_EXTENSIONS):
		return {"ok": false, "erro": "Áudio precisa ser mp3, ogg ou wav.", "id": ""}
	if detected_bpm < 40.0 or detected_bpm > 260.0:
		return {"ok": false, "erro": "BPM inválido ou ainda não detectado.", "id": ""}

	var clean_category: String = _normalize_category(category)
	var songs: Array = all_user_songs()

	for value in songs:
		if value is Dictionary:
			var existing_title: String = str((value as Dictionary).get("title", "")).strip_edges()
			if existing_title.to_upper() == clean_title.to_upper():
				return {
					"ok": false,
					"erro": "Esta música já está cadastrada: " + existing_title,
					"id": str((value as Dictionary).get("id", "")),
				}

	var song_id: String = _unique_id(clean_title, songs)

	var audio_path: String = _copy_media(audio_source, AUDIO_DIR, song_id)
	if audio_path.is_empty():
		return {"ok": false, "erro": "Falha ao copiar o áudio.", "id": ""}

	var video_path: String = ""
	if not video_source.strip_edges().is_empty():
		if not _extension_allowed(video_source, VIDEO_EXTENSIONS):
			_delete_if_exists(audio_path)
			return {"ok": false, "erro": "O vídeo precisa ser .ogv.", "id": ""}
		video_path = _copy_media(video_source, VIDEO_DIR, song_id)
		if video_path.is_empty():
			_delete_if_exists(audio_path)
			return {"ok": false, "erro": "Falha ao copiar o vídeo.", "id": ""}

	var cover_path: String = ""
	if not cover_source.strip_edges().is_empty():
		if not _extension_allowed(cover_source, COVER_EXTENSIONS):
			_delete_if_exists(audio_path)
			_delete_if_exists(video_path)
			return {"ok": false, "erro": "A capa precisa ser PNG, JPG ou WEBP.", "id": ""}
		cover_path = _copy_media(cover_source, COVER_DIR, song_id)
		if cover_path.is_empty():
			_delete_if_exists(audio_path)
			_delete_if_exists(video_path)
			return {"ok": false, "erro": "Falha ao copiar a capa.", "id": ""}

	var song: Dictionary = {
		"id": song_id,
		"title": clean_title.to_upper(),
		"scene": USER_SCENE,
		"audio": audio_path,
		"video": video_path,
		"cover": cover_path,
		"category": clean_category,
		"bpm": clampf(detected_bpm, 40.0, 260.0),
		"chart_start": 4.0,
		"seed": _seed_from_text(song_id),
		"pattern": "diamonds",
		"colors": _colors_for(cover_path, song_id),
		"user_song": true,
	}

	songs.append(song)
	if not save_user_songs(songs):
		_delete_media(song)
		return {"ok": false, "erro": "Não foi possível gravar o catálogo.", "id": ""}

	return {"ok": true, "erro": "", "id": song_id}


## ---------------------------------------------------------------
## PENDRIVE
## ---------------------------------------------------------------

## Escaneia os volumes montados e devolve pacotes encontrados.
## No Windows, DirAccess.get_drive_name() retorna C:, D:, E: etc.
## O drive onde o executável está rodando é ignorado para não vasculhar
## o disco interno da máquina.
static func scan_usb_packages() -> Array:
	var packages: Array = []
	var seen_folders: Dictionary = {}
	var system_drive: String = _system_drive_name()

	for drive_index in range(DirAccess.get_drive_count()):
		var drive_name: String = DirAccess.get_drive_name(drive_index).strip_edges()
		if drive_name.is_empty():
			continue

		if OS.get_name() == "Windows":
			if drive_name.to_upper() == system_drive.to_upper():
				continue

		var root: String = _drive_root(drive_name)
		if root.is_empty() or not DirAccess.dir_exists_absolute(root):
			continue

		# 1) Aceita uma música diretamente na raiz.
		_append_package_if_present(root, packages, seen_folders, drive_name)

		# 2) Pastas padrão para os pendrives que serão vendidos.
		for container_name in USB_CONTAINER_NAMES:
			var container: String = root.path_join(container_name)
			if not DirAccess.dir_exists_absolute(container):
				continue
			_append_package_if_present(container, packages, seen_folders, drive_name)
			_scan_direct_children(container, packages, seen_folders, drive_name)

		# 3) Também aceita pastas de música diretamente na raiz do pendrive.
		# Só olha um nível para não percorrer HDs externos inteiros.
		_scan_direct_children(root, packages, seen_folders, drive_name)

	packages.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("name", a.get("folder", ""))).nocasecmp_to(
			str(b.get("name", b.get("folder", "")))
		) < 0
	)
	return packages


static func _scan_direct_children(
	root: String,
	packages: Array,
	seen_folders: Dictionary,
	drive_name: String
) -> void:
	var dirs: PackedStringArray = DirAccess.get_directories_at(root)
	for dir_name in dirs:
		if str(dir_name).begins_with("."):
			continue
		var folder: String = root.path_join(str(dir_name))
		_append_package_if_present(folder, packages, seen_folders, drive_name)


static func _append_package_if_present(
	folder: String,
	packages: Array,
	seen_folders: Dictionary,
	drive_name: String
) -> void:
	var normalized: String = folder.replace("\\", "/")
	if seen_folders.has(normalized):
		return

	var package: Dictionary = inspect_usb_package(folder)
	if package.is_empty():
		return

	package["drive"] = drive_name
	seen_folders[normalized] = true
	packages.append(package)


## Retorna {} se a pasta nem parece um pacote de música.
## Se parece pacote, retorna um dicionário inclusive quando inválido,
## para a tela poder explicar o que está faltando.
static func inspect_usb_package(folder: String) -> Dictionary:
	if not DirAccess.dir_exists_absolute(folder):
		return {}

	var files: PackedStringArray = DirAccess.get_files_at(folder)
	var mp3_files: Array[String] = []
	var ogv_files: Array[String] = []
	var cover_files: Array[String] = []
	var txt_files: Array[String] = []

	for file_name_value in files:
		var file_name: String = str(file_name_value)
		if file_name.begins_with("."):
			continue
		var ext: String = file_name.get_extension().to_lower()
		match ext:
			"mp3":
				mp3_files.append(folder.path_join(file_name))
			"ogv":
				ogv_files.append(folder.path_join(file_name))
			"png", "jpg", "jpeg", "webp":
				cover_files.append(folder.path_join(file_name))
			"txt":
				txt_files.append(folder.path_join(file_name))

	if mp3_files.is_empty() and ogv_files.is_empty() and cover_files.is_empty() and txt_files.is_empty():
		return {}

	var errors: Array[String] = []
	if mp3_files.size() != 1:
		errors.append("precisa ter exatamente 1 MP3")
	if ogv_files.size() != 1:
		errors.append("precisa ter exatamente 1 OGV")
	if cover_files.size() != 1:
		errors.append("precisa ter exatamente 1 capa")
	if txt_files.size() != 1:
		errors.append("precisa ter exatamente 1 TXT")

	var metadata: Dictionary = {}
	if txt_files.size() == 1:
		metadata = _read_metadata_txt(txt_files[0])
		if str(metadata.get("name", "")).strip_edges().is_empty():
			errors.append('TXT sem name="..."')

	var audio_path: String = mp3_files[0] if mp3_files.size() == 1 else ""
	var bpm_value: float = 0.0
	if not audio_path.is_empty():
		bpm_value = embedded_bpm(audio_path)
		if bpm_value <= 0.0:
			bpm_value = stream_bpm(audio_path)
		if bpm_value <= 0.0:
			bpm_value = float(metadata.get("bpm", 0.0))

	var package_name: String = str(metadata.get("name", "")).strip_edges()
	if package_name.is_empty():
		package_name = folder.get_file().replace("_", " ")

	return {
		"folder": folder.replace("\\", "/"),
		"name": package_name,
		"audio": audio_path,
		"video": ogv_files[0] if ogv_files.size() == 1 else "",
		"cover": cover_files[0] if cover_files.size() == 1 else "",
		"txt": txt_files[0] if txt_files.size() == 1 else "",
		"category": _normalize_category(str(metadata.get("category", "OUTROS"))),
		"bpm": bpm_value,
		"valid": errors.is_empty(),
		"error": " • ".join(errors),
		"metadata": metadata,
	}


## Importa um pacote que já foi validado.
## bpm_override é usado quando config.gd precisou analisar o áudio.
static func import_usb_package(package: Dictionary, bpm_override: float = 0.0) -> Dictionary:
	if package.is_empty():
		return {"ok": false, "erro": "Pacote vazio.", "id": ""}
	if not bool(package.get("valid", false)):
		return {
			"ok": false,
			"erro": str(package.get("error", "Pacote inválido.")),
			"id": "",
		}

	var bpm_value: float = bpm_override
	if bpm_value <= 0.0:
		bpm_value = float(package.get("bpm", 0.0))

	if bpm_value < 40.0 or bpm_value > 260.0:
		return {
			"ok": false,
			"erro": "BPM não detectado. Analise o MP3 antes de importar.",
			"id": "",
		}

	return add_song(
		str(package.get("name", "")),
		str(package.get("audio", "")),
		str(package.get("video", "")),
		str(package.get("cover", "")),
		str(package.get("category", "OUTROS")),
		bpm_value
	)


## TXT simples no formato chave=valor.
## Aceita aspas simples, duplas ou valor sem aspas.
static func _read_metadata_txt(path: String) -> Dictionary:
	var result: Dictionary = {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return result

	var text: String = file.get_as_text()
	file.close()

	for raw_line in text.split("\n"):
		var line: String = str(raw_line).strip_edges()
		if line.is_empty() or line.begins_with("#") or line.begins_with(";"):
			continue

		var equal_index: int = line.find("=")
		if equal_index <= 0:
			continue

		var key: String = line.substr(0, equal_index).strip_edges().to_lower()
		var value: String = line.substr(equal_index + 1).strip_edges()
		value = _strip_matching_quotes(value)

		match key:
			"name":
				result["name"] = value
			"category":
				result["category"] = value
			"bpm":
				var parsed: float = float(value)
				if parsed >= 40.0 and parsed <= 260.0:
					result["bpm"] = parsed

	return result


static func _strip_matching_quotes(value: String) -> String:
	var cleaned: String = value.strip_edges()
	if cleaned.length() >= 2:
		var first: String = cleaned.substr(0, 1)
		var last: String = cleaned.substr(cleaned.length() - 1, 1)
		if (first == '"' and last == '"') or (first == "'" and last == "'"):
			return cleaned.substr(1, cleaned.length() - 2).strip_edges()
	return cleaned


static func _system_drive_name() -> String:
	if OS.get_name() != "Windows":
		return ""
	var executable: String = OS.get_executable_path().replace("\\", "/")
	if executable.length() >= 2 and executable.substr(1, 1) == ":":
		return executable.substr(0, 2)
	return "C:"


static func _drive_root(drive_name: String) -> String:
	var cleaned: String = drive_name.replace("\\", "/").strip_edges()
	if cleaned.is_empty():
		return ""
	if OS.get_name() == "Windows":
		if cleaned.ends_with("/"):
			return cleaned
		return cleaned + "/"
	return cleaned


## ---------------------------------------------------------------
## BPM
## ---------------------------------------------------------------

## Lê TBPM do ID3v2 do MP3. Para os pacotes vendidos pela empresa,
## gravar TBPM é o caminho mais rápido e determinístico.
static func embedded_bpm(audio_path: String) -> float:
	if audio_path.get_extension().to_lower() != "mp3":
		return 0.0

	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(audio_path)
	if bytes.size() < 20:
		return 0.0
	if bytes[0] != 73 or bytes[1] != 68 or bytes[2] != 51: # ID3
		return 0.0

	var version: int = int(bytes[3])
	var tag_size: int = _synchsafe_int(bytes, 6)
	var cursor: int = 10
	var limit: int = mini(bytes.size(), 10 + tag_size)

	while cursor + 10 <= limit:
		var frame_id: String = _ascii(bytes, cursor, 4)
		if frame_id.strip_edges().is_empty():
			break

		var frame_size: int = (
			_synchsafe_int(bytes, cursor + 4)
			if version >= 4
			else _big_endian_int(bytes, cursor + 4)
		)
		if frame_size <= 0 or cursor + 10 + frame_size > limit:
			break

		if frame_id == "TBPM":
			# Primeiro byte do payload é a codificação de texto.
			var text_start: int = cursor + 11
			var text_length: int = maxi(0, frame_size - 1)
			var bpm_text: String = _ascii(bytes, text_start, text_length).strip_edges()
			var parsed_bpm: float = float(bpm_text)
			if parsed_bpm >= 40.0 and parsed_bpm <= 260.0:
				return parsed_bpm

		cursor += 10 + frame_size

	return 0.0


## O Godot expõe a propriedade bpm no AudioStreamMP3. Em arquivos externos
## ela pode vir zerada; por isso é apenas uma das fontes, não a única.
static func stream_bpm(audio_path: String) -> float:
	if audio_path.get_extension().to_lower() != "mp3":
		return 0.0
	if not FileAccess.file_exists(audio_path):
		return 0.0

	var stream: AudioStreamMP3 = AudioStreamMP3.load_from_file(audio_path)
	if stream == null:
		return 0.0

	var value: float = float(stream.bpm)
	return value if value >= 40.0 and value <= 260.0 else 0.0


static func _normalize_category(category: String) -> String:
	var value: String = category.strip_edges().to_upper()
	return value if CATEGORIES.has(value) else "OUTROS"


static func _ascii(bytes: PackedByteArray, start: int, length: int) -> String:
	var text: String = ""
	var end: int = mini(bytes.size(), start + length)
	for index in range(start, end):
		var value: int = int(bytes[index])
		if value == 0:
			continue
		if value >= 32 and value <= 126:
			text += char(value)
	return text


static func _synchsafe_int(bytes: PackedByteArray, start: int) -> int:
	if start + 3 >= bytes.size():
		return 0
	return (
		((int(bytes[start]) & 0x7F) << 21)
		| ((int(bytes[start + 1]) & 0x7F) << 14)
		| ((int(bytes[start + 2]) & 0x7F) << 7)
		| (int(bytes[start + 3]) & 0x7F)
	)


static func _big_endian_int(bytes: PackedByteArray, start: int) -> int:
	if start + 3 >= bytes.size():
		return 0
	return (
		(int(bytes[start]) << 24)
		| (int(bytes[start + 1]) << 16)
		| (int(bytes[start + 2]) << 8)
		| int(bytes[start + 3])
	)


## ---------------------------------------------------------------
## REMOÇÃO / CARREGAMENTO
## ---------------------------------------------------------------

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

	match path.get_extension().to_lower():
		"mp3":
			return AudioStreamMP3.load_from_file(path)
		"ogg":
			var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
			if bytes.is_empty():
				return null
			return AudioStreamOggVorbis.load_from_buffer(bytes)
		"wav":
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
		var make_error: Error = DirAccess.make_dir_recursive_absolute(directory)
		if make_error != OK and not DirAccess.dir_exists_absolute(directory):
			return ""

	var target: String = "%s/%s.%s" % [
		directory,
		song_id,
		source.get_extension().to_lower(),
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


static func _delete_if_exists(path: String) -> void:
	if not path.is_empty() and path.begins_with("user://") and FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


static func _delete_media(song: Dictionary) -> void:
	for key in ["audio", "video", "cover"]:
		_delete_if_exists(str(song.get(key, "")))


static func _unique_id(title: String, songs: Array) -> String:
	var base: String = ""
	var lowered: String = title.to_lower()

	for index in range(lowered.length()):
		var character: String = lowered.substr(index, 1)
		var code: int = character.unicode_at(0)
		var is_ascii_letter: bool = code >= 97 and code <= 122
		var is_digit: bool = code >= 48 and code <= 57
		if is_ascii_letter or is_digit:
			base += character
		elif character == " " or character == "-" or character == "_":
			if not base.ends_with("_"):
				base += "_"

	base = base.trim_suffix("_")
	if base.is_empty():
		base = "musica"
	base = "user_" + base

	var taken: Dictionary = {}
	for value in songs:
		if value is Dictionary:
			taken[str((value as Dictionary).get("id", ""))] = true

	if not taken.has(base):
		return base

	var suffix: int = 2
	while taken.has("%s_%d" % [base, suffix]):
		suffix += 1
	return "%s_%d" % [base, suffix]


static func _seed_from_text(text: String) -> int:
	var value: int = 1013
	for index in range(text.length()):
		value = posmod(value * 31 + text.unicode_at(index), 100000)
	return value


static func _colors_for(cover_path: String, song_id: String) -> Dictionary:
	var primary := Color(0.05, 0.92, 1.0, 1.0)

	var texture: Texture2D = load_cover(cover_path)
	if texture != null:
		var image: Image = texture.get_image()
		if image != null and not image.is_empty():
			primary = _dominant_color(image)
	else:
		var hue: float = float(_seed_from_text(song_id) % 1000) / 1000.0
		primary = Color.from_hsv(hue, 0.78, 1.0, 1.0)

	var secondary_hue: float = fmod(primary.h + 0.46, 1.0)
	var secondary := Color.from_hsv(secondary_hue, 0.72, 1.0, 1.0)

	return {
		"primary": primary.to_html(false),
		"secondary": secondary.to_html(false),
	}


static func _dominant_color(image: Image) -> Color:
	var working: Image = image.duplicate()
	var max_side: int = maxi(working.get_width(), working.get_height())
	if max_side > 64:
		var scale: float = 64.0 / float(max_side)
		working.resize(
			maxi(1, int(float(working.get_width()) * scale)),
			maxi(1, int(float(working.get_height()) * scale)),
			Image.INTERPOLATE_BILINEAR
		)

	var accumulated := Color(0.0, 0.0, 0.0, 0.0)
	var weight_sum: float = 0.0

	for y in range(working.get_height()):
		for x in range(working.get_width()):
			var color: Color = working.get_pixel(x, y)
			if color.a < 0.25:
				continue
			var saturation: float = color.s
			var value: float = color.v
			if value < 0.18:
				continue
			var weight: float = 0.15 + saturation * 0.85
			accumulated.r += color.r * weight
			accumulated.g += color.g * weight
			accumulated.b += color.b * weight
			weight_sum += weight

	if weight_sum <= 0.001:
		return Color(0.05, 0.92, 1.0, 1.0)

	return Color(
		clampf(accumulated.r / weight_sum, 0.05, 1.0),
		clampf(accumulated.g / weight_sum, 0.05, 1.0),
		clampf(accumulated.b / weight_sum, 0.05, 1.0),
		1.0
	)
