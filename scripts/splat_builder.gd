extends RefCounted
# SPLAT BUILDER - makes "pixel splat" models out of simple shapes.
# Source: a GDScript port of gen.py, the Python script that built the first
# two demon models (Wailer and Crawler). The recipe is the same:
#   1. describe the model with simple shapes (balls, tubes, rings, boxes)
#   2. scatter random points over the surface of each shape
#   3. give every point ONE flat colour from a short palette ("ramp"),
#      darker where the surface faces away from a pretend light
#   4. turn every point into a tiny flat square
# Rendered at 480x270 the squares read as pixel art.

var density := 4200.0     # squares per square metre of surface
var quad := 0.028         # size of one square, in metres
var shade_noise := 0.07
var layer_offset := 0.0
var light_dir := Vector3(0.35, 1.0, 0.45).normalized()
var rng := RandomNumberGenerator.new()
var solid := false
var metal := 0.0

var _verts := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()
var _uvs := PackedVector2Array()
var _indices := PackedInt32Array()
var _pivot := Vector3.ZERO


func _init(seed_value: int = 1) -> void:
	rng.seed = seed_value


# Points are stored relative to the pivot, so a limb can rotate around its joint.
func set_pivot(p: Vector3) -> void:
	_pivot = p


# Palette helper: ["120d18", "2e2136"] -> [Color, Color] (dark to light).
static func ramp(hex_list: Array) -> Array:
	var out = []
	for h in hex_list:
		out.append(Color.html(str(h)))
	return out


func _unit() -> Vector3:
	var v = Vector3(rng.randfn(), rng.randfn(), rng.randfn())
	if v.length() < 0.0001:
		return Vector3.UP
	return v.normalized()


# Pick a palette colour from how much the surface faces the light.
func _shade(p: Vector3, n: Vector3, colors: Array) -> Color:
	if colors.size() == 1:
		return colors[0]
	var d = n.dot(light_dir) + (rng.randfn(0.0, shade_noise) if shade_noise > 0.0 else 0.0)
	d -= clampf(0.25 - p.y, 0.0, 1.0) * 0.8    # darker close to the floor
	var steps = colors.size() - 1
	var idx = 0
	for k in range(steps):
		var threshold = -0.25 + float(k) / float(max(steps - 1, 1))
		if d > threshold:
			idx = k + 1
	return colors[idx]


func _add(p: Vector3, n: Vector3, colors: Array) -> void:
	if n.length() < 0.0001:
		n = Vector3.UP
	n = n.normalized()
	var col = _shade(p, n, colors)
	var t = n.cross(Vector3.UP)
	if t.length() < 0.01:
		t = n.cross(Vector3.RIGHT)
	t = t.normalized()
	var b = n.cross(t)
	var ang = rng.randf() * TAU
	var half = quad * 0.5
	var t2 = (t * cos(ang) + b * sin(ang)) * half
	var b2 = (b * cos(ang) - t * sin(ang)) * half
	var first = _verts.size()
	var r = rng.randf()
	var q = p - _pivot + n * r * layer_offset
	_verts.append(q - t2 - b2)
	_verts.append(q + t2 - b2)
	_verts.append(q + t2 + b2)
	_verts.append(q - t2 + b2)
	for k in range(4):
		_normals.append(n)
		_colors.append(col)
		_uvs.append(Vector2(r, 0.0))
	_indices.append(first)
	_indices.append(first + 1)
	_indices.append(first + 2)
	_indices.append(first)
	_indices.append(first + 2)
	_indices.append(first + 3)


# A ball, or a squashed ball. c = centre, r = radius along x, y and z.
func ellipsoid(c: Vector3, r: Vector3, colors: Array) -> void:
	if solid:
		_solid_ellipsoid(c, r, colors)
		return
	var e = 1.6
	var area = 4.0 * PI * pow((pow(r.x * r.y, e) + pow(r.x * r.z, e) + pow(r.y * r.z, e)) / 3.0, 1.0 / e)
	var count = int(area * density) + 8
	for k in range(count):
		var u = _unit()
		_add(c + u * r, u / r, colors)


# A tube from a to b that can get thinner (radius r0 at a, r1 at b).
func capsule(a: Vector3, b: Vector3, r0: float, r1: float, colors: Array, ends: bool = true) -> void:
	var axis = b - a
	var seg_len = axis.length()
	if seg_len < 0.0001:
		return
	axis = axis / seg_len
	if solid:
		_solid_tube(a, b, r0, r1, colors)
		if ends:
			_solid_ellipsoid(a, Vector3(r0, r0, r0), colors)
			_solid_ellipsoid(b, Vector3(r1, r1, r1), colors)
		return
	var t0 = axis.cross(Vector3.UP)
	if t0.length() < 0.001:
		t0 = axis.cross(Vector3.RIGHT)
	t0 = t0.normalized()
	var t1 = axis.cross(t0)
	var count = int(PI * (r0 + r1) * seg_len * density) + 6
	for k in range(count):
		var along = rng.randf()
		var th = rng.randf() * TAU
		var rad = t0 * cos(th) + t1 * sin(th)
		_add(a + axis * (along * seg_len) + rad * lerpf(r0, r1, along), rad, colors)
	if ends:
		ellipsoid(a, Vector3(r0, r0, r0), colors)
		ellipsoid(b, Vector3(r1, r1, r1), colors)


# Several tubes joined end to end (an arm, a horn, a tail).
func chain(points: Array, r0: float, r1: float, colors: Array) -> void:
	var m = points.size() - 1
	for i in range(m):
		var ra = lerpf(r0, r1, float(i) / float(m))
		var rb = lerpf(r0, r1, float(i + 1) / float(m))
		capsule(points[i], points[i + 1], ra, rb, colors)


# A ring, or part of a ring (a0..a1 in radians). Used for ribs and the halo.
func torus(c: Vector3, axis: Vector3, big_r: float, small_r: float, a0: float, a1: float, colors: Array) -> void:
	axis = axis.normalized()
	var t0 = axis.cross(Vector3.BACK)
	if t0.length() < 0.001:
		t0 = axis.cross(Vector3.RIGHT)
	t0 = t0.normalized()
	var t1 = axis.cross(t0)
	if solid:
		_solid_torus(c, axis, t0, t1, big_r, small_r, a0, a1, colors)
		return
	var count = int((a1 - a0) * big_r * TAU * small_r * density) + 10
	for k in range(count):
		var a = a0 + rng.randf() * (a1 - a0)
		var b = rng.randf() * TAU
		var ring = t0 * cos(a) + t1 * sin(a)
		var nn = ring * cos(b) + axis * sin(b)
		_add(c + ring * big_r + nn * small_r, nn, colors)


# A box. c = centre, size = full width, height and depth.
func box(c: Vector3, size: Vector3, colors: Array) -> void:
	var h = size * 0.5
	if solid:
		_solid_box(c, h, colors)
		return
	var areas = [size.y * size.z, size.x * size.z, size.x * size.y]
	for axis in range(3):
		var count = int(areas[axis] * density) + 2
		for side in [-1.0, 1.0]:
			for k in range(count):
				var p = Vector3(rng.randf_range(-h.x, h.x), rng.randf_range(-h.y, h.y), rng.randf_range(-h.z, h.z))
				var n = Vector3.ZERO
				p[axis] = h[axis] * side
				n[axis] = side
				_add(c + p, n, colors)


func lathe(c: Vector3, profile: Array, colors: Array, segments := 28) -> void:
	var col := _solid_color(colors)
	var rows := []
	for pt in profile:
		var row := []
		for k in segments + 1:
			var a := TAU * k / segments
			row.append(c + Vector3(cos(a) * pt.x, pt.y, sin(a) * pt.x))
		rows.append(row)
	for i in profile.size() - 1:
		var d: Vector2 = profile[i + 1] - profile[i]
		var n2 := Vector2(d.y, -d.x).normalized()
		for k in segments:
			var a0 := TAU * k / segments
			var a1 := TAU * (k + 1) / segments
			var na := Vector3(cos(a0) * n2.x, n2.y, sin(a0) * n2.x)
			var nb := Vector3(cos(a1) * n2.x, n2.y, sin(a1) * n2.x)
			_quad_s(rows[i][k], rows[i][k + 1], rows[i + 1][k + 1], rows[i + 1][k], na, nb, nb, na, col)


func _solid_color(colors: Array) -> Color:
	return colors[mini(colors.size() - 1, colors.size() * 2 / 3)]


func _vert_s(p: Vector3, n: Vector3, col: Color) -> int:
	var shade := 1.0 - clampf(0.25 - p.y, 0.0, 1.0) * 1.2
	_verts.append(p - _pivot)
	_normals.append(n.normalized())
	_colors.append(Color(col.r * shade, col.g * shade, col.b * shade, 1.0))
	_uvs.append(Vector2(rng.randf(), metal))
	return _verts.size() - 1


func _quad_s(a: Vector3, b: Vector3, c: Vector3, d: Vector3, na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3, col: Color) -> void:
	var i0 := _vert_s(a, na, col)
	var i1 := _vert_s(b, nb, col)
	var i2 := _vert_s(c, nc, col)
	var i3 := _vert_s(d, nd, col)
	var face := (b - a).cross(d - a)
	if face.dot(na + nb + nc + nd) >= 0.0:
		_indices.append_array([i0, i2, i1, i0, i3, i2])
	else:
		_indices.append_array([i0, i1, i2, i0, i2, i3])


func _solid_ellipsoid(c: Vector3, r: Vector3, colors: Array) -> void:
	var col := _solid_color(colors)
	var rings := 12
	var segs := 20
	var pts := []
	var nrm := []
	for i in rings + 1:
		var th := PI * i / rings
		var rowp := []
		var rown := []
		for k in segs + 1:
			var ph := TAU * k / segs
			var u := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
			rowp.append(c + u * r)
			rown.append(u / r)
		pts.append(rowp)
		nrm.append(rown)
	for i in rings:
		for k in segs:
			_quad_s(pts[i][k], pts[i][k + 1], pts[i + 1][k + 1], pts[i + 1][k], nrm[i][k], nrm[i][k + 1], nrm[i + 1][k + 1], nrm[i + 1][k], col)


func _frame(axis: Vector3) -> Array:
	var t0 := axis.cross(Vector3.UP)
	if t0.length() < 0.001:
		t0 = axis.cross(Vector3.RIGHT)
	t0 = t0.normalized()
	return [t0, axis.cross(t0)]


func _solid_tube(a: Vector3, b: Vector3, r0: float, r1: float, colors: Array) -> void:
	var col := _solid_color(colors)
	var axis := (b - a).normalized()
	var f := _frame(axis)
	var segs := 16
	var slope := (r0 - r1) / maxf(a.distance_to(b), 0.0001)
	for k in segs:
		var a0 := TAU * k / segs
		var a1 := TAU * (k + 1) / segs
		var d0: Vector3 = f[0] * cos(a0) + f[1] * sin(a0)
		var d1: Vector3 = f[0] * cos(a1) + f[1] * sin(a1)
		var n0 := d0 + axis * slope
		var n1 := d1 + axis * slope
		_quad_s(a + d0 * r0, a + d1 * r0, b + d1 * r1, b + d0 * r1, n0, n1, n1, n0, col)


func _solid_torus(c: Vector3, axis: Vector3, t0: Vector3, t1: Vector3, big_r: float, small_r: float, a0: float, a1: float, colors: Array) -> void:
	var col := _solid_color(colors)
	var big := maxi(6, int(28.0 * (a1 - a0) / TAU) + 2)
	var small := 10
	for i in big:
		var u0 := a0 + (a1 - a0) * i / big
		var u1 := a0 + (a1 - a0) * (i + 1) / big
		var ring0 := t0 * cos(u0) + t1 * sin(u0)
		var ring1 := t0 * cos(u1) + t1 * sin(u1)
		for k in small:
			var v0 := TAU * k / small
			var v1 := TAU * (k + 1) / small
			var n00 := ring0 * cos(v0) + axis * sin(v0)
			var n01 := ring0 * cos(v1) + axis * sin(v1)
			var n10 := ring1 * cos(v0) + axis * sin(v0)
			var n11 := ring1 * cos(v1) + axis * sin(v1)
			_quad_s(c + ring0 * big_r + n00 * small_r, c + ring1 * big_r + n10 * small_r, c + ring1 * big_r + n11 * small_r, c + ring0 * big_r + n01 * small_r, n00, n10, n11, n01, col)


func _solid_box(c: Vector3, h: Vector3, colors: Array) -> void:
	var col := _solid_color(colors)
	for axis in 3:
		for side in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[axis] = side
			var u := Vector3.ZERO
			var v := Vector3.ZERO
			u[(axis + 1) % 3] = h[(axis + 1) % 3]
			v[(axis + 2) % 3] = h[(axis + 2) % 3]
			var o := c + n * h[axis]
			_quad_s(o - u - v, o + u - v, o + u + v, o - u + v, n, n, n, n, col)


func is_empty() -> bool:
	return _verts.is_empty()


# Finish: pack everything into one mesh that Godot can draw.
func build() -> ArrayMesh:
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_INDEX] = _indices
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
