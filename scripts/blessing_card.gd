extends Control

signal chosen(id: String)

const UIStyle = preload("res://scripts/ui_style.gd")
const Boons = preload("res://scripts/boons.gd")
const SIZE := Vector2(120, 150)
const GOLD := Color(0.95, 0.74, 0.36)
const EMBER := Color(1.0, 0.5, 0.2)

var id := ""
var key := 1
var base := Vector2.ZERO
var hover := 0.0
var appear := 0.0
var delay := 0.0
var picked := false
var dismissed := false
var locked := true

var _t := 0.0
var _overlay: Control
var _flare := 0.0


func setup(boon: String, number: int, at: Vector2, wait: float) -> void:
	id = boon
	key = number
	base = at
	delay = wait
	size = SIZE
	pivot_offset = SIZE * 0.5
	position = base + Vector2(0, 24)
	modulate.a = 0.0
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_child(UIStyle.panel(Vector2.ZERO, SIZE, 0.97))
	_overlay = Control.new()
	_overlay.size = SIZE
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	var info: Array = Boons.POOL[id]
	_label(info[0], Rect2(6, 74, SIZE.x - 12, 18), 13, UIStyle.BONE)
	_label(info[1], Rect2(9, 94, SIZE.x - 18, 40), 10, UIStyle.ASH)
	var owned := Boons.n(id)
	_label(str(key) if owned == 0 else "%d   ·   held %d" % [key, owned], Rect2(0, SIZE.y - 16, SIZE.x, 12), 9, GOLD * Color(1, 1, 1, 0.7))
	mouse_entered.connect(grab_focus)
	gui_input.connect(_on_input)


func _label(text: String, box: Rect2, font: int, color: Color) -> void:
	var l = Label.new()
	l.text = text
	l.position = box.position
	l.size = box.size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.clip_text = false
	UIStyle.style_text(l, font, color)
	add_child(l)
	l.custom_minimum_size = Vector2(box.size.x, 0)
	l.size = box.size


func _on_input(event: InputEvent) -> void:
	if locked:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		chosen.emit(id)
	elif event.is_action_pressed("ui_accept"):
		chosen.emit(id)


func flare() -> void:
	picked = true
	_flare = 1.0


func _process(dt: float) -> void:
	_t += dt
	if _t >= delay:
		appear = move_toward(appear, 1.0, dt / 0.45)
	var want = 1.0 if (has_focus() or picked) and not dismissed else 0.0
	hover = move_toward(hover, want, dt / 0.15)
	_flare = move_toward(_flare, 0.0, dt / 0.9)
	var a = smoothstep(0.0, 1.0, appear)
	position = base + Vector2(0, 24.0 * (1.0 - a) - 7.0 * hover)
	var grow = 0.05 * hover + 0.08 * (1.0 - _flare) * float(picked)
	scale = Vector2.ONE * (1.0 + grow)
	modulate.a = a if not dismissed else move_toward(modulate.a, 0.0, dt / 0.3)
	_overlay.queue_redraw()


func _draw_overlay() -> void:
	var o = _overlay
	var flick = 0.85 + 0.15 * sin(_t * 9.0 + key) * sin(_t * 23.0 + key * 2.0)
	var glow = clampf(0.22 + 0.78 * hover * flick + _flare, 0.0, 1.6)
	var c = Vector2(SIZE.x * 0.5, 40)
	for i in 5:
		var r = 30.0 - i * 5.0
		o.draw_circle(c, r, Color(EMBER, (0.025 + 0.02 * i) * (0.4 + hover + _flare)))
	var frame = GOLD * Color(1, 1, 1, glow)
	var inset = 4.0
	o.draw_rect(Rect2(inset, inset, SIZE.x - inset * 2, SIZE.y - inset * 2), frame, false, 1.0)
	o.draw_rect(Rect2(inset + 2, inset + 2, SIZE.x - inset * 2 - 4, SIZE.y - inset * 2 - 4), Color(frame, glow * 0.35), false, 1.0)
	for p in [Vector2(inset, inset), Vector2(SIZE.x - inset, inset), Vector2(inset, SIZE.y - inset), Vector2(SIZE.x - inset, SIZE.y - inset)]:
		o.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -3), p + Vector2(3, 0), p + Vector2(0, 3), p + Vector2(-3, 0)]), frame)
	o.draw_line(Vector2(30, 68), Vector2(SIZE.x - 30, 68), Color(GOLD, 0.35 + 0.4 * hover), 1.0)
	var ink = GOLD.lerp(Color(1.0, 0.95, 0.8), 0.4 * hover + _flare * 0.6)
	_icon(o, c, ink)


func _ellipse(o: Control, c: Vector2, r: Vector2, col: Color) -> void:
	var pts = PackedVector2Array()
	for i in 21:
		var a = TAU * i / 20.0
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	o.draw_polyline(pts, col, 1.0)


func _icon(o: Control, c: Vector2, ink: Color) -> void:
	match id:
		"ward":
			o.draw_arc(c, 13, 0, TAU, 24, ink, 1.0)
			o.draw_arc(c, 10, 0, TAU, 24, Color(ink, 0.5), 1.0)
			o.draw_line(c + Vector2(0, -7), c + Vector2(0, 8), ink, 2.0)
			o.draw_line(c + Vector2(-5, -2), c + Vector2(5, -2), ink, 2.0)
			o.draw_line(c + Vector2(0, -13), c + Vector2(0, -20), Color(ink, 0.7), 1.0)
		"chalk_max":
			for i in 3:
				var y = c.y + 6 - i * 7
				o.draw_rect(Rect2(c.x - 13 + i * 2, y, 22, 5), Color(0.92, 0.9, 0.82), true)
				o.draw_rect(Rect2(c.x - 13 + i * 2, y, 22, 5), ink, false, 1.0)
			o.draw_line(c + Vector2(13, -14), c + Vector2(13, -6), ink, 1.0)
			o.draw_line(c + Vector2(9, -10), c + Vector2(17, -10), ink, 1.0)
		"chalk_regen":
			o.draw_rect(Rect2(c.x - 4, c.y - 9, 8, 18), Color(0.92, 0.9, 0.82), true)
			o.draw_arc(c, 15, -PI * 0.8, PI * 0.6, 20, ink, 1.0)
			var tip = c + Vector2.from_angle(PI * 0.6) * 15
			o.draw_colored_polygon(PackedVector2Array([tip + Vector2(-5, -1), tip + Vector2(3, -4), tip + Vector2(1, 4)]), ink)
		"stamina":
			_ellipse(o, c + Vector2(-7, 4), Vector2(6, 11), ink)
			_ellipse(o, c + Vector2(7, 4), Vector2(6, 11), ink)
			o.draw_line(c + Vector2(0, -16), c + Vector2(0, -4), ink, 1.0)
			o.draw_line(c + Vector2(0, -4), c + Vector2(-5, 0), ink, 1.0)
			o.draw_line(c + Vector2(0, -4), c + Vector2(5, 0), ink, 1.0)
		"breath":
			for i in 3:
				var pts = PackedVector2Array()
				for k in 13:
					var x = -16.0 + k * 2.7
					pts.append(c + Vector2(x, -8 + i * 8 + sin(x * 0.4 + _t * 3.0 + i) * 2.0))
				o.draw_polyline(pts, Color(ink, 1.0 - i * 0.2), 1.0)
		"quiet":
			o.draw_line(c + Vector2(-12, 14), c + Vector2(12, -14), ink, 1.0)
			for k in 7:
				var p = c + Vector2(-9 + k * 3.5, 10 - k * 4.0)
				o.draw_line(p, p + Vector2(-7, -3), Color(ink, 0.8), 1.0)
				o.draw_line(p, p + Vector2(3, 7), Color(ink, 0.8), 1.0)
		"candle":
			o.draw_rect(Rect2(c.x - 5, c.y - 4, 10, 18), Color(0.9, 0.86, 0.76), true)
			o.draw_rect(Rect2(c.x - 9, c.y + 14, 18, 3), ink, true)
			var f = sin(_t * 11.0) * 1.2
			o.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -19 + f), c + Vector2(4, -9), c + Vector2(0, -5), c + Vector2(-4, -9)]), EMBER)
			o.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -14 + f), c + Vector2(2, -9), c + Vector2(0, -7), c + Vector2(-2, -9)]), Color(1, 0.95, 0.7))
		"swift":
			for i in 3:
				var x = c.x - 14 + i * 9
				o.draw_polyline(PackedVector2Array([Vector2(x, c.y - 9), Vector2(x + 7, c.y), Vector2(x, c.y + 9)]), Color(ink, 0.5 + i * 0.25), 2.0)
		"mend":
			var heart = PackedVector2Array()
			for i in 24:
				var a = TAU * i / 24.0
				var hx = 16.0 * pow(sin(a), 3)
				var hy = -(13.0 * cos(a) - 5.0 * cos(2 * a) - 2.0 * cos(3 * a) - cos(4 * a))
				heart.append(c + Vector2(hx, hy) * 0.8)
			heart.append(heart[0])
			o.draw_polyline(heart, ink, 1.0)
			for k in 4:
				var y = c.y - 4 + k * 4
				o.draw_line(Vector2(c.x - 3, y), Vector2(c.x + 3, y + 2), Color(ink, 0.8), 1.0)
			o.draw_line(c + Vector2(0, -6), c + Vector2(0, 11), Color(ink, 0.6), 1.0)
		"reach":
			o.draw_line(c + Vector2(-16, 6), c + Vector2(10, -6), ink, 2.0)
			o.draw_rect(Rect2(c.x + 8, c.y - 10, 8, 4), Color(0.92, 0.9, 0.82), true)
			o.draw_line(c + Vector2(-16, 14), c + Vector2(16, 14), Color(ink, 0.6), 1.0)
			o.draw_line(c + Vector2(12, 11), c + Vector2(16, 14), Color(ink, 0.6), 1.0)
			o.draw_line(c + Vector2(12, 17), c + Vector2(16, 14), Color(ink, 0.6), 1.0)
