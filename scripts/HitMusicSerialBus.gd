extends Node
## HitMusicSerialBus.gd
## Adicione como Autoload em:
## Project > Project Settings > Globals/Autoload
## Nome recomendado: HitMusicSerial

const BASE_DIR := "user://hit_music_serial"
const SPOOL_DIR := BASE_DIR + "/spool"
const ALIVE_PATH := BASE_DIR + "/bridge_alive.txt"
const READY_PATH := BASE_DIR + "/bridge_ready.txt"

var _seq: int = 0
var _ultimo_multi: String = ""

func _ready() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SPOOL_DIR))

func bridge_pronta() -> bool:
    return FileAccess.file_exists(READY_PATH)

func enviar(comando: String) -> bool:
    var cmd := comando.strip_edges()
    if cmd.is_empty():
        return false

    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SPOOL_DIR))

    _seq = (_seq + 1) % 1000000
    var stamp := Time.get_ticks_usec()
    var nome := "%020d_%06d_%06d.cmd" % [stamp, OS.get_process_id(), _seq]
    var final_path := ProjectSettings.globalize_path(SPOOL_DIR.path_join(nome))
    var tmp_path := final_path + ".tmp"

    var f := FileAccess.open(tmp_path, FileAccess.WRITE)
    if f == null:
        push_error("HitMusicSerial: nao foi possivel criar " + tmp_path)
        return false

    f.store_string(cmd)
    f.flush()
    f.close()

    var err := DirAccess.rename_absolute(tmp_path, final_path)
    if err != OK:
        if FileAccess.file_exists(tmp_path):
            DirAccess.remove_absolute(tmp_path)
        push_error("HitMusicSerial: erro ao publicar comando: %s" % err)
        return false

    return true

func clear() -> bool:
    _ultimo_multi = ""
    return enviar("CLEAR")

func menu(
    cor_a: Color,
    cor_b: Color,
    idx_a: int = 0,
    idx_b: int = 1
) -> bool:
    return enviar(
        "MENU %d %d %d %d %d %d %d %d" % [
            roundi(cor_a.r * 255.0),
            roundi(cor_a.g * 255.0),
            roundi(cor_a.b * 255.0),
            roundi(cor_b.r * 255.0),
            roundi(cor_b.g * 255.0),
            roundi(cor_b.b * 255.0),
            idx_a,
            idx_b
        ]
    )

func led(idx: int, cor: Color) -> bool:
    return enviar(
        "LED %d %d %d %d" % [
            idx,
            roundi(cor.r * 255.0),
            roundi(cor.g * 255.0),
            roundi(cor.b * 255.0)
        ]
    )

func hit(idx: int, cor: Color, duracao_ms: int = 220) -> bool:
    return enviar(
        "HIT %d %d %d %d %d" % [
            idx,
            roundi(cor.r * 255.0),
            roundi(cor.g * 255.0),
            roundi(cor.b * 255.0),
            clampi(duracao_ms, 90, 1200)
        ]
    )

func ok(idx: int) -> bool:
    return enviar("OK %d" % idx)

func erro(idx: int) -> bool:
    return enviar("ERR %d" % idx)

func pulse(idx: int) -> bool:
    return enviar("PULSE %d" % idx)

func scene(cor: Color) -> bool:
    return enviar(
        "SCENE %d %d %d" % [
            roundi(cor.r * 255.0),
            roundi(cor.g * 255.0),
            roundi(cor.b * 255.0)
        ]
    )

func scene2(cor_a: Color, cor_b: Color) -> bool:
    return enviar(
        "SCENE2 %d %d %d %d %d %d" % [
            roundi(cor_a.r * 255.0),
            roundi(cor_a.g * 255.0),
            roundi(cor_a.b * 255.0),
            roundi(cor_b.r * 255.0),
            roundi(cor_b.g * 255.0),
            roundi(cor_b.b * 255.0)
        ]
    )

func multi(cores: Array[Color]) -> bool:
    var hex := ""
    for i in range(8):
        var c := Color(0, 0, 0)
        if i < cores.size():
            c = cores[i]
        var r := clampi(roundi(c.r * 255.0), 0, 255)
        var g := clampi(roundi(c.g * 255.0), 0, 255)
        var b := clampi(roundi(c.b * 255.0), 0, 255)
        hex += "%02X%02X%02X" % [r, g, b]

    # Não cria tráfego serial se o quadro não mudou.
    if hex == _ultimo_multi:
        return true

    _ultimo_multi = hex
    return enviar("MULTI " + hex)

func apagar_guias() -> bool:
    var apagadas: Array[Color] = []
    for _i in range(8):
        apagadas.append(Color(0, 0, 0))
    return multi(apagadas)

func ready_flash() -> bool:
    return enviar("READY")

func count(n: int) -> bool:
    return enviar("COUNT %d" % clampi(n, 0, 9))

func attract() -> bool:
    return enviar("ATTRACT")

func bright(valor: int) -> bool:
    return enviar("BRIGHT %d" % clampi(valor, 0, 255))
