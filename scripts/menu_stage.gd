extends Node3D

const Chalk = preload("res://scripts/chalk.gd")
const Candle = preload("res://scripts/candle.gd")
const Models = preload("res://scripts/models.gd")
const WALL_SHADER = preload("res://shaders/psx_wall_paint.gdshader")
const FLOOR_SHADER = preload("res://shaders/psx_floor.gdshader")
const FIRE_SHADER = preload("res://shaders/menu_chalk_fire.gdshader")
const CHALK_COLOR := Color("#d2bd99")

const CIRCLE_CENTER := Vector3(1.79, 0.0, 0.0)
const CIRCLE_RADIUS := 1.54
const CHALK_SEGMENTS := 128
const BURN_TIME := 1.28
const FLAME_HEIGHT := 0.63
const SPARK_LIFETIME := 0.64
const IDLE_HEAD := Vector3(0.10, 0.31, -0.03)

var _wailer: Node3D
var _head: Node3D
var _spine: Node3D
var _idle: Tween
var _candle: Node3D
var _chalk: MeshInstance3D
var _chalk_material: ShaderMaterial
var _flames: MeshInstance3D
var _fire_material: ShaderMaterial
var _ember_lights: Array[OmniLight3D] = []
var _sparks: Array[CPUParticles3D] = []
var _time := 0.0
var _burn_progress := 0.0

@onready var _camera: Camera3D = $Camera


func _ready() -> void:
	_camera.look_at(Vector3(-0.18, 1.24, 0.0))
	_build_chamber()
	_build_circle()
	_build_fire()

	var model := Models.wailer()
	_wailer = model["root"]
	var parts: Dictionary = model["parts"]
	_head = parts["head"]
	_spine = parts["spine"]
	var skin: ShaderMaterial = model["material"]
	skin.set_shader_parameter("brightness", 0.82)
	skin.set_shader_parameter("skin_detail", 1.0)
	var glow: StandardMaterial3D = parts["glow"].material_override.duplicate()
	glow.albedo_color = Color("#b15a3f")
	parts["glow"].material_override = glow
	add_child(_wailer)
	_wailer.position = CIRCLE_CENTER + Vector3(-0.24, 0.0, 0.9)
	var to_camera := _camera.position - _wailer.position
	_wailer.rotation.y = atan2(-to_camera.x, -to_camera.z) + 0.68
	_head.rotation = IDLE_HEAD
	_start_idle()


func _process(delta: float) -> void:
	_time += delta
	_spine.rotation.x = sin(_time * 1.35) * 0.01 + _burn_progress * 0.065
	_candle.tick(delta, _burn_progress * 0.75)


func wailer_node() -> Node3D:
	return _wailer


func face_camera() -> void:
	_idle.kill()
	var glance := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	glance.tween_property(_head, "rotation", _camera_gaze(), 0.32)
	await glance.finished


func _camera_gaze() -> Vector3:
	var to_camera := _spine.global_basis.inverse() * (_camera.global_position - _head.global_position)
	# The splat model faces +Z underneath the Wailer's flipped root.
	var yaw := atan2(to_camera.x, to_camera.z)
	var pitch := atan2(-to_camera.y, Vector2(to_camera.x, to_camera.z).length())
	return Vector3(pitch, yaw, 0.0)


func burn_circle() -> void:
	_flames.show()
	var burn := create_tween()
	burn.tween_method(_set_burn_progress, 0.0, 1.0, BURN_TIME)
	await burn.finished
	_chalk.hide()
	_flames.hide()


func last_ember_uv() -> Vector2:
	var position_on_ring := _circle_point(PI) + Vector3.UP * 0.22
	return _camera.unproject_position(position_on_ring) / get_viewport().get_visible_rect().size


func _set_burn_progress(progress: float) -> void:
	_burn_progress = progress
	var front := lerpf(-0.08, 1.08, progress)
	_chalk_material.set_shader_parameter("burn_front", front)
	_fire_material.set_shader_parameter("burn_front", front)
	var angle := clampf(front, 0.0, 1.0) * PI
	var heat := smoothstep(-0.08, 0.07, front) * (1.0 - smoothstep(0.88, 1.08, front))
	for i in range(_ember_lights.size()):
		var side := 1.0 if i == 0 else -1.0
		var ember := _ember_lights[i]
		ember.position = _circle_point(angle * side) + Vector3.UP * 0.24
		ember.light_energy = heat * (3.5 + 0.7 * sin(_time * 33.0 + float(i) * 9.0))
		_sparks[i].emitting = front >= -0.04 and front < 1.02


func _start_idle() -> void:
	_idle = create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_idle.tween_interval(2.6)
	_idle.tween_property(_head, "rotation", Vector3(0.06, 0.66, -0.04), 2.3)
	_idle.tween_interval(1.9)
	_idle.tween_property(_head, "rotation", Vector3(0.53, 0.17, 0.07), 2.5)
	_idle.tween_interval(2.8)
	_idle.tween_property(_head, "rotation", Vector3(0.06, -0.18, 0.03), 2.6)
	_idle.tween_interval(1.8)
	_idle.tween_property(_head, "rotation", IDLE_HEAD, 2.15)


func _circle_point(angle: float) -> Vector3:
	var radius := CIRCLE_RADIUS + sin(angle * 9.0) * 0.018 + sin(angle * 17.0) * 0.009
	return CIRCLE_CENTER + Vector3(sin(angle), 0.0, cos(angle)) * radius


func _build_circle() -> void:
	var points := PackedVector2Array()
	for i in range(CHALK_SEGMENTS):
		var point := _circle_point(TAU * float(i) / CHALK_SEGMENTS)
		points.append(Vector2(point.x, point.z))
	var mesh := ImmediateMesh.new()
	Chalk.fill_ribbon(mesh, points, true, 0.14)
	_chalk_material = ShaderMaterial.new()
	_chalk_material.shader = Chalk.LINE_SHADER
	_chalk_material.set_shader_parameter("color", CHALK_COLOR)
	_chalk_material.set_shader_parameter("burn_origin", Vector2(CIRCLE_CENTER.x, CIRCLE_CENTER.z))
	_chalk = MeshInstance3D.new()
	_chalk.mesh = mesh
	_chalk.material_override = _chalk_material
	add_child(_chalk)


func _build_fire() -> void:
	_fire_material = ShaderMaterial.new()
	_fire_material.shader = FIRE_SHADER
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _fire_material)
	for i in range(CHALK_SEGMENTS + 1):
		var u := float(i) / CHALK_SEGMENTS
		var point := _circle_point(TAU * u) + Vector3.UP * 0.012
		mesh.surface_set_uv(Vector2(u, 0.0))
		mesh.surface_add_vertex(point)
		mesh.surface_set_uv(Vector2(u, 1.0))
		mesh.surface_add_vertex(point + Vector3.UP * FLAME_HEIGHT)
	mesh.surface_end()
	_flames = MeshInstance3D.new()
	_flames.mesh = mesh
	_flames.hide()
	add_child(_flames)

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.vertex_color_use_as_albedo = true
	var spark_mesh := BoxMesh.new()
	spark_mesh.size = Vector3(0.018, 0.036, 0.018)
	spark_mesh.material = material
	var colors := Gradient.new()
	colors.offsets = PackedFloat32Array([0.0, 0.24, 1.0])
	colors.colors = PackedColorArray([Color("#fff3bd"), Color("#ff922f"), Color("#cb231800")])
	for i in range(2):
		var ember := OmniLight3D.new()
		ember.light_color = Color("#ff8543")
		ember.light_energy = 0.0
		ember.omni_range = 3.7
		ember.omni_attenuation = 1.35
		add_child(ember)
		_ember_lights.append(ember)

		var sparks := CPUParticles3D.new()
		sparks.emitting = false
		sparks.amount = 110
		sparks.lifetime = SPARK_LIFETIME
		sparks.lifetime_randomness = 0.32
		sparks.local_coords = false
		sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		sparks.emission_sphere_radius = 0.09
		sparks.direction = Vector3.UP
		sparks.spread = 57.0
		sparks.gravity = Vector3(0.0, -1.25, 0.0)
		sparks.initial_velocity_min = 0.55
		sparks.initial_velocity_max = 2.7
		sparks.scale_amount_min = 0.46
		sparks.scale_amount_max = 1.25
		sparks.color_ramp = colors
		sparks.mesh = spark_mesh
		sparks.position.y = -0.19
		ember.add_child(sparks)
		_sparks.append(sparks)


func _build_chamber() -> void:
	var wall := _stone_material(WALL_SHADER, Color("#776b73"))
	var masonry := _stone_material(WALL_SHADER, Color("#958189"))
	var floor_material := _stone_material(FLOOR_SHADER, Color("#a08d97"))
	masonry.set_shader_parameter("paint_bands", 0.0)
	floor_material.set_shader_parameter("style", 1)
	_box(Vector3(0.0, -0.17, 0.0), Vector3(19.0, 0.34, 20.0), floor_material)
	_box(Vector3(0.0, 3.0, -3.6), Vector3(19.0, 6.0, 0.4), wall)
	_box(Vector3(0.0, 0.16, -3.34), Vector3(19.0, 0.32, 0.22), masonry)
	_box(Vector3(0.0, 0.39, -3.37), Vector3(19.0, 0.13, 0.14), masonry)

	_build_arch(Vector3(CIRCLE_CENTER.x, 0.0, -3.25), masonry)

	var stand := CIRCLE_CENTER + Vector3(0.96, 0.0, 1.5)
	_box(stand + Vector3.UP * 0.075, Vector3(0.39, 0.15, 0.37), masonry)
	_box(stand + Vector3.UP * 0.15, Vector3(0.31, 0.10, 0.30), masonry)
	_candle = Candle.new()
	_candle.held = false
	_candle.burns = false
	_candle.energy = 5.6
	_candle.reach = 7.2
	_candle.attenuation = 0.85
	_candle.light_lift = 0.27
	_candle.position = stand + Vector3.UP * 0.2
	_candle.scale = Vector3.ONE * 1.55
	add_child(_candle)


func _build_arch(base: Vector3, material: Material) -> void:
	const RADIUS := 1.54
	const SPRING_HEIGHT := 1.95
	var recess := StandardMaterial3D.new()
	recess.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	recess.cull_mode = BaseMaterial3D.CULL_DISABLED
	recess.albedo_color = Color("#130e14")
	var silhouette := ImmediateMesh.new()
	silhouette.surface_begin(Mesh.PRIMITIVE_TRIANGLES, recess)
	var center := base + Vector3(0.0, SPRING_HEIGHT, -0.09)
	for i in range(12):
		var a := PI * float(i) / 12.0
		var b := PI * float(i + 1) / 12.0
		silhouette.surface_add_vertex(center)
		silhouette.surface_add_vertex(center + Vector3(cos(a), sin(a), 0.0) * RADIUS)
		silhouette.surface_add_vertex(center + Vector3(cos(b), sin(b), 0.0) * RADIUS)
	silhouette.surface_end()
	var alcove := MeshInstance3D.new()
	alcove.mesh = silhouette
	add_child(alcove)
	_box(base + Vector3(0.0, SPRING_HEIGHT * 0.5, -0.10), Vector3(RADIUS * 2.0, SPRING_HEIGHT, 0.025), recess)
	for side in [-1.0, 1.0]:
		var column := base + Vector3(side * RADIUS, 0.0, 0.0)
		_box(column + Vector3.UP * SPRING_HEIGHT * 0.5, Vector3(0.32, SPRING_HEIGHT, 0.39), material)
		_box(column + Vector3.UP * 0.23, Vector3(0.48, 0.46, 0.46), material)
		_box(column + Vector3.UP * SPRING_HEIGHT, Vector3(0.43, 0.21, 0.48), material)
	for i in range(13):
		var angle := PI * float(i) / 12.0
		var block_center := base + Vector3(cos(angle) * RADIUS, SPRING_HEIGHT + sin(angle) * RADIUS, 0.0)
		var block := _box(block_center, Vector3(0.38, 0.41, 0.39), material)
		block.rotation.z = angle


func _stone_material(shader: Shader, tint: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("tint", tint)
	return material


func _box(center: Vector3, dimensions: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = center
	add_child(node)
	return node
