extends Node3D
## Put on a room's root. When the room loads it:
##  1. opens the doorways listed in `open_doors` and walls up every other DoorSlot_* (for the level generator),
##  2. lights every FlameSpot_* marker that came in with a prop (flame mesh + flickering candle light),
##  3. gives everything visible trimesh collision, so rooms need no hand-made colliders.
## Nodes whose name starts with "NoCollide" (and everything under them) are skipped for collision.
## Prop spawning (PropSpawner on the "Slots" node) runs before this, because children are ready first.

const FLAME_SHADER := preload("res://shaders/kit/prop_flame.gdshader")
const FLICKER := preload("res://scripts/candle_flicker.gd")

## DoorSlot names (without the "DoorSlot_" prefix) that should be open doorways, e.g. ["S1", "E1"].
## "*" opens every slot (handy for previews). The level generator sets this before adding the room.
@export var open_doors: PackedStringArray = PackedStringArray(["*"])
## Slots that show nothing at all (another room already has a wall or doorway there).
@export var empty_doors: PackedStringArray = PackedStringArray()
## false = leave the FlameSpots alone (room_level.gd lights them itself, so the demon can blow them out).
@export var light_flames := true
## false = build no collision here (room_level.gd adds simple boxes instead: much cheaper than mesh collision).
@export var make_collision := true
@export var candle_color := Color(1.0, 0.42, 0.22)
@export var candle_energy := 0.7
@export var candle_range := 2.8
## Only this many candle lights cast shadows (shadows are expensive).
@export var shadowed_candles := 3

var _flame_mesh: SphereMesh
var _flame_mat: ShaderMaterial


func _ready() -> void:
	configure_doors(open_doors, empty_doors)
	if not light_flames:
		if make_collision:
			_collide(self)
		return
	_flame_mesh = SphereMesh.new()
	_flame_mesh.radius = 0.011
	_flame_mesh.height = 0.04
	_flame_mesh.radial_segments = 6
	_flame_mesh.rings = 4
	_flame_mat = ShaderMaterial.new()
	_flame_mat.shader = FLAME_SHADER
	var spots: Array[Node3D] = []
	_find_spots(self, spots)
	for i in spots.size():
		_light(spots[i], i < shadowed_candles)
	if make_collision:
		_collide(self)


## Shows the doorway (frame + door) on open slots and a plain wall on the rest.
func configure_doors(open: PackedStringArray, empty := PackedStringArray()) -> void:
	for slot in find_children("DoorSlot_*", "", true, false):
		var key := String(slot.name).trim_prefix("DoorSlot_")
		var is_open := open.has("*") or open.has(key)
		var wall := slot.get_node_or_null("Wall")
		var way := slot.get_node_or_null("Doorway")
		var is_empty := empty.has(key)
		if wall: wall.visible = not is_open and not is_empty
		if way: way.visible = is_open and not is_empty


func _find_spots(n: Node, out: Array[Node3D]) -> void:
	if n is Node3D and not n.is_visible_in_tree():
		return
	if n is Node3D and n.name.begins_with("FlameSpot"):
		out.append(n)
	for c in n.get_children():
		_find_spots(c, out)


func _light(spot: Node3D, shadow: bool) -> void:
	var flame := MeshInstance3D.new()
	flame.mesh = _flame_mesh
	flame.material_override = _flame_mat
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spot.add_child(flame)
	var l := OmniLight3D.new()
	l.light_color = candle_color
	l.light_energy = candle_energy
	l.omni_range = candle_range
	l.omni_attenuation = 1.4
	l.light_volumetric_fog_energy = 0.6
	l.shadow_enabled = shadow
	l.position = Vector3(0, 0.03, 0)
	l.set_script(FLICKER)
	spot.add_child(l)


func _collide(n: Node) -> void:
	if n.name.begins_with("NoCollide"):
		return
	if n is Node3D and not n.is_visible_in_tree():
		return
	if n is MeshInstance3D and n.mesh != null and not String(n.get_parent().name).begins_with("FlameSpot"):
		n.create_trimesh_collision()
	for c in n.get_children():
		_collide(c)
