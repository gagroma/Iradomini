extends Control

signal back_requested
signal controls_requested

const UIStyle = preload("res://scripts/ui_style.gd")
const DIMENSIONS := Vector2(336, 172)
const BRASS := Color("#b48c5a")
const COLUMN := 176.0
const ROW_W := 148.0

var _volume: HSlider
var _sensitivity: HSlider
var _rows := {}
var _note: Label


func _ready() -> void:
	size = DIMENSIONS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(UIStyle.panel(Vector2.ZERO, DIMENSIONS))
	var divider := ColorRect.new()
	divider.color = Color(UIStyle.ASH, 0.25)
	divider.position = Vector2(COLUMN - 8, 12)
	divider.size = Vector2(1, DIMENSIONS.y - 24)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(divider)

	_volume = _slider("Master Volume", 10, 0.0, 100.0, 1.0)
	_volume.value_changed.connect(func(value: float):
		GameSettings.set_master_volume(value)
		GameSettings.save_settings()
	)
	_sensitivity = _slider("Mouse Sensitivity", 50, 50.0, 200.0, 5.0)
	_sensitivity.value_changed.connect(func(value: float):
		GameSettings.mouse_sensitivity = value
		GameSettings.save_settings()
	)
	var back := UIStyle.action_button("Back", Rect2(12, 140, 66, 23), 16)
	back.pressed.connect(func(): back_requested.emit())
	add_child(back)
	var controls := UIStyle.action_button("Controls", Rect2(84, 140, 80, 23), 16)
	controls.pressed.connect(func(): controls_requested.emit())
	add_child(controls)

	var heading := Label.new()
	heading.text = "Display"
	heading.position = Vector2(COLUMN, 6)
	UIStyle.style_text(heading, 12, BRASS)
	add_child(heading)
	var y := 24.0
	for key in ["picture", "mode", "window", "screen", "scaling", "vsync", "fps"]:
		_rows[key] = _row(key, y)
		y += 18.0
	_note = Label.new()
	_note.position = Vector2(COLUMN, y + 2)
	_note.size = Vector2(ROW_W, 20)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.add_theme_constant_override("line_spacing", -3)
	UIStyle.style_text(_note, 9, UIStyle.ASH)
	add_child(_note)
	_refresh()


func open() -> void:
	_refresh()
	show()
	_volume.grab_focus()


func toggle_fullscreen() -> void:
	GameSettings.set_fullscreen(not GameSettings.fullscreen)
	GameSettings.save_settings()
	_refresh()


func _refresh() -> void:
	_volume.set_value_no_signal(GameSettings.master_volume)
	_sensitivity.set_value_no_signal(GameSettings.mouse_sensitivity)
	_update_readout(_volume, GameSettings.master_volume)
	_update_readout(_sensitivity, GameSettings.mouse_sensitivity)
	var owns := GameSettings.can_control_window()
	var screens := DisplayServer.get_screen_count()
	_set_row("mode", "Mode", GameSettings.MODES[GameSettings.display_mode], true)
	var px := GameSettings.effective_size()
	var size_text := "%dx%d" % [px.x, px.y]
	if GameSettings.window_size == Vector2i.ZERO:
		size_text = "Auto " + size_text
	_set_row("window", "Window", size_text, GameSettings.display_mode == 0)
	_set_row("screen", "Monitor", "%d of %d" % [GameSettings.current_screen() + 1, screens], screens > 1)
	_set_row("picture", "Picture", "Sharp" if GameSettings.sharp else "Retro", true)
	_set_row("scaling", "Scaling", "Pixel-perfect" if GameSettings.pixel_perfect else "Fill screen", true)
	_set_row("vsync", "V-Sync", "On" if GameSettings.vsync else "Off", true)
	_set_row("fps", "Frame limit", "Unlimited" if GameSettings.max_fps == 0 else str(GameSettings.max_fps), true)
	_note.text = "" if owns else "In the editor Game tab: saved now, applied in a separate game window."


func _cycle(key: String, dir: int) -> void:
	var button: Button = _rows[key]
	if button.disabled:
		return
	match key:
		"mode":
			GameSettings.display_mode = posmod(GameSettings.display_mode + dir, GameSettings.MODES.size())
		"window":
			var options := [Vector2i.ZERO] + GameSettings.RESOLUTIONS
			var at := options.find(GameSettings.window_size)
			GameSettings.window_size = options[posmod(maxi(at, 0) + dir, options.size())]
		"screen":
			GameSettings.screen = posmod(GameSettings.current_screen() + dir, DisplayServer.get_screen_count())
		"picture":
			GameSettings.sharp = not GameSettings.sharp
		"scaling":
			GameSettings.pixel_perfect = not GameSettings.pixel_perfect
		"vsync":
			GameSettings.vsync = not GameSettings.vsync
		"fps":
			var limits: Array = GameSettings.FPS_LIMITS
			var at := limits.find(GameSettings.max_fps)
			GameSettings.max_fps = limits[posmod(maxi(at, 0) + dir, limits.size())]
	GameSettings.apply_display()
	GameSettings.save_settings()
	_refresh()


func _row(key: String, y: float) -> Button:
	var button := UIStyle.action_button("", Rect2(COLUMN - 4, y, ROW_W + 8, 17), 11)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_color_override("font_disabled_color", Color(UIStyle.ASH, 0.45))
	button.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
	var value := Label.new()
	value.position = Vector2(60, -2)
	value.size = Vector2(ROW_W - 56, 17)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIStyle.style_text(value, 11, BRASS)
	button.add_child(value)
	button.set_meta("value", value)
	button.button_mask = MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT
	button.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			_cycle(key, -1 if event.button_index == MOUSE_BUTTON_RIGHT else 1)
			button.accept_event()
		elif event.is_action_pressed("ui_left"):
			_cycle(key, -1)
			button.accept_event()
		elif event.is_action_pressed("ui_right") or event.is_action_pressed("ui_accept"):
			_cycle(key, 1)
			button.accept_event()
	)
	add_child(button)
	return button


func _set_row(key: String, caption: String, value: String, enabled: bool) -> void:
	var button: Button = _rows[key]
	button.text = " " + caption
	button.disabled = not enabled
	button.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
	var label: Label = button.get_meta("value")
	label.text = "‹ %s ›" % value
	label.modulate.a = 1.0 if enabled else 0.4


func _slider(caption: String, y: float, low: float, high: float, step_size: float) -> HSlider:
	var label := Label.new()
	label.text = caption
	label.position = Vector2(12, y)
	UIStyle.style_text(label, 12)
	add_child(label)
	var readout := Label.new()
	readout.position = Vector2(121, y)
	readout.size.x = 39
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UIStyle.style_text(readout, 11, UIStyle.ASH)
	add_child(readout)

	var slider := HSlider.new()
	slider.position = Vector2(12, y + 17)
	slider.size = Vector2(148, 15)
	slider.min_value = low
	slider.max_value = high
	slider.step = step_size
	slider.tooltip_text = caption
	slider.set_meta("readout", readout)
	slider.add_theme_stylebox_override("slider", _track(Color("#352a2b")))
	slider.add_theme_stylebox_override("grabber_area", _track(Color("#8d6744")))
	slider.add_theme_stylebox_override("grabber_area_highlight", _track(BRASS))
	slider.add_theme_icon_override("grabber", _diamond(BRASS))
	slider.add_theme_icon_override("grabber_highlight", _diamond(UIStyle.BONE))
	slider.value_changed.connect(func(value: float): _update_readout(slider, value))
	add_child(slider)
	return slider


func _update_readout(slider: HSlider, value: float) -> void:
	var label: Label = slider.get_meta("readout")
	label.text = "%d%%" % int(value)


func _track(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	return style


func _diamond(color: Color) -> ImageTexture:
	var image := Image.create_empty(9, 9, false, Image.FORMAT_RGBA8)
	for y in range(9):
		for x in range(9):
			if absi(x - 4) + absi(y - 4) <= 4:
				image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)
