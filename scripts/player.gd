extends CharacterBody3D
# PLAYER - first-person walking, looking, hiding, and holding the chalk.
#
# Sources:
#  - Movement is the standard Godot CharacterBody3D pattern: set "velocity",
#    call move_and_slide() (same idea as the CharacterBody2D player from the
#    course, with one more axis).
#  - GDD v6 "Kamera i oshchushchenie": a body, not a flying camera - head bob,
#    breathing, turn inertia, FOV 62 that narrows to 50 near the demon.
#  - GDD v6 "Upravlenie": WASD, Shift, Ctrl, left mouse to draw, E to take.
#
# Keys are read directly (Input.is_physical_key_pressed), so the project needs
# no Input Map setup.

const T = preload("res://scripts/tuning.gd")
const Models = preload("res://scripts/models.gd")

const MOUSE_SENSITIVITY := 0.0022
const EYE_HEIGHT := 1.55
const CROUCH_HEIGHT := 0.8
const CANDLE_ENERGY := 2.2    # how bright the candle in your hand is

var main
var head: Node3D
var cam: Camera3D
var hands: Node3D
var chalk_stick: MeshInstance3D
var candle_light: OmniLight3D

var yaw := 0.0              # where the body really looks (left/right)
var pitch := 0.0            # where the head really looks (up/down)
var yaw_target := 0.0       # where the mouse wants to look
var pitch_target := 0.0

var alive := true
var frozen := false         # true during the ending
var crouching := false
var running := false
var is_hidden_now := false  # crouched next to cover: the demon cannot see you
var critical := false       # wounded: the next hit kills (GDD "Zdorovie")
var critical_time := 0.0
var relics_found := 0       # each one makes your steps louder
var fear := 0.0             # 0..1, set by main.gd from the demon's distance
var aim_valid := false      # true when you look at floor within chalk reach
var aim_point := Vector2.ZERO
var drawing := false
var erase_progress := 0.0
var death_look := Vector3.ZERO

var _time := 0.0
var _bob := 0.0
var _step_acc := 0.0
var _kick := 0.0
var _head_y := EYE_HEIGHT


func setup(main_node) -> void:
	main = main_node
	collision_layer = 2         # the player is on layer 2, walls are on layer 1
	collision_mask = 1
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING   # flat floor: no gravity needed

	var shape = CollisionShape3D.new()
	var capsule = CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.7
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.85, 0.0)
	add_child(shape)

	head = Node3D.new()
	head.position = Vector3(0.0, EYE_HEIGHT, 0.0)
	add_child(head)
	cam = Camera3D.new()
	cam.fov = T.FOV_NORMAL
	cam.near = 0.05
	cam.far = 90.0
	head.add_child(cam)
	cam.current = true

	# what you hold: a candle in the left hand, the chalk in the right
	hands = Node3D.new()
	cam.add_child(hands)
	var candle = Models.candle()
	candle.position = Vector3(-0.2, -0.27, -0.42)
	hands.add_child(candle)
	candle_light = OmniLight3D.new()
	candle_light.position = Vector3(-0.2, 0.05, -0.35)
	candle_light.light_color = Color(1.0, 0.66, 0.34)
	candle_light.light_energy = CANDLE_ENERGY
	candle_light.omni_range = 7.5
	candle_light.omni_attenuation = 1.1
	hands.add_child(candle_light)

	chalk_stick = MeshInstance3D.new()
	var bm = BoxMesh.new()
	bm.size = Vector3(0.022, 0.022, 0.14)
	chalk_stick.mesh = bm
	var cm = StandardMaterial3D.new()
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.albedo_color = Color(0.92, 0.88, 0.76)
	chalk_stick.material_override = cm
	chalk_stick.position = Vector3(0.19, -0.2, -0.38)
	chalk_stick.rotation = Vector3(-0.5, 0.3, 0.0)
	hands.add_child(chalk_stick)


func pos2() -> Vector2:
	return Vector2(global_position.x, global_position.z)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if alive and not frozen:
			var rel = event.screen_relative
			yaw_target -= rel.x * MOUSE_SENSITIVITY
			pitch_target = clampf(pitch_target - rel.y * MOUSE_SENSITIVITY, -1.5, 1.4)


func _physics_process(dt: float) -> void:
	_time += dt
	var captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var can_act = alive and not frozen

	# --- looking, with a little inertia so it feels like a head, not a cursor ---
	if not alive:
		_look_towards(death_look)
	var k = 1.0 - exp(-22.0 * dt)
	yaw = lerpf(yaw, yaw_target, k)
	pitch = lerpf(pitch, pitch_target, k)
	rotation.y = yaw
	head.rotation.x = pitch

	# --- moving ---
	var input = Vector2.ZERO
	if can_act:
		if Input.is_physical_key_pressed(KEY_W):
			input.y -= 1.0
		if Input.is_physical_key_pressed(KEY_S):
			input.y += 1.0
		if Input.is_physical_key_pressed(KEY_A):
			input.x -= 1.0
		if Input.is_physical_key_pressed(KEY_D):
			input.x += 1.0
	crouching = can_act and Input.is_physical_key_pressed(KEY_CTRL)
	running = can_act and not crouching and Input.is_physical_key_pressed(KEY_SHIFT) and input.length() > 0.0
	var speed = T.WALK_SPEED
	if crouching:
		speed = T.CROUCH_SPEED
	elif running:
		speed = T.RUN_SPEED
	var wish = Vector3.ZERO
	if input.length() > 0.0:
		input = input.normalized()
		wish = (transform.basis * Vector3(input.x, 0.0, input.y)) * speed
	var accel = 30.0 if can_act else 8.0
	velocity.x = move_toward(velocity.x, wish.x, accel * dt)
	velocity.z = move_toward(velocity.z, wish.z, accel * dt)
	velocity.y = 0.0
	move_and_slide()
	position.y = 0.0

	# --- footsteps: every stride makes a sound the demon may hear ---
	var moved = Vector2(velocity.x, velocity.z).length() * dt
	var stride = 0.8
	if running:
		stride = 1.15
	elif crouching:
		stride = 0.6
	if can_act and moved > 0.0005:
		_step_acc += moved
		_bob += moved * (TAU / (stride * 2.0))
		if _step_acc >= stride:
			_step_acc = 0.0
			main.player_step(running, crouching)
	else:
		_step_acc = minf(_step_acc, stride * 0.5)

	# --- hiding: crouch next to a pew, column or altar (GDD "Pryatatsya") ---
	is_hidden_now = crouching and main.level.near_cover(pos2(), T.COVER_DISTANCE)

	# --- wounded timer (GDD: 20 seconds, then back to normal) ---
	if critical:
		critical_time -= dt
		if critical_time <= 0.0:
			critical = false

	_update_camera(dt, moved)
	_update_chalk(dt, can_act and captured)


func _update_camera(dt: float, moved: float) -> void:
	var target_y = CROUCH_HEIGHT if crouching else EYE_HEIGHT
	_head_y = lerpf(_head_y, target_y, 1.0 - exp(-10.0 * dt))
	var moving = 1.0 if moved > 0.0005 else 0.0
	var bob_y = sin(_bob) * 0.035 * moving
	var bob_x = cos(_bob * 0.5) * 0.02 * moving
	var breath = sin(_time * 1.4) * 0.008            # breathing while standing still
	var shake = fear * fear * 0.006
	head.position = Vector3(bob_x + randf_range(-shake, shake), _head_y + bob_y + breath + randf_range(-shake, shake), 0.0)
	_kick = move_toward(_kick, 0.0, dt * 2.2)
	cam.rotation.z = sin(_time * 0.7) * 0.004 + _kick * 0.35 * sin(_time * 38.0)
	# GDD: FOV 62, narrowing to 50 next to the demon
	var fov_target = lerpf(T.FOV_NORMAL, T.FOV_NEAR_DEMON, fear)
	cam.fov = lerpf(cam.fov, fov_target, 1.0 - exp(-4.0 * dt))
	# GDD: the candle in your hand flickers harder the closer the demon is
	var flick = sin(_time * 11.0) * sin(_time * 4.7 + 1.3)
	var amount = 0.06 + 0.5 * fear
	candle_light.light_energy = CANDLE_ENERGY * (1.0 - amount * (0.5 + 0.5 * flick))
	# hands sway a little with the walk
	hands.position = Vector3(-bob_x * 0.5, -bob_y * 0.5 - (0.04 if drawing else 0.0), 0.0)
	# GDD "Zapas bez interfeisa": the chalk stick gets shorter as you use it
	var left = clampf(main.chalk.chalk / T.CHALK_MAX, 0.0, 1.0)
	chalk_stick.scale = Vector3(1.0, 1.0, maxf(0.06, left))
	chalk_stick.visible = left > 0.005


func _update_chalk(dt: float, can_draw: bool) -> void:
	# GDD: "a ray from the centre of the screen into the floor", reach 2.5 m
	var origin = cam.global_position
	var dir = -cam.global_transform.basis.z
	aim_valid = false
	if dir.y < -0.05:
		var t = -origin.y / dir.y
		if t <= T.CHALK_REACH:
			aim_point = Vector2(origin.x + dir.x * t, origin.z + dir.z * t)
			aim_valid = true

	var want_draw = can_draw and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if want_draw:
		drawing = true
		if aim_valid:
			main.chalk.try_add_point(aim_point)
	elif drawing:
		drawing = false
		main.chalk.release()

	# erasing: hold the right mouse button on one of your circles
	erase_progress = 0.0
	if can_draw and not want_draw and aim_valid and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		erase_progress = main.chalk.erase_tick(aim_point, dt)
	else:
		main.chalk.erase_cancel()


# Turn the head towards a point in the world (death and ending cameras).
func _look_towards(point: Vector3) -> void:
	var to = point - cam.global_position
	if to.length() < 0.01:
		return
	var want_yaw = atan2(-to.x, -to.z)
	var want_pitch = atan2(to.y, Vector2(to.x, to.z).length())
	yaw_target = yaw + wrapf(want_yaw - yaw, -PI, PI)
	pitch_target = clampf(want_pitch, -1.4, 1.4)


func look_at_point(point: Vector3) -> void:
	_look_towards(point)


# Called by the demon when its claws land.
func take_hit(from: Vector3) -> void:
	if not alive:
		return
	if critical:
		alive = false
		death_look = from + Vector3(0.0, 2.05, 0.0)
		main.chalk.release()
		main.on_player_died()
		return
	critical = true
	critical_time = T.CRITICAL_TIME
	_kick = 1.0
	var away = global_position - from
	away.y = 0.0
	if away.length() > 0.01:
		velocity = away.normalized() * 7.0
	main.on_player_hit()
