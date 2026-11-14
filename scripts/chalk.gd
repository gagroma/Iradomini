extends Node3D
# CHALK - drawing lines on the floor, closing them into circles, and THE RULE:
# the demon can never cross a closed line (GDD: "Pravilo kruga").
#
# Sources:
#  - GDD v6, sections "Mel" and "Pravilo kruga" (all numbers are in tuning.gd).
#  - Closing a line into an area is the idea of the arcade game Qix (1981).
#  - Geometry2D is Godot's built-in helper for "do two lines cross?" and
#    "is this point inside this shape?".
#
# A line is a list of points on the floor (Vector2: x and z in metres).
# While you hold the mouse it is a "stroke". If it comes back to its start, or
# crosses itself, it becomes a "loop" (a closed circle). If you let go before
# that, the chalk you used burns away.

const T = preload("res://scripts/tuning.gd")
const LINE_SHADER = preload("res://shaders/chalk_line.gdshader")
const LINE_Y := 0.012               # height above the floor (just enough not to flicker)

signal loop_closed(loop)
signal stroke_burned
signal altar_sealed

var nav
var chalk: float = T.CHALK_MAX           # metres of chalk left in your hand
var loops := []                     # every closed circle (each one is a Dictionary)
var stroke := PackedVector2Array()  # the line being drawn right now
var stroke_len := 0.0
var jitter := 0.0                   # 0..1 - the line shakes when the demon is near

var _next_id := 1
var _time := 0.0
var _stroke_node: MeshInstance3D
var _stroke_mesh := ImmediateMesh.new()
var _burns := []                    # burnt lines that are fading out
var _erase_id := -1
var _erase_t := 0.0
var _decor := PackedVector2Array()  # the old exorcist's unfinished circle
var _decor_node: MeshInstance3D
var _decor_mesh := ImmediateMesh.new()
var _decor_mat: ShaderMaterial
var _stroke_seed := 0.0             # every line gets its own grain and wobble
var _rng := RandomNumberGenerator.new()
var _decor_close := -1.0            # 0..1 while the ending closes the gap
var _altar_armed := false
const ALTAR_END_REACH := 0.20


func setup(nav_grid) -> void:
	nav = nav_grid
	_stroke_node = MeshInstance3D.new()
	_stroke_node.mesh = _stroke_mesh
	_stroke_node.material_override = _line_material(Color(0.8, 0.78, 0.7))
	add_child(_stroke_node)
	_rng.randomize()


# Chalk look: shaders/chalk_line.gdshader (ragged, grainy, streaky).
func _line_material(c: Color, line_seed: float = -1.0) -> ShaderMaterial:
	var m = ShaderMaterial.new()
	m.shader = LINE_SHADER
	m.set_shader_parameter("color", c)
	m.set_shader_parameter("seed", line_seed if line_seed >= 0.0 else _rng.randf() * 100.0)
	return m


func _set_line(mat: ShaderMaterial, c: Color, fade: float = 0.0) -> void:
	mat.set_shader_parameter("color", c)
	mat.set_shader_parameter("fade", fade)


# ------------------------------------------------------------------ DRAWING

# Called every frame while the left mouse button is held and you look at the floor.
func try_add_point(p: Vector2) -> void:
	if chalk <= 0.0:
		return
	if not nav.is_free(p):
		return                      # no drawing through walls and pews
	if stroke.is_empty():
		stroke.append(p)
		stroke_len = 0.0
		_stroke_seed = _rng.randf() * 100.0
		_stroke_node.material_override.set_shader_parameter("seed", _stroke_seed)
		return
	var last = stroke[stroke.size() - 1]
	var d = last.distance_to(p)
	if d < T.MIN_STEP:
		return                      # too close to the last point - wait
	if d > T.MAX_STEP:
		return                      # the aim jumped away - the line waits for you to come back
	if d > chalk:
		p = last + (p - last) / d * chalk
		d = chalk
	# Did this new piece cross an older piece of the same line? Then the part
	# between the crossing and here is a closed shape.
	var count = stroke.size()
	for i in range(count - 2):
		var hit = Geometry2D.segment_intersects_segment(stroke[i], stroke[i + 1], last, p)
		if hit != null:
			var poly = PackedVector2Array()
			poly.append(hit)
			for k in range(i + 1, count):
				poly.append(stroke[k])
			if _valid(poly):
				chalk -= d
				_finish_stroke(poly)
				return
			break                   # a tiny accidental crossing - keep drawing
	stroke.append(p)
	stroke_len += d
	chalk -= d
	if _altar_armed and _stroke_seals_altar():
		_altar_armed = false
		stroke.clear()
		stroke_len = 0.0
		_stroke_mesh.clear_surfaces()
		altar_sealed.emit()
		return
	# Did the line come back to where it started?
	if stroke_len >= T.MIN_LOOP_LENGTH and p.distance_to(stroke[0]) <= T.CLOSE_DISTANCE and _valid(stroke):
		_finish_stroke(stroke.duplicate())


# A shape only counts as a circle if it is big enough to stand in.
func _valid(poly: PackedVector2Array) -> bool:
	return poly.size() >= 3 and _area(poly) >= T.MIN_LOOP_AREA and _perimeter(poly) >= T.MIN_LOOP_LENGTH


# Called when the left mouse button is released.
func release() -> void:
	if stroke.size() >= 2:
		_burn(stroke.duplicate())   # GDD: an unclosed line burns away for nothing
		stroke_burned.emit()
	stroke.clear()
	stroke_len = 0.0
	_stroke_mesh.clear_surfaces()


func _finish_stroke(poly: PackedVector2Array) -> void:
	stroke.clear()
	stroke_len = 0.0
	_stroke_mesh.clear_surfaces()
	var loop = _make_loop(poly, false)
	loop_closed.emit(loop)


func _area(poly: PackedVector2Array) -> float:
	var sum = 0.0
	for i in range(poly.size()):
		var a = poly[i]
		var b = poly[(i + 1) % poly.size()]
		sum += a.x * b.y - b.x * a.y
	return absf(sum) * 0.5


func _perimeter(poly: PackedVector2Array) -> float:
	var sum = 0.0
	for i in range(poly.size()):
		sum += poly[i].distance_to(poly[(i + 1) % poly.size()])
	return sum


func _make_loop(poly: PackedVector2Array, permanent: bool) -> Dictionary:
	var rect = Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		rect = rect.expand(p)
	var line_seed = _stroke_seed if not permanent else 3.0
	var mat = _line_material(Color(1.0, 0.96, 0.82), line_seed)
	var mesh = ImmediateMesh.new()
	var node = MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	add_child(node)
	var loop = {
		"id": _next_id,
		"pts": poly,
		"length": _perimeter(poly),
		"rect": rect.grow(0.05),
		"node": node,
		"mesh": mesh,
		"mat": mat,
		"permanent": permanent,
		"flash": 1.0,       # bright for a moment when the circle closes
		"trap": 0.0,        # 0..1 gold glow after it banished the demon
		"seed": line_seed,
	}
	_next_id += 1
	if permanent:
		# the salt line at the door: only the piece across the doorway is visible
		fill_ribbon(mesh, PackedVector2Array([poly[0], poly[1]]), false, 0.14, 0.0, line_seed)
	else:
		fill_ribbon(mesh, poly, true, T.LINE_WIDTH * 1.2, 0.0, line_seed)
	loops.append(loop)
	nav.set_chalk(loops)
	return loop


# A circle that is part of the level and can never be erased (the salt threshold).
func add_permanent(poly: PackedVector2Array) -> void:
	_make_loop(poly, true)


func _remove_loop(loop: Dictionary) -> void:
	loop["node"].queue_free()
	for i in range(loops.size()):
		if loops[i]["id"] == loop["id"]:
			loops.remove_at(i)
			break
	nav.set_chalk(loops)


func _burn(pts: PackedVector2Array, line_seed: float = -1.0) -> void:
	if pts.size() < 2:
		return
	if line_seed < 0.0:
		line_seed = _stroke_seed
	var mat = _line_material(Color(1.0, 0.5, 0.15), line_seed)
	var mesh = ImmediateMesh.new()
	var node = MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	add_child(node)
	fill_ribbon(mesh, pts, false, T.LINE_WIDTH, 0.0, line_seed)
	_burns.append({"node": node, "mat": mat, "t": 0.6})


# Draw a line as a flat ribbon lying on the floor, the way a hand draws it:
# the points are smoothed into a curve, the hand presses harder and lighter
# along the way (width), trembles a little sideways, and an open stroke
# tapers where the chalk first touched and where it lifted off.
# Everything depends on the distance along the line, not on time, so a line
# keeps its look while it grows and after it closes.
static func fill_ribbon(mesh: ImmediateMesh, pts: PackedVector2Array, closed: bool, width: float, wobble := 0.0, line_seed := 0.0, time := 0.0, append := false) -> void:
	if not append:
		mesh.clear_surfaces()
	if pts.size() < 2:
		return
	var curve = _smooth(pts, closed, 3)
	var n = curve.size()
	var count = n + 1 if closed else n
	# distance along the line at every point
	var dist = PackedFloat32Array()
	dist.resize(count)
	dist[0] = 0.0
	for k in range(1, count):
		dist[k] = dist[k - 1] + curve[k % n].distance_to(curve[(k - 1) % n])
	var total = dist[count - 1]

	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for k in range(count):
		var i = k % n
		var prev = curve[(i - 1 + n) % n] if (closed or i > 0) else curve[i]
		var next = curve[(i + 1) % n] if (closed or i < n - 1) else curve[i]
		var dir = next - prev
		if dir.length() < 0.0001:
			dir = Vector2(1.0, 0.0)
		dir = dir.normalized()
		var normal = Vector2(-dir.y, dir.x)
		var s = dist[k]
		var pressure = 0.5 + 0.5 * (0.6 * sin(s * 2.3 + line_seed) + 0.4 * sin(s * 5.9 + line_seed * 1.7))
		var w = width * (0.78 + 0.32 * pressure)
		if not closed:
			w *= lerpf(0.35, 1.0, smoothstep(0.0, 0.06, s)) * lerpf(0.45, 1.0, smoothstep(0.0, 0.04, total - s))
		var tremor = 0.0035 * (sin(s * 11.0 + line_seed * 3.0) + 0.6 * sin(s * 26.0 + line_seed))
		var p = curve[i] + normal * tremor
		if wobble > 0.0:
			p += Vector2(sin(time * 31.0 + i * 1.7), cos(time * 27.0 + i * 2.3)) * wobble
		# the ribbon is wider than the chalk: the shader tears the edges
		var half = normal * (w * 0.5 / 0.62)
		mesh.surface_set_color(Color(pressure, 0.0, 0.0))
		mesh.surface_set_uv(Vector2(s, 0.0))
		mesh.surface_add_vertex(Vector3(p.x - half.x, LINE_Y, p.y - half.y))
		mesh.surface_set_color(Color(pressure, 0.0, 0.0))
		mesh.surface_set_uv(Vector2(s, 1.0))
		mesh.surface_add_vertex(Vector3(p.x + half.x, LINE_Y, p.y + half.y))
	mesh.surface_end()


# Catmull-Rom: a smooth curve through the points (the mouse gives a point
# every 6 cm, which would show as corners).
static func _smooth(pts: PackedVector2Array, closed: bool, steps: int) -> PackedVector2Array:
	var n = pts.size()
	if n < 3:
		return pts
	var out = PackedVector2Array()
	var segs = n if closed else n - 1
	for i in range(segs):
		var p0 = pts[(i - 1 + n) % n] if (closed or i > 0) else pts[i]
		var p1 = pts[i]
		var p2 = pts[(i + 1) % n]
		var p3 = pts[(i + 2) % n] if (closed or i + 2 < n) else p2
		for k in range(steps):
			var t = float(k) / steps
			var t2 = t * t
			var t3 = t2 * t
			out.append(0.5 * ((2.0 * p1) + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3))
	if not closed:
		out.append(pts[n - 1])
	return out


# ----------------------------------------------------------------- THE RULE

# True if a and b are on different sides of ANY closed circle.
# GDD: "if the player and the demon are on different sides of any circle,
# the demon cannot reach him".
func is_separated(a: Vector2, b: Vector2) -> bool:
	for loop in loops:
		var pts = loop["pts"]
		if Geometry2D.is_point_in_polygon(a, pts) != Geometry2D.is_point_in_polygon(b, pts):
			return true
	return false


# True if walking in a straight line from a to b would step over a closed line.
func segment_blocked(a: Vector2, b: Vector2) -> bool:
	var box = Rect2(a, Vector2.ZERO).expand(b).grow(0.05)
	for loop in loops:
		if not box.intersects(loop["rect"]):
			continue
		var pts = loop["pts"]
		var count = pts.size()
		for i in range(count):
			if Geometry2D.segment_intersects_segment(a, b, pts[i], pts[(i + 1) % count]) != null:
				return true
	return false


# The closest closed line and its nearest point, if it is within reach.
func closest_line(p: Vector2, within: float, threshold_range := INF) -> Dictionary:
	var best := {}
	var best_d = within
	for loop in loops:
		if not loop["rect"].grow(within).has_point(p):
			continue
		var pts = loop["pts"]
		var count = pts.size()
		var segs = count if not loop["permanent"] else 1
		var limit: float = threshold_range if loop["permanent"] else within
		for i in range(segs):
			var q = Geometry2D.get_closest_point_to_segment(p, pts[i], pts[(i + 1) % count])
			var d = q.distance_to(p)
			if d < minf(best_d, limit):
				best_d = d
				best = {"point": q, "permanent": loop["permanent"]}
	return best


# The player-made circle that p stands inside, or null.
func loop_containing(p: Vector2) -> Variant:
	for loop in loops:
		if loop["permanent"]:
			continue
		if Geometry2D.is_point_in_polygon(p, loop["pts"]):
			return loop
	return null


# The player-made circle you are aiming at (inside it or close to its line).
func loop_at(p: Vector2) -> Variant:
	for loop in loops:
		if loop["permanent"]:
			continue
		var pts = loop["pts"]
		if Geometry2D.is_point_in_polygon(p, pts):
			return loop
		var count = pts.size()
		for i in range(count):
			var near = Geometry2D.get_closest_point_to_segment(p, pts[i], pts[(i + 1) % count])
			if near.distance_to(p) < 0.35:
				return loop
	return null


# Chalk that is lying on the floor in your own circles.
func locked() -> float:
	var sum = 0.0
	for loop in loops:
		if not loop["permanent"]:
			sum += loop["length"]
	return sum


# ----------------------------------------------------------------- ERASING

# Hold the right mouse button on a circle. Returns progress 0..1.
func erase_tick(aim: Vector2, dt: float) -> float:
	var loop = loop_at(aim)
	if loop == null:
		erase_cancel()
		return 0.0
	if loop["id"] != _erase_id:
		_erase_id = loop["id"]
		_erase_t = 0.0
	_erase_t += dt
	if _erase_t >= T.ERASE_TIME:
		# GDD: an erased circle gives ALL its chalk back
		chalk = minf(T.CHALK_MAX, chalk + loop["length"])
		_remove_loop(loop)
		erase_cancel()
		return 1.0
	return _erase_t / T.ERASE_TIME


func erase_cancel() -> void:
	_erase_id = -1
	_erase_t = 0.0


# --------------------------------------------------------------- BANISHING

# The circle caught the demon: it blazes gold for a moment, then stays on the
# floor as an ordinary circle. Its chalk comes back only when you rub it out.
func on_banish(loop: Dictionary) -> void:
	loop["trap"] = 1.0
	loop["flash"] = 1.0


# ------------------------------------------------------- THE ALTAR'S CIRCLE

# The old exorcist's circle: a line with a gap. It blocks nothing.
func add_decor(pts: PackedVector2Array, staged := false) -> void:
	_decor = pts
	_decor_mat = _line_material(Color(0.7, 0.67, 0.58), 61.0)
	_decor_mat.set_shader_parameter("fade", 0.15)        # old, scuffed chalk
	_decor_node = MeshInstance3D.new()
	_decor_node.mesh = _decor_mesh
	_decor_node.material_override = _decor_mat
	add_child(_decor_node)
	if staged:
		show_altar_progress(0)
	else:
		fill_ribbon(_decor_mesh, _decor, false, T.LINE_WIDTH * 1.3, 0.0, 61.0)


func show_altar_progress(placed: int) -> void:
	_decor_mesh.clear_surfaces()
	var start := 0
	for i in range(placed + 1, T.RELICS_NEEDED):
		var gap := roundi(float(i) * (_decor.size() - 1) / T.RELICS_NEEDED)
		fill_ribbon(_decor_mesh, _decor.slice(start, gap - 2), false, T.LINE_WIDTH * 1.3, 0.0, 61.0, 0.0, true)
		start = gap + 3
	fill_ribbon(_decor_mesh, _decor.slice(start), false, T.LINE_WIDTH * 1.3, 0.0, 61.0, 0.0, true)


func prepare_altar_gap() -> void:
	_altar_armed = true
	chalk = maxf(chalk, _decor[0].distance_to(_decor[-1]) + 0.4)
	_set_line(_decor_mat, Color(1.0, 0.86, 0.58))


func is_near_altar_gap(aim: Vector2) -> bool:
	if not _altar_armed:
		return false
	var gap_point := Geometry2D.get_closest_point_to_segment(aim, _decor[0], _decor[-1])
	return gap_point.distance_to(aim) < 0.55


func _stroke_seals_altar() -> bool:
	var a := _decor[0]
	var b := _decor[-1]
	var start := stroke[0]
	var end := stroke[-1]
	var forward := start.distance_to(a) <= ALTAR_END_REACH and end.distance_to(b) <= ALTAR_END_REACH
	var reverse := start.distance_to(b) <= ALTAR_END_REACH and end.distance_to(a) <= ALTAR_END_REACH
	return (forward or reverse) and stroke_len <= a.distance_to(b) + 0.35


func close_decor() -> void:
	if _decor.size() >= 2:
		_decor_close = 0.0


func _process(dt: float) -> void:
	_time += dt

	# the line being drawn (shakes when the demon is close - looks only)
	if stroke.size() >= 2:
		fill_ribbon(_stroke_mesh, stroke, false, T.LINE_WIDTH, jitter * 0.025, _stroke_seed, _time)

	# closed circles: flash when new, blaze gold when they banish the demon
	for loop in loops:
		loop["flash"] = maxf(0.0, loop["flash"] - dt * 1.5)
		var col = Color(0.95, 0.9, 0.74)
		if loop["permanent"]:
			col = Color(0.9, 0.92, 1.0)
		loop["trap"] = maxf(0.0, loop["trap"] - dt * 0.4)     # the gold of a banishing fades
		var trap = loop["trap"]
		if trap > 0.0:
			var pulse = 0.5 + 0.5 * sin(_time * (4.0 + trap * 10.0))
			col = col.lerp(Color(1.0, 0.72, 0.15), 0.4 + 0.6 * trap)
			col = col.lerp(Color(1.0, 1.0, 0.9), pulse * 0.35)
		col = col.lerp(Color(1.6, 1.6, 1.5), loop["flash"])
		var fade = 0.0
		if loop["id"] == _erase_id:
			# rubbing it out: the chalk smears thinner and greyer
			var e = _erase_t / T.ERASE_TIME
			col = col.lerp(Color(0.45, 0.43, 0.4), e)
			fade = e * 0.85
		_set_line(loop["mat"], col, fade)

	# burnt lines fade from orange to nothing
	for i in range(_burns.size() - 1, -1, -1):
		var burn = _burns[i]
		burn["t"] -= dt
		var k = clampf(burn["t"] / 0.6, 0.0, 1.0)
		_set_line(burn["mat"], Color(1.0 * k, 0.45 * k * k, 0.1 * k * k), (1.0 - k) * 0.6)
		if burn["t"] <= 0.0:
			burn["node"].queue_free()
			_burns.remove_at(i)

	# chalk slowly comes back by itself, but only up to what is not lying on
	# the floor in your circles (rub them out to get that back at once)
	var room = T.CHALK_MAX - locked() - stroke_len - chalk
	if room > 0.0:
		chalk += minf(room, T.CHALK_MAX / T.CHALK_REGEN_TIME * dt)

	# ending animation of the altar circle
	if _decor_close >= 0.0 and _decor_close < 1.0:
		_decor_close = minf(1.0, _decor_close + dt / 3.0)
		var first = _decor[0]
		var last = _decor[_decor.size() - 1]
		var pts = _decor.duplicate()
		pts.append(last.lerp(first, _decor_close))
		fill_ribbon(_decor_mesh, pts, _decor_close >= 1.0, T.LINE_WIDTH * 1.5, 0.0, 61.0)
		_set_line(_decor_mat, Color(0.7, 0.67, 0.58).lerp(Color(1.4, 1.1, 0.5), _decor_close), 0.15 * (1.0 - _decor_close))
