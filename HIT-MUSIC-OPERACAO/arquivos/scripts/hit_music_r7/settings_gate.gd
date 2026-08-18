extends RefCounted
## Ponto unico de acesso a tela de Configuracoes. Nunca durante uma
## partida em andamento, pra nao interromper musica/LEDs no meio do jogo.
##
## O F9 do teclado NAO e mais chamado tela a tela: quem escuta e o autoload
## ArcadeShell, uma vez so, e por isso o atalho vale em todo o jogo —
## inclusive em telas que ainda nem existem. Antes cada tela precisava
## lembrar de chamar try_open_from_keyboard(), e a maioria nao chamava.
##
## O botao fisico SELECT continua sendo tratado por tela, com
## try_open_from_action() no _process().

const CONFIG_SCENE_PATH: String = "res://scenes/config.tscn"
const RETURN_META_KEY: String = "hit_music_settings_return"
const DEFAULT_RETURN_PATH: String = "res://scenes/opening.tscn"


static func try_open_from_keyboard(event: InputEvent) -> bool:
	if not (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and event.keycode == KEY_F9
	):
		return false

	return open_settings()


static func try_open_from_action() -> bool:
	if not InputMap.has_action("input_select"):
		return false
	if not Input.is_action_just_pressed("input_select"):
		return false
	return open_settings()


static func open_settings() -> bool:
	var main_loop: Variant = Engine.get_main_loop()
	if not main_loop is SceneTree:
		return false

	var tree: SceneTree = main_loop as SceneTree
	var return_path: String = DEFAULT_RETURN_PATH
	if tree.current_scene != null and not tree.current_scene.scene_file_path.is_empty():
		return_path = tree.current_scene.scene_file_path

	tree.set_meta(RETURN_META_KEY, return_path)
	tree.change_scene_to_file(CONFIG_SCENE_PATH)
	return true


static func return_path() -> String:
	var main_loop: Variant = Engine.get_main_loop()
	if not main_loop is SceneTree:
		return DEFAULT_RETURN_PATH
	var tree: SceneTree = main_loop as SceneTree
	if not tree.has_meta(RETURN_META_KEY):
		return DEFAULT_RETURN_PATH
	var value: Variant = tree.get_meta(RETURN_META_KEY)
	if value is String and not (value as String).is_empty():
		return value as String
	return DEFAULT_RETURN_PATH
