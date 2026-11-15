extends Node
# Test tool (cathedral scenario): logs the demon over the first seconds of a level, then puts a closed
# chalk circle in front of the player with the demon close by and times frames and the slow parts.
#   godot --path . res://scenes/perf_test.tscn

var main

func _ready() -> void:
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	if main.candle_intro:
		main.finish_candle_intro()
	if main.intro:
		main.end_intro()
	var d = main.demon
	var pp: Vector2 = main.player.pos2()
	print("player start ", pp, "  demon start ", d.pos2, "  distance %.1f m" % pp.distance_to(d.pos2))
	# 1) the first 20 s of a level (player standing at the start)
	var t := 0.0
	var first_seen := -1.0
	var next_log := 0.0
	while t < 40.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if d.sees_player and first_seen < 0.0:
			first_seen = t
		if t >= next_log:
			next_log += 4.0
			print("  t=%4.1f  demon %-11s at %s  %.1f m from you  sees you: %s" % [t, d.state_name(), str(d.pos2.snapped(Vector2(0.1, 0.1))), d.pos2.distance_to(main.player.pos2()), str(d.sees_player)])
	print("demon first saw you at: %s" % ("never" if first_seen < 0.0 else "%.1f s" % first_seen))
	# 2) frame time with a closed circle in front of you and the demon near
	var base := await _frames(90)
	var c: Vector2 = main.player.pos2() + Vector2(0, -1.6)
	var poly := PackedVector2Array()
	for k in 60:
		var a := TAU * k / 60.0
		poly.append(c + Vector2(cos(a) * 0.7, sin(a) * 0.55))
	main.chalk._make_loop(poly, false)
	main.chalk.nav.set_chalk(main.chalk.loops)
	var with_circle := await _frames(90)
	d.pos2 = main.player.pos2() + Vector2(0.4, -4.0)
	d._start_chase()
	var with_demon := await _frames(150)
	print("worst frame / avg frame (ms): standing %s | circle in front %s | circle + demon chasing %s" % [base, with_circle, with_demon])
	# 3) you standing right on the edge of a circle (your map cell is taken by the chalk), demon chasing
	var c2: Vector2 = main.player.pos2() + Vector2(0, -0.62)
	var poly2 := PackedVector2Array()
	for k in 60:
		var a2 := TAU * k / 60.0
		poly2.append(c2 + Vector2(cos(a2) * 0.6, sin(a2) * 0.6))
	main.chalk._make_loop(poly2, false)
	main.chalk.nav.set_chalk(main.chalk.loops)
	d.pos2 = main.player.pos2() + Vector2(0.3, -5.0)
	d._start_chase()
	var t0 := Time.get_ticks_usec()
	var cr = main.level.nav.closest_reachable(d.pos2, main.player.pos2(), main.chalk)
	print("one closest_reachable() call: %.1f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	var at_line := await _frames(150)
	print("you on a circle's edge + demon chasing: %s" % at_line)
	get_tree().quit()


func _frames(n: int) -> String:
	var worst := 0.0
	var total := 0.0
	var last := Time.get_ticks_usec()
	for f in n:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		last = now
		if f > 2:
			worst = maxf(worst, ms)
			total += ms
	return "%.1f/%.1f" % [worst, total / (n - 3)]
