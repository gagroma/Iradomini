extends Node3D

const Sfx = preload("res://scripts/sfx.gd")
const UIStyle = preload("res://scripts/ui_style.gd")
const SettingsPanel = preload("res://scripts/settings_panel.gd")
const TitleWordmark = preload("res://scripts/title_wordmark.gd")
const HowToPlay = preload("res://scripts/how_to_play.gd")
const ControlsPanel = preload("res://scripts/controls_panel.gd")
const FlameTransition = preload("res://scripts/flame_transition.gd")
const POST_SHADER = preload("res://shaders/post.gdshader")
const GAME_SCENE = preload("res://main.tscn")   # level 1 starts in the church; the passage comes between levels
const INK := UIStyle.BONE
const MUTED_INK := UIStyle.ASH

var _choices: Control
var _settings: SettingsPanel
var _title_art: Control
var _play_button: Button
var _how_to_button: Button
var _how_to: HowToPlay
var _controls: ControlsPanel
var _controls_button: Button
var _controls_from_settings := false
var _settings_button: Button
var _fade: ColorRect
var _breath: AudioStreamPlayer3D
var _drone: AudioStreamPlayer
var _sfx: Node
var _intro: Tween
var _starting := false
var _choice_highlight: ColorRect
var _choice_buttons: Array[Button] = []

@onready var _stage = $Stage


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_interface()
	_sfx = Sfx.new()
	add_child(_sfx)
	_drone = _sfx.loop("drone", -21.0)
	_breath = _sfx.loop_at("demon_breath", _stage.wailer_node(), -12.0)
	_play_button.grab_focus()
	_intro = create_tween()
	_intro.tween_property(_fade, "color:a", 0.0, 0.6)


func _unhandled_input(event: InputEvent) -> void:
	if _starting:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F11:
		_settings.toggle_fullscreen()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and _settings.visible:
		_close_settings()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	var hovered := get_viewport().gui_get_hovered_control() as Button
	_choice_highlight.hide()
	for button in _choice_buttons:
		var selected := button == hovered and button.is_visible_in_tree()
		var caption: String = button.get_meta("caption")
		var text := "> " + caption if selected else caption
		if button.text != text:
			button.text = text
			button.modulate = Color.WHITE if selected else MUTED_INK
		if selected:
			_choice_highlight.global_position = button.global_position - Vector2(4, 3)
			_choice_highlight.show()


func _start_game() -> void:
	if _starting:
		return
	_starting = true
	_intro.kill()
	_fade.color.a = 0.0
	_choices.hide()
	await _stage.face_camera()
	if _breath != null:
		_breath.stop()
	_sfx.play("burn", -4.0, 0.52)
	if _drone != null:
		create_tween().tween_property(_drone, "volume_db", -60.0, 1.2)
	var title_fade := create_tween()
	title_fade.tween_property(_title_art, "modulate:a", 0.0, 0.65)
	await _stage.burn_circle()
	Engine.set_meta("ira_level", 1)
	for k in ["ira_gun", "ira_loaded", "ira_spare"]:
		if Engine.has_meta(k):
			Engine.remove_meta(k)
	var transition := FlameTransition.new()
	get_tree().root.add_child(transition)
	transition.open_game(GAME_SCENE, _stage.last_ember_uv(), _sfx.streams.get("burn"))


func _open_settings() -> void:
	_choices.hide()
	_settings.open()


func _open_how_to() -> void:
	_choices.hide()
	_title_art.hide()
	_how_to.open()


func _close_how_to() -> void:
	_how_to.close()
	_title_art.show()
	_choices.show()
	_how_to_button.grab_focus()


func _open_controls(from_settings: bool) -> void:
	_controls_from_settings = from_settings
	_choices.hide()
	_settings.hide()
	_title_art.hide()
	_controls.open()


func _close_controls() -> void:
	_controls.hide()
	_title_art.show()
	if _controls_from_settings:
		_settings.open()
	else:
		_choices.show()
		_controls_button.grab_focus()


func _close_settings() -> void:
	_settings.hide()
	_choices.show()
	_settings_button.grab_focus()


func _quit_game() -> void:
	_choices.hide()
	if _breath != null:
		_breath.stop()
	if _drone != null:
		_drone.stop()
	# Give the audio mixer time to release the two looping streams.
	await get_tree().create_timer(0.1).timeout
	get_tree().quit()


func _build_interface() -> void:
	var overlay := CanvasLayer.new()
	add_child(overlay)
	var ui := Control.new()
	overlay.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var post := ColorRect.new()
	ui.add_child(post)
	post.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var post_material := ShaderMaterial.new()
	post_material.shader = POST_SHADER
	post_material.set_shader_parameter("levels", 128.0)
	post.material = post_material
	_add_left_shade(ui)

	_title_art = Control.new()
	_title_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_title_art)
	var title := TitleWordmark.new()
	title.position = Vector2(22, 16)
	_title_art.add_child(title)

	_choices = Control.new()
	_choices.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_choices)
	_choice_highlight = UIStyle.panel(Vector2.ZERO, Vector2(156, 29), 0.82)
	_choice_highlight.z_index = 1
	_choice_highlight.hide()
	ui.add_child(_choice_highlight)
	_play_button = _button(_choices, "Play", 128, _start_game)
	_how_to_button = _button(_choices, "How to Play", 154, _open_how_to)
	_controls_button = _button(_choices, "Controls", 180, _open_controls.bind(false))
	_settings_button = _button(_choices, "Settings", 206, _open_settings)
	_button(_choices, "Exit", 232, _quit_game)
	_build_settings(ui)
	_controls = ControlsPanel.new()
	ui.add_child(_controls)
	_controls.back_requested.connect(_close_controls)
	_settings.controls_requested.connect(_open_controls.bind(true))
	_how_to = HowToPlay.new()
	ui.add_child(_how_to)
	_how_to.back_requested.connect(_close_how_to)

	_fade = ColorRect.new()
	_fade.z_index = 3
	ui.add_child(_fade)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.color = Color.BLACK


func _add_left_shade(parent: Control) -> void:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.29, 0.68])
	gradient.colors = PackedColorArray([Color("#0b080cf8"), Color("#0b080cda"), Color("#0b080c00")])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 480
	texture.height = 1
	var shade := TextureRect.new()
	parent.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.texture = texture
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _build_settings(parent: Control) -> void:
	_settings = SettingsPanel.new()
	_settings.position = Vector2(20, 90)
	parent.add_child(_settings)
	_settings.hide()
	_settings.back_requested.connect(_close_settings)


func _button(parent: Control, caption: String, y: float, clicked: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.set_meta("caption", caption)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.position = Vector2(26 if parent == _choices else 32, y)
	button.size = Vector2(148, 23)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.z_index = 2
	UIStyle.style_text(button, 19)
	button.modulate = MUTED_INK
	var style := StyleBoxEmpty.new()
	style.content_margin_left = 10.0
	style.content_margin_right = 6.0
	for state in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, style)
	for state in ["font_hover_color", "font_focus_color", "font_pressed_color"]:
		button.add_theme_color_override(state, INK)
	button.pressed.connect(clicked)
	parent.add_child(button)
	_choice_buttons.append(button)
	return button


func _label(parent: Control, caption: String, at: Vector2, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = caption
	label.position = at
	UIStyle.style_text(label, size, color)
	parent.add_child(label)
	return label
