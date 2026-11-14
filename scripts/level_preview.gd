extends Node3D
# LEVEL PREVIEW (test tool) - builds room levels for a few seeds and saves a top-down picture of each,
# with the relics (yellow), player start (green), demon start (red) and patrol route (red dots) marked,
# plus an eye-level shot from the player's start.
#   godot --path . res://scenes/level_preview.tscn -- --shots=<folder> [--seeds=1,2,3]
# Ceilings are hidden in the top-down view.

const RoomLevel = preload("res://scripts/room_level.gd")

var cam: Camera3D
var env: Environment


func _ready() -> void:
	var out := ""
	var seeds := [11, 22, 33, 44]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			out = arg.substr(8)
		elif arg.begins_with("--seeds="):
			seeds = []
			for s in arg.substr(8).split(","):
				seeds.append(int(s))
	get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED   # full-size pictures
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.018, 0.006, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.26, 0.6)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	cam = Camera3D.new()
	cam.far = 200.0
	add_child(cam)
	cam.current = true
	if out == "":
		return
	DirAccess.make_dir_recursive_absolute(out)
	for s in seeds:
		var level = RoomLevel.new()
		add_child(level)
		level.build(s)
		print("seed %d: %d rooms, %d candles, %d covers, %d relics, %d patrol points" % [
			s, level.rooms.size(), level.candles.size(), level.covers.size(), level.relic_spots.size(), level.patrol_points.size()])
		for r in level.rooms:
			print("   ", r["name"], " at ", r["pos"], " turn ", r["rot"] * 90)
		var marks := _marks(level)
		# top-down
		for c in level.find_children("Ceiling*", "", true, false):
			c.visible = false
		var box := Rect2(level.rooms[0]["rect"])
		for r in level.rooms:
			box = box.merge(r["rect"])
		var c2 := box.get_center()
		var span := maxf(box.size.x * 0.6, box.size.y)
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = span + 4.0
		cam.global_position = Vector3(c2.x, 60.0, c2.y)
		cam.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
		env.ambient_light_energy = 2.5
		env.fog_enabled = false
		await _settle()
		get_viewport().get_texture().get_image().save_png(out.path_join("level_%d_top.png" % s))
		# eye level from the start
		for c in level.find_children("Ceiling*", "", true, false):
			c.visible = true
		marks.visible = false
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.fov = 70.0
		cam.global_position = level.player_start + Vector3(0, 1.6, 0)
		cam.rotation = Vector3(-0.05, level.player_yaw, 0.0)
		env.ambient_light_energy = 0.6
		env.fog_enabled = true
		env.fog_light_color = Color(0.035, 0.014, 0.06)
		env.fog_density = 0.06
		await _settle()
		get_viewport().get_texture().get_image().save_png(out.path_join("level_%d_start.png" % s))
		level.queue_free()
		marks.queue_free()
		await get_tree().process_frame
	get_tree().quit()


func _marks(level) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	var dot := func(p: Vector3, col: Color, size: float):
		var mi := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = Vector3(size, 0.2, size)
		mi.mesh = m
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = col
		mi.material_override = mat
		mi.position = p + Vector3(0, 5.0, 0)
		root.add_child(mi)
	for r in level.relic_spots:
		dot.call(r["pos"], Color(1, 0.85, 0.1), 0.7)
	dot.call(level.player_start, Color(0.2, 1, 0.3), 0.9)
	dot.call(Vector3(level.demon_start.x, 0, level.demon_start.y), Color(1, 0.1, 0.1), 0.9)
	for p in level.patrol_points:
		dot.call(Vector3(p.x, 0, p.y), Color(0.8, 0.1, 0.1), 0.3)
	return root


func _settle() -> void:
	for i in 40:
		await get_tree().process_frame
