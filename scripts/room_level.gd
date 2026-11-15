extends Node3D
# ROOM LEVEL - builds a level R.E.P.O.-style out of the 7 room templates (scenes/rooms/dressed/,
# made by tools/build_rooms.py) and gives the rest of the game exactly what level.gd gives it:
# nav, covers, patrol_points, candles, relic_spots, player_start, demon_start, altar_*, narthex_poly,
# crossing_rect, door_pos, near_cover() and update_candles().
#
# How a level is made (all from the seed, so R rebuilds it and a death rolls a new one):
#   1. START is placed first. Its back door (S1) is the way you came in and stays shut.
#   2. The big hall, 3-4 normal rooms and 2-4 corridors are shuffled and each one is attached to a
#      random free doorway of the rooms already placed. A room may be turned by 0/90/180/270 degrees;
#      its doorway must face the free doorway and the two rooms must not overlap.
#   3. END is attached last, to the free doorway that is the most rooms away from START.
#   4. Doorways that meet another room's doorway are opened, every other doorway is walled up.
#      Where two rooms share a wall only the first room's wall is kept (no doubled walls).
#   5. Each room fills its prop slots at random (prop_spawner.gd); then the demon's map, the
#      cover spots, the candles, the relics and the patrol route are read from what was placed.
#
# Directions: Godot x/z. A room's doorway list (scripts/room_templates.gd) gives each doorway's
# position and outward direction for an unturned room.

const T = preload("res://scripts/tuning.gd")
const Nav = preload("res://scripts/nav.gd")
const Models = preload("res://scripts/models.gd")
const Exterior = preload("res://scripts/exterior.gd")
const Tpl = preload("res://scripts/room_templates.gd")
const FlameCluster = preload("res://scripts/flame_cluster.gd")

const MAX_CANDLE_LIGHTS := 30      # GL Compatibility draws at most 64 lights; keep room for the rest
const CIRCLE_RADIUS := 2.2         # the old exorcist's unfinished circle round the altar
const DOOR_HALF_WIDTH := 0.75
const DOOR_APPROACH := 1.85
const CATHEDRAL_LINK := -2

# --- the same public interface as level.gd ---
var nav
var rng := RandomNumberGenerator.new()
var covers := []
var patrol_points := []
var candles := []
var relic_spots := []
var player_start := Vector3.ZERO
var player_yaw := 0.0
var demon_start := Vector2.ZERO
var altar_pos := Vector2.ZERO
var altar_top := Vector3.ZERO
var altar_front := Vector3.BACK
var altar_way_in := Vector2.ZERO
var altar_way_dir := Vector2.ZERO
var altar_circle := PackedVector2Array()
var narthex_poly := PackedVector2Array()
var crossing_rect := Rect2()
var door_pos := Vector3.ZERO
var entrance_leaf: Node3D
var intro_crates: Node3D
var intro_gun_table: Node3D
var extra_rooms := 0
var relic_hardness := 0.0
var _outside: Node3D

# --- the plan ---
# room: {name, tpl, kind, pos: Vector2 (centre), rot: int (quarter turns), rect: Rect2, node,
#        doors: [{key, pos, dir, link (room index or -1), own (draws the doorway), entrance}]}
var rooms := []
var reserved := []                 # Rect2 kept free (outside the entrance door)
var _time := 0.0
var _body: StaticBody3D      # all level collision: simple boxes (mesh collision was slow and snagged on floors)


func build(seed_value: int) -> void:
	var ok := false
	for attempt in range(40):
		rng.seed = seed_value + attempt * 7919
		if _plan():
			ok = true
			break
	if not ok:
		push_error("room_level: no layout found for seed %d" % seed_value)
	var bounds: Rect2 = rooms[0]["rect"]
	for r in rooms:
		bounds = bounds.merge(r["rect"])
	nav = Nav.new()
	nav.setup(bounds.grow(3.0))
	_body = StaticBody3D.new()
	_body.name = "LevelCollision"
	add_child(_body)
	_instance_rooms()
	_place_intro_crates()
	_place_gun_table()
	_clear_doorways_and_props()
	_keep_passable()
	_wall_boxes()
	_carve_and_block()
	_light_candles()
	_start_room()
	_end_room()
	_place_relics()
	_route()
	nav.commit()


# The cathedral owns the shared navigation grid and reserves its central footprint.
func plan_wings(seed_value: int, cathedral: Rect2, portals: Array[Vector2]) -> Rect2:
	rng.seed = seed_value
	for attempt in 41:
		rooms.clear()
		reserved.assign([cathedral, Rect2(-10.0, 6.0, 20.0, 18.0)])
		# Straight corridors into 4 m wide rooms fit even at adjacent cathedral bays.
		var straight_wings := attempt == 40
		var complete := true
		for portal in portals:
			var out := Vector2(signf(portal.x), 0.0)
			var turns := [1] if out.x > 0.0 else [3]
			var tpl := "room6_corridor_long" if straight_wings or rng.randf() < 0.5 else "room7_corridor_short"
			var root_index := rooms.size()
			if not _attach_to(tpl, turns, portal, out):
				complete = false
				break
			var connectors := _open_doors().filter(func(c): return c.x == root_index)
			var normal := "room1_normal" if not straight_wings and rng.randf() < 0.5 else "room5_normal_wide"
			if straight_wings:
				connectors = connectors.filter(func(c): return rooms[c.x]["doors"][c.y]["dir"] == out)
			var room_turns := [0] if straight_wings else [0, 1, 2, 3]
			if not _attach(normal, room_turns, connectors):
				complete = false
				break
		if complete:
			for i in 3 + extra_rooms:
				var tpl := "room1_normal" if rng.randf() < 0.55 else ("room5_normal_wide" if rng.randf() < 0.5 else "room7_corridor_short")
				_attach(tpl, [0, 1, 2, 3], _open_doors())
			if not _attach_end(cathedral.get_center()):
				continue
			var bounds := cathedral
			for room in rooms:
				bounds = bounds.merge(room["rect"])
			return bounds
	push_error("Could not plan cathedral wings for seed %d" % seed_value)
	return cathedral


func _attach_end(centre: Vector2) -> bool:
	var opens := _open_doors()
	opens.sort_custom(func(a, b): return rooms[a.x]["doors"][a.y]["pos"].distance_to(centre) > rooms[b.x]["doors"][b.y]["pos"].distance_to(centre))
	for o in opens:
		if _attach("room2_end", [0, 2], [o]):
			return true
	return false


func build_wings(shared_nav) -> void:
	nav = shared_nav
	_body = StaticBody3D.new()
	_body.name = "WingCollision"
	add_child(_body)
	_instance_rooms()
	_clear_doorways_and_props()
	_keep_passable()
	_wall_boxes()
	_carve_and_block()
	_light_candles(12)
	_place_relics(true)
	_end_room()


# =================================================================== PLANNING

func _rot(v: Vector2, k: int) -> Vector2:
	var a := k * PI * 0.5
	var c := cos(a)
	var s := sin(a)
	# same turn as Node3D.rotation.y = a (x/z plane)
	return Vector2(snappedf(v.x * c + v.y * s, 0.001), snappedf(-v.x * s + v.y * c, 0.001))


func _rect(name: String, pos: Vector2, k: int) -> Rect2:
	var half: Vector2 = Tpl.TEMPLATES[name]["half"]
	if k % 2 == 1:
		half = Vector2(half.y, half.x)
	return Rect2(pos - half, half * 2.0)


func _add_room(name: String, pos: Vector2, k: int) -> int:
	var t: Dictionary = Tpl.TEMPLATES[name]
	var doors := []
	for d in t["doors"]:
		doors.append({"key": d[0], "pos": pos + _rot(d[1], k), "dir": _rot(d[2], k), "link": -1, "own": false, "entrance": false})
	rooms.append({"name": name, "kind": t["kind"], "pos": pos, "rot": k, "rect": _rect(name, pos, k), "doors": doors, "node": null})
	return rooms.size() - 1


func _fits(rect: Rect2, wing := -1) -> bool:
	var inner := rect.grow(-0.05)
	for r in rooms:
		# Wings can start on different tile grids. Leave their wall trim clear of each other.
		if wing >= 0 and r["wing"] != wing and rect.grow(0.65).intersects(r["rect"]):
			return false
		if r["rect"].grow(-0.05).intersects(inner):
			return false
	for r in reserved:
		if r.intersects(inner):
			return false
	return true


func _open_doors() -> Array:
	var out := []
	for i in rooms.size():
		for j in rooms[i]["doors"].size():
			var d = rooms[i]["doors"][j]
			if d["link"] == -1 and not d["entrance"]:
				out.append(Vector2i(i, j))
	return out


func _shuffle(list: Array) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = list[i]
		list[i] = list[j]
		list[j] = tmp


func _plan() -> bool:
	rooms.clear()
	reserved.clear()
	var s := _add_room("room3_start", Vector2.ZERO, rng.randi_range(0, 3))
	for d in rooms[s]["doors"]:
		if d["key"] == "S1":
			d["entrance"] = true
			var dir: Vector2 = d["dir"]
			var size := Vector2(18.0, 20.0) if absf(dir.x) > 0.5 else Vector2(20.0, 18.0)
			reserved.append(Rect2(d["pos"] + dir * 9.2 - size * 0.5, size))
	var pieces := ["room4_big_hall"]
	for i in rng.randi_range(3, 4) + extra_rooms / 2:
		pieces.append("room1_normal" if rng.randf() < 0.5 else "room5_normal_wide")
	for i in rng.randi_range(2, 4) + extra_rooms - extra_rooms / 2:
		pieces.append("room6_corridor_long" if rng.randf() < 0.5 else "room7_corridor_short")
	_shuffle(pieces)
	# a corridor first keeps START from opening straight into a big room
	pieces.push_front("room6_corridor_long" if rng.randf() < 0.5 else "room7_corridor_short")
	var normals := 0
	var hall := false
	for p in pieces:
		if _attach(p, [0, 1, 2, 3], _open_doors()):
			if p == "room4_big_hall": hall = true
			if p.begins_with("room1") or p.begins_with("room5"): normals += 1
	if not hall or normals < 2:
		return false
	# END goes to the free doorway furthest (in rooms) from START
	var depth := _depths()
	var opens := _open_doors()
	opens.sort_custom(func(a, b): return depth[a.x] > depth[b.x])
	for o in opens:
		if _attach("room2_end", [0, 2], [o]):     # 0/180 only: the relics are laid along the altar's x
			return true
	return false


func _attach(name: String, turns: Array, connectors: Array) -> bool:
	var cons := connectors.duplicate()
	if cons.size() > 1:
		_shuffle(cons)
	for c in cons:
		var a = rooms[c.x]["doors"][c.y]
		if _attach_to(name, turns, a["pos"], a["dir"], c):
			return true
	return false


func _attach_to(name: String, turns: Array, portal: Vector2, out: Vector2, connector := Vector2i(-1, -1)) -> bool:
	var doors: Array = Tpl.TEMPLATES[name]["doors"]
	var wing: int = rooms[connector.x].get("wing", -1) if connector.x >= 0 else rooms.size()
	var options := []
	for di in doors.size():
		for k in turns:
			if _rot(doors[di][2], k).is_equal_approx(-out):
				options.append([di, k])
	_shuffle(options)
	for option in options:
		var pos := portal - _rot(doors[option[0]][1], option[1])
		if not _fits(_rect(name, pos, option[1]), wing):
			continue
		var b := _add_room(name, pos, option[1])
		if connector.x >= 0:
			_link(connector.x, connector.y, b, option[0])
		else:
			var d: Dictionary = rooms[b]["doors"][option[0]]
			d["link"] = CATHEDRAL_LINK
			d["own"] = true
		if wing >= 0:
			rooms[b]["wing"] = wing
		_auto_link(b)
		return true
	return false


func _link(ia: int, da: int, ib: int, db: int) -> void:
	rooms[ia]["doors"][da]["link"] = ib
	rooms[ia]["doors"][da]["own"] = true          # the older room draws the doorway
	rooms[ib]["doors"][db]["link"] = ia


# A new room may by chance line a free doorway up with another room's free doorway: join them.
func _auto_link(b: int) -> void:
	for db in rooms[b]["doors"].size():
		var d = rooms[b]["doors"][db]
		if d["link"] != -1:
			continue
		for ia in range(b):
			for da in rooms[ia]["doors"].size():
				var e = rooms[ia]["doors"][da]
				if e["link"] == -1 and not e["entrance"] and e["pos"].distance_to(d["pos"]) < 0.1 and e["dir"].is_equal_approx(-d["dir"]):
					_link(ia, da, b, db)


func _neighbours(i: int) -> Array:
	var out := []
	for d in rooms[i]["doors"]:
		if d["link"] >= 0:
			out.append(d["link"])
	return out


func _depths() -> Array:
	var depth := []
	depth.resize(rooms.size())
	depth.fill(-1)
	depth[0] = 0
	var queue := [0]
	while not queue.is_empty():
		var i: int = queue.pop_front()
		for j in _neighbours(i):
			if depth[j] < 0:
				depth[j] = depth[i] + 1
				queue.append(j)
	return depth


# ================================================================= BUILDING

func _key(p: Vector3) -> String:
	return "%d_%d" % [roundi(p.x * 10.0), roundi(p.z * 10.0)]


func _instance_rooms() -> void:
	var owner_of := {}            # wall/window/doorway position -> room index (first one wins)
	var door_pilasters := {}
	for r in rooms:
		for d in r["doors"]:
			if d["link"] != -1 and d["own"]:
				var p: Vector2 = d["pos"]
				var side: Vector2 = d["dir"].orthogonal()
				for edge in [p - side, p + side]:
					door_pilasters[_key(Vector3(edge.x, 0.0, edge.y))] = true
	for i in rooms.size():
		var r = rooms[i]
		var node: Node3D = load(Tpl.TEMPLATES[r["name"]]["scene"]).instantiate()
		node.name = "Room%d_%s" % [i, r["kind"]]
		node.position = Vector3(r["pos"].x, 0.0, r["pos"].y)
		node.rotation.y = r["rot"] * PI * 0.5
		node.light_flames = false
		node.make_collision = false
		var xf := node.transform
		var open := PackedStringArray()
		var empty := PackedStringArray()
		for d in r["doors"]:
			if d["entrance"] or (d["link"] != -1 and d["own"]):
				open.append(d["key"])
			elif d["link"] >= 0:
				empty.append(d["key"])
		# walls and windows another room already has
		var shell := node.get_node("Shell")
		for c in shell.get_children():
			var nm := String(c.name)
			if not (nm.begins_with("Wall_") or nm.begins_with("Window_") or nm.begins_with("Pilaster_")):
				continue
			var point := _key(xf * c.position)
			var pilaster := nm.begins_with("Pilaster")
			if pilaster and door_pilasters.has(point):
				c.visible = false
				continue
			var k := ("p" if pilaster else "w") + point
			if owner_of.has(k) and owner_of[k] != i:
				c.visible = false
				var moon := node.get_node_or_null("Lights/Moon_" + nm.get_slice("_", 1))
				if moon: moon.visible = false
			else:
				owner_of[k] = i
		for slot in node.get_children():
			var sn := String(slot.name)
			if not sn.begins_with("DoorSlot_"):
				continue
			var key := sn.trim_prefix("DoorSlot_")
			var k := "w" + _key(xf * slot.position)
			if owner_of.has(k) and owner_of[k] != i:
				if not empty.has(key):
					empty.append(key)
				var at := open.find(key)
				if at >= 0:
					open.remove_at(at)
			else:
				owner_of[k] = i
		node.open_doors = open
		node.empty_doors = empty
		for d in r["doors"]:
			if not open.has(d["key"]):
				continue
			var door: Node3D = node.get_node("DoorSlot_%s/Doorway/Door" % d["key"])
			if d["entrance"]:
				door.get_node("DoorFrame").hide()
				var leaf: Node3D = door.get_node("DoorLeaf")
				leaf.position.x = -DOOR_HALF_WIDTH
				leaf.scale.x = 1.4
				entrance_leaf = leaf
			else:
				# Linked rooms share a clear stone arch. Only the entrance has a door.
				door.hide()
		var slots = node.get_node_or_null("Slots")
		if slots:
			slots.seed_value = (rng.randi() & 0x7fffffff) | 1
		for l in node.find_children("*", "Light3D", true, false):
			l.shadow_enabled = false
		add_child(node)              # the room fills its slots and builds its collision here
		r["node"] = node


# ------------------------------------------------------------- doorways stay clear


func _footprint(box: AABB) -> Rect2:
	return Rect2(box.position.x, box.position.z, box.size.x, box.size.z)


func _door_strip(d: Dictionary, depth: float, half_width: float) -> Rect2:
	var axis: Vector2 = d["dir"].abs()
	var half := axis * depth + Vector2(axis.y, axis.x) * half_width
	return Rect2(d["pos"] - half, half * 2.0)


func _clear_doorways_and_props() -> void:
	var zones: Array[Rect2] = []
	for r in rooms:
		for d in r["doors"]:
			if (d["link"] != -1 and d["own"]) or d["entrance"]:
				zones.append(_door_strip(d, DOOR_APPROACH, DOOR_HALF_WIDTH + 0.12))
	for r in rooms:
		var occupied := []
		var fixed: Node = r["node"].get_node_or_null("Fixed")
		for prop in _props_of(r["node"]):
			var box := _world_box(prop)
			if box.size == Vector3.ZERO:
				continue
			if box.position.y < 2.3 and box.end.y > 0.06:
				var foot := _footprint(box)
				if zones.any(func(zone): return zone.intersects(foot)):
					prop.hide()
					continue
			# Companions authored in one group may overlap. Require clearance between random groups.
			var parent: Node = prop.get_parent()
			var group: Node = prop if parent is Marker3D else parent
			var inset := (box.size * 0.25).min(Vector3.ONE * 0.035)
			var inner := AABB(box.position + inset, box.size - inset * 2.0)
			if parent != fixed and occupied.any(func(other): return other[0] != group and other[1].intersects(inner)):
				prop.hide()
				continue
			occupied.append([group, box])


const PASS_CELL := 0.2
const PASS_RADIUS := 0.36


func _keep_passable() -> void:
	var bounds: Rect2 = rooms[0]["rect"]
	for r in rooms:
		bounds = bounds.merge(r["rect"])
	bounds = bounds.grow(1.0)
	var w := int(ceil(bounds.size.x / PASS_CELL))
	var h := int(ceil(bounds.size.y / PASS_CELL))
	var at := func(p: Vector2) -> int:
		var c := Vector2i(((p - bounds.position) / PASS_CELL).floor())
		return clampi(c.x, 0, w - 1) + clampi(c.y, 0, h - 1) * w
	var walk := PackedByteArray()
	walk.resize(w * h)
	var areas: Array[Rect2] = []
	var roots: Array[Vector2] = []
	var targets: Array[Vector2] = []
	for r in rooms:
		areas.append(r["rect"].grow(-0.5))
		for d in r["doors"]:
			if d["link"] == -1 and not d["entrance"]:
				continue
			targets.append(d["pos"] - d["dir"] * 0.7)
			if d["entrance"] or d["link"] == CATHEDRAL_LINK:
				roots.append(d["pos"] - d["dir"] * 0.7)
			if d["own"] or d["entrance"]:
				areas.append(_door_strip(d, 0.8, DOOR_HALF_WIDTH - PASS_RADIUS))
	if roots.is_empty():
		roots.append(targets[0] if not targets.is_empty() else rooms[0]["pos"])
	for area in areas:
		var a: int = at.call(area.position)
		var b: int = at.call(area.end)
		for z in range(a / w, b / w + 1):
			for x in range(a % w, b % w + 1):
				var c := bounds.position + (Vector2(x, z) + Vector2(0.5, 0.5)) * PASS_CELL
				if area.has_point(c):
					walk[x + z * w] = 1
	var props := []
	var blocker := PackedInt32Array()
	blocker.resize(w * h)
	blocker.fill(-1)
	for r in rooms:
		var fixed: Node = r["node"].get_node_or_null("Fixed")
		for prop in _props_of(r["node"]):
			var box := _world_box(prop)
			if box.size == Vector3.ZERO or box.position.y > 0.5 or box.end.y < 0.45:
				continue
			var ob := _oriented_box(prop)
			var xf: Transform3D = ob[0]
			var half: Vector3 = ob[1] * 0.44 + Vector3.ONE * PASS_RADIUS
			var foot: Rect2 = ob[2].grow(PASS_RADIUS)
			var index := props.size()
			props.append([prop, prop.get_parent() == fixed])
			var inv := xf.affine_inverse()
			var a: int = at.call(foot.position)
			var b: int = at.call(foot.end)
			for z in range(a / w, b / w + 1):
				for x in range(a % w, b % w + 1):
					var c := bounds.position + (Vector2(x, z) + Vector2(0.5, 0.5)) * PASS_CELL
					var l := inv * Vector3(c.x, xf.origin.y, c.y)
					if absf(l.x) <= half.x and absf(l.z) <= half.z and blocker[x + z * w] == -1:
						blocker[x + z * w] = index
	for _attempt in 8:
		var seen := _pass_flood(walk, blocker, w, h, roots.map(func(p): return at.call(p)))
		var goals := []
		for t in targets:
			var i: int = at.call(t)
			if walk[i] and blocker[i] == -1 and not seen[i]:
				goals.append(i)
		for cells in _pass_pockets(walk, blocker, w, h, seen):
			if cells.size() >= 24:
				goals.append(cells[cells.size() / 2])
		if goals.is_empty():
			return
		var cut := _pass_cut(walk, blocker, props, w, h, seen, goals)
		if cut.is_empty():
			return
		for k in cut:
			props[k][0].hide()
			for i in w * h:
				if blocker[i] == k:
					blocker[i] = -1


func _pass_flood(walk: PackedByteArray, blocker: PackedInt32Array, w: int, h: int, starts: Array) -> PackedByteArray:
	var seen := PackedByteArray()
	seen.resize(w * h)
	var stack := []
	for s in starts:
		if walk[s] and blocker[s] == -1 and not seen[s]:
			seen[s] = 1
			stack.append(s)
	while not stack.is_empty():
		var i: int = stack.pop_back()
		var x: int = i % w
		for n in [i - 1 if x > 0 else -1, i + 1 if x < w - 1 else -1, i - w, i + w]:
			if n >= 0 and n < w * h and walk[n] and blocker[n] == -1 and not seen[n]:
				seen[n] = 1
				stack.append(n)
	return seen


func _pass_pockets(walk: PackedByteArray, blocker: PackedInt32Array, w: int, h: int, seen: PackedByteArray) -> Array:
	var mark := seen.duplicate()
	var out := []
	for s in w * h:
		if mark[s] or not walk[s] or blocker[s] != -1:
			continue
		var cells := [s]
		mark[s] = 1
		var k := 0
		while k < cells.size():
			var i: int = cells[k]
			k += 1
			var x: int = i % w
			for n in [i - 1 if x > 0 else -1, i + 1 if x < w - 1 else -1, i - w, i + w]:
				if n >= 0 and n < w * h and walk[n] and blocker[n] == -1 and not mark[n]:
					mark[n] = 1
					cells.append(n)
		out.append(cells)
	return out


func _pass_cut(walk: PackedByteArray, blocker: PackedInt32Array, props: Array, w: int, h: int, seen: PackedByteArray, goals: Array) -> Array:
	var dist := PackedInt32Array()
	dist.resize(w * h)
	dist.fill(1 << 30)
	var from := PackedInt32Array()
	from.resize(w * h)
	from.fill(-1)
	var buckets := {0: []}
	for i in w * h:
		if seen[i]:
			dist[i] = 0
			buckets[0].append(i)
	var left := goals.size()
	var d := 0
	var top := 0
	while d <= top and left > 0:
		var bucket: Array = buckets.get(d, [])
		buckets.erase(d)
		for i in bucket:
			if dist[i] != d:
				continue
			if i in goals:
				left -= 1
			var x: int = i % w
			for n in [i - 1 if x > 0 else -1, i + 1 if x < w - 1 else -1, i - w, i + w]:
				if n < 0 or n >= w * h or not walk[n]:
					continue
				var step := 1
				if blocker[n] >= 0:
					step = 120 if props[blocker[n]][1] else 12
				var nd := d + step
				if nd < dist[n]:
					dist[n] = nd
					from[n] = i
					if not buckets.has(nd):
						buckets[nd] = []
					buckets[nd].append(n)
					top = maxi(top, nd)
		d += 1
	var cut := {}
	for g in goals:
		var i: int = g
		while i >= 0 and dist[i] > 0:
			if blocker[i] >= 0:
				cut[blocker[i]] = true
			i = from[i]
	return cut.keys()


# ------------------------------------------------------------- collision

func _box(xf: Transform3D, centre: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.transform = xf * Transform3D(Basis.IDENTITY, centre)
	_body.add_child(cs)


# Walls, window walls and pilasters as plain boxes; the jambs match the open arch.
# Floors get no collision at all: the player floats at y = 0, like in level.gd.
func _wall_boxes() -> void:
	for r in rooms:
		var node: Node3D = r["node"]
		for c in node.get_node("Shell").get_children():
			if not c.visible:
				continue
			var nm := String(c.name)
			if nm.begins_with("Wall_"):
				_box(c.global_transform, Vector3(0, 2.25, 0), Vector3(2.0, 4.5, 0.4))
			elif nm.begins_with("Pilaster_"):
				_box(c.global_transform, Vector3(0, 2.25, 0), Vector3(0.7, 4.5, 0.7))
		for d in r["doors"]:
			var slot := node.get_node_or_null("DoorSlot_" + d["key"])
			if slot == null:
				continue
			var wall: Node3D = slot.get_node("Wall")
			var way: Node3D = slot.get_node("Doorway")
			if wall.visible:
				_box(slot.global_transform, Vector3(0, 2.25, 0), Vector3(2.0, 4.5, 0.4))
			elif way.visible:
				var jamb_width := 1.0 - DOOR_HALF_WIDTH
				for sx in [-1.0, 1.0]:
					_box(slot.global_transform, Vector3(sx * (1.0 - jamb_width * 0.5), 2.25, 0), Vector3(jamb_width, 4.5, 0.4))
				_box(slot.global_transform, Vector3(0, 3.5, 0), Vector3(2.0, 2.0, 0.4))         # above the arch
				if d["entrance"]:
					var leaf_box := _world_box(way.get_node("Door/DoorLeaf"))
					_box_xf(Transform3D(Basis.IDENTITY, leaf_box.get_center()), leaf_box.size)


# ------------------------------------------------- demon map + hiding spots

func _carve_and_block() -> void:
	for r in rooms:
		nav.carve(r["rect"].grow(-0.26))
		for d in r["doors"]:
			if d["link"] != -1 and d["own"]:
				nav.carve(_door_strip(d, 0.7, DOOR_HALF_WIDTH - 0.2))
	for r in rooms:
		for prop in _props_of(r["node"]):
			var box := _world_box(prop)
			if box.size == Vector3.ZERO:
				continue
			if box.position.y > 0.5:               # wall-mounted (sconces, crosses, banners)
				continue
			var tall := box.end.y
			if tall < 0.45:                        # low things (bottles, bones, books, sacks' spill): step over them
				continue
			var ob := _oriented_box(prop)
			var foot: Rect2 = ob[2]
			# the demon's map: the prop's real (turned) outline with a small margin
			nav.block(foot.grow(-0.06), 0.12)
			if tall > 0.7:
				covers.append(foot)
			# you bump into a box a little smaller than the prop, so you slide past corners
			_box_xf(ob[0], ob[1] * Vector3(0.88, 1.0, 0.88))


# Every placed prop instance of a room: the fixed set pieces and what the spawner put in the slots.
func _props_of(room: Node) -> Array:
	var out := []
	var fixed := room.get_node_or_null("Fixed")
	if fixed:
		for c in fixed.get_children():
			if not String(c.name).begins_with("NoCollide"):
				out.append(c)
	var slots := room.get_node_or_null("Slots")
	if slots:
		for marker in slots.get_children():
			for g in marker.get_children():
				if not (g is Node3D):
					continue
				if String(g.scene_file_path).ends_with(".glb"):
					out.append(g)                 # clutter or an artifact: a single model
				else:
					for c in g.get_children():
						if c is Node3D and not (c is Marker3D) and not String(c.name).begins_with("NoCollide"):
							out.append(c)
	return out


# The prop's bounds in its own (turned) frame: [Transform3D of the box centre, size, world footprint Rect2].
func _oriented_box(n: Node3D) -> Array:
	var inv := n.global_transform.affine_inverse()
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		if not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		var b: AABB = (inv * mi.global_transform) * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var xf := n.global_transform
	var scale := xf.basis.get_scale()
	var centre := xf * box.get_center()
	var basis := xf.basis.orthonormalized()
	var size := box.size * scale
	var foot := Rect2(Vector2(centre.x, centre.z), Vector2.ZERO)
	for sx in [-0.5, 0.5]:
		for sz in [-0.5, 0.5]:
			var c := centre + basis * Vector3(size.x * sx, 0.0, size.z * sz)
			foot = foot.expand(Vector2(c.x, c.z))
	return [Transform3D(basis, Vector3(centre.x, centre.y, centre.z)), size, foot]


func _box_xf(xf: Transform3D, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.transform = xf
	_body.add_child(cs)


func _world_box(n: Node3D) -> AABB:
	var box := AABB()
	if not n.is_visible_in_tree():
		return box
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		if not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if n is MeshInstance3D and n.mesh != null:
		var b2: AABB = n.global_transform * n.get_aabb()
		box = b2 if first else box.merge(b2)
	return box


# ------------------------------------------------------------- candles

# The props' FlameSpot markers become flame clusters (one light per prop) the demon can blow out.
func _light_candles(light_limit := MAX_CANDLE_LIGHTS) -> void:
	var clusters := []            # [room index, [positions]]
	for i in rooms.size():
		var spots := []
		for s in rooms[i]["node"].find_children("FlameSpot*", "", true, false):
			if s.is_visible_in_tree():
				spots.append(s.global_position)
		while not spots.is_empty():
			var seed_p: Vector3 = spots.pop_back()
			var group := [seed_p]
			for j in range(spots.size() - 1, -1, -1):
				if spots[j].distance_to(seed_p) < 0.9:
					group.append(spots[j])
					spots.remove_at(j)
			clusters.append([i, group])
	# share the lights out fairly: every room's first cluster first, then the rest
	_shuffle(clusters)
	clusters.sort_custom(func(a, b): return a[0] < b[0])
	var given := {}
	var order := []
	for pass_n in 8:
		for c in clusters:
			if given.get(c[0], 0) == pass_n and not order.has(c):
				order.append(c)
				given[c[0]] = pass_n + 1
	for c in clusters:
		if not order.has(c):
			order.append(c)
	for n in order.size():
		var group: Array = order[n][1]
		var centre := Vector3.ZERO
		for p in group:
			centre += p
		centre /= group.size()
		var cl = FlameCluster.new()
		add_child(cl)
		cl.global_position = centre
		cl.setup(group, n < light_limit)
		candles.append({"pos": centre, "pos2": Vector2(centre.x, centre.z), "candle": cl, "lit": true, "timer": 0.0})


# ----------------------------------------------------------- START and END

func drop_outside() -> void:
	if _outside != null:
		_outside.queue_free()
		_outside = null


func _place_intro_crates() -> void:
	var room: Node3D = rooms[0]["node"]
	var fixed := room.get_node_or_null("Fixed")
	var marker := room.get_node_or_null("Slots/corner_SE") as Node3D
	if fixed == null or marker == null:
		return
	var c: Node3D = load("res://assets/props/crates.glb").instantiate()
	c.name = "IntroCrates"
	fixed.add_child(c)
	c.global_transform = marker.global_transform
	intro_crates = c


func _place_gun_table() -> void:
	var room: Node3D = rooms[0]["node"]
	var fixed := room.get_node_or_null("Fixed")
	if fixed == null:
		return
	var t: Node3D = load("res://assets/props/chalktable.glb").instantiate()
	t.name = "GunTable"
	fixed.add_child(t)
	t.global_transform = room.global_transform * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-2.42, 0.0, -0.05))
	intro_gun_table = t


func _start_room() -> void:
	var r = rooms[0]
	var entrance: Dictionary = {}
	var exit: Dictionary = {}
	for d in r["doors"]:
		if d["entrance"]:
			entrance = d
		elif d["link"] >= 0:
			exit = d
	var c: Vector2 = r["pos"]
	var e: Vector2 = entrance["pos"]
	var p := c.lerp(e, 0.45)
	player_start = Vector3(p.x, 0.0, p.y)
	var x: Vector2 = exit["pos"]
	var to := x - p
	player_yaw = atan2(-to.x, -to.y)
	door_pos = Vector3(e.x, 1.5, e.y)
	_outside = Exterior.new()
	add_child(_outside)
	var out_dir: Vector2 = entrance["dir"]
	_outside.build(Vector3(e.x, 0.0, e.y), Vector3(out_dir.x, 0.0, out_dir.y), rng.randi())
	# the salt threshold: the whole START room is safe; only the edge across the exit doorway is drawn
	var o: Vector2 = exit["dir"]
	var a := Vector2(-o.y, o.x)
	var rect: Rect2 = r["rect"]
	var depth := absf(o.x) * rect.size.x + absf(o.y) * rect.size.y
	var ha := (absf(a.x) * rect.size.x + absf(a.y) * rect.size.y) * 0.5 + 0.1
	var wall_mid := c + o * depth * 0.5
	var cp := wall_mid + a * ha
	var cm := wall_mid - a * ha
	narthex_poly = PackedVector2Array([
		x - a * 0.85 + o * 0.5, x + a * 0.85 + o * 0.5, x + a * 0.85,
		cp, cp - o * (depth + 0.2), cm - o * (depth + 0.2), cm, x - a * 0.85,
	])
	for i in rooms.size():
		if rooms[i]["kind"] == "big":
			crossing_rect = rooms[i]["rect"]
			demon_start = _free_near(rooms[i]["pos"])


func _end_room() -> void:
	var r = null
	for x in rooms:
		if x["kind"] == "end":
			r = x
	var room: Node3D = r["node"]
	var altar: Node3D = room.get_node("Fixed/altar_0")
	var ap := altar.global_position
	altar_pos = Vector2(ap.x, ap.z)
	altar_top = Vector3(ap.x, 1.03, ap.z)
	# the altar blocks the way; you can hide behind it
	var foot := Rect2(ap.x - 0.9, ap.z - 0.45, 1.8, 0.9)
	if r["rot"] % 2 == 1:
		foot = Rect2(ap.x - 0.45, ap.z - 0.9, 0.9, 1.8)
	# the unfinished circle, its gap turned towards the way in
	var way_in := Vector2.ZERO
	for d in r["doors"]:
		if d["link"] >= 0:
			way_in = d["pos"]
			altar_way_dir = d["dir"]
	altar_way_in = way_in
	var ab := altar.global_basis.orthonormalized()
	var to_way := Vector3(way_in.x - ap.x, 0.0, way_in.y - ap.z)
	altar_front = ab.z if ab.z.dot(to_way) >= 0.0 else -ab.z
	altar_front.y = 0.0
	altar_front = altar_front.normalized()
	var gap_angle := (way_in - altar_pos).angle() + 0.35
	var half_gap := 0.24
	var ang := gap_angle + half_gap
	var a_end := gap_angle - half_gap + TAU
	while ang <= a_end:
		altar_circle.append(altar_pos + Vector2(cos(ang), sin(ang)) * CIRCLE_RADIUS)
		ang += 0.07
	altar_circle.append(altar_pos + Vector2(cos(a_end), sin(a_end)) * CIRCLE_RADIUS)
	# the dead exorcist beside his line, his chalk at its end, claw marks in the gap
	var stop := gap_angle - half_gap
	var line_end := altar_pos + Vector2(cos(stop), sin(stop)) * CIRCLE_RADIUS
	var ahead := Vector2(-sin(stop), cos(stop))
	var outward := Vector2(cos(stop), sin(stop))
	var body = Models.dead_exorcist()
	var o := line_end - ahead * 1.0 - outward * 0.15
	body.name = "DeadExorcist"
	body.transform = Transform3D(Basis(Vector3(ahead.x, 0.0, ahead.y), Vector3.UP, Vector3(-outward.x, 0.0, -outward.y)), Vector3(o.x, 0.0, o.y))
	add_child(body)
	var claws = Models.claw_marks()
	var gap_dir := Vector2(cos(gap_angle), sin(gap_angle))
	var claw_point := altar_pos + gap_dir * (CIRCLE_RADIUS - 0.75)
	claws.position = Vector3(claw_point.x, 0.0, claw_point.y)
	claws.rotation.y = -gap_angle
	add_child(claws)
	covers.append(foot)
	_box(Transform3D.IDENTITY, Vector3(ap.x, 0.55, ap.z), Vector3(foot.size.x, 1.1, foot.size.y))


# ----------------------------------------------------------------- relics

func _place_relics(normal_rooms_only := false) -> void:
	var spots := []               # [room index, Vector3]
	var fallback_spots := []
	for i in rooms.size():
		var r = rooms[i]
		if r["kind"] in ["start", "end"]:
			continue
		if normal_rooms_only and r["kind"] != "normal":
			continue
		var node: Node3D = r["node"]
		for marker in node.find_children("item_*", "Marker3D", true, false):
			var p := Vector2(marker.global_position.x, marker.global_position.z)
			if _relic_floor_is_clear(p):
				spots.append([i, Vector3(p.x, 0.0, p.y)])
		var interior: Rect2 = r["rect"].grow(-0.55)
		var first: Vector2i = nav.cell_of(interior.position)
		var last: Vector2i = nav.cell_of(interior.end)
		for x in range(first.x, last.x + 1):
			for z in range(first.y, last.y + 1):
				var p: Vector2 = nav.center_of(Vector2i(x, z))
				if interior.has_point(p) and _relic_floor_is_clear(p):
					fallback_spots.append([i, Vector3(p.x, 0.0, p.y)])
	_shuffle(spots)
	_shuffle(fallback_spots)
	if relic_hardness > 0.0:
		var origin := _relic_origin()
		var score := func(s): return s[1].distance_to(origin) * relic_hardness + _rng_score(s) * (1.0 - relic_hardness) * 30.0
		spots.sort_custom(func(a, b): return score.call(a) > score.call(b))
	spots.append_array(fallback_spots)
	var kinds := ["chalice", "cross", "censer", "book"]
	var used_areas := {}
	for pass_n in 2:
		for s in spots:
			if relic_spots.size() >= kinds.size():
				return
			var area: int = rooms[s[0]].get("wing", s[0])
			if pass_n == 0 and used_areas.has(area):
				continue
			var taken := false
			for rs in relic_spots:
				if rs["pos"].distance_to(s[1]) < 1.0:
					taken = true
			if taken:
				continue
			used_areas[area] = true
			relic_spots.append({"pos": s[1], "kind": kinds[relic_spots.size()], "chapel": rooms[s[0]]["kind"] == "normal"})


func _relic_origin() -> Vector3:
	if not rooms.is_empty() and rooms[0]["kind"] == "start":
		return Vector3(rooms[0]["pos"].x, 0.0, rooms[0]["pos"].y)
	return Vector3.ZERO


func _rng_score(s: Array) -> float:
	return fposmod(sin(s[1].x * 12.9898 + s[1].z * 78.233) * 43758.5453, 1.0)


func _relic_floor_is_clear(p: Vector2) -> bool:
	if not nav.is_free(p):
		return false
	# Keep the floor pickup and the space immediately around it clear of props.
	for i in 8:
		if not nav.is_free(p + Vector2.from_angle(i * TAU / 8.0) * 0.4):
			return false
	return true


# ----------------------------------------------------------------- patrol

# The demon walks the rooms in a fixed order (depth first from START, and back), so players can learn it.
func _route() -> void:
	var seen := {0: true}
	var exit_pos := Vector2.ZERO
	for d in rooms[0]["doors"]:
		if d["link"] >= 0:
			exit_pos = d["pos"] + d["dir"] * 1.2
	patrol_points.append(exit_pos)
	_walk(0, seen)
	patrol_points.append(exit_pos)


func _walk(i: int, seen: Dictionary) -> void:
	for d in rooms[i]["doors"]:
		var j: int = d["link"]
		if j < 0 or seen.has(j):
			continue
		seen[j] = true
		patrol_points.append(_free_near(rooms[j]["pos"]))
		_walk(j, seen)
		if i != 0:
			patrol_points.append(_free_near(rooms[i]["pos"]))


func _free_near(p: Vector2) -> Vector2:
	if nav.is_free(p):
		return p
	for ring in range(1, 8):
		for k in 12:
			var q := p + Vector2(cos(k * TAU / 12.0), sin(k * TAU / 12.0)) * ring * 0.4
			if nav.is_free(q):
				return q
	return p


# ----------------------------------------------------------------- QUERIES (as level.gd)

func near_cover(p: Vector2, dist: float) -> bool:
	for r in covers:
		var c = Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
		if c.distance_to(p) <= dist:
			return true
	return false


func update_candles(prowling: PackedVector2Array, dt: float, sfx, _viewer := Vector2.INF) -> void:
	_time += dt
	var demon_active := not prowling.is_empty()
	for c in candles:
		var d = nearest(c["pos2"], prowling)
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


static func nearest(p: Vector2, points: PackedVector2Array) -> float:
	var best := INF
	for q in points:
		best = minf(best, p.distance_to(q))
	return best
