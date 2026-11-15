extends Node

const Lighter = preload("res://scripts/lighter.gd")
const PrayerBook = preload("res://scripts/prayer_book.gd")
const Models = preload("res://scripts/models.gd")
const BODY = preload("res://assets/models/player_body.glb")


func run(main) -> void:
	var cover: CanvasLayer
	if not main.candle_intro:
		cover = CanvasLayer.new()
		cover.layer = 100
		add_child(cover)
		var black = ColorRect.new()
		black.color = Color.BLACK
		black.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cover.add_child(black)
		black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 400.0
	cam.far = 400.0
	add_child(cam)
	cam.global_transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, 150.0, -15.0))
	cam.current = true

	var start: Vector3 = main.level.player_start
	var kept := []
	for at in [start + Vector3(0.0, 1.2, 0.0), start + Vector3(0.0, 1.2, -7.0)]:
		var props = Node3D.new()
		add_child(props)
		props.global_position = at
		var lighter = Lighter.new()
		lighter.opened = 1.0
		props.add_child(lighter)
		lighter.strike()
		var book = PrayerBook.new()
		book.opened = 0.5
		book.position = Vector3(0.3, 0.0, 0.0)
		props.add_child(book)
		var body = Models._glb(BODY)
		body.position = Vector3(-0.6, 0.0, 0.0)
		props.add_child(body)
		var wailer: Node3D = Models.wailer()["root"]
		wailer.position = Vector3(0.9, 0.0, 0.0)
		props.add_child(wailer)
		kept.append(props)

	var player = main.player
	var shown := []
	for node in [player.right_hand, player.left_hand, main.hud, main._pause_menu, main._win]:
		if not node.visible:
			shown.append(node)
			node.visible = true

	var masks := {}
	for light in main.find_children("*", "Light3D", true, false):
		masks[light] = light.light_cull_mask
		light.light_cull_mask = 0
	var omni = OmniLight3D.new()
	omni.omni_range = 500.0
	add_child(omni)
	omni.global_position = Vector3(0.0, 40.0, -15.0)
	var spot = SpotLight3D.new()
	spot.spot_range = 500.0
	spot.spot_angle = 80.0
	add_child(spot)
	spot.global_transform = cam.global_transform
	for combo in [[false, false], [true, false], [false, true], [true, true]]:
		omni.visible = combo[0]
		spot.visible = combo[1]
		await get_tree().process_frame
	omni.queue_free()
	spot.queue_free()
	for light in masks:
		if is_instance_valid(light):
			light.light_cull_mask = masks[light]

	for node in shown:
		if is_instance_valid(node):
			node.visible = false
	player.cam.make_current()
	cam.queue_free()
	if cover != null:
		cover.queue_free()
	for props in kept:
		props.visible = false
		props.process_mode = Node.PROCESS_MODE_DISABLED
