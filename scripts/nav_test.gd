extends Node
# Test tool: builds room levels for many seeds and checks the demon's map:
# every patrol leg must have a path, and every room must be reachable from the START exit.
#   godot --headless --path . res://scenes/nav_test.tscn

const RoomLevel = preload("res://scripts/room_level.gd")

func _ready() -> void:
	var bad_total := 0
	for s in range(1, 13):
		var lv = RoomLevel.new()
		add_child(lv)
		lv.build(s * 101)
		var legs := 0
		var bad := []
		var pts: Array = lv.patrol_points
		for i in pts.size():
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[(i + 1) % pts.size()]
			legs += 1
			if a.distance_to(b) > 0.7 and lv.nav.find_path(a, b).is_empty():
				bad.append("%s->%s" % [a, b])
		var unreachable := []
		for r in lv.rooms:
			if r["kind"] == "start":
				continue
			var c: Vector2 = lv._free_near(r["pos"])
			if lv.nav.find_path(pts[0], c).is_empty():
				unreachable.append(r["name"])
		var free := 0
		var total := 0
		for r in lv.rooms:
			var rect: Rect2 = r["rect"].grow(-0.3)
			var y := rect.position.y + 0.25
			while y < rect.end.y:
				var x := rect.position.x + 0.25
				while x < rect.end.x:
					total += 1
					if lv.nav.is_free(Vector2(x, y)):
						free += 1
					x += 0.5
				y += 0.5
		bad_total += bad.size() + unreachable.size()
		print("seed %d: %d rooms, patrol legs %d, broken legs %d, unreachable rooms %s, open floor %d%%" % [
			s * 101, lv.rooms.size(), legs, bad.size(), str(unreachable), int(100.0 * free / maxi(total, 1))])
		for b in bad:
			print("    broken: ", b)
		if s == 3:
			for r in lv.rooms:
				if r["kind"] != "big":
					continue
				var rect: Rect2 = r["rect"].grow(1.5)
				print("big hall map (# solid, . free), rect ", r["rect"], " turn ", r["rot"])
				var y := rect.position.y + 0.25
				while y < rect.end.y:
					var line := ""
					var x := rect.position.x + 0.25
					while x < rect.end.x:
						line += "." if lv.nav.is_free(Vector2(x, y)) else "#"
						x += 0.5
					print("    ", line)
					y += 0.5
				var pew = r["node"].get_node("Fixed/pew_0")
				print("    pew scale ", pew.global_transform.basis.get_scale(), " local scale ", pew.scale, " transform ", pew.transform)
				var inv = pew.global_transform.affine_inverse()
				for mi in pew.find_children("*", "MeshInstance3D", true, false):
					print("      mesh ", mi.name, " aabb ", mi.get_aabb(), " in pew frame ", (inv * mi.global_transform) * mi.get_aabb())
				for pr in lv._props_of(r["node"]):
					var ob = lv._oriented_box(pr)
					print("    prop ", pr.name, " foot ", ob[2])
		lv.free()
	print("TOTAL problems: %d" % bad_total)
	get_tree().quit()
