extends Node3D
# LEVEL - builds the cathedral out of the room modules listed in the GDD
# ("Moduli komnat"): narthex, nave with pews, side aisles with columns,
# chapels, pulpit, crossing and altar.
#
# Sources:
#  - GDD v6, "Urovni i lokatsiya". The seed changes how many bays the nave
#    has, which chapels exist and where the pulpit and relics are.
#  - The look is PS1-style: plain boxes, tiny textures, fog (see psx.gdshader).
#
# Directions: you start in the narthex at +Z and walk "north" towards -Z.
# X is left/right. The floor is flat at y = 0 everywhere.

const T = preload("res://scripts/tuning.gd")
const Nav = preload("res://scripts/nav.gd")
const Textures = preload("res://scripts/textures.gd")
const Models = preload("res://scripts/models.gd")
const PSX_SHADER = preload("res://shaders/psx.gdshader")
const PSX_MODEL_SHADER = preload("res://shaders/psx_model.gdshader")
const PEW = preload("res://assets/models/pew.glb")      # tools/make_pew.py
const Candle = preload("res://scripts/candle.gd")       # the same candle as in your hand
const Art = preload("res://scripts/church_art.gd")
const WALL_PAINT_SHADER = preload("res://shaders/psx_wall_paint.gdshader")
const FLOOR_SHADER = preload("res://shaders/psx_floor.gdshader")
# public-domain paintings (Met Open Access, CC0) - see assets/art/CREDITS.md
const ART_VAN_EYCK_CRUCIFIXION = preload("res://assets/art/van_eyck_crucifixion.png")
const ART_VAN_EYCK_JUDGMENT = preload("res://assets/art/van_eyck_last_judgment.png")
const ART_MICHAEL_DRAGON = preload("res://assets/art/saint_michael_dragon.png")
const ART_RIES_MICHAEL = preload("res://assets/art/ries_saint_michael.png")
const ART_ANGELICO = preload("res://assets/art/fra_angelico_crucifixion.png")
const ART_CHRISTUS = preload("res://assets/art/christus_lamentation.png")
const ART_MURILLO = preload("res://assets/art/murillo_crucifixion.png")
const ART_DADDI = preload("res://assets/art/daddi_crucifixion.png")
const ART_DUCCIO = preload("res://assets/art/duccio_madonna.png")

const WALL_H := 6.0
const WALL_T := 0.4
const BAY := 5.0            # length of one nave section

var nav
var rng := RandomNumberGenerator.new()
var bays := 4
var z_end := 0.0            # the z where the nave stops and the crossing starts
var covers := []            # Rect2 list: things you can hide next to
var patrol_points := []     # Vector2 list: the demon's route
var candles := []
var relic_spots := []       # {"pos": Vector3, "kind": String, "chapel": bool}
var player_start := Vector3(0.0, 0.0, 3.6)
var demon_start := Vector2.ZERO
var altar_pos := Vector2.ZERO
var altar_top := Vector3.ZERO
var altar_circle := PackedVector2Array()
var narthex_poly := PackedVector2Array()
var crossing_rect := Rect2()
var window_pos := Vector3.ZERO
var door_pos := Vector3(0.0, 1.5, 5.6)

var _mats := {}
var _beam_mat: StandardMaterial3D
var _pew_mats := []
var pew_backs := []
var _chapels := []
var _deco := RandomNumberGenerator.new()   # looks only, so the layout of a seed stays the same
var _time := 0.0


func build(seed_value: int) -> void:
	rng.seed = seed_value
	_deco.seed = seed_value + 7919
	bays = rng.randi_range(3, 4)
	z_end = -0.2 - BAY * bays
	nav = Nav.new()
	nav.setup(Rect2(-13.5, z_end - 18.5, 27.0, 25.0 - z_end))
	_make_materials()

	_build_narthex()
	var chapels = _pick_chapels()
	_chapels = chapels
	_build_nave(chapels)
	_build_crossing()
	_build_apse()
	_build_route(chapels)
	_decorate()
	nav.commit()


# ---------------------------------------------------------------- MATERIALS

func _psx(tex: Texture2D, tint: Color, tex_scale: float) -> ShaderMaterial:
	var m = ShaderMaterial.new()
	m.shader = PSX_SHADER
	m.set_shader_parameter("tex", tex)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("tex_scale", tex_scale)
	return m


# Stone and floors draw themselves in their shaders (no texture).
func _shaded(shader: Shader, tint: Color) -> ShaderMaterial:
	var m = ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("tint", tint)
	return m


func _make_materials() -> void:
	rng.randi()       # (these two once seeded textures; kept so a seed still builds
	rng.randi()       #  the same layout as before)
	_mats["wall"] = _shaded(WALL_PAINT_SHADER, Color(1.0, 1.0, 1.0))      # stone with old wall painting
	_mats["stone"] = _shaded(WALL_PAINT_SHADER, Color(1.12, 1.1, 1.14))   # columns, tables: bare stone
	_mats["stone"].set_shader_parameter("paint_bands", 0.0)
	_mats["plinth"] = _mats["stone"].duplicate()       # the base course along the walls
	_mats["plinth"].set_shader_parameter("tint", Color(0.82, 0.8, 0.82))
	_mats["floor"] = _shaded(FLOOR_SHADER, Color(1.0, 1.0, 1.0))          # limestone flags (narthex)
	_mats["floor_nave"] = _mats["floor"].duplicate()    # + marble runner, grave slabs in the aisles
	_mats["floor_nave"].set_shader_parameter("aisle_half", 1.05)
	_mats["floor_nave"].set_shader_parameter("ledgers", true)
	_mats["floor_inlay"] = _mats["floor"].duplicate()   # marble chequer + the roundel (crossing)
	_mats["floor_inlay"].set_shader_parameter("style", 1)
	_mats["floor_chapel"] = _mats["floor"].duplicate()  # worn terracotta
	_mats["floor_chapel"].set_shader_parameter("style", 2)
	_mats["floor_apse"] = _mats["floor"].duplicate()    # red and grey marble lozenges
	_mats["floor_apse"].set_shader_parameter("style", 3)
	_mats["wood"] = _psx(Textures.wood(rng.randi()), Color(1.0, 1.0, 1.0), 1.0)
	_mats["cloth"] = _psx(Textures.cloth(rng.randi()), Color(1.0, 1.0, 1.0), 2.0)
	# pews: one oak texture, three slightly different stains, like pews
	# bought and repaired over the years
	var oak = Textures.oak(_deco.randi())
	_pew_mats = []
	for tint in [Color(1.0, 1.0, 1.0), Color(0.9, 0.86, 0.84), Color(1.06, 1.0, 0.92)]:
		var m = ShaderMaterial.new()
		m.shader = PSX_MODEL_SHADER
		m.set_shader_parameter("tex", oak)
		m.set_shader_parameter("tint", tint)
		_pew_mats.append(m)
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam_mat.albedo_texture = Textures.beam()
	_beam_mat.albedo_color = Color(0.45, 0.6, 1.0, 0.5)
	_beam_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST


# ------------------------------------------------------------ SMALL HELPERS

# A box you can see and (if solid) bump into. center and size are in metres.
func _box(center: Vector3, size: Vector3, mat_name: String, solid: bool = true) -> void:
	var mi = MeshInstance3D.new()
	var bm = BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mats[mat_name]
	mi.position = center
	add_child(mi)
	if solid:
		_collider(center, size)


func _collider(center: Vector3, size: Vector3) -> void:
	var body = StaticBody3D.new()
	var cs = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	body.position = center
	add_child(body)


# The floor of one room (only the look - walking is decided by nav.carve).
func _floor(x0: float, z0: float, x1: float, z1: float, mat_name: String = "floor") -> void:
	var mi = MeshInstance3D.new()
	var pm = PlaneMesh.new()
	pm.size = Vector2(x1 - x0, z1 - z0)
	pm.subdivide_width = int((x1 - x0) / 2.0)
	pm.subdivide_depth = int((z1 - z0) / 2.0)
	mi.mesh = pm
	mi.material_override = _mats[mat_name]
	mi.position = Vector3((x0 + x1) * 0.5, 0.0, (z0 + z1) * 0.5)
	add_child(mi)


func _carve(x0: float, z0: float, x1: float, z1: float) -> void:
	nav.carve(Rect2(x0, z0, x1 - x0, z1 - z0))


# A piece of furniture: blocks the demon's path and gives you cover.
func _obstacle(x0: float, z0: float, x1: float, z1: float, is_cover: bool = true) -> void:
	var rect = Rect2(x0, z0, x1 - x0, z1 - z0)
	nav.block(rect)
	if is_cover:
		covers.append(rect)


# A plinth: a course of bigger stones along the foot of a wall, standing out
# a little on both sides (looks only).
func _plinth(center: Vector3, size: Vector3) -> void:
	_box(Vector3(center.x, 0.12, center.z), Vector3(size.x, 0.24, size.z), "plinth", false)


# A wall running left-right at a fixed z. gaps = [[x_from, x_to], ...] doorways.
func _wall_x(z: float, x0: float, x1: float, gaps: Array = [], h: float = WALL_H) -> void:
	var cuts = gaps.duplicate()
	cuts.sort_custom(func(a, b): return a[0] < b[0])
	var cur = x0
	for g in cuts:
		if g[0] > cur:
			_box(Vector3((cur + g[0]) * 0.5, h * 0.5, z), Vector3(g[0] - cur, h, WALL_T), "wall")
			_plinth(Vector3((cur + g[0]) * 0.5, 0.0, z), Vector3(g[0] - cur, 0.0, WALL_T + 0.12))
		_box(Vector3((g[0] + g[1]) * 0.5, 2.6 + (h - 2.6) * 0.5, z), Vector3(g[1] - g[0], h - 2.6, WALL_T), "wall", false)
		cur = g[1]
	if x1 > cur:
		_box(Vector3((cur + x1) * 0.5, h * 0.5, z), Vector3(x1 - cur, h, WALL_T), "wall")
		_plinth(Vector3((cur + x1) * 0.5, 0.0, z), Vector3(x1 - cur, 0.0, WALL_T + 0.12))


# A wall running front-back at a fixed x. gaps = [[z_from, z_to], ...] doorways.
func _wall_z(x: float, z0: float, z1: float, gaps: Array = [], h: float = WALL_H) -> void:
	var cuts = gaps.duplicate()
	cuts.sort_custom(func(a, b): return a[0] < b[0])
	var cur = z0
	for g in cuts:
		if g[0] > cur:
			_box(Vector3(x, h * 0.5, (cur + g[0]) * 0.5), Vector3(WALL_T, h, g[0] - cur), "wall")
			_plinth(Vector3(x, 0.0, (cur + g[0]) * 0.5), Vector3(WALL_T + 0.12, 0.0, g[0] - cur))
		_box(Vector3(x, 2.6 + (h - 2.6) * 0.5, (g[0] + g[1]) * 0.5), Vector3(WALL_T, h - 2.6, g[1] - g[0]), "wall", false)
		cur = g[1]
	if z1 > cur:
		_box(Vector3(x, h * 0.5, (cur + z1) * 0.5), Vector3(WALL_T, h, z1 - cur), "wall")
		_plinth(Vector3(x, 0.0, (cur + z1) * 0.5), Vector3(WALL_T + 0.12, 0.0, z1 - cur))


# One oak pew (model: tools/make_pew.py). Old pews never stand perfectly
# in line, so each one is nudged and turned a tiny bit.
func _pew(p: Vector3) -> void:
	var node = PEW.instantiate()
	node.position = p + Vector3(_deco.randf_range(-0.03, 0.03), 0.0, _deco.randf_range(-0.015, 0.015))
	node.rotation.y = _deco.randf_range(-0.012, 0.012)
	add_child(node)
	var mat = _pew_mats[_deco.randi() % _pew_mats.size()]
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = mat


# --------------------------------------------------------------- DECORATION
# The church's art: everything here is for the eyes only (no collisions, no
# effect on the demon or the layout). See church_art.gd for where it comes from.

# Put a node on a wall: at p, its front turned towards `facing` (flat).
func _hang(node: Node3D, p: Vector3, facing: Vector3) -> void:
	node.position = p
	node.rotation.y = atan2(facing.x, facing.z)
	add_child(node)


func _decorate() -> void:
	# --- nave: a stained-glass lancet high in the outer wall of every bay,
	# throwing coloured moonlight down into the aisle
	for b in range(bays):
		var zc = _bay_center(b)
		for side in [-1.0, 1.0]:
			var into = Vector3(-side, 0.0, 0.0)
			var glass = Art.lancet(Vector2(1.0, 2.4), _deco.randf() * 50.0)
			_hang(glass, Vector3(side * 7.99, 4.1, zc), into)
			var sl = SpotLight3D.new()
			add_child(sl)
			sl.position = Vector3(side * 7.7, 4.4, zc)
			sl.look_at(sl.position + Vector3(-side * 0.9, -1.4, 0.0))
			sl.light_color = Color(0.5, 0.42, 1.0).lerp(Color(1.0, 0.35, 0.3), _deco.randf() * 0.35)
			sl.light_energy = 1.3
			sl.spot_range = 9.0
			sl.spot_angle = 20.0
			sl.spot_attenuation = 1.2

	# --- Stations of the Cross: I to XIV round the nave walls
	var slots = []
	for b in range(bays - 1, -1, -1):            # left wall, from the crossing to the door
		var zc = _bay_center(b)
		slots.append([Vector3(-7.99, 1.95, zc - 1.6), Vector3(1, 0, 0)])
		slots.append([Vector3(-7.99, 1.95, zc + 1.6), Vector3(1, 0, 0)])
	for b in range(bays):                        # right wall, from the door to the crossing
		var zc = _bay_center(b)
		slots.append([Vector3(7.99, 1.95, zc + 1.6), Vector3(-1, 0, 0)])
		slots.append([Vector3(7.99, 1.95, zc - 1.6), Vector3(-1, 0, 0)])
	for zx in [z_end - 8.3, z_end - 1.7]:        # the rest on the crossing walls
		slots.append([Vector3(10.99, 1.95, zx), Vector3(-1, 0, 0)])
		slots.append([Vector3(-10.99, 1.95, zx), Vector3(1, 0, 0)])
	for i in range(mini(14, slots.size())):
		_hang(Art.station(i + 1), slots[i][0], slots[i][1])

	# --- crossing: the two wings of van Eyck's diptych face each other,
	# the Crucifixion on the left and the Last Judgment (with hell) on the right,
	# each with a votive candle under it
	var zx = z_end - 5.0
	_hang(Art.painting(ART_VAN_EYCK_CRUCIFIXION, 3.5, 0.16), Vector3(-10.99, 3.25, zx), Vector3(1, 0, 0))
	_hang(Art.painting(ART_VAN_EYCK_JUDGMENT, 3.5, 0.16), Vector3(10.99, 3.25, zx), Vector3(-1, 0, 0))
	for side in [-1.0, 1.0]:
		_box(Vector3(side * 10.87, 1.05, zx), Vector3(0.26, 0.05, 0.34), "wood", false)
		_candle(Vector3(side * 10.85, 1.075, zx), 1.5, 5.5, false, true)

	# --- chapels: an altarpiece above each little altar table
	var chapel_art = [ART_ANGELICO, ART_CHRISTUS, ART_MURILLO, ART_DADDI]
	for i in range(_chapels.size()):
		var side = _chapels[i][0]
		var zc = _bay_center(_chapels[i][1])
		var tex = chapel_art[i % chapel_art.size()]
		var h = 1.0 if tex.get_width() > tex.get_height() else 1.35
		_hang(Art.painting(tex, h, 0.11), Vector3(side * 12.39, 2.25, zc), Vector3(-side, 0, 0))

	# --- apse: gold mosaics on both side walls, and Saint Michael
	# casting down the devil as the altarpiece
	var zm = z_end - 13.5
	_hang(Art.mosaic(ART_DUCCIO, Vector2(6.2, 4.4), 3.2, 1.0), Vector3(-4.99, 4.3, zm), Vector3(1, 0, 0))
	_hang(Art.mosaic(ART_MICHAEL_DRAGON, Vector2(6.2, 4.4), 3.2, 2.0), Vector3(4.99, 4.3, zm), Vector3(-1, 0, 0))
	_hang(Art.painting(ART_RIES_MICHAEL, 1.2, 0.12, true), Vector3(0.0, 1.15 + 0.12 + 0.6, altar_pos.y - 0.38), Vector3(0, 0, 1))


# A candle in a brass chamberstick, standing at p (the bottom of the dish).
# The demon blows these out as it passes. Old candles are of all heights;
# fresh = true for a new one (the altar).
func _candle(p: Vector3, energy: float = 1.6, reach: float = 4.5, fresh: bool = false, decor: bool = false) -> void:
	if not decor:
		rng.randf()   # (kept so a seed still builds the same layout as before)
	var c = Candle.new()
	c.held = false
	c.burns = false
	c.left = 1.0 if fresh else _deco.randf_range(0.3, 0.95)
	c.energy = energy
	c.reach = reach
	c.attenuation = 1.2
	c.light_lift = 0.2
	c.self_layer = 1 << (10 + candles.size() % 9)     # layers 11-19 (20 is your candle)
	c.position = p
	c.rotation.y = _deco.randf() * TAU
	add_child(c)
	candles.append({
		"pos": p + Vector3(0.0, 0.12, 0.0),
		"pos2": Vector2(p.x, p.z),
		"candle": c,
		"lit": true,
		"timer": 0.0,
	})


# A cold column of moonlight from above (GDD: "kholodnye lunnye stolby").
func _moon_shaft(p: Vector2, width: float, energy: float) -> void:
	var sl = SpotLight3D.new()
	sl.position = Vector3(p.x, 9.0, p.y)
	sl.rotation.x = -PI / 2.0
	sl.light_color = Color(0.55, 0.68, 1.0)
	sl.light_energy = energy
	sl.spot_range = 11.0
	sl.spot_angle = rad_to_deg(atan(width / 9.0)) + 5.0
	add_child(sl)
	for k in range(2):
		var q = MeshInstance3D.new()
		var qm = QuadMesh.new()
		qm.size = Vector2(width * 1.5, 8.5)
		q.mesh = qm
		q.material_override = _beam_mat
		q.position = Vector3(p.x, 4.25, p.y)
		q.rotation.y = k * PI / 2.0 + 0.4
		add_child(q)


func _shuffle(list: Array) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j = rng.randi_range(0, i)
		var tmp = list[i]
		list[i] = list[j]
		list[j] = tmp


func _bay_center(b: int) -> float:
	return -0.2 - BAY * b - BAY * 0.5


# ------------------------------------------------------------------ NARTHEX
# GDD "Pritvor": the start room. The salt line on its doorstep is already
# closed, so you are safe here until you step out.

func _build_narthex() -> void:
	_floor(-4.0, 0.2, 4.0, 5.6)
	_carve(-3.7, 0.5, 3.7, 5.3)
	_wall_x(5.8, -4.4, 4.4)
	_wall_z(-4.2, 0.2, 6.0)
	_wall_z(4.2, 0.2, 6.0)
	# the wall between the narthex and the nave, with the doorway in it
	_wall_x(0.0, -8.4, 8.4, [[-1.3, 1.3]])
	_floor(-1.3, -0.2, 1.3, 0.2)
	_carve(-1.0, -0.5, 1.0, 0.5)
	# the big door you came in through (it will not open again)
	_box(Vector3(0.0, 1.5, 5.62), Vector3(2.2, 3.0, 0.1), "wood", false)
	_candle(Vector3(-3.6, 1.45, 0.5), 1.4, 4.0)
	_candle(Vector3(3.6, 1.45, 0.5), 1.4, 4.0)
	_box(Vector3(-3.6, 1.42, 0.5), Vector3(0.2, 0.06, 0.3), "wood", false)
	_box(Vector3(3.6, 1.42, 0.5), Vector3(0.2, 0.06, 0.3), "wood", false)
	# The safe area: the whole narthex. Only its first edge (the line across
	# the doorway) is drawn; the other edges run inside the walls.
	narthex_poly = PackedVector2Array([
		Vector2(-1.4, -0.5), Vector2(1.4, -0.5), Vector2(1.4, 0.0), Vector2(4.3, 0.0),
		Vector2(4.3, 5.9), Vector2(-4.3, 5.9), Vector2(-4.3, 0.0), Vector2(-1.4, 0.0),
	])


# ------------------------------------------------------- NAVE, AISLES, CHAPELS

# Pick 4 chapel places out of all the bays on both sides.
func _pick_chapels() -> Array:
	var slots = []
	for side in [-1.0, 1.0]:
		for b in range(bays):
			slots.append([side, b])
	_shuffle(slots)
	return slots.slice(0, 4)


func _build_nave(chapels: Array) -> void:
	# floor, one piece per bay
	for b in range(bays):
		var z0 = -0.2 - BAY * (b + 1)
		_floor(-8.0, z0, 8.0, z0 + BAY, "floor_nave")
	_carve(-7.7, z_end, 7.7, -0.5)

	# outer walls with a doorway for every chapel
	var gaps_west = []
	var gaps_east = []
	for ch in chapels:
		var zc = _bay_center(ch[1])
		if ch[0] < 0.0:
			gaps_west.append([zc - 0.9, zc + 0.9])
		else:
			gaps_east.append([zc - 0.9, zc + 0.9])
	_wall_z(-8.2, z_end, 0.2, gaps_west)
	_wall_z(8.2, z_end, 0.2, gaps_east)

	# GDD "Bokovye prokhody": columns between the nave and the side aisles
	for k in range(1, bays):
		var zk = -0.2 - BAY * k
		for side in [-1.0, 1.0]:
			var x = side * 4.5
			_box(Vector3(x, WALL_H * 0.5, zk), Vector3(0.8, WALL_H, 0.8), "stone")
			_box(Vector3(x, 0.2, zk), Vector3(1.05, 0.4, 1.05), "stone", false)
			_obstacle(x - 0.4, zk - 0.4, x + 0.4, zk + 0.4)
			_candle(Vector3(x - side * 0.5, 1.65, zk))
			_box(Vector3(x - side * 0.5, 1.62, zk), Vector3(0.2, 0.06, 0.2), "wood", false)

	# GDD "Nef": pews in solid blocks, a centre aisle and cross gaps.
	# The first bay stays empty so there is open floor after the door.
	for b in range(1, bays):
		var zc = _bay_center(b)
		for side in [-1.0, 1.0]:
			var x = side * 2.3
			for row in range(4):
				var zr = zc - 1.3 + row * 0.87
				_pew(Vector3(x, 0.0, zr))
			_collider(Vector3(x, 0.47, zc), Vector3(2.4, 0.94, 3.4))
			pew_backs.append({"x": x, "half": 1.1, "rail_z": zc + 1.55, "back_z": zc + 1.7})
			_obstacle(x - 1.2, zc - 1.7, x + 1.2, zc + 1.7)
		if b % 2 == 1:
			_moon_shaft(Vector2(0.0, zc), 1.6, 1.6)

	# GDD "Kapelly": dead ends with warm light. Three hold a relic, one is only shelter.
	var kinds = ["chalice", "cross", "censer"]
	for i in range(chapels.size()):
		var side = chapels[i][0]
		var zc = _bay_center(chapels[i][1])
		var xa = 8.4          # where the chapel starts (just outside the nave wall)
		var xb = 12.4         # where it ends
		_floor(minf(side * xa, side * xb), zc - 1.8, maxf(side * xa, side * xb), zc + 1.8, "floor_chapel")
		_floor(minf(side * 8.0, side * 8.4), zc - 0.9, maxf(side * 8.0, side * 8.4), zc + 0.9, "floor_chapel")
		_carve(minf(side * 8.7, side * 12.1), zc - 1.5, maxf(side * 8.7, side * 12.1), zc + 1.5)
		_carve(minf(side * 7.6, side * 8.8), zc - 0.7, maxf(side * 7.6, side * 8.8), zc + 0.7)
		_wall_z(side * 12.6, zc - 2.2, zc + 2.2)
		_wall_x(zc - 2.0, minf(side * 8.4, side * 12.8), maxf(side * 8.4, side * 12.8))
		_wall_x(zc + 2.0, minf(side * 8.4, side * 12.8), maxf(side * 8.4, side * 12.8))
		# a small stone table against the far wall
		var tx = side * 11.85
		_box(Vector3(tx, 0.45, zc), Vector3(0.7, 0.9, 1.5), "stone")
		_obstacle(tx - 0.35, zc - 0.75, tx + 0.35, zc + 0.75)
		_candle(Vector3(tx, 0.9, zc - 0.55), 1.8, 5.0)
		if i < kinds.size():
			relic_spots.append({"pos": Vector3(tx, 0.9, zc + 0.15), "kind": kinds[i], "chapel": true})
		else:
			# the shelter chapel: a tall cabinet to crouch behind
			var cx = side * 9.6
			_box(Vector3(cx, 1.0, zc + 1.2), Vector3(1.2, 2.0, 0.7), "wood")
			_obstacle(cx - 0.6, zc + 0.85, cx + 0.6, zc + 1.55)


# ----------------------------------------------------------------- CROSSING
# GDD "Sredokrestie": a big open space with no cover, and the pulpit
# ("Kafedra") standing in plain sight with the prayer book on it.

func _build_crossing() -> void:
	_floor(-11.0, z_end - 10.0, 11.0, z_end, "floor_inlay")
	_mats["floor_inlay"].set_shader_parameter("centre", Vector2(0.0, z_end - 5.0))
	_mats["floor_inlay"].set_shader_parameter("radius", 2.6)
	_carve(-10.7, z_end - 9.7, 10.7, z_end - 0.3)
	_carve(-7.7, z_end - 0.4, 7.7, z_end + 0.1)
	_wall_x(z_end, -11.4, -8.0)
	_wall_x(z_end, 8.0, 11.4)
	_wall_z(-11.2, z_end - 10.2, z_end + 0.2)
	_wall_z(11.2, z_end - 10.2, z_end + 0.2)
	_wall_x(z_end - 10.0, -11.4, -5.0)
	_wall_x(z_end - 10.0, 5.0, 11.4)
	crossing_rect = Rect2(-11.0, z_end - 10.0, 22.0, 10.0)
	_moon_shaft(Vector2(0.0, z_end - 5.0), 3.2, 2.2)

	var side = -1.0 if rng.randf() < 0.5 else 1.0
	var px = side * 3.2
	var pz = z_end - 1.7
	_box(Vector3(px, 0.25, pz), Vector3(1.6, 0.5, 1.6), "wood")
	_box(Vector3(px, 1.05, pz), Vector3(0.35, 1.1, 0.35), "wood", false)
	_box(Vector3(px, 1.63, pz), Vector3(0.55, 0.06, 0.45), "wood", false)
	_obstacle(px - 0.8, pz - 0.8, px + 0.8, pz + 0.8)
	_moon_shaft(Vector2(px, pz), 1.3, 2.0)
	relic_spots.append({"pos": Vector3(px, 1.66, pz), "kind": "book", "chapel": false})
	demon_start = Vector2(0.0, z_end - 5.0)


# --------------------------------------------------------------------- APSE
# GDD "Altar": the old exorcist's circle with a gap, his body in the gap,
# and the round stained-glass window you can see from everywhere.

func _build_apse() -> void:
	var z_back = z_end - 17.0
	_floor(-5.0, z_back, 5.0, z_end - 10.0, "floor_apse")
	_carve(-4.7, z_back + 0.3, 4.7, z_end - 9.6)
	_wall_z(-5.2, z_back - 0.2, z_end - 9.8, [], 8.0)
	_wall_z(5.2, z_back - 0.2, z_end - 9.8, [], 8.0)
	_wall_x(z_back - 0.2, -5.4, 5.4, [], 9.0)

	var za = z_end - 14.0
	altar_pos = Vector2(0.0, za)
	altar_top = Vector3(0.0, 1.15, za)
	_box(Vector3(0.0, 0.55, za), Vector3(2.6, 1.1, 1.0), "stone")
	_box(Vector3(0.0, 1.12, za), Vector3(2.7, 0.06, 1.1), "cloth", false)
	_obstacle(-1.3, za - 0.5, 1.3, za + 0.5)
	_candle(Vector3(-1.1, 1.15, za), 1.8, 5.0, true)
	_candle(Vector3(1.1, 1.15, za), 1.8, 5.0, true)
	_moon_shaft(Vector2(0.0, za + 1.2), 2.2, 1.4)

	# the unfinished circle: a ring of radius 2.5 m with a 1.1 m gap
	var radius = 2.5
	var gap_angle = PI * 0.5 + 0.55      # the gap faces the nave, a little to one side
	var half_gap = 0.22
	var a = gap_angle + half_gap
	var a_end = gap_angle - half_gap + TAU
	while a <= a_end:
		altar_circle.append(altar_pos + Vector2(cos(a), sin(a)) * radius)
		a += 0.07
	altar_circle.append(altar_pos + Vector2(cos(a_end), sin(a_end)) * radius)

	# He died drawing it: his line stops at the piece of chalk in his reaching
	# hand, just short of the gap. He lies beside the line, outside the circle,
	# along the way he was drawing - never on top of his own chalk.
	var gap_dir = Vector2(cos(gap_angle), sin(gap_angle))
	var stop = gap_angle - half_gap                      # where the line ends
	var line_end = altar_pos + Vector2(cos(stop), sin(stop)) * radius
	var ahead = Vector2(-sin(stop), cos(stop))           # the way he was drawing
	var outward = Vector2(cos(stop), sin(stop))
	var body = Models.dead_exorcist()
	# model: head along +X, his chalk at (1.14, 0, 0.47), his right side +Z
	var o = line_end - ahead * 1.14 + outward * 0.47
	body.transform = Transform3D(Basis(Vector3(ahead.x, 0.0, ahead.y), Vector3.UP, Vector3(-outward.x, 0.0, -outward.y)), Vector3(o.x, 0.0, o.y))
	add_child(body)
	var claws = Models.claw_marks()
	var claw_point = altar_pos + gap_dir * (radius - 0.75)
	claws.position = Vector3(claw_point.x, 0.0, claw_point.y)
	claws.rotation.y = -gap_angle
	add_child(claws)

	# the rose window: glows through the fog so you always know where "north" is
	window_pos = Vector3(0.0, 5.2, z_back + 0.05)
	var win = MeshInstance3D.new()
	var qm = QuadMesh.new()
	qm.size = Vector2(5.6, 5.6)
	win.mesh = qm
	var wm = StandardMaterial3D.new()
	wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wm.albedo_texture = Textures.rose_window()
	wm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	wm.disable_fog = true
	win.material_override = wm
	win.position = window_pos
	add_child(win)
	var glow = OmniLight3D.new()
	glow.position = Vector3(0.0, 4.2, z_back + 2.0)
	glow.light_color = Color(0.55, 0.45, 1.0)
	glow.light_energy = 1.2
	glow.omni_range = 9.0
	add_child(glow)


# ------------------------------------------------------------- DEMON ROUTE
# GDD "Patrol": the demon walks a fixed loop so players can learn to read it:
# up the nave, round the crossing, down one aisle, back up the other.

func _build_route(chapels: Array) -> void:
	var door = Vector2(0.0, -2.2)
	patrol_points.append(door)
	for b in range(1, bays):
		patrol_points.append(Vector2(0.0, _bay_center(b)))
	patrol_points.append(Vector2(0.0, z_end - 5.0))
	patrol_points.append(Vector2(0.0, z_end - 10.8))
	patrol_points.append(Vector2(-9.0, z_end - 5.0))
	for b in range(bays - 1, -1, -1):
		_route_aisle(-1.0, b, chapels)
	patrol_points.append(door)
	for b in range(bays):
		_route_aisle(1.0, b, chapels)
	patrol_points.append(Vector2(9.0, z_end - 5.0))
	patrol_points.append(Vector2(0.0, z_end - 5.0))


func _route_aisle(side: float, b: int, chapels: Array) -> void:
	var zc = _bay_center(b)
	patrol_points.append(Vector2(side * 6.3, zc))
	for ch in chapels:
		if ch[0] == side and ch[1] == b:
			patrol_points.append(Vector2(side * 10.2, zc))
			patrol_points.append(Vector2(side * 6.3, zc))


# ----------------------------------------------------------------- QUERIES

# True if p is within "dist" metres of something you can hide next to.
func near_cover(p: Vector2, dist: float) -> bool:
	for r in covers:
		var c = Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
		if c.distance_to(p) <= dist:
			return true
	return false


# GDD "Vsegda sebya vydayot": candles go out where the demon walks.
func update_candles(demon_pos: Vector2, demon_active: bool, dt: float, sfx) -> void:
	_time += dt
	for c in candles:
		var d = c["pos2"].distance_to(demon_pos)
		# the flame shudders as the demon comes near, then it goes out
		var near = 0.0
		if demon_active:
			near = clampf(1.0 - (d - 3.5) / 5.0, 0.0, 1.0)
		if c["lit"]:
			if demon_active and d < 3.5:
				c["lit"] = false
				c["timer"] = 25.0
				c["candle"].blow_out()
				sfx.play_at("candle_out", c["pos"], -8.0)
		else:
			c["timer"] -= dt
			if c["timer"] <= 0.0 and (not demon_active or d > 7.0):
				c["lit"] = true
				c["candle"].relight()
		c["candle"].tick(dt, near)
