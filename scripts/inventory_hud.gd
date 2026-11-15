extends Control

const FONT = preload("res://assets/fonts/Tinos-Regular.ttf")
const BRASS := Color("#b48c5a")
const BONE := Color("#f4ead6")
const ASH := Color("#a49e98")
const SLOT := Vector2(20, 13)
const GAP := 3.0
const NAMES := ["Chalk", "Sawn-off"]

var player
var _show := 0.0
var _sel := 0.0
var _target := 0
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func pop(selected: int) -> void:
	_target = selected
	_show = 2.6


func _process(dt: float) -> void:
	_t += dt
	_show = maxf(0.0, _show - dt)
	_sel = lerpf(_sel, float(_target), 1.0 - exp(-14.0 * dt))
	queue_redraw()


func _draw() -> void:
	if player == null or not player.has_gun:
		return
	_draw_ammo_corner()
	var a := clampf(_show / 0.4, 0.0, 1.0)
	if a <= 0.0:
		return
	var rise := (1.0 - a) * 3.0
	var total := SLOT.x * 2.0 + GAP
	var origin := Vector2(240.0 - total * 0.5, 246.0 + rise)
	for i in 2:
		var pos := origin + Vector2(i * (SLOT.x + GAP), 0.0)
		var on := 1.0 - clampf(absf(_sel - i), 0.0, 1.0)
		var r := Rect2(pos, SLOT)
		draw_rect(r, Color(0.04, 0.03, 0.035, 0.75 * a).lerp(Color(0.14, 0.09, 0.06, 0.85 * a), on))
		draw_rect(r, Color(BRASS, (0.25 + 0.75 * on) * a), false, 1.0)
		var ink := ASH.lerp(BONE, on)
		ink.a = a
		draw_set_transform(r.get_center(), 0.0, Vector2.ONE * 0.36)
		if i == 0:
			_chalk_icon(Vector2.ZERO, ink)
		else:
			_gun_icon(Vector2.ZERO, ink)
		draw_set_transform(Vector2.ZERO)


func _draw_ammo_corner() -> void:
	if player.weapon != 1:
		return
	var base := Vector2(452, 246)
	for k in 2:
		_shell_icon(base + Vector2(k * 8, 0), k < player.shells, 1.0, 1.4)


func _text(s: String, at: Vector2, size: int, col: Color, centre: bool, right := false) -> void:
	var w := FONT.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x := at.x - (w * 0.5 if centre else (w if right else 0.0))
	draw_string(FONT, Vector2(x + 1, at.y + 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, col.a * 0.7))
	draw_string(FONT, Vector2(x, at.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _chalk_icon(c: Vector2, ink: Color) -> void:
	var dir := Vector2(1, -0.42).normalized()
	var n := Vector2(-dir.y, dir.x)
	var a := c - dir * 13.0
	var b := c + dir * 11.0
	var w := 3.2
	draw_colored_polygon(PackedVector2Array([a + n * w, b + n * w * 0.9, b - n * w * 0.9, a - n * w]), Color(ink.r, ink.g, ink.b, ink.a * 0.95))
	draw_colored_polygon(PackedVector2Array([b + n * w * 0.9, b + dir * 3.0 + n * 1.2, b + dir * 3.0 - n * 1.2, b - n * w * 0.9]), Color(ink.r * 0.85, ink.g * 0.85, ink.b * 0.8, ink.a))
	draw_line(a + n * w * 0.4, b + n * w * 0.35, Color(1, 1, 1, ink.a * 0.35), 1.0)


func _gun_icon(c: Vector2, ink: Color) -> void:
	var metal := Color(ink.r * 0.75, ink.g * 0.75, ink.b * 0.8, ink.a)
	var wood := Color(ink.r * 0.85, ink.g * 0.62, ink.b * 0.42, ink.a)
	var o := c + Vector2(-20, -3)
	draw_rect(Rect2(o + Vector2(14, -1), Vector2(26, 2.2)), metal)
	draw_rect(Rect2(o + Vector2(14, 1.6), Vector2(26, 2.2)), metal)
	draw_rect(Rect2(o + Vector2(39, -1.5), Vector2(1.5, 5.6)), metal)
	draw_rect(Rect2(o + Vector2(20, 4.2), Vector2(11, 2.2)), wood)
	draw_rect(Rect2(o + Vector2(8, -2), Vector2(7, 7.5)), metal)
	draw_colored_polygon(PackedVector2Array([o + Vector2(10, -3.2), o + Vector2(12, -6), o + Vector2(13.2, -5.4), o + Vector2(12, -2)]), metal)
	draw_colored_polygon(PackedVector2Array([o + Vector2(8.5, -1.5), o + Vector2(0.5, 4.5), o + Vector2(-1.5, 9.5), o + Vector2(2.5, 11.2), o + Vector2(6.5, 6.5), o + Vector2(9.5, 5.2)]), wood)
	draw_arc(o + Vector2(11.5, 6.4), 2.6, 0.2, PI - 0.2, 8, metal, 1.0)
	draw_line(o + Vector2(11.5, 5.2), o + Vector2(11.2, 7.4), metal, 1.0)


func _shell_icon(at: Vector2, full: bool, a: float, k := 1.0) -> void:
	var hull := Color(0.72, 0.1, 0.07, a) if full else Color(0.25, 0.2, 0.2, 0.55 * a)
	var brass := Color(0.86, 0.64, 0.3, a) if full else Color(0.35, 0.3, 0.25, 0.55 * a)
	draw_rect(Rect2(at, Vector2(4, 7) * k), hull)
	draw_rect(Rect2(at + Vector2(-0.5, 7) * k, Vector2(5, 2.4) * k), brass)
	if full:
		draw_rect(Rect2(at + Vector2(0.6, 0.5) * k, Vector2(0.8, 6) * k), Color(1, 0.6, 0.5, 0.35 * a))
