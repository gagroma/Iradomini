extends RefCounted

const PROPS_DIR := "res://assets/props/"


static func apply(root: Node) -> int:
	var cache := {}
	var count := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or mi.material_override != null:
			continue
		for s in mi.mesh.get_surface_count():
			var original := mi.get_active_material(s) as BaseMaterial3D
			if original == null or original.has_meta("aged") or not _is_prop(original):
				continue
			if not cache.has(original):
				cache[original] = _aged(original)
			mi.set_surface_override_material(s, cache[original])
			count += 1
	return count


static func _is_prop(m: BaseMaterial3D) -> bool:
	if m.resource_path.begins_with(PROPS_DIR):
		return true
	return m.albedo_texture != null and m.albedo_texture.resource_path.begins_with(PROPS_DIR)


static func _aged(m: BaseMaterial3D) -> BaseMaterial3D:
	var aged := m.duplicate() as BaseMaterial3D
	if m.metallic >= 0.3:
		aged.metallic = 0.55
		aged.roughness = maxf(m.roughness, 0.58)
		aged.metallic_specular = 0.35
		aged.albedo_color = m.albedo_color * Color(0.86, 0.82, 0.74)
	else:
		aged.roughness = maxf(m.roughness, 0.84)
		aged.metallic_specular = 0.22
	aged.rim_enabled = true
	aged.rim = 0.12
	aged.rim_tint = 0.6
	aged.set_meta("aged", true)
	return aged
