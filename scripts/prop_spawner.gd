extends Node3D
## Random room dressing, like R.E.P.O.'s prop groups. Put on a room's "Slots" node.
## Every child Marker3D is a slot named "<type>_<id>":
##   wall_*   back against a wall, facing into the room        (bookshelf, wardrobe, study desk, storage...)
##   narrow_* wall slot in a corridor: only shallow groups
##   deco_*   on a wall face, groups set their own height      (sconce, banner) - skipped above tall wall groups
##   corner_* inner room corner, facing the room centre
##   center_* open floor, any rotation                         (rug, tomb, font, floor candles...)
##   clutter_* drops 1-3 small items around the spot
##   item_*   candidate spot for an artifact
## Wall and deco slots on the same wall segment share an id (wall_N0 / deco_N0).
## Spawned groups may contain "ItemSpot*" markers; they join the artifact candidates.
## This node is a child of the room root, so it runs before room_runtime.gd lights and collides everything.

@export var enabled := true
## 0 = different every load; any other value = the same dressing every time.
@export var seed_value := 0
## How many artifacts to place in this room (min, max).
@export var artifacts := Vector2i(1, 2)
# kept fairly low so rooms stay open enough to run through (and for the demon to chase you through)
@export var chance := {"wall": 0.65, "narrow": 0.2, "deco": 0.6, "corner": 0.5, "center": 0.35, "clutter": 0.5}

const G := "res://scenes/groups/"
# group scene, weight, tall (blocks the deco slot above)
const LIBRARY := {
	"wall": [["wall_bookshelf", 3, true], ["wall_wardrobe", 4, true], ["wall_study", 3, false], ["wall_storage", 3, false],
		["wall_lectern", 2, false], ["wall_statue", 1, true], ["wall_shrine", 2, true]],
	"narrow": [["narrow_urns", 2, false], ["narrow_sack", 2, false], ["narrow_candelabrum", 2, false], ["narrow_bones", 1, false]],
	"deco": [["deco_sconce", 3, false], ["deco_banner", 2, false]],
	"corner": [["corner_crates", 3, false], ["corner_candelabrum", 2, false], ["corner_urns", 2, false], ["corner_sack", 2, false]],
	"center": [["center_rug", 3, false], ["center_tomb", 1, false], ["center_font", 1, false], ["center_candles", 2, false],
		["center_statue", 1, false]],
}
const CLUTTER := ["skull", "bones", "bottle_tall", "bottle_round", "plate", "cup", "candle_single", "book_stack", "pages"]
const ARTIFACTS := ["chalice", "reliquary", "censer", "icon", "candlestick", "crown", "gospel"]

var rng := RandomNumberGenerator.new()


func _ready() -> void:
	if not enabled:
		return
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	var item_spots: Array[Node3D] = []
	var tall := {}
	var slots := get_children().filter(func(c): return c is Marker3D)
	# walls first, so deco slots know what is under them
	slots.sort_custom(func(a, b): return _order(a) < _order(b))
	for slot in slots:
		var parts := String(slot.name).split("_", true, 1)
		var kind := parts[0]
		var sid: String = parts[1] if parts.size() > 1 else ""
		match kind:
			"item":
				item_spots.append(slot)
			"clutter":
				if rng.randf() < chance.get("clutter", 0.6):
					_clutter(slot)
			"deco":
				if not tall.has(sid) and rng.randf() < chance.get("deco", 0.6):
					_spawn(slot, _pick("deco"))
			_:
				if LIBRARY.has(kind) and rng.randf() < chance.get(kind, 0.7):
					var entry: Array = _pick_entry(kind)
					var g := _spawn(slot, entry[0], kind == "center")
					if entry[2]:
						tall[sid] = true
					if g:
						for s in g.find_children("ItemSpot*", "", true, false):
							item_spots.append(s)
	_place_artifacts(item_spots)


func _order(n: Node) -> int:
	var k := String(n.name).split("_")[0]
	return {"wall": 0, "narrow": 0, "corner": 1, "center": 2, "deco": 3, "clutter": 4, "item": 5}.get(k, 6)


func _pick_entry(kind: String) -> Array:
	var lib: Array = LIBRARY[kind]
	var total := 0
	for e in lib: total += e[1]
	var r := rng.randi_range(1, total)
	for e in lib:
		r -= e[1]
		if r <= 0: return e
	return lib[0]


func _pick(kind: String) -> String:
	return _pick_entry(kind)[0]


func _spawn(slot: Node3D, group: String, any_rotation := false) -> Node3D:
	var ps: PackedScene = load(G + group + ".tscn")
	if ps == null:
		return null
	var g: Node3D = ps.instantiate()
	slot.add_child(g)
	if any_rotation:
		g.rotation.y = deg_to_rad(90.0 * rng.randi_range(0, 3) + rng.randf_range(-6, 6))
	else:
		g.rotation.y = deg_to_rad(rng.randf_range(-2.5, 2.5))
	return g


func _clutter(slot: Node3D) -> void:
	for i in rng.randi_range(1, 3):
		var ps: PackedScene = load("res://assets/props/%s.glb" % CLUTTER[rng.randi_range(0, CLUTTER.size() - 1)])
		var c: Node3D = ps.instantiate()
		slot.add_child(c)
		c.position = Vector3(rng.randf_range(-0.45, 0.45), 0, rng.randf_range(-0.3, 0.3))
		c.rotation.y = rng.randf_range(0, TAU)


func _place_artifacts(spots: Array[Node3D]) -> void:
	if spots.is_empty():
		return
	var n := mini(rng.randi_range(artifacts.x, artifacts.y), spots.size())
	for i in n:
		var k := rng.randi_range(0, spots.size() - 1)
		var spot: Node3D = spots.pop_at(k)
		var ps: PackedScene = load("res://assets/props/%s.glb" % ARTIFACTS[rng.randi_range(0, ARTIFACTS.size() - 1)])
		var a: Node3D = ps.instantiate()
		a.name = "Artifact_%d" % i
		spot.add_child(a)
		a.rotation.y = rng.randf_range(0, TAU)
