extends Node
# Test tool for levels with several demons and for hiding in a wardrobe.
#   1. Each demon has its own stretch of the patrol route.
#   2. While you run about making noise, never more than one demon is after you.
#   3. A demon chases you, you get into a wardrobe: the scene cannot be skipped, you are not hurt,
#      the demon comes to the doors and then goes back to patrolling.
#   godot --path . res://scenes/pack_test.tscn -- [--level=3]

var main

func _ready() -> void:
	var lvl := 3
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--level="):
			lvl = int(arg.substr(8))
	Engine.set_meta("ira_level", lvl)
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	if main.candle_intro:
		main.finish_candle_intro()
	if main.intro:
		main.end_intro()
	for c in main.get_children():          # the door intro keeps walking you in otherwise
		if c.get_script() == load("res://scripts/door_intro.gd"):
			c.queue_free()
	main.demon_grace = 0.0
	await _wait(30)
	var points: Array = main.level.patrol_points
	print("level %d: %d demons, %d patrol points, %d wardrobes" % [main.level_no, main.demons.size(), points.size(), main.wardrobes.size()])

	# --- 1. routes
	var seen := {}
	var shared := 0
	for i in main.demons.size():
		var d = main.demons[i]
		print("  demon %d patrols points %s" % [i, str(d._route)])
		for k in d._route:
			if seen.has(k):
				shared += 1
			seen[k] = true
	print("1. patrol points shared between demons: %d   (0 = each has its own stretch)" % shared)

	# --- 2. run about, loudly (with medallions enough that the test itself survives)
	main.player.wards = 9999
	var t := 0.0
	var most_hunting := 0
	var most_chasing := 0
	var hunts := 0
	var last_hunter = null
	var next_move := 0.0
	var next_step := 0.0
	var next_force := 4.0
	var at := 0
	while t < 60.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if t >= next_move:
			next_move += 2.5
			at = (at + 3) % points.size()
			main.player.position = Vector3(points[at].x, 0, points[at].y)
		if t >= next_step:
			next_step += 0.4
			main.player_step(true, false)          # running footsteps
		if t >= next_force:                       # ...and now and then another one spots you
			next_force += 6.0
			main.demons[randi() % main.demons.size()]._start_chase()
		var hunting := 0
		var chasing := 0
		for d in main.demons:
			if d.is_hunting():
				hunting += 1
			if d.state == 2:
				chasing += 1
		most_hunting = maxi(most_hunting, hunting)
		most_chasing = maxi(most_chasing, chasing)
		var h = main.hunting_demon()
		if h != null and h != last_hunter:
			hunts += 1
		last_hunter = h
		if not main.player.alive:
			break
	print("2. over %.0f s of running about: most demons after you at once %d (chasing at once %d), the hunt changed hands %d times" % [t, most_hunting, most_chasing, hunts])

	# --- 3. the wardrobe
	if main.wardrobes.is_empty():
		print("3. no wardrobe in this level (seed %d) - run again" % main._seed)
		get_tree().quit()
		return
	for d in main.demons:
		d.call_off()
	var p = main.player
	p.wards = 0
	print("   (game state: %s, you are alive: %s)" % [main.game_state, str(p.alive)])
	var w: Node3D = main.wardrobes[0]
	var front: Vector3 = w.global_basis.z
	front.y = 0.0
	front = front.normalized()
	var out: Vector3 = Vector3(w.global_position.x, 0, w.global_position.z) + front * 0.8
	p.position = out + front * 0.4
	await _wait(5)
	var out2 := Vector2(out.x, out.z)
	var d0 = main.demons[0]
	d0.pos2 = main.level.nav.closest_reachable(out2 + Vector2(front.x, front.z) * 2.0, out2 + Vector2(front.x, front.z) * 6.0, null, 60.0)
	d0._retreat = 0.0
	d0._start_chase()
	d0.sees_player = true
	print("   wardrobe at %s, demon 0 starts chasing from %.1f m" % [str(out2.snapped(Vector2(0.1, 0.1))), d0.pos2.distance_to(out2)])
	var hide = load("res://scripts/wardrobe_hide.gd").new()
	main.hiding = hide
	main.add_child(hide)
	hide.start(main, w)
	t = 0.0
	var inside_at := -1.0
	var closest := 999.0
	var hurt := false
	var entered_skip := false
	var next_log := 0.0
	while t < 30.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if t > 0.3 and not entered_skip:           # try to skip the scene
			entered_skip = true
			var e := InputEventKey.new()
			e.keycode = KEY_ENTER
			e.physical_keycode = KEY_ENTER
			e.pressed = true
			Input.parse_input_event(e)
		if inside_at < 0.0 and is_instance_valid(hide) and hide.is_inside():
			inside_at = t
		if inside_at >= 0.0:
			closest = minf(closest, d0.pos2.distance_to(out2))
		if not p.alive or p.critical:
			hurt = true
		if t >= next_log:
			next_log += 3.0
			print("   t=%4.1f  %-9s demon0 %-11s %.1f m from the doors  hunting %s" % [t, "inside" if p.in_wardrobe else "outside", d0.state_name(), d0.pos2.distance_to(out2), str(main.hunting_demon() != null)])
	print("3. getting in took %.1f s (Enter pressed at 0.3 s: %s).  Hurt in the wardrobe: %s.  The demon came within %.1f m of the doors and is now %s" % [inside_at, "NOT skipped" if inside_at > 1.5 else "SKIPPED", str(hurt), closest, d0.state_name()])
	get_tree().quit()


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame
