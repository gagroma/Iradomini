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
var light_dir := Vector3(0.35, 1.0, 0.45).normalized()
var rng := RandomNumberGenerator.new()

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
	var d = n.dot(light_dir) + rng.randfn(0.0, 0.07)
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
	var q = p - _pivot
	var r = rng.randf()
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
