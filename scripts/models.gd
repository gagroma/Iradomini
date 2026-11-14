extends RefCounted
# MODELS - every pixel-splat model in the game, described with simple shapes.
# Source: the Wailer below is the same demon as demon_wailer.ply from gen.py,
# rebuilt here in parts (body, two arms, two legs) so the limbs can swing.
# To change a model, change the shapes: Vector3(x, y, z) is in metres,
# x = left/right, y = up, z = forward for the demon.

const SplatBuilder = preload("res://scripts/splat_builder.gd")
const SPLAT_SHADER = preload("res://shaders/splat.gdshader")

# Palettes, dark to light.
const DEMON_SKIN = ["120d18", "2e2136", "5a4460", "9c8089"]
const BONE = ["3a2c33", "8f7a6c", "d9c3a5", "f3e6c8"]
const RAGS = ["0b0810", "1a1322", "2e2136"]
const GOLD = ["3d2a12", "8a5a1c", "d9a53a", "ffe9a0"]
const SILVER = ["2b2f3a", "5d6678", "a9b4c6", "eef3ff"]
const BRONZE = ["2a1a10", "6b3d1e", "b8742f", "f0c070"]
const RED = ["2a0b10", "5c1220", "8f1f2e", "c9463f"]
const EMBER = ["ff8a1f"]
const EMBER_HOT = ["ffd15a"]


# Models are slow to build (thousands of squares), so each one is built once
# and remembered, even when the level restarts after a death.
static func _cache() -> Dictionary:
	if not Engine.has_meta("ira_mesh_cache"):
		Engine.set_meta("ira_mesh_cache", {})
	return Engine.get_meta("ira_mesh_cache")


static func _pal(hex_list: Array) -> Array:
	return SplatBuilder.ramp(hex_list)


static func new_splat_material() -> ShaderMaterial:
	var m = ShaderMaterial.new()
	m.shader = SPLAT_SHADER
	return m


static func shared_splat_material() -> ShaderMaterial:
	var cache = _cache()
	if not cache.has("mat_shared"):
		var m = new_splat_material()
		m.set_shader_parameter("brightness", 0.8)
		cache["mat_shared"] = m
	return cache["mat_shared"]


# Material for things that must glow through the fog (eyes, flames).
static func glow_material() -> StandardMaterial3D:
	var cache = _cache()
	if not cache.has("mat_glow"):
		var m = StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.disable_fog = true
		cache["mat_glow"] = m
	return cache["mat_glow"]


static func _instance(mesh: Mesh, material: Material) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	return mi


# ---------------------------------------------------------------- THE WAILER
# Tall hunched demon: floor-length bone fingers, ember mouth, broken halo
# (a circle with a gap - the game's rule in one picture).

# The model is cut at its joints so it can move like a body: pelvis (with
# the rags), spine (ribs, shoulders), head (neck, skull, horns, halo, and the
# glowing mouth and eyes), and for each arm the upper arm, forearm and hand
# (four long bone fingers), for each leg the thigh and the shin with the foot.
# Joints, in metres, the model facing +Z:
const W_HIP := Vector3(0, 1.05, 0)
const W_NECK := Vector3(0, 1.95, 0.4)
const W_SHOULDER := Vector3(0.24, 1.84, 0.24)
const W_ELBOW := Vector3(0.42, 1.28, 0.36)
const W_WRIST := Vector3(0.33, 0.6, 0.58)
const W_LEG := Vector3(0.12, 1.0, 0.0)
const W_KNEE := Vector3(0.21, 0.55, 0.2)
const W_ANKLE := Vector3(0.17, 0.09, -0.04)


static func _wb(seed_value: int, pivot: Vector3) -> RefCounted:
	var b = SplatBuilder.new(seed_value)
	b.density = 3400.0
	b.quad = 0.032
	b.set_pivot(pivot)
	return b


static func _build_wailer() -> Dictionary:
	var skin = _pal(DEMON_SKIN)
	var bone = _pal(BONE)
	var rags = _pal(RAGS)
	var out = {}

	# --- pelvis and the rags hanging from it ---
	var hb = _wb(11, W_HIP)
	hb.ellipsoid(Vector3(0, 1.05, 0), Vector3(0.19, 0.15, 0.14), skin)
	for sx in [-1.0, 1.0]:
		for k in range(4):
			var x = sx * (0.05 + 0.05 * k)
			var z = -0.1 + 0.06 * k
			hb.chain([Vector3(x, 1.0, z), Vector3(x * 1.3, 0.7, z - 0.03), Vector3(x * 1.5, 0.35 + 0.08 * k, z + 0.02)], 0.035, 0.008, rags)
	out["hips"] = hb.build()

	# --- spine, ribs left open at the back, shoulders ---
	var sb = _wb(17, W_HIP)
	sb.chain([Vector3(0, 1.1, 0), Vector3(0, 1.42, 0.06), Vector3(0, 1.74, 0.2), Vector3(0, 1.95, 0.4)], 0.12, 0.15, skin)
	var ribs = [[1.5, 0.1, 0.19], [1.6, 0.14, 0.22], [1.7, 0.19, 0.23], [1.8, 0.25, 0.21]]
	for rib in ribs:
		sb.torus(Vector3(0, rib[0], rib[1]), Vector3(0, 1, -0.45), rib[2], 0.024, PI * 0.5 + 0.5, PI * 2.5 - 0.5, bone)
	for sx in [-1.0, 1.0]:
		sb.ellipsoid(Vector3(sx * 0.24, 1.84, 0.24), Vector3(0.09, 0.08, 0.08), skin)
	out["spine"] = sb.build()

	# --- neck, skull, horns, the broken halo ---
	var kb = _wb(18, W_NECK)
	kb.chain([Vector3(0, 1.95, 0.4), Vector3(0, 2.05, 0.52), Vector3(0, 2.08, 0.62)], 0.07, 0.06, skin)
	kb.ellipsoid(Vector3(0, 2.08, 0.7), Vector3(0.16, 0.25, 0.19), skin)
	kb.torus(Vector3(0, 2.48, 0.66), Vector3(0.12, 1, 0.1), 0.3, 0.022, 0.55, TAU, _pal(["e8d27a"]))
	for sx in [-1.0, 1.0]:
		kb.chain([Vector3(sx * 0.1, 2.27, 0.62), Vector3(sx * 0.2, 2.5, 0.5), Vector3(sx * 0.3, 2.62, 0.32), Vector3(sx * 0.34, 2.66, 0.14)], 0.045, 0.008, bone)
	out["head"] = kb.build()

	# --- glow: mouth, wax drips and two eyes (drawn through the fog), on the head ---
	var g = SplatBuilder.new(12)
	g.density = 9000.0
	g.quad = 0.022
	g.set_pivot(W_NECK)
	g.ellipsoid(Vector3(0, 2.0, 0.86), Vector3(0.085, 0.17, 0.05), _pal(EMBER))
	g.ellipsoid(Vector3(0, 2.0, 0.885), Vector3(0.05, 0.12, 0.03), _pal(EMBER_HOT))
	for y in [1.78, 1.72, 1.66]:
		g.capsule(Vector3(0, y + 0.05, 0.9), Vector3(0, y - 0.12, 0.9), 0.012, 0.004, _pal(EMBER), false)
	for sx in [-1.0, 1.0]:
		g.ellipsoid(Vector3(sx * 0.075, 2.2, 0.85), Vector3(0.026, 0.02, 0.02), _pal(EMBER_HOT))
	out["glow"] = g.build()

	# --- arms: upper arm, forearm, hand of four long bone fingers ---
	for sx in [-1.0, 1.0]:
		var side = "_l" if sx < 0.0 else "_r"
		var m = Vector3(sx, 1, 1)
		var shoulder = W_SHOULDER * m
		var elbow = W_ELBOW * m
		var wrist = W_WRIST * m
		var ua = _wb(13 if sx < 0.0 else 14, shoulder)
		ua.chain([shoulder, elbow], 0.055, 0.045, skin)
		out["arm" + side] = ua.build()
		var fa = _wb(23 if sx < 0.0 else 24, elbow)
		fa.chain([elbow, wrist], 0.045, 0.035, skin)
		out["fore" + side] = fa.build()
		var hd = _wb(33 if sx < 0.0 else 34, wrist)
		var fingers = [[-0.07, 0.1], [0.0, 0.16], [0.07, 0.1], [0.1, -0.02]]
		for f in fingers:
			hd.chain([wrist, Vector3(wrist.x + sx * f[0] * 0.6, 0.36, wrist.z + f[1] * 0.7), Vector3(wrist.x + sx * f[0], 0.12, wrist.z + f[1])], 0.02, 0.006, bone)
		out["hand" + side] = hd.build()

	# --- legs: thigh, shin with the foot ---
	for sx in [-1.0, 1.0]:
		var side = "_l" if sx < 0.0 else "_r"
		var m = Vector3(sx, 1, 1)
		var hip = W_LEG * m
		var knee = W_KNEE * m
		var ankle = W_ANKLE * m
		var th = _wb(15 if sx < 0.0 else 16, hip)
		th.chain([hip, knee], 0.07, 0.055, skin)
		out["leg" + side] = th.build()
		var sh = _wb(25 if sx < 0.0 else 26, knee)
		sh.chain([knee, ankle], 0.055, 0.04, skin)
		sh.capsule(ankle, Vector3(sx * 0.18, 0.035, 0.2), 0.04, 0.03, skin)
		out["shin" + side] = sh.build()
	return out


# Returns {"root": Node3D, "parts": {name: MeshInstance3D}, "material": ShaderMaterial}.
# The root faces -Z (Godot's "forward"), so demon.gd can simply turn the root.
# Every part is a joint: turn it and everything below it turns too.
static func wailer() -> Dictionary:
	var cache = _cache()
	if not cache.has("wailer2"):
		cache["wailer2"] = _build_wailer()
	var data = cache["wailer2"]
	var material = new_splat_material()
	var root = Node3D.new()
	var flip = Node3D.new()        # the shapes were modelled facing +Z; turn them around
	flip.rotation.y = PI
	root.add_child(flip)
	var parts = {"flip": flip}

	var joint = func(key: String, mesh_key: String, parent: Node3D, at: Vector3, parent_at: Vector3, mat: Material) -> MeshInstance3D:
		var mi = _instance(data[mesh_key], mat)
		mi.position = at - parent_at
		parent.add_child(mi)
		parts[key] = mi
		return mi

	var hips = joint.call("hips", "hips", flip, W_HIP, Vector3.ZERO, material)
	var spine = joint.call("spine", "spine", hips, W_HIP, W_HIP, material)
	var head = joint.call("head", "head", spine, W_NECK, W_HIP, material)
	joint.call("glow", "glow", head, W_NECK, W_NECK, glow_material())
	for sx in [-1.0, 1.0]:
		var side = "_l" if sx < 0.0 else "_r"
		var m = Vector3(sx, 1, 1)
		var arm = joint.call("arm" + side, "arm" + side, spine, W_SHOULDER * m, W_HIP, material)
		var fore = joint.call("fore" + side, "fore" + side, arm, W_ELBOW * m, W_SHOULDER * m, material)
		joint.call("hand" + side, "hand" + side, fore, W_WRIST * m, W_ELBOW * m, material)
		var leg = joint.call("leg" + side, "leg" + side, hips, W_LEG * m, W_HIP, material)
		joint.call("shin" + side, "shin" + side, leg, W_KNEE * m, W_LEG * m, material)
	return {"root": root, "parts": parts, "material": material}


# ------------------------------------------------------------------- PROPS

static func _small_builder(seed_value: int) -> RefCounted:
	var b = SplatBuilder.new(seed_value)
	b.density = 16000.0
	b.quad = 0.016
	return b


static func _build_relic(kind: String) -> ArrayMesh:
	var b = _small_builder(kind.hash())
	if kind == "chalice":
		var gold = _pal(GOLD)
		b.ellipsoid(Vector3(0, 0.02, 0), Vector3(0.07, 0.02, 0.07), gold)
		b.capsule(Vector3(0, 0.02, 0), Vector3(0, 0.16, 0), 0.018, 0.018, gold)
		b.ellipsoid(Vector3(0, 0.24, 0), Vector3(0.075, 0.08, 0.075), gold)
	elif kind == "cross":
		var silver = _pal(SILVER)
		b.ellipsoid(Vector3(0, 0.02, 0), Vector3(0.06, 0.02, 0.06), silver)
		b.capsule(Vector3(0, 0.02, 0), Vector3(0, 0.36, 0), 0.022, 0.022, silver)
		b.capsule(Vector3(-0.11, 0.26, 0), Vector3(0.11, 0.26, 0), 0.02, 0.02, silver)
	elif kind == "censer":
		var bronze = _pal(BRONZE)
		b.ellipsoid(Vector3(0, 0.09, 0), Vector3(0.08, 0.07, 0.08), bronze)
		b.ellipsoid(Vector3(0, 0.17, 0), Vector3(0.05, 0.05, 0.05), bronze)
		b.capsule(Vector3(0, 0.2, 0), Vector3(0, 0.42, 0), 0.008, 0.008, bronze, false)
		b.torus(Vector3(0, 0.45, 0), Vector3(0, 0, 1), 0.03, 0.008, 0.0, TAU, bronze)
		b.ellipsoid(Vector3(0, 0.1, 0.075), Vector3(0.02, 0.02, 0.012), _pal(EMBER))
	else:
		# the prayer book
		b.box(Vector3(0, 0.035, 0), Vector3(0.24, 0.07, 0.32), _pal(RED))
		b.box(Vector3(0, 0.074, 0), Vector3(0.03, 0.006, 0.18), _pal(["ffe9a0"]))
		b.box(Vector3(0, 0.074, -0.03), Vector3(0.11, 0.006, 0.03), _pal(["ffe9a0"]))
	return b.build()


# kind is "chalice", "cross", "censer" or "book".
static func relic(kind: String) -> MeshInstance3D:
	var cache = _cache()
	var key = "relic_" + kind
	if not cache.has(key):
		cache[key] = _build_relic(kind)
	return _instance(cache[key], shared_splat_material())


# The exorcist who came before you, lying where his circle was left open,
# and the claw gouges next to him. Modelled in Blender: tools/make_exorcist.py
# (assets/models/dead_exorcist.glb, claw_marks.glb). Along +X: feet at -X,
# head and reaching arm at +X.
const EXORCIST_MODEL = preload("res://assets/models/dead_exorcist.glb")
const CLAWS_MODEL = preload("res://assets/models/claw_marks.glb")
const VCOLOR_SHADER = preload("res://shaders/psx_vcolor.gdshader")


static func _vcolor_material() -> ShaderMaterial:
	var cache = _cache()
	if not cache.has("mat_vcolor"):
		var m = ShaderMaterial.new()
		m.shader = VCOLOR_SHADER
		cache["mat_vcolor"] = m
	return cache["mat_vcolor"]


static func _glb(scene: PackedScene) -> Node3D:
	var node = scene.instantiate()
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = _vcolor_material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


static func dead_exorcist() -> Node3D:
	return _glb(EXORCIST_MODEL)


# Three claw gouges torn into the floor.
static func claw_marks() -> Node3D:
	return _glb(CLAWS_MODEL)
