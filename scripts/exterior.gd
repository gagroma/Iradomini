extends Node3D

const GROUND_SHADER = preload("res://shaders/exterior_ground.gdshader")
const STONE = preload("res://materials/kit/kit_stone.tres")
const WALL = preload("res://assets/kit/wall_2m.glb")
const PILASTER = preload("res://assets/kit/pilaster.glb")
const LANTERN = preload("res://assets/props/lantern.glb")
const OUTSIDE_LAYER := 1 << 18
const ROAD_LENGTH := 22.0

var _rng := RandomNumberGenerator.new()
var _out := Vector3.ZERO
var _side := Vector3.ZERO
var _door := Vector3.ZERO


func build(door: Vector3, out: Vector3, seed_value: int) -> void:
	_rng.seed = seed_value
	_door = Vector3(door.x, 0.0, door.z)
	_out = out.normalized()
	_side = Vector3.UP.cross(_out)
	_ground()
	_facade()
	_lanterns()
	_graves()
	_moon()
	for v in find_children("*", "VisualInstance3D", true, false):
		v.layers = 1 | OUTSIDE_LAYER


func _basis() -> Basis:
	return Basis(_side, Vector3.UP, _out)


func _at(lateral: float, outward: float, up: float = 0.0) -> Vector3:
	return _door + _side * lateral + _out * outward + Vector3.UP * up


func _ground() -> void:
	var mesh = PlaneMesh.new()
	mesh.size = Vector2(44.0, 34.0)
	mesh.subdivide_width = 22
	mesh.subdivide_depth = 17
	var mat = ShaderMaterial.new()
	mat.shader = GROUND_SHADER
	mat.set_shader_parameter("road_start", Vector2(_door.x, _door.z))
	mat.set_shader_parameter("road_dir", Vector2(_out.x, _out.z))
	mat.set_shader_parameter("road_length", ROAD_LENGTH)
	var g = MeshInstance3D.new()
	g.mesh = mesh
	g.material_override = mat
	add_child(g)
	g.global_transform = Transform3D(_basis(), _at(0.0, 17.0 + 0.3, -0.005))
	for s in [-1.0, 1.0]:
		var o = 0.6
		while o < ROAD_LENGTH - 3.0:
			if _rng.randf() < 0.55:
				var w = _rng.randf_range(0.14, 0.26)
				_box(Vector3(w, _rng.randf_range(0.05, 0.1), _rng.randf_range(0.22, 0.4)),
					Transform3D(Basis(Vector3.UP, _rng.randf_range(-0.2, 0.2)) * _basis(), _at(s * (1.32 + _rng.randf_range(-0.05, 0.08)), o, 0.0)), STONE)
			o += _rng.randf_range(0.3, 0.55)


func _facade() -> void:
	var b = _basis()
	for row in range(3):
		for col in range(-4, 5):
			if row == 0 and col == 0:
				continue
			if row == 2 and absi(col) > 1:
				continue
			var w = WALL.instantiate()
			add_child(w)
			w.global_transform = Transform3D(b, _at(col * 2.0, 0.62, row * 4.5))
	for col in [-9.0, -5.0, -1.4, 1.4, 5.0, 9.0]:
		var rows = 3 if absf(col) < 2.0 else 2
		for row in range(rows):
			var p = PILASTER.instantiate()
			add_child(p)
			p.global_transform = Transform3D(b, _at(col, 1.0, row * 4.5))
	_box(Vector3(3.6, 0.35, 0.8), Transform3D(b, _at(0.0, 1.05, 4.6)), STONE)
	_box(Vector3(19.0, 0.3, 0.5), Transform3D(b, _at(0.0, 1.0, 9.05)), STONE)
	_box(Vector3(2.4, 0.06, 0.9), Transform3D(b, _at(0.0, 0.45, 0.03)), STONE)


func _lanterns() -> void:
	for s in [-1.0, 1.0]:
		var at = _at(s * 2.3, 1.15, 2.55)
		var l = LANTERN.instantiate()
		add_child(l)
		l.global_transform = Transform3D(_basis(), at)
		var light = OmniLight3D.new()
		light.light_color = Color(1.0, 0.62, 0.32)
		light.light_energy = 1.1
		light.omni_range = 4.5
		light.omni_attenuation = 1.6
		add_child(light)
		light.global_position = at + _out * 0.15 + Vector3(0, 0.15, 0)


func _graves() -> void:
	var placed := []
	var tries = 0
	while placed.size() < 26 and tries < 400:
		tries += 1
		var s = -1.0 if _rng.randf() < 0.5 else 1.0
		var lat = s * _rng.randf_range(2.6, 9.0)
		var o = _rng.randf_range(2.5, 17.0)
		var p = Vector2(lat, o)
		var ok = true
		for q in placed:
			if q.distance_to(p) < 1.3:
				ok = false
				break
		if not ok:
			continue
		placed.append(p)
		var tilt = Basis(_out, _rng.randf_range(-0.12, 0.12)) * Basis(_side, _rng.randf_range(-0.15, 0.1))
		var yaw = Basis(Vector3.UP, _rng.randf_range(-0.25, 0.25) + (PI * 0.5 if _rng.randf() < 0.15 else 0.0))
		var b = tilt * yaw * Basis(Vector3.UP, PI * 0.5 * (1.0 - s)) * _basis()
		var root = _at(lat, o, -0.05)
		var kind = _rng.randi_range(0, 2)
		var h = _rng.randf_range(0.6, 1.0)
		if kind == 0:
			var w = _rng.randf_range(0.45, 0.6)
			_box(Vector3(w, h, 0.12), Transform3D(b, root + b.y * h * 0.5), STONE)
			var top = MeshInstance3D.new()
			var cyl = CylinderMesh.new()
			cyl.top_radius = w * 0.5
			cyl.bottom_radius = w * 0.5
			cyl.height = 0.12
			cyl.radial_segments = 10
			top.mesh = cyl
			top.material_override = STONE
			add_child(top)
			top.global_transform = Transform3D(b * Basis(Vector3.RIGHT, PI * 0.5), root + b.y * h)
		elif kind == 1:
			_box(Vector3(0.11, h + 0.35, 0.11), Transform3D(b, root + b.y * (h + 0.35) * 0.5), STONE)
			_box(Vector3(0.5, 0.11, 0.11), Transform3D(b, root + b.y * (h + 0.05)), STONE)
		else:
			_box(Vector3(0.7, 0.18, 1.6), Transform3D(b, root + b.y * 0.09), STONE)
			_box(Vector3(0.4, h * 0.6, 0.1), Transform3D(b, root + b.y * h * 0.3 - b.z * 0.85), STONE)


func _moon() -> void:
	var moon = OmniLight3D.new()
	moon.light_color = Color(0.55, 0.5, 0.9)
	moon.light_energy = 3.2
	moon.omni_range = 30.0
	moon.omni_attenuation = 0.45
	moon.light_cull_mask = OUTSIDE_LAYER
	add_child(moon)
	moon.global_position = _at(-5.0, 9.0, 7.5)


func _box(size: Vector3, xf: Transform3D, mat: Material) -> void:
	var m = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = size
	m.mesh = box
	m.material_override = mat
	add_child(m)
	m.global_transform = xf
