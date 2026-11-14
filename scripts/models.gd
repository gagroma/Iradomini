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
const WAX = ["6b5a45", "a8957a", "d9c8a8", "f5ecd6"]
const CASSOCK = ["0b0a10", "1b1824", "2e2a3c", "4a4460"]
const SKIN = ["5a4a48", "9a8478", "d8c2ae"]
const EMBER = ["ff8a1f"]
const EMBER_HOT = ["ffd15a"]
const BLOOD = ["4a0a10"]
const WAILER_HEAD_PIVOT := Vector3(0.0, 2.02, 0.48)


# Keep the meshes across scene changes and release them with the root window
# before Godot shuts down the renderer.
static func _cache() -> Dictionary:
	var window := (Engine.get_main_loop() as SceneTree).root
	if not window.has_meta("ira_mesh_cache"):
		window.set_meta("ira_mesh_cache", {})
	return window.get_meta("ira_mesh_cache")


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

static func _build_wailer() -> Dictionary:
	var skin = _pal(DEMON_SKIN)
	var bone = _pal(BONE)
	var rags = _pal(RAGS)
	var out = {}

	# --- body: pelvis, spine, ribs, neck, shoulders and rags ---
	var b = SplatBuilder.new(11)
	b.density = 3400.0
	b.quad = 0.032
	b.ellipsoid(Vector3(0, 1.05, 0), Vector3(0.19, 0.15, 0.14), skin)
	b.chain([Vector3(0, 1.05, 0), Vector3(0, 1.42, 0.06), Vector3(0, 1.74, 0.2), Vector3(0, 1.95, 0.4)], 0.12, 0.15, skin)
	var ribs = [[1.5, 0.1, 0.19], [1.6, 0.14, 0.22], [1.7, 0.19, 0.23], [1.8, 0.25, 0.21]]
	for rib in ribs:
		# each rib is a ring left open at the back
		b.torus(Vector3(0, rib[0], rib[1]), Vector3(0, 1, -0.45), rib[2], 0.024, PI * 0.5 + 0.5, PI * 2.5 - 0.5, bone)
	b.chain([Vector3(0, 1.95, 0.4), WAILER_HEAD_PIVOT], 0.07, 0.066, skin)
	var head = SplatBuilder.new(17)
	head.density = b.density
	head.quad = b.quad
	head.set_pivot(WAILER_HEAD_PIVOT)
	head.chain([WAILER_HEAD_PIVOT, Vector3(0, 2.05, 0.52), Vector3(0, 2.08, 0.62)], 0.066, 0.06, skin)
	head.ellipsoid(Vector3(0, 2.08, 0.7), Vector3(0.16, 0.25, 0.19), skin)
	head.torus(Vector3(0, 2.48, 0.66), Vector3(0.12, 1, 0.1), 0.3, 0.022, 0.55, TAU, _pal(["e8d27a"]))
	for sx in [-1.0, 1.0]:
		head.chain([Vector3(sx * 0.1, 2.27, 0.62), Vector3(sx * 0.2, 2.5, 0.5), Vector3(sx * 0.3, 2.62, 0.32), Vector3(sx * 0.34, 2.66, 0.14)], 0.045, 0.008, bone)
		b.ellipsoid(Vector3(sx * 0.24, 1.84, 0.24), Vector3(0.09, 0.08, 0.08), skin)
		for k in range(4):
			var x = sx * (0.05 + 0.05 * k)
			var z = -0.1 + 0.06 * k
			b.chain([Vector3(x, 1.0, z), Vector3(x * 1.3, 0.7, z - 0.03), Vector3(x * 1.5, 0.35 + 0.08 * k, z + 0.02)], 0.035, 0.008, rags)
	out["body"] = b.build()
	out["head"] = head.build()

	# --- glow: mouth, wax drips and two eyes (drawn through the fog) ---
	var g = SplatBuilder.new(12)
	g.density = 9000.0
	g.quad = 0.022
	g.set_pivot(WAILER_HEAD_PIVOT)
	g.ellipsoid(Vector3(0, 2.0, 0.86), Vector3(0.085, 0.17, 0.05), _pal(EMBER))
	g.ellipsoid(Vector3(0, 2.0, 0.885), Vector3(0.05, 0.12, 0.03), _pal(EMBER_HOT))
	for y in [1.78, 1.72, 1.66]:
		g.capsule(Vector3(0, y + 0.05, 0.9), Vector3(0, y - 0.12, 0.9), 0.012, 0.004, _pal(EMBER), false)
	for sx in [-1.0, 1.0]:
		g.ellipsoid(Vector3(sx * 0.075, 2.2, 0.85), Vector3(0.026, 0.02, 0.02), _pal(EMBER_HOT))
	out["glow"] = g.build()

	# --- arms: shoulder -> elbow -> wrist, then four long bone fingers ---
	for sx in [-1.0, 1.0]:
		var a = SplatBuilder.new(13 if sx < 0.0 else 14)
		a.density = 3400.0
		a.quad = 0.032
		var shoulder = Vector3(sx * 0.24, 1.84, 0.24)
		var elbow = Vector3(sx * 0.42, 1.28, 0.36)
		var wrist = Vector3(sx * 0.33, 0.6, 0.58)
		a.set_pivot(shoulder)
		a.chain([shoulder, elbow, wrist], 0.055, 0.035, skin)
		var fingers = [[-0.07, 0.1], [0.0, 0.16], [0.07, 0.1], [0.1, -0.02]]
		for f in fingers:
			a.chain([wrist, Vector3(wrist.x + sx * f[0] * 0.6, 0.36, wrist.z + f[1] * 0.7), Vector3(wrist.x + sx * f[0], 0.12, wrist.z + f[1])], 0.02, 0.006, bone)
		var arm_key = "arm_l" if sx < 0.0 else "arm_r"
		out[arm_key] = a.build()
		out[arm_key + "_pivot"] = shoulder

	# --- legs: hip -> knee -> ankle -> foot ---
	for sx in [-1.0, 1.0]:
		var l = SplatBuilder.new(15 if sx < 0.0 else 16)
		l.density = 3400.0
		l.quad = 0.032
		var hip = Vector3(sx * 0.12, 1.0, 0.0)
		var knee = Vector3(sx * 0.21, 0.55, 0.2)
		var ankle = Vector3(sx * 0.17, 0.09, -0.04)
		l.set_pivot(hip)
		l.chain([hip, knee, ankle], 0.07, 0.04, skin)
		l.capsule(ankle, Vector3(sx * 0.18, 0.035, 0.2), 0.04, 0.03, skin)
		var leg_key = "leg_l" if sx < 0.0 else "leg_r"
		out[leg_key] = l.build()
		out[leg_key + "_pivot"] = hip
	return out


# Returns {"root": Node3D, "parts": {name: MeshInstance3D}, "material": ShaderMaterial}.
# The root faces -Z (Godot's "forward"), so demon.gd can simply turn the root.
static func wailer() -> Dictionary:
	var cache = _cache()
	if not cache.has("wailer"):
		cache["wailer"] = _build_wailer()
	var data = cache["wailer"]
	var material = new_splat_material()
	var root = Node3D.new()
	var flip = Node3D.new()        # the shapes were modelled facing +Z; turn them around
	flip.rotation.y = PI
	root.add_child(flip)
	var parts = {}
	var body = _instance(data["body"], material)
	flip.add_child(body)
	parts["body"] = body
	var head = Node3D.new()
	head.position = WAILER_HEAD_PIVOT
	flip.add_child(head)
	head.add_child(_instance(data["head"], material))
	parts["head"] = head
	var glow = _instance(data["glow"], glow_material())
	head.add_child(glow)
	parts["glow"] = glow
	for key in ["arm_l", "arm_r", "leg_l", "leg_r"]:
		var limb = _instance(data[key], material)
		limb.position = data[key + "_pivot"]
		flip.add_child(limb)
		parts[key] = limb
	parts["flip"] = flip
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


# A candle: wax + a flame that can be switched off ("Flame" child).
static func candle() -> Node3D:
	var cache = _cache()
	if not cache.has("candle_wax"):
		var w = _small_builder(21)
		w.capsule(Vector3(0, 0, 0), Vector3(0, 0.18, 0), 0.025, 0.022, _pal(WAX))
		cache["candle_wax"] = w.build()
		var f = _small_builder(22)
		f.ellipsoid(Vector3(0, 0.235, 0), Vector3(0.022, 0.05, 0.022), _pal(EMBER))
		f.ellipsoid(Vector3(0, 0.225, 0), Vector3(0.012, 0.028, 0.012), _pal(EMBER_HOT))
		cache["candle_flame"] = f.build()
	var root = Node3D.new()
	var wax = _instance(cache["candle_wax"], shared_splat_material())
	wax.name = "Wax"
	root.add_child(wax)
	var flame = _instance(cache["candle_flame"], glow_material())
	flame.name = "Flame"
	root.add_child(flame)
	return root


# The exorcist who came before you, lying where his circle was left open.
# Modelled along +X: feet at -X, head and reaching arm at +X.
static func dead_exorcist() -> MeshInstance3D:
	var cache = _cache()
	if not cache.has("body"):
		var b = SplatBuilder.new(31)
		b.density = 6000.0
		b.quad = 0.026
		var cloth = _pal(CASSOCK)
		var skin = _pal(SKIN)
		b.capsule(Vector3(-0.2, 0.14, 0), Vector3(0.45, 0.14, 0), 0.17, 0.15, cloth)
		b.ellipsoid(Vector3(0.68, 0.12, 0.02), Vector3(0.11, 0.11, 0.1), skin)
		b.capsule(Vector3(-0.2, 0.12, 0.09), Vector3(-1.05, 0.08, 0.16), 0.09, 0.06, cloth)
		b.capsule(Vector3(-0.2, 0.12, -0.09), Vector3(-1.0, 0.08, -0.2), 0.09, 0.06, cloth)
		b.capsule(Vector3(0.4, 0.12, 0.15), Vector3(0.98, 0.05, 0.4), 0.055, 0.04, cloth)
		b.ellipsoid(Vector3(1.04, 0.04, 0.43), Vector3(0.06, 0.03, 0.05), skin)
		b.capsule(Vector3(0.38, 0.12, -0.15), Vector3(0.15, 0.08, -0.42), 0.055, 0.04, cloth)
		b.box(Vector3(1.14, 0.02, 0.47), Vector3(0.07, 0.02, 0.02), _pal(["f3ead2"]))   # his last piece of chalk
		cache["body"] = b.build()
	return _instance(cache["body"], shared_splat_material())


# Three claw scratches on the floor.
static func claw_marks() -> MeshInstance3D:
	var cache = _cache()
	if not cache.has("claws"):
		var b = _small_builder(41)
		for k in range(3):
			var z = (k - 1) * 0.14
			b.capsule(Vector3(-0.4, 0.012, z), Vector3(0.4, 0.012, z + 0.1), 0.012, 0.004, _pal(BLOOD), false)
		cache["claws"] = b.build()
	return _instance(cache["claws"], shared_splat_material())
