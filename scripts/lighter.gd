extends Node3D

const W := 0.036
const H := 0.052
const D := 0.013
const LID_H := 0.017
const FLAME_SHADER = preload("res://shaders/candle_flame.gdshader")
const FLAME_HEIGHT := 0.036
const FLAME_BASE := Vector3(0.004, H + 0.015, 0.0)
const FLAME_AT := Vector3(0.004, H + 0.026, 0.0)

var opened := 0.0
var burning := false

var _lid: Node3D
var _wheel: Node3D
var _flame_root: Node3D
var _flame_mat: ShaderMaterial
var _prev := Vector3.ZERO
var _vel := Vector3.ZERO
var _lean := Vector2.ZERO
var _light: OmniLight3D
var _wax_light: OmniLight3D
var _size := 0.0
var _spin := 0.0
var _time := 0.0
var _noise := FastNoiseLite.new()


func _ready() -> void:
	var steel = StandardMaterial3D.new()
	steel.albedo_color = Color(0.55, 0.53, 0.5)
	steel.metallic = 0.85
	steel.roughness = 0.38
	var dark = StandardMaterial3D.new()
	dark.albedo_color = Color(0.18, 0.17, 0.16)
	dark.metallic = 0.7
	dark.roughness = 0.5
	_part(Vector3(W, H, D), Vector3(0, H * 0.5, 0), steel, self)
	_part(Vector3(W * 1.01, 0.0025, D * 1.01), Vector3(0, H - 0.001, 0), dark, self)
	var chimney = Node3D.new()
	add_child(chimney)
	_part(Vector3(0.022, 0.017, 0.011), Vector3(0.004, H + 0.0085, 0), dark, chimney)
	for i in 3:
		for side in [-1.0, 1.0]:
			_part(Vector3(0.003, 0.003, 0.0005), Vector3(-0.003 + i * 0.007, H + 0.009, side * 0.0057), Color(0.02, 0.02, 0.02), chimney)
	_wheel = Node3D.new()
	_wheel.position = Vector3(-0.0115, H + 0.016, 0)
	add_child(_wheel)
	var wm = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.0045
	cyl.bottom_radius = 0.0045
	cyl.height = 0.007
	cyl.radial_segments = 8
	wm.mesh = cyl
	wm.material_override = dark
	wm.rotation.x = PI * 0.5
	_wheel.add_child(wm)
	_lid = Node3D.new()
	_lid.position = Vector3(W * 0.5, H, 0)
	add_child(_lid)
	_part(Vector3(W, LID_H, D), Vector3(-W * 0.5, LID_H * 0.5, 0), steel, _lid)
	_flame_root = Node3D.new()
	_flame_root.top_level = true
	add_child(_flame_root)
	var box := BoxMesh.new()
	box.size = Vector3(0.12, 0.12, 0.12)
	var flame := MeshInstance3D.new()
	flame.mesh = box
	flame.position = Vector3(0.0, 0.03, 0.0)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flame_mat = ShaderMaterial.new()
	_flame_mat.shader = FLAME_SHADER
	_flame_mat.set_shader_parameter("wick_offset", Vector3(0.0, -0.03, 0.0))
	_flame_mat.set_shader_parameter("box_half", box.size * 0.5)
	_flame_mat.set_shader_parameter("height", FLAME_HEIGHT)
	_flame_mat.set_shader_parameter("radius", 0.0066)
	_flame_mat.set_shader_parameter("seed", 4.7)
	flame.material_override = _flame_mat
	_flame_root.add_child(flame)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.66, 0.34)
	_light.omni_range = 1.6
	_light.omni_attenuation = 1.4
	_light.light_cull_mask = ~(1 << 19)
	_wax_light = OmniLight3D.new()
	_wax_light.light_color = Color(1.0, 0.66, 0.34)
	_wax_light.omni_range = 0.8
	_wax_light.omni_attenuation = 1.6
	_wax_light.light_cull_mask = 1 << 19
	add_child(_wax_light)
	add_child(_light)
	_noise.seed = 77
	_noise.frequency = 0.9


func strike() -> void:
	burning = true
	_spin = 1.0


func snuff() -> void:
	burning = false


func _part(size: Vector3, at: Vector3, mat, parent: Node3D) -> void:
	var m = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = size
	m.mesh = box
	if mat is Color:
		var c = StandardMaterial3D.new()
		c.albedo_color = mat
		m.material_override = c
	else:
		m.material_override = mat
	m.position = at
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)


func _process(dt: float) -> void:
	_time += dt
	_lid.rotation.z = -2.3 * smoothstep(0.0, 1.0, opened)
	_spin = maxf(0.0, _spin - dt * 3.0)
	_wheel.rotation.z += _spin * dt * 40.0
	var want = 1.0 if burning and opened > 0.9 else 0.0
	_size = move_toward(_size, want, dt * (9.0 if want > _size else 14.0))
	var flick = 1.0 + 0.12 * _noise.get_noise_1d(_time * 14.0) + 0.05 * _noise.get_noise_1d(_time * 37.0 + 9.0)
	var s = _size * flick
	var base: Vector3 = global_transform * FLAME_BASE
	if dt > 0.0:
		var v := (base - _prev) / dt
		if v.length() < 20.0:
			_vel = _vel.lerp(v, 1.0 - exp(-12.0 * dt))
	_prev = base
	_lean = _lean.lerp(Vector2(-_vel.x, -_vel.z) * 0.3, 1.0 - exp(-10.0 * dt))
	_flame_root.global_transform = Transform3D(Basis.IDENTITY, base)
	_flame_root.visible = s > 0.02
	_flame_mat.set_shader_parameter("size", s)
	_flame_mat.set_shader_parameter("lean", _lean.limit_length(1.0))
	_flame_mat.set_shader_parameter("turbulence", 0.15 + minf(_vel.length(), 1.5) * 0.5)
	_light.visible = s > 0.02
	_wax_light.visible = s > 0.02
	_wax_light.light_energy = 0.06 * s
	_wax_light.position = FLAME_AT + Vector3(0.0, 0.04, 0.12)
	_light.light_energy = 0.5 * s
	_light.position = FLAME_AT + Vector3(0.0, 0.03, 0.06)
