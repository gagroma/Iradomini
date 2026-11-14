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

signal loop_closed(loop)
signal stroke_burned

var nav
var chalk: float = T.CHALK_MAX           # metres of chalk left in your hand
var loops := []                     # every closed circle (each one is a Dictionary)
var stroke := PackedVector2Array()  # the line being drawn right now
var stroke_len := 0.0
var regenerating := false           # true after a banishing, until the chalk is back
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
var _decor_mat: StandardMaterial3D
var _decor_close := -1.0            # 0..1 while the ending closes the gap


func setup(nav_grid) -> void:
	nav = nav_grid
	_stroke_node = MeshInstance3D.new()
	_stroke_node.mesh = _stroke_mesh
	_stroke_node.material_override = _line_material(Color(0.8, 0.78, 0.7))
	add_child(_stroke_node)


func _line_material(c: Color) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


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
	var mat = _line_material(Color(1.0, 0.96, 0.82))
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
		"trap": 0.0,        # 0..1 progress of a banishing inside this circle
	}
	_next_id += 1
	if permanent:
		# the salt line at the door: only the piece across the doorway is visible
		_fill_ribbon(mesh, PackedVector2Array([poly[0], poly[1]]), false, 0.14, 0.0)
	else:
		_fill_ribbon(mesh, poly, true, T.LINE_WIDTH * 1.2, 0.0)
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


func _burn(pts: PackedVector2Array) -> void:
	if pts.size() < 2:
		return
	var mat = _line_material(Color(1.0, 0.5, 0.15))
	var mesh = ImmediateMesh.new()
	var node = MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	add_child(node)
	_fill_ribbon(mesh, pts, false, T.LINE_WIDTH, 0.0)
	_burns.append({"node": node, "mat": mat, "t": 0.6})


# Draw a line as a flat ribbon lying on the floor.
func _fill_ribbon(mesh: ImmediateMesh, pts: PackedVector2Array, closed: bool, width: float, wobble: float) -> void:
	mesh.clear_surfaces()
	var n = pts.size()
	if n < 2:
		return
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var count = n
	if closed:
		count = n + 1
	for k in range(count):
		var i = k % n
		var prev = pts[i]
		var next = pts[i]
		if closed or i > 0:
			prev = pts[(i - 1 + n) % n]
		if closed or i < n - 1:
			next = pts[(i + 1) % n]
		var dir = next - prev
		if dir.length() < 0.0001:
			dir = Vector2(1.0, 0.0)
		dir = dir.normalized()
		# hand-drawn look: the width changes a little from point to point
		var w = width * (0.7 + 0.6 * absf(sin(float(i) * 12.9898)))
		var side = Vector2(-dir.y, dir.x) * w * 0.5
		var p = pts[i]
		if wobble > 0.0:
			p += Vector2(sin(_time * 31.0 + i * 1.7), cos(_time * 27.0 + i * 2.3)) * wobble
		mesh.surface_add_vertex(Vector3(p.x - side.x, 0.03, p.y - side.y))
		mesh.surface_add_vertex(Vector3(p.x + side.x, 0.03, p.y + side.y))
	mesh.surface_end()


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

# GDD: after a successful banishing the supply is emptied and comes back in 1 minute.
func on_banish(loop: Dictionary) -> void:
	_burn(loop["pts"])
	_remove_loop(loop)
	chalk = 0.0
	regenerating = true


# ------------------------------------------------------- THE ALTAR'S CIRCLE

# The old exorcist's circle: a line with a gap. It blocks nothing.
func add_decor(pts: PackedVector2Array) -> void:
	_decor = pts
	_decor_mat = _line_material(Color(0.5, 0.48, 0.42))
	_decor_node = MeshInstance3D.new()
	_decor_node.mesh = _decor_mesh
	_decor_node.material_override = _decor_mat
	add_child(_decor_node)
	_fill_ribbon(_decor_mesh, _decor, false, T.LINE_WIDTH * 1.3, 0.0)


# The ending: the gap closes by itself. The circle is full.
func close_decor() -> void:
	if _decor.size() >= 2:
		_decor_close = 0.0


func _process(dt: float) -> void:
	_time += dt

	# the line being drawn (shakes when the demon is close - looks only)
	if stroke.size() >= 2:
		_fill_ribbon(_stroke_mesh, stroke, false, T.LINE_WIDTH, jitter * 0.025)

	# closed circles: flash when new, turn gold while they hold the demon
	for loop in loops:
		loop["flash"] = maxf(0.0, loop["flash"] - dt * 1.5)
		var col = Color(0.95, 0.9, 0.74)
		if loop["permanent"]:
			col = Color(0.9, 0.92, 1.0)
		var trap = loop["trap"]
		if trap > 0.0:
			var pulse = 0.5 + 0.5 * sin(_time * (4.0 + trap * 10.0))
			col = col.lerp(Color(1.0, 0.72, 0.15), 0.4 + 0.6 * trap)
			col = col.lerp(Color(1.0, 1.0, 0.9), pulse * 0.35)
		col = col.lerp(Color(1.6, 1.6, 1.5), loop["flash"])
		if loop["id"] == _erase_id:
			col = col.lerp(Color(0.12, 0.11, 0.1), _erase_t / T.ERASE_TIME)
		loop["mat"].albedo_color = col

	# burnt lines fade from orange to nothing
	for i in range(_burns.size() - 1, -1, -1):
		var burn = _burns[i]
		burn["t"] -= dt
		var k = clampf(burn["t"] / 0.6, 0.0, 1.0)
		burn["mat"].albedo_color = Color(1.0 * k, 0.45 * k * k, 0.1 * k * k)
		if burn["t"] <= 0.0:
			burn["node"].queue_free()
			_burns.remove_at(i)

	# chalk growing back after a banishing
	if regenerating:
		chalk += T.CHALK_MAX / T.CHALK_REGEN_TIME * dt
		if chalk + locked() >= T.CHALK_MAX:
			chalk = maxf(0.0, T.CHALK_MAX - locked())
			regenerating = false

	# ending animation of the altar circle
	if _decor_close >= 0.0 and _decor_close < 1.0:
		_decor_close = minf(1.0, _decor_close + dt / 3.0)
		var first = _decor[0]
		var last = _decor[_decor.size() - 1]
		var pts = _decor.duplicate()
		pts.append(last.lerp(first, _decor_close))
		_fill_ribbon(_decor_mesh, pts, _decor_close >= 1.0, T.LINE_WIDTH * 1.5, 0.0)
		_decor_mat.albedo_color = Color(0.5, 0.48, 0.42).lerp(Color(1.4, 1.1, 0.5), _decor_close)
