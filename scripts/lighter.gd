extends Node3D

const W := 0.036
const H := 0.052
const D := 0.013
const LID_H := 0.017
const FLAME_AT := Vector3(0.004, H + 0.026, 0.0)

var opened := 0.0
var burning := false

var _lid: Node3D
var _wheel: Node3D
var _flame: MeshInstance3D
var _flame_mat: StandardMaterial3D
var _light: OmniLight3D
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
	_flame_mat = StandardMaterial3D.new()
	_flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flame_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flame_mat.albedo_color = Color(1.0, 0.62, 0.25, 0.9)
	_flame_mat.emission_enabled = true
	_flame_mat.emission = Color(1.0, 0.55, 0.2)
	_flame_mat.emission_energy_multiplier = 3.0
	_flame = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 10
	sphere.rings = 6
	_flame.mesh = sphere
	_flame.material_override = _flame_mat
	_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flame)
	var core = MeshInstance3D.new()
	var cs = SphereMesh.new()
	cs.radius = 0.5
	cs.height = 1.0
	cs.radial_segments = 8
	cs.rings = 4
	core.mesh = cs
	var core_mat = _flame_mat.duplicate()
	core_mat.albedo_color = Color(0.35, 0.45, 1.0, 0.8)
	core_mat.emission = Color(0.3, 0.4, 1.0)
	core.material_override = core_mat
	core.scale = Vector3(0.45, 0.35, 0.45)
	core.position = Vector3(0, -0.3, 0)
	_flame.add_child(core)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.66, 0.34)
	_light.omni_range = 1.6
	_light.omni_attenuation = 1.4
	_light.light_cull_mask = ~(1 << 19)
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
	var flick = 1.0 + 0.18 * _noise.get_noise_1d(_time * 14.0) + 0.08 * _noise.get_noise_1d(_time * 37.0 + 9.0)
	var s = _size * flick
	_flame.visible = s > 0.02
	_flame.scale = Vector3(0.011, 0.03, 0.011) * s
	_flame.position = FLAME_AT + Vector3(0.0015 * _noise.get_noise_1d(_time * 6.0 + 40.0), 0.0, 0.0)
	_light.visible = s > 0.02
	_light.light_energy = 0.5 * s
	_light.position = FLAME_AT + Vector3(0.0, 0.03, 0.06)
