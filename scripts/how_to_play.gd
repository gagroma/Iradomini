extends Control

signal back_requested

const UIStyle = preload("res://scripts/ui_style.gd")
const SLIDE_1_CHALK = preload("res://assets/tutorial/chalk.ogv")
const SLIDE_2_GOAL = preload("res://assets/tutorial/goal.ogv")
const SLIDE_3_BANISH = preload("res://assets/tutorial/banish.ogv")
const CLIPS := [SLIDE_1_CHALK, SLIDE_2_GOAL, SLIDE_3_BANISH]
const TITLES := ["1. The Chalk", "2. The Goal", "3. Banishing the Demon"]
const EXPLANATIONS := [
	"Hold Left Mouse to draw on the floor. Join the line back to itself to keep the demon out. Open lines burn away. Hold Right Mouse to erase a circle and recover chalk.",
	"Gather all 4 relics with E and place them on the main altar. Hold Ctrl near pews, pillars, or the altar to hide.",
	"Close a chalk circle around the demon while staying outside it to banish it immediately. The demon returns after a while. Hold Right Mouse to erase the circle and recover its chalk.",
]

var _slide := 0
var _video: VideoStreamPlayer
var _title: Label
var _description: Label
var _counter: Label
var _back: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()
	add_child(UIStyle.panel(Vector2(63, 4), Vector2(354, 262), 0.98))
	_title = _label(Rect2(78, 12, 324, 18), 16, HORIZONTAL_ALIGNMENT_CENTER)
	add_child(UIStyle.panel(Vector2(98, 31), Vector2(284, 161), 1.0))
	var frame := Panel.new()
	frame.position = Vector2(103, 34)
	frame.size = Vector2(274, 155)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var border := StyleBoxFlat.new()
	border.bg_color = Color("#100e11")
	border.border_color = Color("#7b6c58")
	border.set_border_width_all(1)
	frame.add_theme_stylebox_override("panel", border)
	add_child(frame)

	_video = VideoStreamPlayer.new()
	_video.position = Vector2(104, 35)
	_video.size = Vector2(272, 153)
	_video.expand = true
	_video.loop = true
	_video.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_video)

	_description = _label(Rect2(95, 194, 290, 41), 11, HORIZONTAL_ALIGNMENT_LEFT)
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_counter = _label(Rect2(215, 243, 50, 14), 12, HORIZONTAL_ALIGNMENT_CENTER)
	_button("<", Rect2(184, 237, 24, 22), func(): _show_slide(_slide - 1))
	_button(">", Rect2(272, 237, 24, 22), func(): _show_slide(_slide + 1))
	_back = _button("Back", Rect2(94, 237, 50, 22), func(): back_requested.emit())


func open() -> void:
	show()
	_show_slide(0)
	_back.grab_focus()


func close() -> void:
	_video.stop()
	hide()


func _input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_LEFT:
			_show_slide(_slide - 1)
		KEY_RIGHT:
			_show_slide(_slide + 1)
		KEY_ESCAPE:
			back_requested.emit()
		_:
			return
	get_viewport().set_input_as_handled()


func _show_slide(index: int) -> void:
	_slide = posmod(index, CLIPS.size())
	_video.stop()
	_video.stream = CLIPS[_slide]
	_video.play()
	_title.text = TITLES[_slide]
	_description.text = EXPLANATIONS[_slide]
	_counter.text = "%d / %d" % [_slide + 1, CLIPS.size()]


func _label(rect: Rect2, size: int, alignment: int) -> Label:
	var label := Label.new()
	label.position = rect.position
	label.size = rect.size
	label.horizontal_alignment = alignment
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIStyle.style_text(label, size)
	add_child(label)
	return label


func _button(caption: String, rect: Rect2, action: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.position = rect.position
	button.size = rect.size
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	UIStyle.style_text(button, 15)
	var empty := StyleBoxEmpty.new()
	var selected := StyleBoxFlat.new()
	selected.bg_color = Color("#f4ead619")
	selected.border_color = UIStyle.ASH
	selected.border_width_bottom = 1
	button.add_theme_stylebox_override("normal", empty)
	for state in ["hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, selected)
		button.add_theme_color_override("font_" + state + "_color", UIStyle.BONE)
	button.pressed.connect(action)
	add_child(button)
	return button
