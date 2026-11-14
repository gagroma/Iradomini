extends CanvasLayer
# HUD - the few words on screen. The GDD wants almost no interface (the chalk
# supply is shown by the chalk stick in your hand), so this is only: a dot in
# the middle, a one-line prompt, short notes, and a debug panel (F3) for testers.
# Source: Godot Label nodes inside a CanvasLayer (2D drawn on top of 3D).
# The screen is 480x270 pixels, so positions below are in those pixels.

var dot: ColorRect
var prompt: Label
var status: Label
var note: Label
var help: Label
var title: Label
var subtitle: Label
var debug: Label

var _note_time := 0.0
var _help_time := 16.0


func setup() -> void:
	layer = 2
	dot = ColorRect.new()
	dot.size = Vector2(2, 2)
	dot.position = Vector2(239, 134)
	dot.color = Color(1.0, 1.0, 1.0, 0.55)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dot)

	prompt = _label(Vector2(0, 150), Vector2(480, 14), 10, HORIZONTAL_ALIGNMENT_CENTER)
	status = _label(Vector2(6, 4), Vector2(300, 14), 10, HORIZONTAL_ALIGNMENT_LEFT)
	note = _label(Vector2(0, 60), Vector2(480, 14), 10, HORIZONTAL_ALIGNMENT_CENTER)
	help = _label(Vector2(20, 206), Vector2(440, 60), 9, HORIZONTAL_ALIGNMENT_CENTER)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.text = "WASD - идти  ·  Shift - бег  ·  Ctrl - присесть у укрытия\nЛКМ (держать) - чертить мелом по полу  ·  ПКМ (держать) - стереть круг\nE - взять  ·  Замкни круг: демон не пересечёт черту"
	title = _label(Vector2(0, 92), Vector2(480, 30), 24, HORIZONTAL_ALIGNMENT_CENTER)
	subtitle = _label(Vector2(0, 126), Vector2(480, 14), 10, HORIZONTAL_ALIGNMENT_CENTER)
	debug = _label(Vector2(300, 4), Vector2(176, 120), 8, HORIZONTAL_ALIGNMENT_RIGHT)
	debug.visible = false


func _label(pos: Vector2, box: Vector2, font_size: int, align: int) -> Label:
	var l = Label.new()
	l.position = pos
	l.size = box
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color(0.93, 0.88, 0.74))
	l.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	l.add_theme_constant_override("outline_size", 3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func set_prompt(text: String) -> void:
	prompt.text = text


func set_status(text: String) -> void:
	status.text = text


# A short message that fades away by itself.
func show_note(text: String, seconds: float = 4.0) -> void:
	note.text = text
	_note_time = seconds


func show_title(big: String, small: String) -> void:
	title.text = big
	subtitle.text = small


func set_dot(active: bool) -> void:
	dot.color = Color(1.0, 1.0, 1.0, 0.8) if active else Color(1.0, 1.0, 1.0, 0.25)


func set_debug(on: bool, text: String) -> void:
	debug.visible = on
	if on:
		debug.text = text


func _process(dt: float) -> void:
	if _note_time > 0.0:
		_note_time -= dt
		note.modulate.a = clampf(_note_time, 0.0, 1.0)
	else:
		note.modulate.a = 0.0
	if _help_time > 0.0:
		_help_time -= dt
		help.modulate.a = clampf(_help_time, 0.0, 1.0)
	else:
		help.modulate.a = 0.0
