extends Node
# Test tool: runs the real game scene and saves a few screenshots at the game's own resolution.
#   godot --path . res://scenes/game_shot.tscn -- --shots=<folder>

func _ready() -> void:
	var out := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			out = arg.substr(8)
	var main = load("res://main.tscn").instantiate()
	add_child(main)
	if out == "":
		return
	DirAccess.make_dir_recursive_absolute(out)
	await _wait(90)
	_save(out, "game_1_start")
	var lv = main.level
	# look round the first rooms: stand in each of the next rooms and face back the way you came
	var k := 2
	for i in [1, 2, 4, lv.rooms.size() - 1]:
		if i >= lv.rooms.size():
			continue
		var r = lv.rooms[i]
		var p: Vector2 = lv._free_near(r["pos"])
		main.player.position = Vector3(p.x, 0.0, p.y)
		var look: Vector2 = lv.rooms[maxi(i - 1, 0)]["pos"] - p
		var yaw := atan2(-look.x, -look.y) + PI
		main.player.yaw = yaw
		main.player.yaw_target = yaw
		await _wait(60)
		_save(out, "game_%d_%s" % [k, r["kind"]])
		k += 1
	get_tree().quit()


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _save(out: String, name: String) -> void:
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
