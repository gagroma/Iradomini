extends Node3D

const Sfx = preload("res://scripts/sfx.gd")
const UIStyle = preload("res://scripts/ui_style.gd")
const TitleWordmark = preload("res://scripts/title_wordmark.gd")
const HowToPlay = preload("res://scripts/how_to_play.gd")
const FlameTransition = preload("res://scripts/flame_transition.gd")
const POST_SHADER = preload("res://shaders/post.gdshader")
const GAME_SCENE = preload("res://main.tscn")
const INK := UIStyle.BONE
const MUTED_INK := UIStyle.ASH
const BRASS := Color("#b48c5a")

var _choices: Control
var _settings: Control
var _title_art: Control
var _play_button: Button
var _how_to_button: Button
var _how_to: HowToPlay
var _settings_button: Button
var _volume_slider: HSlider
var _fullscreen_button: CheckButton
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
		GameSettings.set_fullscreen(not GameSettings.fullscreen)
		_fullscreen_button.set_pressed_no_signal(GameSettings.fullscreen)
		GameSettings.save_settings()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and _settings.visible:
		_close_settings()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	var hovered := get_viewport().gui_get_hovered_control() as Button
	var focused := get_viewport().gui_get_focus_owner() as Button
	var active := hovered if hovered in _choice_buttons else focused
	_choice_highlight.hide()
	for button in _choice_buttons:
		var selected := button == active and button.is_visible_in_tree()
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
	var transition := FlameTransition.new()
	get_tree().root.add_child(transition)
	transition.open_game(GAME_SCENE, _stage.last_ember_uv(), _sfx.streams.get("burn"))


func _open_settings() -> void:
	_choices.hide()
	_settings.show()
	_volume_slider.grab_focus()


func _open_how_to() -> void:
	_choices.hide()
	_title_art.hide()
	_how_to.open()


func _close_how_to() -> void:
	_how_to.close()
	_title_art.show()
	_choices.show()
	_how_to_button.grab_focus()


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
	post_material.set_shader_parameter("levels", 32.0)
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
	_play_button = _button(_choices, "Play", 139, _start_game)
	_how_to_button = _button(_choices, "How to Play", 167, _open_how_to)
	_settings_button = _button(_choices, "Settings", 195, _open_settings)
	_button(_choices, "Exit", 223, _quit_game)
	_build_settings(ui)
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
	_settings = Control.new()
	_settings.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(_settings)
	_settings.hide()
	_settings.add_child(UIStyle.panel(Vector2(20, 102), Vector2(172, 148)))

	_volume_slider = _slider("Master Volume", 111, 0.0, 100.0, 1.0, GameSettings.master_volume)
	_volume_slider.value_changed.connect(func(value: float):
		GameSettings.set_master_volume(value)
		GameSettings.save_settings()
	)
	var sensitivity := _slider("Mouse Sensitivity", 151, 50.0, 200.0, 5.0, GameSettings.mouse_sensitivity)
	sensitivity.value_changed.connect(func(value: float):
		GameSettings.mouse_sensitivity = value
		GameSettings.save_settings()
	)

	_fullscreen_button = CheckButton.new()
	_fullscreen_button.text = "Fullscreen"
	_fullscreen_button.position = Vector2(32, 190)
	_fullscreen_button.size = Vector2(148, 20)
	UIStyle.style_text(_fullscreen_button, 12)
	var toggle_off := _slider_handle(MUTED_INK)
	var toggle_on := _slider_handle(INK)
	_fullscreen_button.add_theme_icon_override("unchecked", toggle_off)
	_fullscreen_button.add_theme_icon_override("unchecked_mirrored", toggle_off)
	_fullscreen_button.add_theme_icon_override("checked", toggle_on)
	_fullscreen_button.add_theme_icon_override("checked_mirrored", toggle_on)
	var toggle_focus := StyleBoxFlat.new()
	toggle_focus.bg_color = Color("#f4ead611")
	toggle_focus.border_color = MUTED_INK
	toggle_focus.border_width_left = 1
	_fullscreen_button.add_theme_stylebox_override("focus", toggle_focus)
	_fullscreen_button.button_pressed = GameSettings.fullscreen
	_fullscreen_button.toggled.connect(func(enabled: bool):
		GameSettings.set_fullscreen(enabled)
		GameSettings.save_settings()
	)
	_settings.add_child(_fullscreen_button)
	_button(_settings, "Back", 218, _close_settings)


func _slider(label_text: String, y: float, low: float, high: float, step_size: float, initial: float) -> HSlider:
	_label(_settings, label_text, Vector2(32, y), 12, INK)
	var value_label := _label(_settings, "%d%%" % int(initial), Vector2(146, y), 11, MUTED_INK)
	value_label.size.x = 34
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var slider := HSlider.new()
	slider.position = Vector2(32, y + 17)
	slider.size = Vector2(148, 15)
	slider.min_value = low
	slider.max_value = high
	slider.step = step_size
	slider.value = initial
	slider.tooltip_text = label_text
	slider.add_theme_stylebox_override("slider", _slider_track(Color("#352a2b")))
	slider.add_theme_stylebox_override("grabber_area", _slider_track(Color("#8d6744")))
	slider.add_theme_stylebox_override("grabber_area_highlight", _slider_track(BRASS))
	slider.add_theme_icon_override("grabber", _slider_handle(BRASS))
	slider.add_theme_icon_override("grabber_highlight", _slider_handle(INK))
	slider.value_changed.connect(func(value: float): value_label.text = "%d%%" % int(value))
	_settings.add_child(slider)
	return slider


func _slider_track(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	return style


func _slider_handle(color: Color) -> ImageTexture:
	var handle := Image.create_empty(9, 9, false, Image.FORMAT_RGBA8)
	for y in range(9):
		for x in range(9):
			if absi(x - 4) + absi(y - 4) <= 4:
				handle.set_pixel(x, y, color)
	return ImageTexture.create_from_image(handle)


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
