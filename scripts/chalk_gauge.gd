extends Control

const T = preload("res://scripts/tuning.gd")
const UIStyle = preload("res://scripts/ui_style.gd")
const INK := Color("#f8f8f5")
const EDGE := Color("#221d1be8")
const TRACK := Color("#686360")
const TRACK_BEVEL := Color("#45403e")
const CHALK_BEVEL := Color("#b7b7b3")
const BEVEL := 0.37

# Outlines of the same open path, starting at the bottom of the left break.
static var _outer := PackedVector2Array([
	Vector2(3, 16), Vector2(8, 23), Vector2(18, 33), Vector2(30, 29),
	Vector2(34, 17), Vector2(23, 5), Vector2(6, 8),
])
static var _inner := PackedVector2Array([
	Vector2(9, 17), Vector2(11, 21), Vector2(19, 28), Vector2(27, 26),
	Vector2(29, 18), Vector2(22, 9), Vector2(11, 11),
])

var _remaining := T.CHALK_MAX
var _amount: Label
var _outline := PackedVector2Array()
var _lengths := PackedFloat32Array()
var _total_length := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = 13.0
	offset_top = -49.0
	offset_right = 103.0
	offset_bottom = -13.0

	_outline = _outer.duplicate()
	for i in range(_inner.size() - 1, -1, -1):
		_outline.append(_inner[i])
	_outline.append(_outer[0])
	for i in range(_outer.size() - 1):
		var from := _outer[i].lerp(_inner[i], 0.5)
		var to := _outer[i + 1].lerp(_inner[i + 1], 0.5)
		var length := from.distance_to(to)
		_lengths.append(length)
		_total_length += length

	_amount = Label.new()
	_amount.position = Vector2(42.0, 9.0)
	_amount.size = Vector2(46.0, 18.0)
	_amount.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_amount.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIStyle.style_text(_amount, 13)
	_amount.text = "%.1f m" % _remaining
	add_child(_amount)


func set_supply(remaining: float) -> void:
	var available := clampf(remaining, 0.0, T.CHALK_MAX)
	if is_equal_approx(available, _remaining):
		return
	_remaining = available
	var text := "%.1f m" % _remaining
	if _amount.text != text:
		_amount.text = text
	queue_redraw()


func _draw() -> void:
	draw_colored_polygon(_outline, TRACK)
	draw_polyline(_outline, EDGE, 2.0)
	var filled := _total_length * _remaining / T.CHALK_MAX
	for i in range(_lengths.size()):
		var outside := _outer[i]
		var inside := _inner[i]
		var next_outside := _outer[i + 1]
		var next_inside := _inner[i + 1]
		var bevel_start := outside.lerp(inside, BEVEL)
		var bevel_end := next_outside.lerp(next_inside, BEVEL)
		_draw_quad(outside, next_outside, bevel_end, bevel_start, TRACK_BEVEL)

		var length := _lengths[i]
		var fraction := clampf(filled / length, 0.0, 1.0)
		if fraction > 0.0:
			var end_outside := outside.lerp(next_outside, fraction)
			var end_inside := inside.lerp(next_inside, fraction)
			var end_bevel := end_outside.lerp(end_inside, BEVEL)
			_draw_quad(bevel_start, end_bevel, end_inside, inside, INK)
			_draw_quad(outside, end_outside, end_bevel, bevel_start, CHALK_BEVEL)
			if filled <= length or i == _lengths.size() - 1:
				var direction := (bevel_end - bevel_start).normalized()
				var tip := end_outside.lerp(end_inside, 0.76) + direction * 3.0
				draw_colored_polygon(PackedVector2Array([end_outside, tip, end_inside]), INK)
		filled -= length


func _draw_quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([a, b, c, d]), color)
