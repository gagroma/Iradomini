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
var _time := 0.0


func build(seed_value: int) -> void:
	rng.seed = seed_value
	bays = rng.randi_range(3, 4)
	z_end = -0.2 - BAY * bays
	nav = Nav.new()
	nav.setup(Rect2(-13.5, z_end - 18.5, 27.0, 25.0 - z_end))
	_make_materials()

	_build_narthex()
	var chapels = _pick_chapels()
	_build_nave(chapels)
	_build_crossing()
	_build_apse()
	_build_route(chapels)
	nav.commit()


# ---------------------------------------------------------------- MATERIALS

func _psx(tex: Texture2D, tint: Color, tex_scale: float) -> ShaderMaterial:
	var m = ShaderMaterial.new()
	m.shader = PSX_SHADER
	m.set_shader_parameter("tex", tex)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("tex_scale", tex_scale)
	return m


func _make_materials() -> void:
	var brick = Textures.bricks(rng.randi())
	_mats["wall"] = _psx(brick, Color(1.0, 1.0, 1.0), 0.5)
	_mats["stone"] = _psx(brick, Color(1.3, 1.25, 1.35), 0.5)
	_mats["floor"] = _psx(Textures.tiles(rng.randi()), Color(1.0, 1.0, 1.0), 0.5)
	_mats["wood"] = _psx(Textures.wood(rng.randi()), Color(1.0, 1.0, 1.0), 1.0)
	_mats["cloth"] = _psx(Textures.cloth(rng.randi()), Color(1.0, 1.0, 1.0), 2.0)
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
func _floor(x0: float, z0: float, x1: float, z1: float) -> void:
	var mi = MeshInstance3D.new()
	var pm = PlaneMesh.new()
	pm.size = Vector2(x1 - x0, z1 - z0)
	pm.subdivide_width = int((x1 - x0) / 2.0)
	pm.subdivide_depth = int((z1 - z0) / 2.0)
	mi.mesh = pm
	mi.material_override = _mats["floor"]
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


# A wall running left-right at a fixed z. gaps = [[x_from, x_to], ...] doorways.
func _wall_x(z: float, x0: float, x1: float, gaps: Array = [], h: float = WALL_H) -> void:
	var cuts = gaps.duplicate()
	cuts.sort_custom(func(a, b): return a[0] < b[0])
	var cur = x0
	for g in cuts:
		if g[0] > cur:
			_box(Vector3((cur + g[0]) * 0.5, h * 0.5, z), Vector3(g[0] - cur, h, WALL_T), "wall")
		_box(Vector3((g[0] + g[1]) * 0.5, 2.6 + (h - 2.6) * 0.5, z), Vector3(g[1] - g[0], h - 2.6, WALL_T), "wall", false)
		cur = g[1]
	if x1 > cur:
		_box(Vector3((cur + x1) * 0.5, h * 0.5, z), Vector3(x1 - cur, h, WALL_T), "wall")


# A wall running front-back at a fixed x. gaps = [[z_from, z_to], ...] doorways.
func _wall_z(x: float, z0: float, z1: float, gaps: Array = [], h: float = WALL_H) -> void:
	var cuts = gaps.duplicate()
	cuts.sort_custom(func(a, b): return a[0] < b[0])
	var cur = z0
	for g in cuts:
		if g[0] > cur:
			_box(Vector3(x, h * 0.5, (cur + g[0]) * 0.5), Vector3(WALL_T, h, g[0] - cur), "wall")
		_box(Vector3(x, 2.6 + (h - 2.6) * 0.5, (g[0] + g[1]) * 0.5), Vector3(WALL_T, h - 2.6, g[1] - g[0]), "wall", false)
		cur = g[1]
	if z1 > cur:
		_box(Vector3(x, h * 0.5, (cur + z1) * 0.5), Vector3(WALL_T, h, z1 - cur), "wall")


# A candle with a warm light. The demon blows these out as it passes.
func _candle(p: Vector3, energy: float = 1.6, reach: float = 4.5) -> void:
	var node = Models.candle()
	node.position = p
	add_child(node)
	var light = OmniLight3D.new()
	light.position = p + Vector3(0.0, 0.3, 0.0)
	light.light_color = Color(1.0, 0.62, 0.3)
	light.light_energy = energy
	light.omni_range = reach
	light.omni_attenuation = 1.2
	add_child(light)
	candles.append({
		"pos": p,
		"pos2": Vector2(p.x, p.z),
		"light": light,
		"flame": node.get_node("Flame"),
		"lit": true,
		"timer": 0.0,
		"base": energy,
		"phase": rng.randf() * TAU,
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
	_candle(Vector3(-3.6, 1.5, 0.6), 1.4, 4.0)
	_candle(Vector3(3.6, 1.5, 0.6), 1.4, 4.0)
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
		_floor(-8.0, z0, 8.0, z0 + BAY)
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
			_candle(Vector3(x - side * 0.52, 1.7, zk))
			_box(Vector3(x - side * 0.5, 1.62, zk), Vector3(0.2, 0.06, 0.2), "wood", false)

	# GDD "Nef": pews in solid blocks, a centre aisle and cross gaps.
	# The first bay stays empty so there is open floor after the door.
	for b in range(1, bays):
		var zc = _bay_center(b)
		for side in [-1.0, 1.0]:
			var x = side * 2.3
			for row in range(4):
				var zr = zc - 1.3 + row * 0.87
				_box(Vector3(x, 0.42, zr), Vector3(2.4, 0.08, 0.4), "wood", false)
				_box(Vector3(x, 0.66, zr + 0.2), Vector3(2.4, 0.56, 0.07), "wood", false)
				_box(Vector3(x - 1.17, 0.3, zr), Vector3(0.07, 0.6, 0.42), "wood", false)
				_box(Vector3(x + 1.17, 0.3, zr), Vector3(0.07, 0.6, 0.42), "wood", false)
			_collider(Vector3(x, 0.47, zc), Vector3(2.4, 0.94, 3.4))
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
		_floor(minf(side * xa, side * xb), zc - 1.8, maxf(side * xa, side * xb), zc + 1.8)
		_floor(minf(side * 8.0, side * 8.4), zc - 0.9, maxf(side * 8.0, side * 8.4), zc + 0.9)
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
	_floor(-11.0, z_end - 10.0, 11.0, z_end)
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
	_floor(-5.0, z_back, 5.0, z_end - 10.0)
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
	_candle(Vector3(-1.1, 1.15, za), 1.8, 5.0)
	_candle(Vector3(1.1, 1.15, za), 1.8, 5.0)
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

	# the body lies in the gap, one arm reaching for the other end of the line
	var gap_dir = Vector2(cos(gap_angle), sin(gap_angle))
	var gap_point = altar_pos + gap_dir * radius
	var body = Models.dead_exorcist()
	body.position = Vector3(gap_point.x, 0.0, gap_point.y)
	body.rotation.y = -gap_angle - PI * 0.5 + 0.25
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
		if c["lit"]:
			if demon_active and d < 3.5:
				c["lit"] = false
				c["timer"] = 25.0
				c["light"].visible = false
				c["flame"].visible = false
				sfx.play_at("candle_out", c["pos"], -8.0)
			else:
				var flick = 0.9 + 0.1 * sin(_time * 9.0 + c["phase"]) * sin(_time * 3.3 + c["phase"] * 2.0)
				c["light"].light_energy = c["base"] * flick
		else:
			c["timer"] -= dt
			if c["timer"] <= 0.0 and (not demon_active or d > 7.0):
				c["lit"] = true
				c["light"].visible = true
				c["flame"].visible = true
