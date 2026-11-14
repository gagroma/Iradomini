extends Node3D
# FLAME CLUSTER - the candle flames of one prop (a candle cluster, a candelabrum, a chandelier...)
# with one shared light. Works like candle.gd for level code: blow_out(), relight(), tick(dt, near),
# so the demon puts these out as it passes, the same as the old chambersticks.

const FLAME_SHADER = preload("res://shaders/kit/prop_flame.gdshader")

var light: OmniLight3D = null
var flames: Array[MeshInstance3D] = []
var energy := 0.9
var lit := true
var _level := 1.0          # 0 = out, 1 = burning
var _t := 0.0
var _flicker := 0.0


# spots: global positions of the wicks. with_light: false when the light budget is used up.
func setup(spots: Array, with_light: bool) -> void:
	_t = randf() * 100.0
	var mesh := SphereMesh.new()
	mesh.radius = 0.011
	mesh.height = 0.04
	mesh.radial_segments = 6
	mesh.rings = 4
	var mat := ShaderMaterial.new()
	mat.shader = FLAME_SHADER
	for p in spots:
		var f := MeshInstance3D.new()
		f.mesh = mesh
		f.material_override = mat
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(f)
		f.global_position = p
		flames.append(f)
	if with_light:
		light = OmniLight3D.new()
		light.light_color = Color(1.0, 0.42, 0.22)
		light.omni_range = 2.6 + 0.25 * minf(spots.size(), 6)
		light.omni_attenuation = 1.3
		light.shadow_enabled = false
		add_child(light)
		light.position = Vector3(0.0, 0.05, 0.0)
		energy = 0.55 + 0.12 * minf(spots.size(), 6)


func blow_out() -> void:
	lit = false


func relight() -> void:
	lit = true


# near: 0..1, how close the demon is. The flames shudder, then (level code) go out.
func tick(dt: float, near: float) -> void:
	_t += dt
	_level = move_toward(_level, 1.0 if lit else 0.0, dt * (0.8 if lit else 6.0))
	var n := sin(_t * 7.3) * 0.5 + sin(_t * 13.1 + 1.7) * 0.3 + sin(_t * 23.7 + 4.1) * 0.2
	_flicker = n * (0.15 + 0.6 * near)
	for f in flames:
		f.visible = _level > 0.05
		f.scale = Vector3.ONE * maxf(_level, 0.05) * (1.0 + _flicker * 0.4)
	if light:
		light.visible = _level > 0.01
		light.light_energy = energy * _level * (1.0 + _flicker)
