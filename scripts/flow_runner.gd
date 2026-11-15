extends Node
# (flow_test.gd) lives on the tree root, so it survives the scene changes it checks.

func _ready() -> void:
	var tree := get_tree()
	tree.change_scene_to_file("res://scenes/passage.tscn")
	await tree.scene_changed
	await _wait(30)
	var p = tree.current_scene
	print("1. passage loaded: ", p.scene_file_path, "  level ", p.level, "  length ", p.length, " m")
	p._z = -p.length + 1.0                   # walk to the door
	await tree.create_timer(4.0).timeout
	var m = tree.current_scene
	print("2. after the door: ", m.scene_file_path, "  level meta ", Engine.get_meta("ira_level"))
	await tree.create_timer(2.0).timeout
	m.show_win()                             # pretend the altar ritual is finished
	await tree.create_timer(1.5).timeout
	print("   blessing choice shown: ", m._blessings.visible, "  demons on this level: ", m.demons.size())
	m._after_win()                           # ...and a blessing is chosen
	await tree.create_timer(3.0).timeout
	var p2 = tree.current_scene
	print("3. after the win: ", p2.scene_file_path, "  level ", p2.get("level"))
	tree.quit()


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame
