extends CanvasLayer

signal again_requested
signal title_requested

const UIStyle = preload("res://scripts/ui_style.gd")
const PANEL_SIZE := Vector2(224, 150)

var _dim: ColorRect
var _box: Control
var _again: Button
var _quit: Button


func _ready() -> void:
	layer = 4
	hide()
	_dim = ColorRect.new()
	_dim.color = Color("#09070b")
	add_child(_dim)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_box = Control.new()
	_box.custom_minimum_size = PANEL_SIZE
	center.add_child(_box)
	_box.add_child(UIStyle.panel(Vector2.ZERO, PANEL_SIZE))
	_label("YOU WIN", 12, 28)
	_label("All five churches are cleansed.\nThe last candle holds.", 46, 11, UIStyle.BONE * Color(1, 1, 1, 0.75))
	_again = _button("Play Again", 84, func(): again_requested.emit())
	_quit = _button("Quit to Title", 112, func(): title_requested.emit())


func reveal() -> void:
	_dim.modulate.a = 0.0
	_box.modulate.a = 0.0
	_again.disabled = true
	_quit.disabled = true
	show()
	var fade := create_tween().set_trans(Tween.TRANS_SINE)
	fade.tween_property(_dim, "modulate:a", 0.82, 1.6)
	fade.tween_property(_box, "modulate:a", 1.0, 0.7)
	await fade.finished
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_again.disabled = false
	_quit.disabled = false
	_again.grab_focus()


func _label(caption: String, y: float, size: int, color := UIStyle.BONE) -> void:
	var label := Label.new()
	label.text = caption
	label.position = Vector2(0, y)
	label.size = Vector2(PANEL_SIZE.x, size * 2)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIStyle.style_text(label, size, color)
	_box.add_child(label)


func _button(caption: String, y: float, action: Callable) -> Button:
	var button := UIStyle.action_button(caption, Rect2((PANEL_SIZE.x - 150) * 0.5, y, 150, 26), 17)
	button.pressed.connect(action)
	_box.add_child(button)
	return button
