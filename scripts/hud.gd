extends CanvasLayer
# HUD - the reticle, prompts, chalk supply, stealth eye and debug panel.
# Source: Godot Label nodes inside a CanvasLayer (2D drawn on top of 3D).
# The screen is 480x270 pixels, so positions below are in those pixels.

const ChalkGauge = preload("res://scripts/chalk_gauge.gd")
const UIStyle = preload("res://scripts/ui_style.gd")
const RETICLE_SHADER = preload("res://shaders/chalk_reticle.gdshader")

var prompt: Label
var status: Label
var note: Label
var help: Label
var debug: Label
var stealth                 # stealth_hud.gd: the demon's eye, your footsteps, hidden or not

var _chalk_gauge: ChalkGauge
var _reticle: ColorRect
var _reticle_material: ShaderMaterial
var _floor_amount := 0.0
var _interact_amount := 0.0
var _note_time := 0.0
var _help_time := 16.0


func setup() -> void:
	layer = 2
	_reticle = ColorRect.new()
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reticle_material = ShaderMaterial.new()
	_reticle_material.shader = RETICLE_SHADER
	_reticle.material = _reticle_material
	add_child(_reticle)
	_reticle.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_reticle.offset_left = -12
	_reticle.offset_top = -12
	_reticle.offset_right = 12
	_reticle.offset_bottom = 12

	prompt = _label(Vector2(0, 151), Vector2(480, 15), 12, HORIZONTAL_ALIGNMENT_CENTER)
	status = _label(Vector2(6, 4), Vector2(300, 14), 11, HORIZONTAL_ALIGNMENT_LEFT)
	note = _label(Vector2(0, 60), Vector2(480, 14), 11, HORIZONTAL_ALIGNMENT_CENTER)
	help = _label(Vector2(20, 206), Vector2(440, 60), 11, HORIZONTAL_ALIGNMENT_CENTER)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.text = "WASD  Move  ·  Shift  Run  ·  Ctrl / C  Crouch to hide near cover\nHold LMB  Draw chalk  ·  Hold RMB  Erase a circle\nE  Interact  ·  The demon cannot cross a closed circle"
	debug = _label(Vector2(300, 4), Vector2(176, 120), 8, HORIZONTAL_ALIGNMENT_RIGHT)
	debug.visible = false
	stealth = preload("res://scripts/stealth_hud.gd").new()
	add_child(stealth)
	_chalk_gauge = ChalkGauge.new()
	add_child(_chalk_gauge)


func _label(pos: Vector2, box: Vector2, font_size: int, align: int) -> Label:
	var l = Label.new()
	l.position = pos
	l.size = box
	l.horizontal_alignment = align
	UIStyle.style_text(l, font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func set_prompt(text: String) -> void:
	prompt.text = text


func set_status(text: String) -> void:
	status.text = text


func set_chalk_supply(remaining: float, playing: bool) -> void:
	_chalk_gauge.visible = playing
	if playing:
		_chalk_gauge.set_supply(remaining)


# A short message that fades away by itself.
func show_note(text: String, seconds: float = 4.0) -> void:
	note.text = text
	_note_time = seconds


func update_reticle(playing: bool, floor_in_reach: bool, interactable: bool, erase: float, dt: float) -> void:
	_reticle.visible = playing
	if not playing:
		return
	_floor_amount = move_toward(_floor_amount, 1.0 if floor_in_reach or erase > 0.0 else 0.0, dt * 6.0)
	_interact_amount = move_toward(_interact_amount, 1.0 if interactable and erase <= 0.0 else 0.0, dt * 10.0)
	_reticle_material.set_shader_parameter("floor_amount", _floor_amount)
	_reticle_material.set_shader_parameter("interact_amount", _interact_amount)
	_reticle_material.set_shader_parameter("erase_progress", erase)


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
