extends Node
# Test tool: you stand in a closed circle, the demon runs at you, is blocked, gives up; then you step out
# and walk about. Logs what the demon does afterwards (it should leave, not turn back and hunt you).
#   godot --path . res://scenes/blocked_test.tscn

var main
var _last_state := -1

func _ready() -> void:
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
	var d = main.demon
	await _wait(30)
	# stand in the nave (the start room is behind the salt line, the demon cannot come near there)
	var spot: Vector2 = main.level.patrol_points[2]
	main.player.position = Vector3(spot.x, 0, spot.y)
	await _wait(5)
	var pp: Vector2 = main.player.pos2()
	var poly := PackedVector2Array()
	for k in 72:
		var a := TAU * k / 72.0
		poly.append(pp + Vector2(cos(a), sin(a)) * 1.3)
	main.chalk._make_loop(poly, false)
	main.chalk.nav.set_chalk(main.chalk.loops)
	# put it on walkable floor about 5 m away (the nearest spot it can really reach)
	d.pos2 = main.level.nav.closest_reachable(pp + Vector2(0.0, -2.0), pp + Vector2(0.0, -5.0), null, 60.0)
	print("  demon placed at ", d.pos2, ", ", d.pos2.distance_to(pp), " m from you")
	d._start_chase()
	var t := 0.0
	var phase := "in the circle"
	var stepped := false
	var chased_after := false
	var heard_after := false
	var next_log := 0.0
	var out_pos := Vector2.ZERO
	while t < 50.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if not stepped and d._retreat > 0.0 and t > 1.0:
			# it gave up: step out of the circle, away from it, and make some noise walking
			stepped = true
			phase = "stepped out"
			var away: Vector2 = (pp - d.pos2).normalized()
			out_pos = pp + away * 2.4
			main.player.position = Vector3(out_pos.x, 0, out_pos.y)
			print("  t=%4.1f  gave up -> you step out of the circle" % t)
		if stepped and fmod(t, 1.0) < get_physics_process_delta_time():
			main.player_step(false, false)          # walking footsteps once a second
		if stepped and d.state == 2:
			chased_after = true
		if stepped and d.state == 1:
			heard_after = true
		if d.state != _last_state:
			print("    t=%5.2f state %s -> %s  dist %.2f  separated %s  shield %d still %s  blocked_left %.1f" % [t, ["PATROL","INVESTIGATE","CHASE","BLOCKED","RECOVER","TRAPPED","GONE"][_last_state] if _last_state >= 0 else "-", d.state_name(), d.distance_to_player(), str(main.chalk.is_separated(d.pos2, main.player.pos2())), d._shield_id, str(d._still_shielded(main.player.pos2())), d._blocked_left])
			_last_state = d.state
		if t >= next_log:
			next_log += 3.0
			print("  t=%4.1f  %-14s demon %-11s %.1f m from you   you at %s (circle centre %s) path %d to point %d %s pause %.1f retreat %.1f demon at %s" % [t, phase, d.state_name(), d.distance_to_player(), str(main.player.pos2().snapped(Vector2(0.01,0.01))), str(pp.snapped(Vector2(0.01,0.01))), d._path.size(), d._patrol_i, str(main.level.patrol_points[d._patrol_i]), d._pause, d._retreat, str(d.pos2.snapped(Vector2(0.01,0.01)))])
	print("after it gave up: chased you again: %s, came to investigate your steps: %s" % [str(chased_after), str(heard_after)])
	get_tree().quit()


func _wait(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
