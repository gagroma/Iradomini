extends Node3D

const Sfx = preload("res://scripts/sfx.gd")
const POST_SHADER = preload("res://shaders/post.gdshader")
const GAME_SCENE := "res://main.tscn"
const INK := Color("#f1dfc0")
const MUTED_INK := Color("#bba587")
const BRASS := Color("#b48c5a")

var _choices: Control
var _settings: Control
var _play_button: Button
var _settings_button: Button
var _volume_slider: HSlider
var _fullscreen_button: CheckButton
var _fade: ColorRect
var _breath: AudioStreamPlayer3D
var _drone: AudioStreamPlayer
var _sfx: Node
var _intro: Tween
var _starting := false
var _display_font: Font

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


func _start_game() -> void:
	if _starting:
		return
	_starting = true
	_intro.kill()
	_fade.color.a = 0.0
	_choices.hide()
	_stage.break_circle()
	if _breath != null:
		_breath.stop()
	_sfx.play("burn", -8.0, 0.7)

	var transition := create_tween()
	transition.tween_interval(0.29)
	transition.tween_property(_fade, "color:a", 1.0, 0.57).set_trans(Tween.TRANS_SINE)
	if _drone != null:
		transition.parallel().tween_property(_drone, "volume_db", -50.0, 0.57)
	await transition.finished
	var result := get_tree().change_scene_to_file(GAME_SCENE)
	if result != OK:
		push_error("Could not start the game (%s)." % error_string(result))
		get_tree().reload_current_scene()


func _open_settings() -> void:
	_choices.hide()
	_settings.show()
	_volume_slider.grab_focus()


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
	var fonts := SystemFont.new()
	fonts.font_names = PackedStringArray(["Cormorant Garamond", "Georgia", "Times New Roman", "Liberation Serif", "DejaVu Serif"])
	var display := FontVariation.new()
	display.base_font = fonts
	display.spacing_glyph = 1
	_display_font = display

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

	_label(ui, "IRA DOMINI", Vector2(30, 48), 31, INK, _display_font)
	var rule := ColorRect.new()
	rule.position = Vector2(32, 95)
	rule.size = Vector2(147, 1)
	rule.color = Color("#795638")
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(rule)

	_choices = Control.new()
	_choices.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_choices)
	_play_button = _button(_choices, "Play", 114, _start_game)
	_settings_button = _button(_choices, "Settings", 149, _open_settings)
	_button(_choices, "Quit", 184, _quit_game)
	_build_settings(ui)

	_fade = ColorRect.new()
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
	_fullscreen_button.add_theme_font_size_override("font_size", 11)
	_fullscreen_button.add_theme_color_override("font_color", INK)
	_fullscreen_button.add_theme_stylebox_override("focus", _choice_style(true))
	_fullscreen_button.button_pressed = GameSettings.fullscreen
	_fullscreen_button.toggled.connect(func(enabled: bool):
		GameSettings.set_fullscreen(enabled)
		GameSettings.save_settings()
	)
	_settings.add_child(_fullscreen_button)
	_button(_settings, "Back", 218, _close_settings)


func _slider(label_text: String, y: float, low: float, high: float, step_size: float, initial: float) -> HSlider:
	_label(_settings, label_text, Vector2(32, y), 11, INK)
	var value_label := _label(_settings, "%d%%" % int(initial), Vector2(146, y), 10, MUTED_INK)
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
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.position = Vector2(32, y)
	button.size = Vector2(148, 29)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", _display_font)
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", MUTED_INK)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_focus_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_stylebox_override("normal", _choice_style(false))
	button.add_theme_stylebox_override("hover", _choice_style(true))
	button.add_theme_stylebox_override("pressed", _choice_style(true))
	button.add_theme_stylebox_override("focus", _choice_style(true))
	button.pressed.connect(clicked)
	parent.add_child(button)
	return button


func _choice_style(active: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.content_margin_left = 10.0
	style.content_margin_right = 6.0
	style.bg_color = Color("#b48c5a1b") if active else Color.TRANSPARENT
	style.border_color = BRASS
	style.border_width_left = 1 if active else 0
	return style


func _label(parent: Control, caption: String, at: Vector2, size: int, color: Color, font: Font = null) -> Label:
	var label := Label.new()
	label.text = caption
	label.position = at
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if font != null:
		label.add_theme_font_override("font", font)
	parent.add_child(label)
	return label
