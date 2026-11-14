extends Node
# Test tool: runs the real game, walks the player with W through every doorway it can reach in order
# (START exit first) and reports whether it got through, plus frame/physics times next to props.
#   godot --path . res://scenes/walk_test.tscn

var main
var results := []

func _ready() -> void:
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await _wait(30)
	main.demon.switch_off()
	var lv = main.level
	var idle := 0.0
	for f in 60:
		await get_tree().process_frame
		idle += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	print("standing still at the start: physics avg %.2f ms; collision shapes %d" % [idle / 60.0, lv._body.get_child_count()])
	var tried := 0
	for i in lv.rooms.size():
		for d in lv.rooms[i]["doors"]:
			if d["link"] < 0 or not d["own"] or tried >= 6:
				continue
			tried += 1
			var dir: Vector2 = d["dir"]
			var start: Vector2 = d["pos"] - dir * 1.4
			main.player.position = Vector3(start.x, 0, start.y)
			var yaw := atan2(-dir.x, -dir.y)
			main.player.yaw = yaw
			main.player.yaw_target = yaw
			main.player.rotation.y = yaw
			await _wait(5)
			_key(KEY_W, true)
			await _wait(120)
			_key(KEY_W, false)
			var p: Vector2 = main.player.pos2()
			var through: float = (p - d["pos"]).dot(dir)
			results.append("room %d door %s: %s (%.2f m past the doorway)" % [i, d["key"], "THROUGH" if through > 0.4 else "BLOCKED", through])
			if through <= 0.4:
				var other = lv.rooms[d["link"]]
				results.append("   rooms %s -> %s, player stopped at %s" % [lv.rooms[i]["name"], other["name"], str(p)])
				var qq := PhysicsShapeQueryParameters3D.new()
				var cc := CapsuleShape3D.new()
				cc.radius = 0.31
				cc.height = 1.7
				qq.shape = cc
				qq.transform = Transform3D(Basis.IDENTITY, Vector3(p.x, 0.85, p.y))
				for hit in main.get_world_3d().direct_space_state.intersect_shape(qq, 8):
					var col = hit["collider"]
					var sh = col.shape_owner_get_owner(col.shape_find_owner(hit["shape"])) if col is CollisionObject3D else null
					results.append("   touching: %s shape %s at %s" % [col.name, sh.name if sh else "?", str(sh.global_position if sh else Vector3.ZERO)])
				for k in [i, d["link"]]:
					for prop in lv._props_of(lv.rooms[k]["node"]):
						var bx: AABB = lv._world_box(prop)
						var f2 := Rect2(bx.position.x, bx.position.z, bx.size.x, bx.size.z)
						if f2.grow(0.6).has_point(d["pos"]) or f2.grow(0.4).has_point(p):
							results.append("   near: %s (%s) box %s" % [prop.name, prop.get_parent().get_parent().name, str(f2)])
	for r in results:
		print(r)
	# walk in open floor (no contact) and measure
	var st: Vector2 = lv._free_near(lv.rooms[0]["pos"])
	main.player.position = Vector3(st.x, 0, st.y)
	var open_sum := 0.0
	_key(KEY_W, true)
	for f in 40:
		await get_tree().process_frame
		open_sum += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	_key(KEY_W, false)
	print("walking in the open: physics avg %.2f ms" % (open_sum / 40.0))
	# what is the player touching at a blocked start?
	var q := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	q.shape = cap
	q.collision_mask = 1
	for r in results:
		pass
	# stand right next to props and measure
	var sum_phys := 0.0
	var n_phys := 0
	var worst_phys := 0.0
	var worst_frame := 0.0
	for c in lv.covers.slice(0, 12):
		var ctr: Vector2 = c.get_center()
		main.player.position = Vector3(c.position.x - 0.45, 0, ctr.y)
		_key(KEY_D, true)
		for f in 30:
			await get_tree().process_frame
			var ph: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
			worst_phys = maxf(worst_phys, ph)
			sum_phys += ph
			n_phys += 1
			worst_frame = maxf(worst_frame, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		_key(KEY_D, false)
	# real frame times: open floor vs pressed against props
	var t_open := await _frames(func(): main.player.position = Vector3(st.x, 0, st.y), KEY_W)
	var t_props := 0.0
	for c in lv.covers.slice(0, 8):
		var cc: Vector2 = c.get_center()
		t_props = maxf(t_props, await _frames(func(): main.player.position = Vector3(c.position.x - 0.45, 0, cc.y), KEY_D))
	print("frame time: open floor worst %.1f ms, next to props worst %.1f ms" % [t_open, t_props])
	print("next to props: physics avg %.2f ms, worst %.2f ms; worst process %.2f ms; fps %d" % [sum_phys / maxf(n_phys, 1), worst_phys, worst_frame, Engine.get_frames_per_second()])
	get_tree().quit()


func _frames(place: Callable, key: Key) -> float:
	place.call()
	_key(key, true)
	var worst := 0.0
	var last := Time.get_ticks_usec()
	for f in 40:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		if f > 3:
			worst = maxf(worst, (now - last) / 1000.0)
		last = now
	_key(key, false)
	return worst


func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)


func _wait(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
