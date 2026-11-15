extends Control

const ORDER := ["cross", "chalice", "censer", "book"]
const GOLD := Color(0.98, 0.78, 0.38)
const DIM := Color(0.86, 0.8, 0.7, 0.28)
const STEP := 20.0
const ORIGIN := Vector2(14, 14)

var _state := {}
var _flash := {}
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for k in ORDER:
		_state[k] = 0
		_flash[k] = 0.0


# state: 0 not found, 1 carried, 2 on the altar
func set_state(kind: String, state: int) -> void:
	if _state.get(kind, 0) != state:
		_flash[kind] = 1.0
	_state[kind] = state


func _process(dt: float) -> void:
	_t += dt
	for k in ORDER:
		_flash[k] = maxf(0.0, _flash[k] - dt * 1.4)
	queue_redraw()


func _draw() -> void:
	for i in ORDER.size():
		var kind: String = ORDER[i]
		var c := ORIGIN + Vector2(i * STEP, 0)
		var st: int = _state[kind]
		var f: float = _flash[kind]
		var ink := DIM
		if st >= 1:
			var pulse := 0.85 + 0.15 * sin(_t * 3.0 + i)
			ink = GOLD * Color(pulse, pulse, pulse, 1.0)
		if st == 2:
			for r in [9.0, 7.0]:
				draw_circle(c, r, Color(GOLD, 0.06))
			draw_arc(c + Vector2(0, -1), 8.5, 0, TAU, 20, Color(GOLD, 0.35), 1.0)
		if f > 0.0:
			draw_circle(c, 6.0 + 6.0 * (1.0 - f), Color(1.0, 0.9, 0.6, 0.35 * f))
		_icon(kind, c, ink.lerp(Color(1, 1, 1), f * 0.6))


func _icon(kind: String, c: Vector2, ink: Color) -> void:
	match kind:
		"cross":
			draw_line(c + Vector2(0, -6), c + Vector2(0, 6), ink, 2.0)
			draw_line(c + Vector2(-4, -2), c + Vector2(4, -2), ink, 2.0)
		"chalice":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-5, -5), c + Vector2(5, -5), c + Vector2(3, -1), c + Vector2(-3, -1)]), ink)
			draw_line(c + Vector2(0, -1), c + Vector2(0, 4), ink, 1.0)
			draw_line(c + Vector2(-3, 5), c + Vector2(3, 5), ink, 2.0)
		"censer":
			draw_line(c + Vector2(0, -7), c + Vector2(0, -2), ink, 1.0)
			draw_arc(c + Vector2(0, -7), 1.5, 0, TAU, 8, ink, 1.0)
			draw_circle(c + Vector2(0, 2), 4.0, ink)
			draw_line(c + Vector2(-2, 6), c + Vector2(2, 6), ink, 1.0)
		"book":
			draw_rect(Rect2(c + Vector2(-5, -6), Vector2(10, 12)), ink, true)
			var paper := Color(0.12, 0.08, 0.06, ink.a)
			draw_line(c + Vector2(-3, -6), c + Vector2(-3, 6), paper, 1.0)
			draw_line(c + Vector2(0, -3), c + Vector2(0, 2), paper, 1.0)
			draw_line(c + Vector2(-2, -1), c + Vector2(2, -1), paper, 1.0)
