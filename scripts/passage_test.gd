extends Node
# Test tool: bots walk the road between churches and save screenshots.
#   careful   stops for the music and the eyes, looks down when watched, relights when it is far          -> should arrive
#   careless  holds W the whole time                                                                   -> should be caught
#   starer    like careful, but looks straight at it whenever it is near (looking is safe)            -> should arrive
#   godot --path . res://scenes/passage_test.tscn -- --shots=<folder> [--level=2] [--runs=1]

var out := ""

func _ready() -> void:
	var lvl := 2
	var runs := 1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			out = arg.substr(8)
		elif arg.begins_with("--level="):
			lvl = int(arg.substr(8))
		elif arg.begins_with("--runs="):
			runs = int(arg.substr(7))
	Engine.set_meta("ira_level", lvl)
	if out != "":
		DirAccess.make_dir_recursive_absolute(out)
	for i in runs:
		print("careful run: ", await _run("careful", "careful%d" % i))
	print("careless run: ", await _run("careless", "careless"))
	print("starer run: ", await _run("starer", "starer"))
	get_tree().quit()


func _run(mode: String, tag: String) -> String:
	var p = load("res://scenes/passage.tscn").instantiate()
	add_child(p)
	var t := 0.0
	var shots := {}
	var stops := 0
	var holding := false
	var resend := 0.0
	var result := ""
	await _wait(3)
	_save(tag + "_1_start")
	while t < 400.0 and result == "":
		await get_tree().process_frame
		t += get_process_delta_time()
		var st: String = p._t_state
		var present := st != "away"
		var gap := absf(p._z - p._t_z)
		var want := true
		var look_down := false
		if mode != "careless":
			if present and st != "stand" and (p._distance() < 9.5 or st in ["close", "listen", "back"]):
				want = false
			if st == "stand" and gap < 6.0:
				want = false
			if p._strike > 0.0:
				want = false
			if not p.candle.lit and p._strike <= 0.0 and (not present or (gap > 17.0 and st == "go")):
				_tap(KEY_F)
			if st in ["stand", "close", "listen"]:
				look_down = true
			if mode == "starer" and st in ["stand", "listen"]:
				look_down = false
				var dv: Vector3 = p._figure.position + Vector3(0, 2.5, 0) - p.cam.global_position
				p._yaw = clampf(atan2(-dv.x, -dv.z), -1.3, 1.3)
				p._pitch = atan2(dv.y, Vector2(dv.x, dv.z).length())
			elif look_down:
				p._pitch = lerpf(p._pitch, -0.95, 0.2)
			else:
				p._pitch = lerpf(p._pitch, -0.05, 0.2)
				p._yaw = lerpf(p._yaw, 0.0, 0.2)
		resend += get_process_delta_time()
		if want != holding or resend > 0.4:      # (pressed again now and then: a window that loses focus drops its keys)
			resend = 0.0
			_key(KEY_W, want)
			if not want and holding:
				stops += 1
			holding = want
		# screenshots
		if st == "stand" and gap < 6.5 and p.candle.lit and not shots.has("stand"):
			shots["stand"] = true
			p._pitch = 0.1
			await _wait(3)
			_save(tag + "_stand")
		if st == "listen" and not shots.has("listen"):
			shots["listen"] = true
			var keep_y: float = p._yaw
			p._yaw = -0.75 * signf(p._t_x)
			p._pitch = 0.05
			await _wait(3)
			_save(tag + "_listen_%s" % ("lit" if p.candle.lit else "dark"))
			p._yaw = keep_y
		if not p.candle.lit and p._out_time > 1.4 and not shots.has("dark"):
			shots["dark"] = true
			_save(tag + "_dark")
		if p._z < -p.length * 0.5 + 5.0 and not shots.has("gate"):
			shots["gate"] = true
			_save(tag + "_gate")
		if p._z < -4.0 and not shots.has("road") and p.candle.lit:
			shots["road"] = true
			_save(tag + "_road")
		if p._z < -p.length + 7.0 and not shots.has("door"):
			shots["door"] = true
			_save(tag + "_door")
		if p._state == "caught":
			await _wait(22)
			_save(tag + "_caught")
			result = "CAUGHT at %.0f m of %.0f m after %.0f s" % [-p._z, p.length, t]
		elif p._state == "done":
			result = "REACHED THE DOOR after %.0f s (stopped %d times), level %d, road %.0f m" % [t, stops, p.level, p.length]
	if result == "":
		result = "TIMED OUT at %.0f m (state %s)" % [-p._z, p._t_state]
	_key(KEY_W, false)
	result += "\n      " + ", ".join(PackedStringArray(p.events))
	p.set_process(false)
	p.queue_free()
	await _wait(2)
	return result


func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)


func _tap(k: Key) -> void:
	_key(k, true)
	_key(k, false)


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _save(name: String) -> void:
	if out != "":
		get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
