extends Node
# Test tool: runs the real game with the player parked out of the way and logs the demon's patrol for
# a while: how many patrol points it reached, and every stretch of 4 s it barely moved while patrolling.
#   godot --path . res://scenes/demon_test.tscn [-- --seconds=120]

func _ready() -> void:
	var seconds := 120.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seconds="):
			seconds = float(arg.substr(10))
	Engine.time_scale = 3.0                  # run the clock 3x faster
	var main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().physics_frame
	main.player.position = Vector3(500, 0, 500)   # out of sight and earshot
	main.player.set_physics_process(false)
	var d = main.demon
	var lv = main.level
	print("seed ", main._seed, ": ", lv.rooms.size(), " rooms, ", lv.patrol_points.size(), " patrol points")
	var t := 0.0
	var hist := []
	var stuck := 0.0
	var reached := {}
	var last_i := -1
	while t < seconds:
		await get_tree().physics_frame
		t += get_physics_process_delta_time() * Engine.time_scale
		hist.append([t, d.pos2, d.state])
		if d._patrol_i != last_i:
			reached[d._patrol_i] = true
			last_i = d._patrol_i
		while hist.size() > 1 and t - hist[0][0] > 4.0:
			hist.pop_front()
		if t > 6.0 and hist[0][1].distance_to(d.pos2) < 0.3 and d.state == 0 and d._pause <= 0.0:
			stuck += get_physics_process_delta_time() * Engine.time_scale
	print("patrol points reached: %d of %d" % [reached.size(), lv.patrol_points.size()])
	print("time stuck while patrolling: %.1f s of %.0f s" % [stuck, seconds])
	get_tree().quit()
