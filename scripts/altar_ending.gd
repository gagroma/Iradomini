extends CanvasLayer

signal title_requested

const UIStyle = preload("res://scripts/ui_style.gd")
const PARCHMENT_SHADER = preload("res://shaders/ending_parchment.gdshader")
const INK := Color("#31271e")

var _paper: ColorRect
var _copy: CenterContainer
var _return_button: Button


func _ready() -> void:
	layer = 4
	hide()
	_paper = ColorRect.new()
	var material := ShaderMaterial.new()
	material.shader = PARCHMENT_SHADER
	_paper.material = material
	add_child(_paper)
	_paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_copy = CenterContainer.new()
	_copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_copy)
	_copy.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var content := Control.new()
	content.custom_minimum_size = Vector2(400, 131)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_copy.add_child(content)
	_label(content, "THE CIRCLE IS CLOSED", 8, 29)
	_label(content, "The bells have fallen silent.\nIn the stillness, the last candle holds.", 52, 14)
	var frame := UIStyle.panel(Vector2(118, 98), Vector2(164, 33))
	content.add_child(frame)
	_return_button = UIStyle.action_button("Return to Title", Rect2(124, 101, 152, 26), 16)
	_return_button.pressed.connect(func(): title_requested.emit())
	content.add_child(_return_button)


func reveal() -> void:
	_paper.modulate.a = 0.0
	_copy.modulate.a = 0.0
	_return_button.disabled = true
	show()
	var fade := create_tween().set_trans(Tween.TRANS_SINE)
	fade.tween_interval(2.8)
	fade.tween_property(_paper, "modulate:a", 1.0, 2.2)
	fade.tween_property(_copy, "modulate:a", 1.0, 0.65)
	await fade.finished
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_return_button.disabled = false
	_return_button.grab_focus()


func _label(parent: Control, caption: String, y: float, size: int) -> void:
	var label := Label.new()
	label.text = caption
	label.position.y = y
	label.size.x = 400
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIStyle.style_text(label, size, INK)
	label.add_theme_color_override("font_shadow_color", Color("#c6ad861f"))
	parent.add_child(label)
