extends Node3D

const Chalk = preload("res://scripts/chalk.gd")
const Candle = preload("res://scripts/candle.gd")
const Models = preload("res://scripts/models.gd")
const WALL_SHADER = preload("res://shaders/psx_wall_paint.gdshader")
const FLOOR_SHADER = preload("res://shaders/psx_floor.gdshader")
const CHALK_COLOR := Color("#d2bd99")

const CIRCLE_CENTER := Vector3(1.79, 0.0, 0.0)
const CIRCLE_RADIUS := 1.54
const CHALK_SEGMENTS := 128
const PATROL_RADIUS := 0.94
const HOLD_TIME := 3.8
const WALK_TIME := 9.0

var _wailer: Node3D
var _parts: Dictionary
var _skin: ShaderMaterial
var _candle: Node3D
var _chalk_mesh := ImmediateMesh.new()
var _dust: CPUParticles3D
var _time := 0.0
var _patrol_time := 0.0
var _gap := 0.0
var _gap_segments := -1
var _broken := false

@onready var _camera: Camera3D = $Camera


func _ready() -> void:
	_camera.look_at(Vector3(-0.18, 1.24, 0.0))
	_build_chamber()
	_draw_circle(0)
	var chalk_material := ShaderMaterial.new()
	chalk_material.shader = Chalk.LINE_SHADER
	chalk_material.set_shader_parameter("color", CHALK_COLOR)
	var line := MeshInstance3D.new()
	line.mesh = _chalk_mesh
	line.material_override = chalk_material
	add_child(line)
	_make_dust()

	var model := Models.wailer()
	_wailer = model["root"]
	_parts = model["parts"]
	_skin = model["material"]
	var glow: StandardMaterial3D = _parts["glow"].material_override.duplicate()
	glow.albedo_color = Color("#b15a3f")
	_parts["glow"].material_override = glow
	add_child(_wailer)
	_update_wailer()


func _process(delta: float) -> void:
	_time += delta
	if not _broken:
		_patrol_time = fmod(_patrol_time + delta, HOLD_TIME + WALK_TIME)
	else:
		_gap = move_toward(_gap, 1.0, delta / 0.43)
		_draw_circle(ceili(_gap * 6.0))
	_candle.tick(delta, _gap * 0.7)
	_update_wailer()


func wailer_node() -> Node3D:
	return _wailer


func break_circle() -> void:
	_broken = true
	_dust.restart()
	_dust.emitting = true


func _update_wailer() -> void:
	var walk := clampf((_patrol_time - HOLD_TIME) / WALK_TIME, 0.0, 1.0)
	var moving := smoothstep(0.0, 0.12, walk) * (1.0 - smoothstep(0.88, 1.0, walk))
	# Ease the orbit at both ends so the Wailer comes to a stop at the chalk.
	var angle := TAU * (walk - sin(TAU * walk) / TAU) - 0.26
	_wailer.position = CIRCLE_CENTER + Vector3(sin(angle), 0.0, cos(angle)) * PATROL_RADIUS
	var to_camera := _camera.position - _wailer.position
	var camera_yaw := atan2(-to_camera.x, -to_camera.z)
	var watch := smoothstep(0.65, 1.65, _patrol_time) * (1.0 - smoothstep(HOLD_TIME - 0.75, HOLD_TIME, _patrol_time))
	var posed_yaw := camera_yaw + 0.66
	_wailer.rotation.y = lerp_angle(posed_yaw, angle - PI * 0.5, moving * (1.0 - _gap))
	_parts["head"].rotation.y = -0.66 * maxf(watch, _gap)
	_parts["head"].rotation.z = -0.12 * watch
	var phase := angle * 9.0
	var stride := sin(phase) * moving
	var breath := sin(_time * 2.0)
	_parts["leg_l"].rotation.x = stride * 0.46
	_parts["leg_r"].rotation.x = -stride * 0.46
	_parts["shin_l"].rotation.x = maxf(0.0, -stride) * 0.55
	_parts["shin_r"].rotation.x = maxf(0.0, stride) * 0.55
	_parts["arm_l"].rotation.x = -stride * 0.19 + breath * 0.018
	_parts["arm_r"].rotation.x = stride * 0.19 - breath * 0.018
	_parts["spine"].rotation.x = breath * 0.018
	_parts["flip"].position.y = absf(stride) * 0.042 + breath * 0.012
	_parts["flip"].rotation.x = breath * 0.012 - _gap * 0.10
	_skin.set_shader_parameter("brightness", 0.82 + _gap * 0.18)


func _draw_circle(gap_segments: int) -> void:
	if _gap_segments == gap_segments:
		return
	_gap_segments = gap_segments
	var points := PackedVector2Array()
	var end := CHALK_SEGMENTS if gap_segments == 0 else CHALK_SEGMENTS - gap_segments + 1
	for i in range(gap_segments, end):
		var angle := TAU * float(i) / CHALK_SEGMENTS
		var radius := CIRCLE_RADIUS + sin(angle * 9.0) * 0.018 + sin(angle * 17.0) * 0.009
		points.append(Vector2(CIRCLE_CENTER.x, CIRCLE_CENTER.z) + Vector2(sin(angle), cos(angle)) * radius)
	Chalk.fill_ribbon(_chalk_mesh, points, gap_segments == 0, 0.11)


func _make_dust() -> void:
	_dust = CPUParticles3D.new()
	_dust.emitting = false
	_dust.one_shot = true
	_dust.amount = 72
	_dust.lifetime = 0.6
	_dust.explosiveness = 0.78
	_dust.local_coords = true
	_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_dust.emission_box_extents = Vector3(0.24, 0.012, 0.035)
	_dust.direction = Vector3(0.0, 0.55, 1.0)
	_dust.spread = 55.0
	_dust.gravity = Vector3(0.0, -2.6, 0.0)
	_dust.initial_velocity_min = 0.25
	_dust.initial_velocity_max = 1.25
	_dust.scale_amount_min = 0.48
	_dust.scale_amount_max = 1.45
	_dust.position = CIRCLE_CENTER + Vector3(0.0, 0.025, CIRCLE_RADIUS)
	var grain := BoxMesh.new()
	grain.size = Vector3(0.019, 0.016, 0.019)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = CHALK_COLOR
	grain.material = material
	_dust.mesh = grain
	add_child(_dust)


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
