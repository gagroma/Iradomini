extends Node3D

const GUN = preload("res://assets/models/sawn_off.glb")
const SHELL = preload("res://assets/models/shell.glb")
const VCOLOR = preload("res://shaders/psx_vcolor.gdshader")
const HINGE := Vector3(0.0, -0.012, -0.035)
const GAP := 0.0118
const MUZZLE := Vector3(0.0, 0.006, -0.275)
const OPEN_ANGLE := 0.72

var open := 0.0
var barrels: Node3D
var chambers := []
var sfx

var _mat: ShaderMaterial
var _flash_light: OmniLight3D
var _flash_mesh: MeshInstance3D
var _flash_t := 1.0
var _smoke: CPUParticles3D
var _sparks: CPUParticles3D


static func material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = VCOLOR
	m.set_shader_parameter("snap", false)
	m.set_shader_parameter("roughness", 0.55)
	return m


static func make_shell(mat: Material) -> Node3D:
	var s: Node3D = SHELL.instantiate()
	for mi in s.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return s


func _ready() -> void:
	_mat = material()
	var model: Node3D = GUN.instantiate()
	add_child(model)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = _mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	barrels = model.get_node("barrels")
	for sx in [-1.0, 1.0]:
		var s := make_shell(_mat)
		s.position = Vector3(sx * GAP, 0.0, 0.0025) - HINGE
		s.visible = false
		barrels.add_child(s)
		chambers.append(s)
	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(1.0, 0.7, 0.35)
	_flash_light.omni_range = 9.0
	_flash_light.light_energy = 0.0
	_flash_light.position = MUZZLE + Vector3(0, 0, -0.06)
	add_child(_flash_light)
	_flash_mesh = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.22, 0.22)
	_flash_mesh.mesh = q
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fm.albedo_texture = _flash_texture()
	fm.albedo_color = Color(1.0, 0.75, 0.4)
	fm.disable_fog = true
	_flash_mesh.material_override = fm
	_flash_mesh.position = MUZZLE + Vector3(0, 0, -0.07)
	_flash_mesh.visible = false
	_flash_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flash_mesh)
	_smoke = _particles(26, 1.6, false)
	_sparks = _particles(18, 0.35, true)


func _flash_texture() -> ImageTexture:
	var img := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var d := Vector2(x - 31.5, y - 31.5) / 31.5
			var r := d.length()
			var ang := atan2(d.y, d.x)
			var star := pow(absf(cos(ang * 3.0)), 6.0) * 0.6 + pow(absf(cos(ang * 2.0 + 0.4)), 10.0) * 0.4
			var a := clampf(exp(-r * 4.0) * 1.4 + star * exp(-r * 1.6) * (1.0 - r), 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0 * a, 0.85 * a, 0.6 * a, 1.0))
	return ImageTexture.create_from_image(img)


func _particles(amount: int, life: float, spark: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 0.95
	p.local_coords = false
	p.position = MUZZLE + Vector3(0, 0, -0.03)
	p.direction = Vector3(0, 0.1, -1)
	p.spread = 12.0 if spark else 20.0
	p.initial_velocity_min = 6.0 if spark else 0.6
	p.initial_velocity_max = 12.0 if spark else 1.6
	p.gravity = Vector3(0, -3.0, 0) if spark else Vector3(0, 0.25, 0)
	p.damping_min = 0.5 if spark else 1.4
	p.damping_max = 1.0 if spark else 2.2
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.012, 0.012) if spark else Vector2(0.09, 0.09)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if spark:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	else:
		m.albedo_texture = _smoke_texture()
	mesh.material = m
	p.mesh = mesh
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4 if not spark else 1.0))
	curve.add_point(Vector2(1, 2.4 if not spark else 0.2))
	p.scale_amount_curve = curve
	var g := Gradient.new()
	if spark:
		g.set_color(0, Color(1.0, 0.85, 0.4, 1.0))
		g.set_color(1, Color(1.0, 0.3, 0.05, 0.0))
	else:
		g.set_color(0, Color(0.55, 0.52, 0.5, 0.35))
		g.set_color(1, Color(0.3, 0.3, 0.3, 0.0))
	p.color_ramp = g
	add_child(p)
	return p


func _smoke_texture() -> ImageTexture:
	var img := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var r := Vector2(x - 15.5, y - 15.5).length() / 15.5
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - r, 0.0, 1.0) ** 2))
	return ImageTexture.create_from_image(img)


func set_loaded(count: int) -> void:
	for i in chambers.size():
		chambers[i].visible = i < count


func fire() -> void:
	_flash_t = 0.0
	_flash_mesh.rotation.z = randf() * TAU
	_smoke.restart()
	_sparks.restart()


func eject(world_parent: Node, count: int) -> Array:
	var out := []
	for i in count:
		var src: Node3D = chambers[i]
		var hull := make_shell(_mat)
		world_parent.add_child(hull)
		hull.global_transform = src.global_transform
		src.visible = false
		var back := global_transform.basis.z.normalized()
		var right := global_transform.basis.x.normalized()
		hull.set_meta("vel", back * randf_range(0.7, 1.0) + Vector3.UP * randf_range(1.9, 2.4) + right * randf_range(0.9, 1.3) + right * (0.15 * i))
		hull.set_meta("spin", Vector3(randf_range(-14, 14), randf_range(-8, 8), randf_range(-14, 14)))
		out.append(hull)
	return out


static func fly(hull: Node3D, dt: float, sfx_node) -> bool:
	if not hull.has_meta("vel"):
		return false
	var v: Vector3 = hull.get_meta("vel")
	v.y -= 9.8 * dt
	var p := hull.global_position + v * dt
	var spin: Vector3 = hull.get_meta("spin")
	hull.rotate_x(spin.x * dt)
	hull.rotate_y(spin.y * dt)
	hull.rotate_z(spin.z * dt)
	if p.y <= 0.011:
		p.y = 0.011
		if v.y < -1.0:
			v = Vector3(v.x * 0.35, -v.y * 0.25, v.z * 0.35)
			hull.set_meta("spin", spin * 0.4)
			if sfx_node != null and not hull.has_meta("rang"):
				hull.set_meta("rang", true)
				sfx_node.play_at("shell_drop", p, -8.0)
		else:
			var yaw := hull.rotation.y
			hull.global_transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI * 0.5), Vector3(p.x, 0.011, p.z))
			hull.remove_meta("vel")
			return false
	hull.set_meta("vel", v)
	hull.global_position = p
	return true


func _process(dt: float) -> void:
	if barrels != null:
		barrels.rotation.x = -OPEN_ANGLE * open
	_flash_t += dt
	var f := 1.0 - clampf(_flash_t / 0.07, 0.0, 1.0)
	_flash_mesh.visible = f > 0.0
	_flash_mesh.scale = Vector3.ONE * (0.6 + 0.8 * f)
	_flash_light.light_energy = 9.0 * f * f
