extends RefCounted
# CHURCH ART - the things on the walls: framed paintings, wall mosaics,
# stained-glass windows and the Stations of the Cross.
#
# Sources:
#  - Paintings: public-domain works from The Metropolitan Museum of Art Open
#    Access (CC0), turned into small PS1-style textures by
#    tools/prepare_art.gd. Titles and artists: assets/art/CREDITS.md.
#  - Frames, glass, mosaic stones, numerals: made in code here and in
#    shaders/painting, mosaic, stained_glass.gdshader.
#
# Every builder returns a node that faces +Z (its front) with its centre at
# the origin; level.gd turns it to face into the room.

const PAINTING_SHADER = preload("res://shaders/painting.gdshader")
const MOSAIC_SHADER = preload("res://shaders/mosaic.gdshader")
const GLASS_SHADER = preload("res://shaders/stained_glass.gdshader")
const DECOR_SHADER = preload("res://shaders/decor.gdshader")

# A carved frame moulding, inner edge to outer edge: [across 0..1, height].
# A bead at the sight edge, a hollow, a big rounded "ogee", a step down.
const PROFILE := [
	[0.0, 0.0], [0.0, 0.012], [0.05, 0.026], [0.1, 0.03], [0.16, 0.022],
	[0.24, 0.024], [0.34, 0.042], [0.46, 0.058], [0.58, 0.066], [0.7, 0.06],
	[0.8, 0.045], [0.88, 0.04], [0.94, 0.034], [1.0, 0.024], [1.0, 0.0],
]
const GILT := Color(0.8, 0.6, 0.26)
const GILT_DARK := Color(0.22, 0.14, 0.06)


static func _cache() -> Dictionary:
	var window := (Engine.get_main_loop() as SceneTree).root
	if not window.has_meta("ira_art_cache"):
		window.set_meta("ira_art_cache", {})
	return window.get_meta("ira_art_cache")


# All wall decor uses decor.gdshader (pulled in front of the wobbling wall).
static func decor_material(color: Color, metallic: float = 0.0, roughness: float = 0.8, tex: Texture2D = null, vertex_color: bool = false) -> ShaderMaterial:
	var m = ShaderMaterial.new()
	m.shader = DECOR_SHADER
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("metallic", metallic)
	m.set_shader_parameter("roughness", roughness)
	m.set_shader_parameter("use_vertex_color", vertex_color)
	if tex != null:
		m.set_shader_parameter("tex", tex)
		m.set_shader_parameter("use_tex", true)
	return m


static func _gilt_material() -> ShaderMaterial:
	var cache = _cache()
	if not cache.has("gilt"):
		cache["gilt"] = decor_material(Color.WHITE, 0.55, 0.38, null, true)
	return cache["gilt"]


static func _station_wood() -> ShaderMaterial:
	var cache = _cache()
	if not cache.has("station_wood"):
		cache["station_wood"] = decor_material(Color(0.24, 0.15, 0.09), 0.0, 0.7)
	return cache["station_wood"]


# ------------------------------------------------------------------ FRAMES

# A gilt frame around an opening of inner_w x inner_h metres, moulding
# `width` metres wide. Corners are mitred, the gold is darker in the hollows
# (old gilding: dirt sits in the low parts, the high parts are rubbed bright).
static func frame_mesh(inner_w: float, inner_h: float, width: float) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var depth_scale = width / 0.12
	var top = 0.0
	for p in PROFILE:
		top = maxf(top, p[1])
	# smooth normals along the profile, in (across, height)
	var pn = []
	for i in range(PROFILE.size()):
		var a = PROFILE[maxi(i - 1, 0)]
		var b = PROFILE[mini(i + 1, PROFILE.size() - 1)]
		var t = Vector2((b[0] - a[0]) * width, (b[1] - a[1]) * depth_scale)
		pn.append(Vector2(-t.y, t.x).normalized())
	var dirs = [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]   # outward of each side
	for i in range(PROFILE.size() - 1):
		var p0 = PROFILE[i]
		var p1 = PROFILE[i + 1]
		var c0 = _corners(inner_w * 0.5 + p0[0] * width, inner_h * 0.5 + p0[0] * width)
		var c1 = _corners(inner_w * 0.5 + p1[0] * width, inner_h * 0.5 + p1[0] * width)
		var z0 = p0[1] * depth_scale
		var z1 = p1[1] * depth_scale
		var k0 = _gilt_shade(p0[1] / top, i)
		var k1 = _gilt_shade(p1[1] / top, i + 1)
		for s in range(4):
			var e = (s + 1) % 4
			var out = dirs[s]
			var n0 = Vector3(out.x * pn[i].x, out.y * pn[i].x, pn[i].y).normalized()
			var n1 = Vector3(out.x * pn[i + 1].x, out.y * pn[i + 1].x, pn[i + 1].y).normalized()
			var a = Vector3(c0[s].x, c0[s].y, z0)
			var b = Vector3(c0[e].x, c0[e].y, z0)
			var c = Vector3(c1[e].x, c1[e].y, z1)
			var d = Vector3(c1[s].x, c1[s].y, z1)
			var face_n = (b - a).cross(d - a)
			var want = (n0 + n1)
			if face_n.dot(want) < 0.0:
				_v(st, a, n0, k0); _v(st, b, n0, k0); _v(st, c, n1, k1)
				_v(st, a, n0, k0); _v(st, c, n1, k1); _v(st, d, n1, k1)
			else:
				_v(st, a, n0, k0); _v(st, c, n1, k1); _v(st, b, n0, k0)
				_v(st, a, n0, k0); _v(st, d, n1, k1); _v(st, c, n1, k1)
	return st.commit()


static func _corners(hx: float, hy: float) -> Array:
	return [Vector2(-hx, -hy), Vector2(hx, -hy), Vector2(hx, hy), Vector2(-hx, hy)]


static func _gilt_shade(height01: float, i: int) -> Color:
	var k = clampf(height01, 0.0, 1.0)
	var c = GILT_DARK.lerp(GILT, 0.25 + 0.75 * k)
	if i <= 1:
		c = GILT_DARK          # the sight edge, in shadow
	return c


static func _v(st: SurfaceTool, p: Vector3, n: Vector3, c: Color) -> void:
	st.set_color(c)
	st.set_normal(n)
	st.add_vertex(p)


# ------------------------------------------------------------------ PAINTINGS

# A framed painting `height` metres tall (the painted surface), as wide as
# the picture's shape needs. backed = a wooden back for one standing free.
static func painting(tex: Texture2D, height: float, frame_w: float = 0.12, backed: bool = false, age: float = 0.6) -> Node3D:
	var root = Node3D.new()
	var w = height * float(tex.get_width()) / float(tex.get_height())
	var canvas = MeshInstance3D.new()
	var qm = QuadMesh.new()
	qm.size = Vector2(w, height)
	canvas.mesh = qm
	canvas.position.z = 0.008
	var m = ShaderMaterial.new()
	m.shader = PAINTING_SHADER
	m.set_shader_parameter("tex", tex)
	m.set_shader_parameter("age", age)
	canvas.material_override = m
	root.add_child(canvas)
	var fr = MeshInstance3D.new()
	fr.mesh = frame_mesh(w, height, frame_w)
	fr.material_override = _gilt_material()
	root.add_child(fr)
	if backed:
		var back = MeshInstance3D.new()
		var bm = BoxMesh.new()
		bm.size = Vector3(w + frame_w * 2.0, height + frame_w * 2.0, 0.03)
		back.mesh = bm
		back.position.z = -0.016
		back.material_override = decor_material(Color(0.16, 0.1, 0.07), 0.0, 0.9)
		root.add_child(back)
	for child in root.get_children():
		(child as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


# ------------------------------------------------------------------ MOSAIC

# A wall mosaic size.x by size.y metres, with tex as its central picture.
static func mosaic(tex: Texture2D, size: Vector2, image_h: float, seed_value: float) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	var qm = QuadMesh.new()
	qm.size = size
	mi.mesh = qm
	var m = ShaderMaterial.new()
	m.shader = MOSAIC_SHADER
	m.set_shader_parameter("tex", tex)
	m.set_shader_parameter("size", size)
	m.set_shader_parameter("image_h", image_h)
	m.set_shader_parameter("tex_aspect", float(tex.get_width()) / float(tex.get_height()))
	m.set_shader_parameter("seed", seed_value)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# ------------------------------------------------------------------ GLASS

static func lancet(size: Vector2, seed_value: float, brightness: float = 0.85) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	var qm = QuadMesh.new()
	qm.size = size
	mi.mesh = qm
	var m = ShaderMaterial.new()
	m.shader = GLASS_SHADER
	m.set_shader_parameter("size", size)
	m.set_shader_parameter("seed", seed_value)
	m.set_shader_parameter("brightness", brightness)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# ------------------------------------------------------- STATIONS OF THE CROSS

# A small wooden cross with a brass plaque under it, numbered in Roman
# numerals, as in every Catholic church (fourteen of them round the walls).
static func station(number: int) -> Node3D:
	var wood = _station_wood()
	var root = Node3D.new()
	var parts = [
		[Vector3(0.0, 0.06, 0.015), Vector3(0.05, 0.36, 0.03)],
		[Vector3(0.0, 0.14, 0.015), Vector3(0.22, 0.05, 0.03)],
	]
	for part in parts:
		var mi = MeshInstance3D.new()
		var bm = BoxMesh.new()
		bm.size = part[1]
		mi.mesh = bm
		mi.position = part[0]
		mi.material_override = wood
		root.add_child(mi)
	var plaque = MeshInstance3D.new()
	var qm = QuadMesh.new()
	var tex = _numeral_texture(_roman(number))
	qm.size = Vector2(0.034 * tex.get_width() / 6.0 + 0.04, 0.08)
	plaque.mesh = qm
	plaque.position = Vector3(0.0, -0.2, 0.004)
	plaque.material_override = decor_material(Color.WHITE, 0.5, 0.45, tex)
	root.add_child(plaque)
	return root


static func _roman(n: int) -> String:
	var vals = [[10, "X"], [9, "IX"], [5, "V"], [4, "IV"], [1, "I"]]
	var out = ""
	for v in vals:
		while n >= v[0]:
			out += v[1]
			n -= v[0]
	return out


# 5x7 pixel letters for the plaque
const GLYPHS := {
	"I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
	"V": ["10001", "10001", "10001", "10001", "01010", "01010", "00100"],
	"X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
}


static func _numeral_texture(text: String) -> ImageTexture:
	var w = text.length() * 6 + 3
	var img = Image.create(w, 11, false, Image.FORMAT_RGB8)
	img.fill(Color(0.55, 0.4, 0.16))
	for x in range(w):
		img.set_pixel(x, 0, Color(0.3, 0.2, 0.08))
		img.set_pixel(x, 10, Color(0.3, 0.2, 0.08))
	for y in range(11):
		img.set_pixel(0, y, Color(0.3, 0.2, 0.08))
		img.set_pixel(w - 1, y, Color(0.3, 0.2, 0.08))
	for i in range(text.length()):
		var g = GLYPHS[text[i]]
		for gy in range(7):
			for gx in range(5):
				if g[gy][gx] == "1":
					img.set_pixel(2 + i * 6 + gx, 2 + gy, Color(0.12, 0.07, 0.03))
	return ImageTexture.create_from_image(img)
