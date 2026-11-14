extends Control

signal back_requested

const UIStyle = preload("res://scripts/ui_style.gd")
const DIMENSIONS := Vector2(172, 148)
const BRASS := Color("#b48c5a")

var _volume: HSlider
var _sensitivity: HSlider
var _fullscreen: CheckButton


func _ready() -> void:
	size = DIMENSIONS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(UIStyle.panel(Vector2.ZERO, DIMENSIONS))

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
	_fullscreen = CheckButton.new()
	_fullscreen.text = "Fullscreen"
	_fullscreen.position = Vector2(12, 88)
	_fullscreen.size = Vector2(148, 20)
	UIStyle.style_text(_fullscreen, 12)
	var off := _diamond(UIStyle.ASH)
	var on := _diamond(UIStyle.BONE)
	_fullscreen.add_theme_icon_override("unchecked", off)
	_fullscreen.add_theme_icon_override("unchecked_mirrored", off)
	_fullscreen.add_theme_icon_override("checked", on)
	_fullscreen.add_theme_icon_override("checked_mirrored", on)
	_fullscreen.toggled.connect(func(enabled: bool):
		GameSettings.set_fullscreen(enabled)
		GameSettings.save_settings()
	)
	add_child(_fullscreen)
	var back := UIStyle.action_button("Back", Rect2(12, 116, 66, 23), 16)
	back.pressed.connect(func(): back_requested.emit())
	add_child(back)
	_refresh()


func open() -> void:
	_refresh()
	show()
	_volume.grab_focus()


func toggle_fullscreen() -> void:
	GameSettings.set_fullscreen(not GameSettings.fullscreen)
	GameSettings.save_settings()
	_fullscreen.set_pressed_no_signal(GameSettings.fullscreen)


func _refresh() -> void:
	_volume.set_value_no_signal(GameSettings.master_volume)
	_sensitivity.set_value_no_signal(GameSettings.mouse_sensitivity)
	_update_readout(_volume, GameSettings.master_volume)
	_update_readout(_sensitivity, GameSettings.mouse_sensitivity)
	_fullscreen.set_pressed_no_signal(GameSettings.fullscreen)


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
