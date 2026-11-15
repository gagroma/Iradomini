@tool
extends EditorScript

const TARGET_DIR := "res://assets/"
const SHADER_PATH := "res://assets/stylized_polish.gdshader"
const POLISHED_SUFFIX := "_polished.tscn"
const HIGH_TRI_LIMIT := 20000
const EXTENSIONS := ["glb", "gltf", "obj", "tscn"]

const SHADER_CODE := """shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_texture = false;
uniform bool use_vertex_color = false;
uniform float roughness_value : hint_range(0.75, 0.92) = 0.85;
uniform float noise_strength : hint_range(0.0, 0.3) = 0.08;
uniform float noise_scale = 6.0;
uniform float ground_darkening : hint_range(0.0, 1.0) = 0.35;
uniform float ground_height = 0.6;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.2;
uniform vec4 rim_color : source_color = vec4(1.0, 0.95, 0.85, 1.0);

varying vec3 world_pos;
varying vec3 world_normal;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float layered(vec2 p) {
	return value_noise(p) * 0.6 + value_noise(p * 2.7 + 13.1) * 0.3 + value_noise(p * 7.3 + 41.7) * 0.1;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec4 base = albedo_color;
	if (use_texture) {
		base *= texture(albedo_texture, UV);
	}
	if (use_vertex_color) {
		base *= COLOR;
	}
	vec3 w = pow(abs(world_normal), vec3(4.0));
	w /= max(w.x + w.y + w.z, 0.0001);
	float n = layered(world_pos.zy * noise_scale) * w.x
		+ layered(world_pos.xz * noise_scale) * w.y
		+ layered(world_pos.xy * noise_scale) * w.z;
	vec3 col = base.rgb * (1.0 + (n - 0.5) * 2.0 * noise_strength);
	float grounded = smoothstep(0.0, max(ground_height, 0.001), world_pos.y);
	col *= mix(1.0 - ground_darkening, 1.0, grounded);
	ALBEDO = col;
	ROUGHNESS = roughness_value;
	SPECULAR = 0.3;
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	RIM = rim_strength;
	RIM_TINT = 0.4;
	EMISSION = rim_color.rgb * fresnel * rim_strength * 0.35;
}
"""

var _shader: Shader
var _material_cache := {}
var _polished := 0
var _skipped := 0
var _failed := []
var _heavy := []


func _run() -> void:
	_polished = 0
	_skipped = 0
	_failed.clear()
	_heavy.clear()
	_material_cache.clear()
	_shader = _ensure_shader()
	if _shader == null:
		push_error("Polish: could not create or load %s" % SHADER_PATH)
		return
	var files := []
	_collect(TARGET_DIR, files)
	for path in files:
		_polish_file(path)
	EditorInterface.get_resource_filesystem().scan()
	print("")
	print("==== Asset polish summary ====")
	print("Polished: %d   Skipped: %d   Failed: %d" % [_polished, _skipped, _failed.size()])
	for f in _failed:
		print("  FAILED  ", f)
	if _heavy.is_empty():
		print("No mesh above %d triangles." % HIGH_TRI_LIMIT)
	else:
		print("Meshes above %d triangles:" % HIGH_TRI_LIMIT)
		for h in _heavy:
			print("  HEAVY   ", h)
	print("==============================")


func _ensure_shader() -> Shader:
	if not FileAccess.file_exists(SHADER_PATH):
		var file := FileAccess.open(SHADER_PATH, FileAccess.WRITE)
		if file == null:
			return null
		file.store_string(SHADER_CODE)
		file.close()
		EditorInterface.get_resource_filesystem().update_file(SHADER_PATH)
	return ResourceLoader.load(SHADER_PATH, "Shader", ResourceLoader.CACHE_MODE_REPLACE) as Shader


func _collect(dir_path: String, out: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("Polish: cannot open %s" % dir_path)
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var full := dir_path.path_join(entry)
			if dir.current_is_dir():
				_collect(full, out)
			elif entry.get_extension().to_lower() in EXTENSIONS and not entry.ends_with(POLISHED_SUFFIX):
				out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()


func _polish_file(path: String) -> void:
	var ext := path.get_extension().to_lower()
	var resource = ResourceLoader.load(path)
	if resource == null:
		_failed.append(path + " (could not load)")
		return
	var root: Node
	var save_path := path
	if resource is PackedScene:
		var state := PackedScene.GEN_EDIT_STATE_MAIN if ext == "tscn" else PackedScene.GEN_EDIT_STATE_MAIN_INHERITED
		root = (resource as PackedScene).instantiate(state)
		if ext != "tscn":
			save_path = path.get_basename() + POLISHED_SUFFIX
	elif resource is Mesh:
		root = Node3D.new()
		root.name = path.get_file().get_basename().to_pascal_case()
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		mi.mesh = resource
		root.add_child(mi)
		mi.owner = root
		save_path = path.get_basename() + POLISHED_SUFFIX
	else:
		_skipped += 1
		return
	if not (root is Node3D):
		root.free()
		_skipped += 1
		return
	var meshes := []
	_find_meshes(root, root, meshes)
	if meshes.is_empty():
		root.free()
		_skipped += 1
		return
	if ext == "tscn":
		_mark_instances_editable(root, root)
	for mi in meshes:
		_polish_mesh(mi, path)
	_fix_pivot(root, meshes)
	_fix_collision(root, meshes)
	if ext == "tscn" and FileAccess.file_exists(path):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(path + ".bak"))
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, save_path)
	root.free()
	if err != OK:
		_failed.append("%s (error %s)" % [path, error_string(err)])
		return
	_polished += 1
	print("Polished  %s  ->  %s" % [path, save_path])


func _find_meshes(node: Node, root: Node, out: Array) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(node)
	for child in node.get_children():
		_find_meshes(child, root, out)


func _mark_instances_editable(node: Node, root: Node) -> void:
	for child in node.get_children():
		if child.scene_file_path != "":
			root.set_editable_instance(child, true)
		_mark_instances_editable(child, root)


func _polish_mesh(mi: MeshInstance3D, source: String) -> void:
	var mesh := mi.mesh
	var tris := 0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var indices = arrays[Mesh.ARRAY_INDEX]
		var vertices = arrays[Mesh.ARRAY_VERTEX]
		var colors = arrays[Mesh.ARRAY_COLOR]
		if indices != null and indices.size() > 0:
			tris += indices.size() / 3
		elif vertices != null:
			tris += vertices.size() / 3
		var original := mi.get_active_material(s)
		if original is ShaderMaterial and (original as ShaderMaterial).shader == _shader:
			continue
		var has_colors: bool = colors != null and colors.size() > 0
		mi.set_surface_override_material(s, _material_for(original, has_colors))
	mi.material_override = null
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if tris > HIGH_TRI_LIMIT:
		_heavy.append("%s : %s (%d tris)" % [source, mi.name, tris])


func _material_for(original: Material, has_colors: bool) -> ShaderMaterial:
	var key := [original, has_colors]
	if _material_cache.has(key):
		return _material_cache[key]
	var color := Color.WHITE
	var texture: Texture2D = null
	var roughness := 0.85
	var vertex_color := has_colors
	if original is BaseMaterial3D:
		var base := original as BaseMaterial3D
		color = base.albedo_color
		texture = base.albedo_texture
		roughness = base.roughness
		vertex_color = has_colors and base.vertex_color_use_as_albedo
	elif original is ShaderMaterial:
		var sm := original as ShaderMaterial
		for name in ["albedo_color", "albedo", "tint", "color"]:
			var v = sm.get_shader_parameter(name)
			if v is Color:
				color = v
				break
		for name in ["albedo_texture", "texture_albedo", "tex", "albedo_tex"]:
			var t = sm.get_shader_parameter(name)
			if t is Texture2D:
				texture = t
				break
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("albedo_color", color)
	mat.set_shader_parameter("use_texture", texture != null)
	if texture != null:
		mat.set_shader_parameter("albedo_texture", texture)
	mat.set_shader_parameter("use_vertex_color", vertex_color)
	mat.set_shader_parameter("roughness_value", clampf(roughness, 0.75, 0.92))
	mat.set_shader_parameter("rim_strength", 0.2)
	_material_cache[key] = mat
	return mat


func _to_root(node: Node, root: Node) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var current := node
	while current != null and current != root:
		if current is Node3D:
			xform = (current as Node3D).transform * xform
		current = current.get_parent()
	return xform


func _bounds(root: Node, meshes: Array) -> AABB:
	var box := AABB()
	var first := true
	for mi in meshes:
		var b: AABB = _to_root(mi, root) * (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _fix_pivot(root: Node3D, meshes: Array) -> void:
	if root is MeshInstance3D:
		return
	var box := _bounds(root, meshes)
	var centre := box.get_center()
	var offset := Vector3(-centre.x, -box.position.y, -centre.z)
	if offset.length() < 0.001:
		return
	for child in root.get_children():
		if child is Node3D:
			(child as Node3D).position += offset


func _fix_collision(root: Node3D, meshes: Array) -> void:
	var light_found := false
	for shape_node in root.find_children("*", "CollisionShape3D", true, false):
		var cs := shape_node as CollisionShape3D
		if cs.shape is ConcavePolygonShape3D or cs.shape is ConvexPolygonShape3D:
			cs.disabled = true
		elif cs.shape != null and not cs.disabled:
			light_found = true
	if light_found:
		return
	var box := _bounds(root, meshes)
	var body := StaticBody3D.new()
	body.name = "PolishCollision"
	root.add_child(body)
	body.owner = root
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var footprint := maxf(box.size.x, box.size.z)
	if box.size.y > footprint * 1.5 and footprint > 0.0:
		var capsule := CapsuleShape3D.new()
		capsule.radius = footprint * 0.5
		capsule.height = maxf(box.size.y, footprint)
		cs.shape = capsule
	else:
		var shape := BoxShape3D.new()
		shape.size = Vector3(maxf(box.size.x, 0.01), maxf(box.size.y, 0.01), maxf(box.size.z, 0.01))
		cs.shape = shape
	cs.position = box.get_center()
	body.add_child(cs)
	cs.owner = root
