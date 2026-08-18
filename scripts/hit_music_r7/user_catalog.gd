extends RefCounted
## Catálogo persistente de músicas extras do HIT MUSIC.
##
## REGRAS:
## - músicas de fábrica vêm de res://data/hit_music_songs.json;
## - músicas compradas são copiadas para user:// no disco do cliente;
## - o catálogo impede repetição contra fábrica + músicas já instaladas;
## - nomes são normalizados (acentos, espaços, pontuação e plurais simples);
## - o MP3 recebe SHA-256 para reconhecer conteúdo já instalado;
## - o catálogo possui backup e escrita temporária para reduzir risco de corrupção.
##
## PENDRIVE:
##   PENDRIVE/
##     MUSICA_01/
##       musica.mp3
##       musica.ogv
##       capa.png
##       dados.txt
##     MUSICA_02/
##       ...
##
## dados.txt mínimo:
##   name="NOME DA MUSICA"
##
## opcionais:
##   category="ANIMES"   # será corrigido para ANIME
##   bpm=128
##   id="codigo_unico"

const FACTORY_CATALOG_PATH: String = "res://data/hit_music_songs.json"

const USER_SONGS_PATH: String = "user://hit_music_user_songs.json"
const USER_SONGS_BACKUP_PATH: String = "user://hit_music_user_songs.json.bak"
const USER_SONGS_TEMP_PATH: String = "user://hit_music_user_songs.json.tmp"

const AUDIO_DIR: String = "user://songs"
const VIDEO_DIR: String = "user://medias"
const COVER_DIR: String = "user://covers"
const USER_SCENE: String = "res://scenes/user_song.tscn"

const COPY_CHUNK_SIZE: int = 1024 * 1024
const HASH_CHUNK_SIZE: int = 1024 * 1024

const AUDIO_EXTENSIONS: Array[String] = ["mp3", "ogg", "wav"]
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


## ---------------------------------------------------------------
## CATÁLOGOS
## ---------------------------------------------------------------

static func all_user_songs() -> Array:
	_ensure_legacy_data_migrated()
	return _read_user_catalog()


static func factory_songs() -> Array:
	var file := FileAccess.open(FACTORY_CATALOG_PATH, FileAccess.READ)
	if file == null:
		return []

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()

	if not parsed is Dictionary:
		return []

	var raw: Variant = (parsed as Dictionary).get("songs", [])
	if not raw is Array:
		return []

	var result: Array = []
	for value in (raw as Array):
		if value is Dictionary:
			result.append((value as Dictionary).duplicate(true))
	return result


static func _read_user_catalog() -> Array:
	if _catalog_file_is_valid(USER_SONGS_PATH):
		return _read_catalog_file(USER_SONGS_PATH)

	# Só usa backup se o principal não existir ou estiver realmente inválido.
	if _catalog_file_is_valid(USER_SONGS_BACKUP_PATH):
		return _read_catalog_file(USER_SONGS_BACKUP_PATH)

	return []


static func _catalog_file_is_valid(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()

	if not parsed is Dictionary:
		return false

	return (parsed as Dictionary).get("songs", null) is Array


static func _read_catalog_file(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()

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
	# Mantém um backup do último catálogo bom.
	if _catalog_file_is_valid(USER_SONGS_PATH):
		_copy_file_stream(USER_SONGS_PATH, USER_SONGS_BACKUP_PATH)

	var payload: String = JSON.stringify(
		{
			"schema": 3,
			"updated_at_unix": Time.get_unix_time_from_system(),
			"songs": songs,
		},
		"\t"
	)

	var temp := FileAccess.open(USER_SONGS_TEMP_PATH, FileAccess.WRITE)
	if temp == null:
		push_error("Nao foi possivel gravar catalogo temporario.")
		return false

	temp.store_string(payload)
	temp.flush()
	temp.close()

	# Troca o arquivo somente depois que a escrita temporária terminou.
	if FileAccess.file_exists(USER_SONGS_PATH):
		DirAccess.remove_absolute(USER_SONGS_PATH)

	var rename_error: Error = DirAccess.rename_absolute(
		USER_SONGS_TEMP_PATH,
		USER_SONGS_PATH
	)
	if rename_error != OK:
		push_error("Nao foi possivel finalizar o catalogo de musicas.")
		if FileAccess.file_exists(USER_SONGS_BACKUP_PATH):
			_copy_file_stream(USER_SONGS_BACKUP_PATH, USER_SONGS_PATH)
		return false

	return true


## Atualiza instalações antigas com campos novos sem apagar nada.
static func repair_user_catalog() -> void:
	var songs: Array = all_user_songs()
	if songs.is_empty():
		return

	var changed: bool = false

	for index in range(songs.size()):
		if not songs[index] is Dictionary:
			continue

		var song: Dictionary = songs[index] as Dictionary
		var title: String = str(song.get("title", "")).strip_edges()
		var category_before: String = str(song.get("category", "OUTROS"))
		var category_after: String = normalize_category(category_before)

		if category_before != category_after:
			song["category"] = category_after
			changed = true

		var normalized: String = normalize_title(title)
		if str(song.get("normalized_title", "")) != normalized:
			song["normalized_title"] = normalized
			changed = true

		var audio_path: String = str(song.get("audio", ""))
		if str(song.get("source_hash", "")).is_empty() and FileAccess.file_exists(audio_path):
			var digest: String = file_sha256(audio_path)
			if not digest.is_empty():
				song["source_hash"] = digest
				changed = true

		songs[index] = song

	if changed:
		save_user_songs(songs)


## ---------------------------------------------------------------
## IDENTIFICAÇÃO / DUPLICATAS
## ---------------------------------------------------------------

## Retorna {} quando é nova.
## Caso encontre, retorna id/title/source/reason/score.
static func installed_match(
	title: String,
	audio_hash: String = "",
	package_id: String = ""
) -> Dictionary:
	return _find_installed_match(
		title,
		audio_hash,
		package_id,
		_build_installed_index()
	)


static func _build_installed_index() -> Array:
	var index: Array = []

	for value in factory_songs():
		if not value is Dictionary:
			continue
		var song: Dictionary = value as Dictionary
		index.append({
			"id": str(song.get("id", "")),
			"title": str(song.get("title", "")),
			"normalized_title": normalize_title(str(song.get("title", ""))),
			"compact_title": _compact_title(str(song.get("title", ""))),
			"source_hash": file_sha256(str(song.get("audio", ""))),
			"source": "FABRICA",
		})

	for value in all_user_songs():
		if not value is Dictionary:
			continue
		var song: Dictionary = value as Dictionary
		index.append({
			"id": str(song.get("package_id", song.get("id", ""))),
			"title": str(song.get("title", "")),
			"normalized_title": str(
				song.get(
					"normalized_title",
					normalize_title(str(song.get("title", "")))
				)
			),
			"compact_title": _compact_title(str(song.get("title", ""))),
			"source_hash": str(song.get("source_hash", "")),
			"source": "INSTALADA",
		})

	return index


static func _find_installed_match(
	title: String,
	audio_hash: String,
	package_id: String,
	index: Array
) -> Dictionary:
	var clean_id: String = _normalize_identifier(package_id)
	var normalized: String = normalize_title(title)
	var compact: String = _compact_title(title)

	for value in index:
		if not value is Dictionary:
			continue

		var item: Dictionary = value as Dictionary
		var existing_id: String = _normalize_identifier(str(item.get("id", "")))
		var existing_hash: String = str(item.get("source_hash", ""))

		# ID é a verificação mais forte quando o pacote vendido possuir id=.
		if not clean_id.is_empty() and not existing_id.is_empty() and clean_id == existing_id:
			return _match_result(item, "MESMO ID", 1.0)

		# SHA-256 reconhece o mesmo MP3 mesmo com nome de pasta/TXT alterado.
		if (
			not audio_hash.is_empty()
			and not existing_hash.is_empty()
			and audio_hash == existing_hash
		):
			return _match_result(item, "MESMO AUDIO", 1.0)

		var existing_normalized: String = str(item.get("normalized_title", ""))
		var existing_compact: String = str(item.get("compact_title", ""))

		if not normalized.is_empty() and normalized == existing_normalized:
			return _match_result(item, "MESMO NOME NORMALIZADO", 1.0)

		if not compact.is_empty() and compact == existing_compact:
			return _match_result(item, "MESMO NOME SEM ESPACOS", 1.0)

		var similarity: float = _title_similarity(normalized, existing_normalized)
		if _similar_enough(normalized, existing_normalized, similarity):
			return _match_result(item, "NOME MUITO PARECIDO", similarity)

	return {}


static func _match_result(item: Dictionary, reason: String, score: float) -> Dictionary:
	return {
		"id": str(item.get("id", "")),
		"title": str(item.get("title", "")),
		"source": str(item.get("source", "")),
		"reason": reason,
		"score": score,
	}


## Normalização usada para nome de música.
## Ex.: "DRAGON-BALL", "Dragon Ball " e "dragon_ball" ficam equivalentes.
## Plurais simples também são aproximados: ANIMES -> ANIME, DEMONS -> DEMON.
static func normalize_title(text: String) -> String:
	var basic: String = _ascii_fold(text)
	var tokens: Array[String] = []

	for raw_token in basic.split(" ", false):
		var token: String = _singularize_token(str(raw_token))
		if not token.is_empty():
			tokens.append(token)

	return " ".join(tokens)


static func _compact_title(text: String) -> String:
	return normalize_title(text).replace(" ", "")


static func _singularize_token(token: String) -> String:
	var value: String = token.strip_edges()
	if value.length() <= 3:
		return value

	# Plurais ingleses comuns que aparecem em nomes/licenças.
	if value.length() > 4 and value.ends_with("ies"):
		return value.substr(0, value.length() - 3) + "y"

	if (
		value.length() > 5
		and (
			value.ends_with("ches")
			or value.ends_with("shes")
			or value.ends_with("sses")
			or value.ends_with("xes")
			or value.ends_with("zes")
		)
	):
		return value.substr(0, value.length() - 2)

	# Regra propositalmente conservadora: remove apenas S final.
	# Isso resolve ANIMES/ANIME, DEMONS/DEMON, GIRLS/GIRL etc.
	if value.length() > 4 and value.ends_with("s"):
		return value.substr(0, value.length() - 1)

	return value


static func _ascii_fold(text: String) -> String:
	var value: String = text.to_lower()

	var replacements: Array = [
		["á", "a"], ["à", "a"], ["â", "a"], ["ã", "a"], ["ä", "a"],
		["é", "e"], ["è", "e"], ["ê", "e"], ["ë", "e"],
		["í", "i"], ["ì", "i"], ["î", "i"], ["ï", "i"],
		["ó", "o"], ["ò", "o"], ["ô", "o"], ["õ", "o"], ["ö", "o"],
		["ú", "u"], ["ù", "u"], ["û", "u"], ["ü", "u"],
		["ç", "c"], ["ñ", "n"],
	]

	for pair in replacements:
		value = value.replace(str(pair[0]), str(pair[1]))

	var output: String = ""
	var last_was_space: bool = true

	for index in range(value.length()):
		var character: String = value.substr(index, 1)
		var code: int = character.unicode_at(0)
		var keep: bool = (
			(code >= 97 and code <= 122)
			or (code >= 48 and code <= 57)
		)

		if keep:
			output += character
			last_was_space = false
		elif not last_was_space:
			output += " "
			last_was_space = true

	return output.strip_edges()


static func _title_similarity(a: String, b: String) -> float:
	if a.is_empty() or b.is_empty():
		return 0.0
	if a == b:
		return 1.0

	var compact_a: String = a.replace(" ", "")
	var compact_b: String = b.replace(" ", "")
	var maximum: int = maxi(compact_a.length(), compact_b.length())
	if maximum <= 0:
		return 0.0

	var distance: int = _levenshtein(compact_a, compact_b)
	return 1.0 - (float(distance) / float(maximum))


static func _similar_enough(a: String, b: String, score: float) -> bool:
	var compact_a: String = a.replace(" ", "")
	var compact_b: String = b.replace(" ", "")
	var minimum: int = mini(compact_a.length(), compact_b.length())
	var maximum: int = maxi(compact_a.length(), compact_b.length())

	if minimum < 5:
		return false

	var distance: int = _levenshtein(compact_a, compact_b)

	# Nomes médios: no máximo uma letra diferente.
	if minimum >= 5 and maximum <= 9 and distance <= 1:
		return true

	# Nomes maiores: permite pequenas diferenças de digitação.
	if minimum >= 8 and score >= 0.92:
		return true

	return false


static func _levenshtein(a: String, b: String) -> int:
	var previous: Array[int] = []
	previous.resize(b.length() + 1)

	for j in range(b.length() + 1):
		previous[j] = j

	for i in range(1, a.length() + 1):
		var current: Array[int] = []
		current.resize(b.length() + 1)
		current[0] = i

		for j in range(1, b.length() + 1):
			var cost: int = 0 if a.substr(i - 1, 1) == b.substr(j - 1, 1) else 1
			current[j] = mini(
				mini(
					current[j - 1] + 1,
					previous[j] + 1
				),
				previous[j - 1] + cost
			)

		previous = current

	return previous[b.length()]


static func _normalize_identifier(value: String) -> String:
	return _ascii_fold(value).replace(" ", "_")


## ---------------------------------------------------------------
## CATEGORIA
## ---------------------------------------------------------------

static func normalize_category(category: String) -> String:
	var compact: String = _ascii_fold(category).replace(" ", "")

	match compact:
		"anime", "animes":
			return "ANIME"
		"infantil", "infantis":
			return "INFANTIL"
		"rock", "rocks":
			return "ROCK"
		"pop", "pops":
			return "POP"
		"eletronica", "eletronicas", "eletronico", "eletronicos", "electronic", "electronics":
			return "ELETRONICA"
		"funk", "funks":
			return "FUNK"
		"hiphop", "hiphops":
			return "HIP HOP"
		"sertanejo", "sertanejos", "sertaneja", "sertanejas":
			return "SERTANEJO"
		"gospel", "gospels":
			return "GOSPEL"
		"classica", "classicas", "classico", "classicos", "classical":
			return "CLASSICA"
		"outro", "outros", "other", "others":
			return "OUTROS"
		_:
			return "OUTROS"


## ---------------------------------------------------------------
## INSTALAÇÃO
## ---------------------------------------------------------------

static func add_song(
	title: String,
	audio_source: String,
	video_source: String,
	cover_source: String,
	category: String,
	detected_bpm: float,
	package_id: String = "",
	source_hash_override: String = ""
) -> Dictionary:
	var clean_title: String = title.strip_edges()
	if clean_title.is_empty():
		return {"ok": false, "erro": "Informe o nome da música.", "id": ""}

	if audio_source.strip_edges().is_empty() or not FileAccess.file_exists(audio_source):
		return {"ok": false, "erro": "Áudio MP3 não encontrado.", "id": ""}

	if not _extension_allowed(audio_source, AUDIO_EXTENSIONS):
		return {"ok": false, "erro": "Áudio precisa ser MP3, OGG ou WAV.", "id": ""}

	if detected_bpm < 40.0 or detected_bpm > 260.0:
		return {"ok": false, "erro": "BPM inválido ou ainda não detectado.", "id": ""}

	var source_hash: String = source_hash_override
	if source_hash.is_empty():
		source_hash = file_sha256(audio_source)

	var duplicate: Dictionary = installed_match(
		clean_title,
		source_hash,
		package_id
	)
	if not duplicate.is_empty():
		return {
			"ok": false,
			"already_installed": true,
			"erro": "Já instalada: %s (%s)" % [
				str(duplicate.get("title", clean_title)),
				str(duplicate.get("source", "")),
			],
			"id": str(duplicate.get("id", "")),
		}

	var songs: Array = all_user_songs()
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

	var clean_category: String = normalize_category(category)
	var song: Dictionary = {
		"id": song_id,
		"package_id": _normalize_identifier(package_id),
		"title": clean_title.to_upper(),
		"normalized_title": normalize_title(clean_title),
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
		"source_hash": source_hash,
		"installed_at_unix": Time.get_unix_time_from_system(),
	}

	songs.append(song)
	if not save_user_songs(songs):
		_delete_media(song)
		return {"ok": false, "erro": "Não foi possível gravar o catálogo.", "id": ""}

	return {
		"ok": true,
		"erro": "",
		"id": song_id,
		"category": clean_category,
	}


## ---------------------------------------------------------------
## PENDRIVE
## ---------------------------------------------------------------

static func scan_usb_packages() -> Array:
	repair_user_catalog()

	var packages: Array = []
	var seen_folders: Dictionary = {}
	var system_drive: String = _system_drive_name()
	var installed_index: Array = _build_installed_index()

	for drive_index in range(DirAccess.get_drive_count()):
		var drive_name: String = DirAccess.get_drive_name(drive_index).strip_edges()
		if drive_name.is_empty():
			continue

		if OS.get_name() == "Windows" and drive_name.to_upper() == system_drive.to_upper():
			continue

		var root: String = _drive_root(drive_name)
		if root.is_empty() or not DirAccess.dir_exists_absolute(root):
			continue

		# Formato principal: várias pastas de música diretamente na raiz.
		_scan_direct_children(
			root,
			packages,
			seen_folders,
			drive_name,
			installed_index
		)

		# Também aceita um agrupador opcional, ex.: PENDRIVE/HIT_MUSIC/MUSICA_01.
		for container_name in USB_CONTAINER_NAMES:
			var container: String = root.path_join(container_name)
			if DirAccess.dir_exists_absolute(container):
				_scan_direct_children(
					container,
					packages,
					seen_folders,
					drive_name,
					installed_index
				)

	packages.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("name", "")).nocasecmp_to(str(b.get("name", ""))) < 0
	)

	return packages


static func _scan_direct_children(
	root: String,
	packages: Array,
	seen_folders: Dictionary,
	drive_name: String,
	installed_index: Array
) -> void:
	for dir_name_value in DirAccess.get_directories_at(root):
		var dir_name: String = str(dir_name_value)
		if dir_name.begins_with("."):
			continue

		var folder: String = root.path_join(dir_name)
		_append_package_if_present(
			folder,
			packages,
			seen_folders,
			drive_name,
			installed_index
		)


static func _append_package_if_present(
	folder: String,
	packages: Array,
	seen_folders: Dictionary,
	drive_name: String,
	installed_index: Array
) -> void:
	var normalized_folder: String = folder.replace("\\", "/")
	if seen_folders.has(normalized_folder):
		return
	seen_folders[normalized_folder] = true

	var package: Dictionary = inspect_usb_package(folder, installed_index)

	# Qualquer pasta que não seja um pacote completo é ignorada.
	if package.is_empty() or not bool(package.get("valid", false)):
		return

	package["drive"] = drive_name
	packages.append(package)


static func inspect_usb_package(
	folder: String,
	installed_index: Array = []
) -> Dictionary:
	if not DirAccess.dir_exists_absolute(folder):
		return {}

	var files: PackedStringArray = DirAccess.get_files_at(folder)
	var mp3_files: Array[String] = []
	var ogv_files: Array[String] = []
	var cover_files: Array[String] = []
	var txt_files: Array[String] = []
	var extra_files: Array[String] = []

	for file_name_value in files:
		var file_name: String = str(file_name_value)
		var lower_name: String = file_name.to_lower()

		# Arquivos criados automaticamente pelo Windows não contam.
		if (
			file_name.begins_with(".")
			or lower_name == "thumbs.db"
			or lower_name == "desktop.ini"
		):
			continue

		match file_name.get_extension().to_lower():
			"mp3":
				mp3_files.append(folder.path_join(file_name))
			"ogv":
				ogv_files.append(folder.path_join(file_name))
			"png", "jpg", "jpeg", "webp":
				cover_files.append(folder.path_join(file_name))
			"txt":
				txt_files.append(folder.path_join(file_name))
			_:
				extra_files.append(file_name)

	# Não é pacote HIT MUSIC: ignora.
	if mp3_files.is_empty() and ogv_files.is_empty() and cover_files.is_empty() and txt_files.is_empty():
		return {}

	var errors: Array[String] = []
	if mp3_files.size() != 1:
		errors.append("1 MP3")
	if ogv_files.size() != 1:
		errors.append("1 OGV")
	if cover_files.size() != 1:
		errors.append("1 CAPA")
	if txt_files.size() != 1:
		errors.append("1 TXT")
	if not extra_files.is_empty():
		errors.append("ARQUIVO EXTRA")

	# Pasta incompleta/incorreta será ignorada pelo scanner.
	if not errors.is_empty():
		return {
			"folder": folder.replace("\\", "/"),
			"valid": false,
			"error": " • ".join(errors),
		}

	var metadata: Dictionary = _read_metadata_txt(txt_files[0])
	var package_name: String = str(metadata.get("name", "")).strip_edges()
	if package_name.is_empty():
		return {
			"folder": folder.replace("\\", "/"),
			"valid": false,
			"error": 'TXT SEM name="..."',
		}

	var audio_path: String = mp3_files[0]
	var source_hash: String = file_sha256(audio_path)

	var bpm_value: float = embedded_bpm(audio_path)
	if bpm_value <= 0.0:
		bpm_value = stream_bpm(audio_path)
	if bpm_value <= 0.0:
		bpm_value = float(metadata.get("bpm", 0.0))

	var category_raw: String = str(metadata.get("category", "OUTROS"))
	var category_clean: String = normalize_category(category_raw)
	var package_id: String = str(metadata.get("id", ""))

	var index_to_use: Array = installed_index
	if index_to_use.is_empty():
		index_to_use = _build_installed_index()

	var duplicate: Dictionary = _find_installed_match(
		package_name,
		source_hash,
		package_id,
		index_to_use
	)

	return {
		"folder": folder.replace("\\", "/"),
		"name": package_name,
		"normalized_name": normalize_title(package_name),
		"audio": audio_path,
		"video": ogv_files[0],
		"cover": cover_files[0],
		"txt": txt_files[0],
		"category": category_clean,
		"category_original": category_raw,
		"bpm": bpm_value,
		"package_id": package_id,
		"source_hash": source_hash,
		"valid": true,
		"installed": not duplicate.is_empty(),
		"installed_match": duplicate,
		"error": "",
		"metadata": metadata,
	}


static func import_usb_package(
	package: Dictionary,
	bpm_override: float = 0.0
) -> Dictionary:
	if package.is_empty() or not bool(package.get("valid", false)):
		return {"ok": false, "erro": "Pacote inválido.", "id": ""}

	if bool(package.get("installed", false)):
		var existing: Dictionary = package.get("installed_match", {}) as Dictionary
		return {
			"ok": false,
			"already_installed": true,
			"erro": "Já instalada: " + str(existing.get("title", package.get("name", ""))),
			"id": str(existing.get("id", "")),
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
		bpm_value,
		str(package.get("package_id", "")),
		str(package.get("source_hash", ""))
	)


## ---------------------------------------------------------------
## TXT
## ---------------------------------------------------------------

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
		var value: String = _strip_matching_quotes(
			line.substr(equal_index + 1).strip_edges()
		)

		match key:
			"name":
				result["name"] = value
			"category", "categoria":
				result["category"] = value
			"id", "package_id":
				result["id"] = value
			"bpm":
				var parsed_bpm: float = float(value)
				if parsed_bpm >= 40.0 and parsed_bpm <= 260.0:
					result["bpm"] = parsed_bpm

	return result


static func _strip_matching_quotes(value: String) -> String:
	var cleaned: String = value.strip_edges()
	if cleaned.length() >= 2:
		var first: String = cleaned.substr(0, 1)
		var last: String = cleaned.substr(cleaned.length() - 1, 1)
		if (first == '"' and last == '"') or (first == "'" and last == "'"):
			return cleaned.substr(1, cleaned.length() - 2).strip_edges()
	return cleaned


## ---------------------------------------------------------------
## BPM
## ---------------------------------------------------------------

static func embedded_bpm(audio_path: String) -> float:
	if audio_path.get_extension().to_lower() != "mp3":
		return 0.0

	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(audio_path)
	if bytes.size() < 20:
		return 0.0
	if bytes[0] != 73 or bytes[1] != 68 or bytes[2] != 51:
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
			var text_start: int = cursor + 11
			var text_length: int = maxi(0, frame_size - 1)
			var bpm_text: String = _ascii(
				bytes,
				text_start,
				text_length
			).strip_edges()

			var parsed_bpm: float = float(bpm_text)
			if parsed_bpm >= 40.0 and parsed_bpm <= 260.0:
				return parsed_bpm

		cursor += 10 + frame_size

	return 0.0


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


## ---------------------------------------------------------------
## SHA-256 / CÓPIA PERSISTENTE
## ---------------------------------------------------------------

static func file_sha256(path: String) -> String:
	if path.is_empty() or not FileAccess.file_exists(path):
		return ""

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""

	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		file.close()
		return ""

	while file.get_position() < file.get_length():
		var remaining: int = int(file.get_length() - file.get_position())
		var chunk: PackedByteArray = file.get_buffer(
			mini(remaining, HASH_CHUNK_SIZE)
		)
		if chunk.is_empty():
			break
		if context.update(chunk) != OK:
			file.close()
			return ""

	file.close()
	return context.finish().hex_encode()


static func _copy_media(
	source: String,
	directory: String,
	song_id: String
) -> String:
	if not DirAccess.dir_exists_absolute(directory):
		var make_error: Error = DirAccess.make_dir_recursive_absolute(directory)
		if make_error != OK and not DirAccess.dir_exists_absolute(directory):
			return ""

	var target: String = "%s/%s.%s" % [
		directory,
		song_id,
		source.get_extension().to_lower(),
	]
	var temp_target: String = target + ".tmp"

	if FileAccess.file_exists(temp_target):
		DirAccess.remove_absolute(temp_target)

	if not _copy_file_stream(source, temp_target):
		return ""

	if FileAccess.file_exists(target):
		DirAccess.remove_absolute(target)

	if DirAccess.rename_absolute(temp_target, target) != OK:
		_delete_if_exists(temp_target)
		return ""

	return target


static func _copy_file_stream(source: String, target: String) -> bool:
	if not FileAccess.file_exists(source):
		return false

	var input := FileAccess.open(source, FileAccess.READ)
	if input == null:
		return false

	var output := FileAccess.open(target, FileAccess.WRITE)
	if output == null:
		input.close()
		return false

	while input.get_position() < input.get_length():
		var remaining: int = int(input.get_length() - input.get_position())
		var chunk: PackedByteArray = input.get_buffer(
			mini(remaining, COPY_CHUNK_SIZE)
		)
		if chunk.is_empty():
			break
		output.store_buffer(chunk)

	output.flush()
	output.close()
	input.close()

	return FileAccess.file_exists(target)


## ---------------------------------------------------------------
## MIGRAÇÃO DO user:// ANTIGO
## ---------------------------------------------------------------

## O projeto antes se chamou beta12. Com o diretório customizado novo,
## copiamos automaticamente dados antigos se o cliente já tiver jogado
## uma versão anterior.
static func _ensure_legacy_data_migrated() -> void:
	if FileAccess.file_exists(USER_SONGS_PATH):
		return

	if OS.get_name() != "Windows":
		return

	var appdata: String = OS.get_environment("APPDATA")
	if appdata.is_empty():
		return

	var current_dir: String = OS.get_user_data_dir().replace("\\", "/")
	var candidates: Array[String] = [
		appdata.path_join("Godot/app_userdata/Hit Music"),
		appdata.path_join("Godot/app_userdata/beta12"),
		appdata.path_join("Godot/app_userdata/beta-12"),
	]

	for candidate in candidates:
		var normalized_candidate: String = candidate.replace("\\", "/")
		if normalized_candidate.to_lower() == current_dir.to_lower():
			continue
		if not DirAccess.dir_exists_absolute(candidate):
			continue
		if not _legacy_folder_has_data(candidate):
			continue

		_copy_tree(candidate, current_dir)

		if FileAccess.file_exists(USER_SONGS_PATH):
			return


static func _legacy_folder_has_data(folder: String) -> bool:
	var known_files: Array[String] = [
		"hit_music_user_songs.json",
		"hit_music_arcade_settings.json",
		"hit_music_arcade_counters.json",
	]

	for file_name in known_files:
		if FileAccess.file_exists(folder.path_join(file_name)):
			return true

	return DirAccess.dir_exists_absolute(folder.path_join("songs"))


static func _copy_tree(source_dir: String, target_dir: String) -> void:
	if not DirAccess.dir_exists_absolute(target_dir):
		DirAccess.make_dir_recursive_absolute(target_dir)

	for file_name_value in DirAccess.get_files_at(source_dir):
		var file_name: String = str(file_name_value)
		var source_file: String = source_dir.path_join(file_name)
		var target_file: String = target_dir.path_join(file_name)

		# Não sobrescreve dados mais novos que já existam no destino.
		if not FileAccess.file_exists(target_file):
			_copy_file_stream(source_file, target_file)

	for dir_name_value in DirAccess.get_directories_at(source_dir):
		var dir_name: String = str(dir_name_value)
		if dir_name == "." or dir_name == "..":
			continue

		_copy_tree(
			source_dir.path_join(dir_name),
			target_dir.path_join(dir_name)
		)


## ---------------------------------------------------------------
## CARREGAMENTO / REMOÇÃO
## ---------------------------------------------------------------

static func remove_song(song_id: String) -> bool:
	var songs: Array = all_user_songs()
	var kept: Array = []
	var removed: bool = false

	for value in songs:
		if (
			value is Dictionary
			and str((value as Dictionary).get("id", "")) == song_id
		):
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


## ---------------------------------------------------------------
## UTILITÁRIOS
## ---------------------------------------------------------------

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

	if OS.get_name() == "Windows" and not cleaned.ends_with("/"):
		return cleaned + "/"

	return cleaned


static func _extension_allowed(
	path: String,
	allowed: Array[String]
) -> bool:
	return path.get_extension().to_lower() in allowed


static func _delete_if_exists(path: String) -> void:
	if (
		not path.is_empty()
		and path.begins_with("user://")
		and FileAccess.file_exists(path)
	):
		DirAccess.remove_absolute(path)


static func _delete_media(song: Dictionary) -> void:
	for key in ["audio", "video", "cover"]:
		_delete_if_exists(str(song.get(key, "")))


static func _unique_id(title: String, songs: Array) -> String:
	var base: String = normalize_title(title).replace(" ", "_")
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


static func _ascii(
	bytes: PackedByteArray,
	start: int,
	length: int
) -> String:
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


static func _colors_for(
	cover_path: String,
	song_id: String
) -> Dictionary:
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
	var max_side: int = maxi(
		working.get_width(),
		working.get_height()
	)

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
			if color.a < 0.25 or color.v < 0.18:
				continue

			var weight: float = 0.15 + color.s * 0.85
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
