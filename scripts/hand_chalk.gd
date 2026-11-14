extends MeshInstance3D
# HAND CHALK - the stick of chalk in your right hand.
# GDD "Zapas bez interfeisa": there is no chalk meter, you see how much is
# left by how long the stick is.
#
# How real chalk wears: you hold it at an angle, so the end that rubs on the
# floor wears into a slanted face, with crumbly chips at its edge, while the
# upper side stays longer. The end in your fingers stays where it is and gets
# grey from them. Here the stick is rebuilt as it gets shorter: the worn face
# keeps its slant, but its chips change with every millimetre used, so it
# wears unevenly instead of shrinking like a ruler.
#
# The stick lies along -Z: the end in your fingers at Z = 0, the tip at -Z.

const LENGTH := 0.09         # a fresh stick, metres
const RADIUS := 0.0068
const SIDES := 18
const RINGS := 12
const TIP_RINGS := 4
const SLANT := 0.85          # how steep the worn face is (tan of its angle)
const WEAR_DIR := -PI / 2.0  # the side that rubs the floor (local -Y, underneath)

const BODY := Color(0.9, 0.87, 0.79)
const FRESH := Color(0.98, 0.97, 0.93)   # just-worn chalk is whiter
const GRIP := Color(0.66, 0.64, 0.61)    # grey from your fingers

var _noise := FastNoiseLite.new()
var _built_len := -1.0


func _ready() -> void:
	_noise.seed = 4242
	_noise.frequency = 1.0
	var m = StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	# a little glow of its own so it stays readable in the dark
	m.emission_enabled = true
	m.emission = Color(0.22, 0.21, 0.19)
	material_override = m
	if mesh == null:
		set_left(1.0)


# left: 1 = fresh stick, 0 = nothing in your hand.
func set_left(left: float) -> void:
	visible = left > 0.005
	var length = maxf(SLANT * RADIUS + 0.004, LENGTH * clampf(left, 0.0, 1.0))
	if absf(length - _built_len) < 0.0005:
		return
	_built_len = length
	mesh = _build(length)


# Seamless noise around the stick: angle a, and a third coordinate.
func _n(a: float, scale: float, w: float) -> float:
	return _noise.get_noise_3d(cos(a) * scale, sin(a) * scale, w)


# The stick is hand-pressed: not perfectly round.
func _radius(a: float, d: float) -> float:
	return RADIUS * (1.0 + 0.06 * _n(a, 1.3, d * 30.0))


# How far from your fingers the chalk reaches at angle a and fraction rho of
# the radius (1 = the outer edge): the slanted, chipped, slightly domed face.
func _tip(a: float, rho: float, length: float) -> float:
	# you never hold it at quite the same angle: the slant drifts as it wears
	var slant = SLANT * (1.0 + 0.35 * _noise.get_noise_1d(length * 45.0))
	var facing = cos(a - WEAR_DIR)          # 1 = the side that rubs the floor
	var slope = -slant * RADIUS * rho * facing
	# the face is rubbed into a soft curve, not a flat cut
	var dome = -0.35 * RADIUS * rho * rho
	var chips = RADIUS * rho * (0.5 * _n(a, 1.6, length * 220.0) + 0.3 * _n(a, 4.5, length * 520.0 + 9.0))
	# the long thin point on the upper side crumbles off in bites
	var bite = maxf(0.0, _n(a, 2.2, length * 160.0 + 31.0)) * smoothstep(0.2, 1.0, -facing)
	return maxf(0.003, length + slope + dome + chips - RADIUS * 1.1 * bite * rho)


func _build(length: float) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var angles = []
	for j in range(SIDES):
		angles.append(TAU * j / SIDES)

	# the side, from your fingers to the worn edge
	var side = []
	for j in range(SIDES):
		var a = angles[j]
		var edge = _tip(a, 1.0, length)
		var col = []
		for k in range(RINGS + 1):
			var t = float(k) / RINGS
			var d = edge * t
			var r = _radius(a, d)
			if k == RINGS:
				r = _radius(a, edge) * 0.96          # the worn edge is a bit rounded off
			var c = BODY.lerp(GRIP, (1.0 - smoothstep(0.0, 0.03, d)) * (0.6 + 0.4 * _n(a, 2.0, d * 80.0)))
			c = c.darkened(0.06 * (0.5 + 0.5 * _n(a, 6.0, d * 400.0)))
			col.append([Vector3(cos(a) * r, sin(a) * r, -d), c])
		side.append(col)
	for j in range(SIDES):
		var j2 = (j + 1) % SIDES
		for k in range(RINGS):
			_quad(st, side[j][k], side[j2][k], side[j2][k + 1], side[j][k + 1])

	# the worn face: rings from the edge in to the middle
	var face = []
	for j in range(SIDES):
		var a = angles[j]
		var col = [side[j][RINGS]]
		for k in range(1, TIP_RINGS + 1):
			var rho = 1.0 - float(k) / TIP_RINGS
			var r = _radius(a, length) * 0.96 * rho
			var c = FRESH.darkened(0.05 * (0.5 + 0.5 * _n(a, 3.0, rho * 7.0 + length * 300.0)))
			col.append([Vector3(cos(a) * r, sin(a) * r, -_tip(a, rho, length)), c])
		col[0] = [col[0][0], FRESH]
		face.append(col)
	for j in range(SIDES):
		var j2 = (j + 1) % SIDES
		for k in range(TIP_RINGS):
			_quad(st, face[j][k], face[j2][k], face[j2][k + 1], face[j][k + 1])

	# the end in your fingers: flat
	var back_c = [Vector3.ZERO, GRIP]
	for j in range(SIDES):
		var j2 = (j + 1) % SIDES
		_tri(st, back_c, [side[j][0][0], GRIP], [side[j2][0][0], GRIP])

	st.index()
	st.generate_normals()
	return st.commit()


func _tri(st: SurfaceTool, a: Array, b: Array, c: Array) -> void:
	for v in [a, b, c]:
		st.set_color(v[1])
		st.add_vertex(v[0])


func _quad(st: SurfaceTool, a: Array, b: Array, c: Array, d: Array) -> void:
	_tri(st, a, b, c)
	_tri(st, a, c, d)
