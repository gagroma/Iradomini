extends Node
# Test tool for the relic music: silent with 4 or 3 relics left, a track with 2 or 1 left,
# fades out when the last relic is found.
#   godot --path . res://scenes/music_test.tscn -- [--level=2]

var main

func _ready() -> void:
	var lvl := 1
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
	main.player.wards = 9999
	for d in main.demons:
		d.set_process(false)
		d.set_physics_process(false)
	for found in [0, 1, 2, 3, 4]:
		main.carried = found
		await get_tree().create_timer(3.0).timeout
		var m = main._music
		print("found %d (left %d): %s" % [found, 4 - found,
			"silent" if m == null else "%s  %.1f dB  playing=%s" % [m.stream.resource_path.get_file(), m.volume_db, m.playing]])
	await get_tree().create_timer(2.0).timeout
	print("after fade: ", "silent" if main._music == null else "%.1f dB" % main._music.volume_db)
	get_tree().quit()
