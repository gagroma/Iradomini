extends Node
# Test tool: dies, presses Enter (skip) after a given delay, and checks the "Try Again" screen shows.
#   godot --path . res://scenes/death_test.tscn -- --skip=<seconds> [--shots=<folder>]

var main

func _ready() -> void:
	var skip := 0.1
	var mash := false
	var out := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--skip="):
			skip = float(arg.substr(7))
		elif arg == "--mash":
			mash = true
		elif arg.begins_with("--shots="):
			out = arg.substr(8)
	Engine.set_meta("ira_level", 2)
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	if main.candle_intro:
		main.finish_candle_intro()
	if main.intro:
		main.end_intro()
	for c in main.get_children():
		if c.get_script() == load("res://scripts/door_intro.gd"):
			c.queue_free()
	await _wait(30)
	var p = main.player
	p.critical = true
	p.wards = 0
	var d = main.demons[0]
	p.take_hit(Vector3(d.pos2.x, 0, d.pos2.y))
	var death = null
	for c in main.get_children():
		if c.get_script() == load("res://scripts/death_scene.gd"):
			death = c
	var t := 0.0
	var pressed := false
	while t < 9.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		if (not pressed or (mash and t < skip + 1.8 and fmod(t, 0.15) < get_process_delta_time())) and t >= skip:
			pressed = true
			var e := InputEventKey.new()
			e.keycode = KEY_ENTER
			e.physical_keycode = KEY_ENTER
			e.pressed = true
			Input.parse_input_event(e)
			await get_tree().process_frame
			var u := InputEventKey.new()
			u.keycode = KEY_ENTER
			u.physical_keycode = KEY_ENTER
			u.pressed = false
			Input.parse_input_event(u)
	if out != "":
		get_viewport().get_texture().get_image().save_png(out.path_join("death_skip_%s.png" % str(skip)))
	print("mash" if mash else "", " current scene: ", get_tree().current_scene.name, "  main valid: ", is_instance_valid(main))
	if not is_instance_valid(death):
		print("death scene gone"); get_tree().quit(); return
	print("skip at %.2f s: death _t %.1f, text writing %s done %s, dim %.2f, try-again alpha %.2f enabled %s, scene still %s" % [skip, death._t, str(death._text.writing), str(death._text.done()), death._dim, death._retry_box.modulate.a, str(not death._retry.disabled), str(is_instance_valid(death))])
	get_tree().quit()


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame
