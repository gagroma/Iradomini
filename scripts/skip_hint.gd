extends CanvasLayer

signal skipped

const UIStyle = preload("res://scripts/ui_style.gd")

var _label: Label
var _t := 0.0
var _used := false


static func attach(parent: Node, main) -> Node:
	if main.level_no <= 1:
		return null
	var hint = load("res://scripts/skip_hint.gd").new()
	parent.add_child(hint)
	return hint


func _ready() -> void:
	layer = 7
	_label = Label.new()
	_label.text = "Enter  ·  Skip"
	_label.position = Vector2(360, 250)
	_label.size = Vector2(112, 14)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIStyle.style_text(_label, 10, UIStyle.BONE)
	_label.modulate.a = 0.0
	add_child(_label)


func _process(dt: float) -> void:
	_t += dt
	var want = 0.0 if _used else 0.55 + 0.15 * sin(_t * 2.5)
	_label.modulate.a = move_toward(_label.modulate.a, want, dt * (1.5 if want > 0.0 else 4.0))


func _input(event: InputEvent) -> void:
	if _used or get_tree().paused:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER]:
		get_viewport().set_input_as_handled()
		_used = true
		skipped.emit()
