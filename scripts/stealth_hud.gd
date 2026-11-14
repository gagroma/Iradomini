extends Control
# STEALTH HUD - makes hiding, being heard and being seen readable.
# A small pixel eye at the top of the screen with sound arcs either side:
#   the eye is the demon's attention -
#     closed           it has no idea where you are
#     half open, amber it heard something and is coming to look
#     wide open, red   it sees you
#   the arcs are your footsteps - one per step, more arcs = heard further
#     (crouch 1, walk 2, run 4, more with each relic); they flash red when
#     the step reached the demon's ears.
# Under it, one word about you: crouched with no cover near, or hidden.
# It fades in only when there is something to tell, and out again.
# Drawn with Control._draw() at the game's 480x270, so lines stay pixel-sharp.

const CENTRE := Vector2(240, 14)
const PALE := Color(0.9, 0.86, 0.74)
const AMBER := Color(1.0, 0.68, 0.18)
const RED := Color(1.0, 0.16, 0.1)
const GREEN := Color(0.66, 0.9, 0.7)
const T_RECOVER := 0.4      # tuning.gd STAMINA_RECOVER: where running comes back

var awareness := 0          # 0 unaware, 1 heard something, 2 sees you
var crouching := false
var is_hidden := false
var stamina := 1.0          # 0..1
var winded := false

var _open := 0.12           # how open the eye is drawn (follows awareness)
var _alpha := 0.0
var _flash := 0.0           # the eye flares when the demon becomes more aware
var _time := 0.0
var _rings := []            # footsteps: {arcs, t, heard}
var _label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label = Label.new()
	_label.position = Vector2(0, 24)
	_label.size = Vector2(480, 12)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 8)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_label.add_theme_constant_override("outline_size", 3)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)


func set_state(new_awareness: int, is_crouching: bool, is_hidden_now: bool) -> void:
	if new_awareness > awareness:
		_flash = 1.0
	awareness = new_awareness
	crouching = is_crouching
	is_hidden = is_hidden_now


# One footstep: arcs = how far it carries, heard = it reached the demon.
func step(arcs: int, heard: bool) -> void:
	_rings.append({"arcs": arcs, "t": 0.0, "heard": heard})


func _process(dt: float) -> void:
	_time += dt
	_flash = maxf(0.0, _flash - dt * 2.0)
	var want_open = [0.12, 0.55, 1.0][awareness]
	_open = move_toward(_open, want_open, dt * 3.0)
	for r in _rings:
		r["t"] += dt
	_rings = _rings.filter(func(r): return r["t"] < 0.9)
	var show = crouching or awareness > 0 or not _rings.is_empty() or _flash > 0.0 or stamina < 0.999
	_alpha = move_toward(_alpha, 1.0 if show else 0.0, dt * (4.0 if show else 1.2))
	modulate.a = _alpha

	if is_hidden:
		_label.text = "HIDDEN"
		_label.add_theme_color_override("font_color", GREEN)
	elif crouching:
		_label.text = "Crouching  ·  No cover nearby"
		_label.add_theme_color_override("font_color", PALE * Color(1, 1, 1, 0.8))
	else:
		_label.text = ""
	queue_redraw()


func set_stamina(amount: float, is_winded: bool) -> void:
	stamina = clampf(amount, 0.0, 1.0)
	winded = is_winded


func _eye_colour() -> Color:
	var c = [PALE * Color(1, 1, 1, 0.55), AMBER, RED][awareness]
	if awareness == 2:
		c = c.lerp(Color(1, 0.6, 0.5), 0.3 + 0.3 * sin(_time * 10.0))
	return c.lerp(Color(1, 1, 1), _flash * 0.6)


func _draw() -> void:
	# footstep arcs, left and right of the eye
	for r in _rings:
		var k = 1.0 - r["t"] / 0.9
		var col = (RED if r["heard"] else PALE)
		col.a = k * (0.9 if r["heard"] else 0.6)
		for i in range(r["arcs"]):
			var rad = 15.0 + i * 4.0 + r["t"] * 6.0
			draw_arc(CENTRE, rad, deg_to_rad(150), deg_to_rad(210), 6, col, 1.0, false)
			draw_arc(CENTRE, rad, deg_to_rad(-30), deg_to_rad(30), 6, col, 1.0, false)

	# stamina: a thin bar under the eye, red while you are out of breath
	if stamina < 0.999:
		var bar = Rect2(CENTRE + Vector2(-20, 9), Vector2(40, 2))
		draw_rect(bar, Color(0, 0, 0, 0.6))
		var c = RED if winded else PALE
		draw_rect(Rect2(bar.position, Vector2(40.0 * stamina, 2)), c)
		if winded:
			draw_rect(Rect2(bar.position + Vector2(40.0 * T_RECOVER, -1), Vector2(1, 4)), PALE * Color(1, 1, 1, 0.6))

	# the eye: two lids, and an iris when open
	var w = 11.0
	var h = 6.0 * _open
	var col_e = _eye_colour()
	var upper = PackedVector2Array()
	var lower = PackedVector2Array()
	for i in range(13):
		var t = float(i) / 12.0
		var x = lerpf(-w, w, t)
		var y = sin(t * PI) * h
		upper.append(CENTRE + Vector2(x, -y))
		lower.append(CENTRE + Vector2(x, y * 0.8))
	draw_polyline(upper, col_e, 1.0, false)
	draw_polyline(lower, col_e, 1.0, false)
	if _open > 0.3:
		var iris = 3.2 * _open
		draw_circle(CENTRE + Vector2(0, -0.5), iris, col_e)
		draw_circle(CENTRE + Vector2(0, -0.5), iris * 0.45, Color(0.05, 0.02, 0.02, col_e.a))
	else:
		# closed: lashes hanging from the lid
		for x in [-6.0, -2.0, 2.0, 6.0]:
			draw_line(CENTRE + Vector2(x, 1), CENTRE + Vector2(x * 1.15, 4), col_e, 1.0, false)
