extends Control

const TEXT_FIT: Script = preload("res://scripts/hit_music_r7/text_fit.gd")

signal celebration_finished

const DURATION: float = 3.65
const SAMPLE_RATE: int = 44100

var _song_title: String = "HIT MUSIC"
var _score: float = 0.0
var _previous_best: float = 0.0
var _primary: Color = Color(0.0, 0.85, 1.0)
var _accent: Color = Color(1.0, 0.86, 0.08)
var _top_rect: Rect2 = Rect2(12.0, 12.0, 696.0, 250.0)
var _circle_center: Vector2 = Vector2(360.0, 900.0)
var _circle_radius: float = 340.0
var _time: float = 0.0
var _built: bool = false
var _content: Control
var _record_label: Label
var _score_label: Label
var _sound: AudioStreamPlayer
var _title_font: Font
var _body_font: Font


func configure(
	song_title: String,
	score: float,
	previous_best: float,
	primary: Color,
	accent: Color,
	top_rect: Rect2,
	circle_center: Vector2,
	circle_radius: float
) -> void:
	_song_title = song_title
	_score = score
	_previous_best = previous_best
	_primary = primary
	_accent = accent
	_top_rect = top_rect
	_circle_center = circle_center
	_circle_radius = circle_radius
	if is_inside_tree():
		_build()


func _ready() -> void:
	z_index = 500
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_play_record_sound()
	set_process(true)


func _build() -> void:
	if _built:
		return
	_built = true
	_title_font = _load_font("res://fonts/Bungee-Regular.ttf")
	_body_font = _load_font("res://fonts/Oxanium-VariableFont_wght.ttf")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content = Control.new()
	_content.modulate.a = 0.0
	add_child(_content)

	var top_panel := Panel.new()
	top_panel.position = _top_rect.position
	top_panel.size = _top_rect.size
	top_panel.add_theme_stylebox_override("panel", _panel_style(22))
	_content.add_child(top_panel)

	var top_title := _label("NOVO RECORDE", int(_top_rect.size.y * 0.26), _accent, true)
	top_title.position = Vector2(_top_rect.size.x * 0.04, _top_rect.size.y * 0.06)
	top_title.size = Vector2(_top_rect.size.x * 0.92, _top_rect.size.y * 0.36)
	top_panel.add_child(top_title)

	var track := _label(_song_title, int(_top_rect.size.y * 0.115), Color.WHITE, false)
	track.position = Vector2(_top_rect.size.x * 0.05, _top_rect.size.y * 0.43)
	top_panel.add_child(track)
	# O nome vem do catalogo do operador e pode ser bem comprido: cabe
	# entre "NOVO RECORDE" e a comparacao de porcentagem, em duas linhas
	# se precisar, sem empurrar nenhuma das duas.
	TEXT_FIT.definir(
		track,
		_song_title,
		_top_rect.size.x * 0.90,
		_top_rect.size.y * 0.20,
		int(_top_rect.size.y * 0.115),
		int(_top_rect.size.y * 0.052),
		true
	)

	var comparison := _label(
		"ANTERIOR %.2f%%   →   NOVO %.2f%%" % [_previous_best, _score],
		int(_top_rect.size.y * 0.105),
		_primary.lerp(Color.WHITE, 0.44),
		false
	)
	comparison.position = Vector2(_top_rect.size.x * 0.04, _top_rect.size.y * 0.68)
	comparison.size = Vector2(_top_rect.size.x * 0.92, _top_rect.size.y * 0.18)
	top_panel.add_child(comparison)

	var circle_panel := Panel.new()
	var panel_size := Vector2.ONE * (_circle_radius * 1.34)
	circle_panel.position = _circle_center - panel_size * 0.5
	circle_panel.size = panel_size
	circle_panel.pivot_offset = panel_size * 0.5
	circle_panel.scale = Vector2(0.76, 0.76)
	circle_panel.add_theme_stylebox_override("panel", _panel_style(int(_circle_radius * 0.10)))
	_content.add_child(circle_panel)

	_record_label = _label("VOCÊ BATEU O RECORDE!", int(_circle_radius * 0.095), _accent, true)
	_record_label.position = Vector2(panel_size.x * 0.08, panel_size.y * 0.14)
	_record_label.size = Vector2(panel_size.x * 0.84, panel_size.y * 0.16)
	circle_panel.add_child(_record_label)

	_score_label = _label("%.2f%%" % _score, int(_circle_radius * 0.23), Color.WHITE, true)
	_score_label.position = Vector2(panel_size.x * 0.07, panel_size.y * 0.31)
	_score_label.size = Vector2(panel_size.x * 0.86, panel_size.y * 0.29)
	_score_label.pivot_offset = _score_label.size * 0.5
	circle_panel.add_child(_score_label)

	var message := _label("NOVO MELHOR DESEMPENHO", int(_circle_radius * 0.070), _primary.lerp(_accent, 0.44), false)
	message.position = Vector2(panel_size.x * 0.08, panel_size.y * 0.64)
	message.size = Vector2(panel_size.x * 0.84, panel_size.y * 0.13)
	circle_panel.add_child(message)

	var tween := create_tween()
	tween.set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_content, "modulate:a", 1.0, 0.34)
	tween.tween_property(circle_panel, "scale", Vector2.ONE, 0.58)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()
	if _record_label != null:
		var pulse := 0.86 + 0.14 * sin(_time * 6.0)
		_record_label.modulate = Color(1.0, pulse, 0.48 + pulse * 0.32, 1.0)
	if _score_label != null:
		_score_label.scale = Vector2.ONE * (1.0 + 0.018 * sin(_time * 5.0))
	if _time >= DURATION:
		set_process(false)
		var tween := create_tween()
		tween.tween_property(_content, "modulate:a", 0.0, 0.32).set_trans(Tween.TRANS_QUINT)
		tween.tween_callback(func() -> void: celebration_finished.emit())


func _draw() -> void:
	var pulse := 0.5 + 0.5 * sin(_time * 4.0)
	draw_rect(_top_rect, Color(0.003, 0.008, 0.025, 0.92), true)
	draw_circle(_circle_center, _circle_radius * 0.992, Color(0.002, 0.006, 0.020, 0.94), true)
	for ring in range(6):
		var radius := _circle_radius * (0.28 + float(ring) * 0.115) + pulse * 5.0
		var color := _primary.lerp(_accent, float(ring) / 5.0)
		draw_arc(_circle_center, radius, -_time * (0.24 + ring * 0.035), TAU, 96, Color(color.r, color.g, color.b, 0.25 - ring * 0.025), maxf(2.0, _circle_radius * 0.012), true)
	for spark in range(24):
		var angle := TAU * float(spark) / 24.0 + _time * (0.24 if spark % 2 == 0 else -0.18)
		var distance := _circle_radius * (0.72 + 0.08 * sin(_time * 3.2 + spark))
		var point := _circle_center + Vector2(cos(angle), sin(angle)) * distance
		var color := _accent if spark % 2 == 0 else _primary
		draw_circle(point, _circle_radius * (0.010 + pulse * 0.006), Color(color.r, color.g, color.b, 0.72), true)


func _play_record_sound() -> void:
	_sound = AudioStreamPlayer.new()
	_sound.bus = "Master"
	_sound.volume_db = -1.5
	_sound.stream = _make_record_chime()
	add_child(_sound)
	_sound.play()


func _make_record_chime() -> AudioStreamWAV:
	var duration := 1.75
	var sample_count := int(duration * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(sample_count * 4)
	var notes: Array[float] = [523.25, 659.25, 783.99, 1046.50]
	for index in range(sample_count):
		var time := float(index) / float(SAMPLE_RATE)
		var value := 0.0
		for note_index in range(notes.size()):
			var start := float(note_index) * 0.19
			var local_time := time - start
			if local_time < 0.0:
				continue
			var envelope := exp(-local_time * 3.1) * minf(1.0, local_time * 28.0)
			value += sin(TAU * notes[note_index] * local_time) * envelope * 0.20
			value += sin(TAU * notes[note_index] * 2.0 * local_time) * envelope * 0.055
		var shimmer := sin(TAU * 2093.0 * time) * exp(-time * 2.6) * 0.035
		var left := clampi(roundi((value + shimmer) * 24500.0), -32768, 32767)
		var right := clampi(roundi((value - shimmer * 0.35) * 24500.0), -32768, 32767)
		data.encode_s16(index * 4, left)
		data.encode_s16(index * 4 + 2, right)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = true
	stream.data = data
	return stream


func _label(text_value: String, font_size: int, color: Color, title: bool) -> Label:
	var label := Label.new()
	label.text = text_value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	var font := _title_font if title else _body_font
	if font != null:
		label.add_theme_font_override("font", font)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.96))
	label.add_theme_constant_override("outline_size", maxi(3, int(font_size * 0.11)))
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return label


func _load_font(path: String) -> Font:
	if ResourceLoader.exists(path):
		var resource := load(path)
		if resource is Font:
			return resource as Font
	return ThemeDB.fallback_font


func _panel_style(radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.006, 0.014, 0.040, 0.89)
	style.border_color = _primary.lerp(_accent, 0.42)
	style.set_border_width_all(4)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(_primary.r, _primary.g, _primary.b, 0.34)
	style.shadow_size = 20
	return style
