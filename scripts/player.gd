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
const HandCandle = preload("res://scripts/candle.gd")
const HandChalk = preload("res://scripts/hand_chalk.gd")
const Models = preload("res://scripts/models.gd")
const HAND_RIGHT = preload("res://assets/models/hand_right.glb")   # tools/make_hands.py
const HAND_LEFT = preload("res://assets/models/hand_left.glb")
# where the right hand rests (it holds the chalk at its back end, tip forward)
const RIGHT_REST := Vector3(0.2, -0.15, -0.33)
const RIGHT_REST_ROT := Vector3(-0.5, 0.3, 0.0)

const MOUSE_SENSITIVITY := 0.0022
const EYE_HEIGHT := 1.55
const CROUCH_HEIGHT := 0.8
const CANDLE_ENERGY := 2.2    # how bright the candle in your hand is

var main
var head: Node3D
var cam: Camera3D
var hands: Node3D
var chalk_stick              # hand_chalk.gd: wears down unevenly as you draw
var candle                  # candle.gd: burns down, flame reacts to wind and fear
var right_hand: Node3D      # holds the chalk; reaches for the floor while you draw
var rubbing := false        # right mouse held on the floor: rubbing a circle out
var _reach := 0.0           # 0 = hand at rest, 1 = arm stretched out to the floor
var _lag := Vector2.ZERO    # the hands trail a little behind the turning head

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
	candle = HandCandle.new()
	candle.energy = CANDLE_ENERGY
	candle.sfx = main.sfx
	candle.position = Vector3(-0.2, -0.2, -0.39)
	candle.rotation.y = -2.36       # finger ring towards your hand
	hands.add_child(candle)

	# your hands (models: tools/make_hands.py), each built round what it holds
	var hand_mat = ShaderMaterial.new()
	hand_mat.shader = Models.VCOLOR_SHADER
	hand_mat.set_shader_parameter("snap", false)
	hand_mat.set_shader_parameter("roughness", 0.7)
	var left = _hand_model(HAND_LEFT, hand_mat)
	left.rotation.y = 2.36          # undo the candle's turn: the hand is in your hands' space
	candle.add_child(left)          # so it rises with the candle as the candle burns down

	right_hand = Node3D.new()
	right_hand.position = RIGHT_REST
	right_hand.rotation = RIGHT_REST_ROT
	hands.add_child(right_hand)
	chalk_stick = HandChalk.new()   # the end in your fingers at the hand's origin, tip forward
	right_hand.add_child(chalk_stick)
	right_hand.add_child(_hand_model(HAND_RIGHT, hand_mat))


func _hand_model(scene: PackedScene, mat: Material) -> Node3D:
	var node = scene.instantiate()
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


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
	crouching = can_act and (Input.is_physical_key_pressed(KEY_CTRL) or Input.is_physical_key_pressed(KEY_C))
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
	# hands sway a little with the walk, and trail a little behind the head
	hands.position = Vector3(-bob_x * 0.5, -bob_y * 0.5, 0.0)
	var lag_want = Vector2(clampf(pitch_target - pitch, -0.3, 0.3), clampf(yaw_target - yaw, -0.3, 0.3)) * -0.35
	_lag = _lag.lerp(lag_want, 1.0 - exp(-12.0 * dt))
	hands.rotation = Vector3(_lag.x, _lag.y, 0.0)
	_update_right_hand(dt)
	# the candle burns down; its flame leans in the wind of your movement and
	# flickers harder the closer the demon is (GDD)
	candle.tick(dt, fear)
	# GDD "Zapas bez interfeisa": the chalk stick gets shorter as you use it
	chalk_stick.set_left(clampf(main.chalk.chalk / T.CHALK_MAX, 0.0, 1.0))


# Drawing: the right arm stretches out towards the spot on the floor you look
# at, the chalk turned tip-first to it, trembling as it scrapes the stone.
# Rubbing out: the arm reaches out and scrubs from side to side.
func _update_right_hand(dt: float) -> void:
	var want = 1.0 if (drawing and aim_valid) or rubbing else 0.0
	_reach = move_toward(_reach, want, dt * (4.5 if want > _reach else 3.0))
	var k = smoothstep(0.0, 1.0, _reach)
	var rest = Transform3D(Basis.from_euler(RIGHT_REST_ROT), RIGHT_REST)
	if k <= 0.001:
		right_hand.transform = rest
		return
	# the floor spot, in the hands' own space
	var spot = hands.global_transform.affine_inverse() * Vector3(aim_point.x, 0.0, aim_point.y)
	# the hand goes out and down to the lower right of the line of sight
	var grip = spot.normalized() * 0.47 + Vector3(0.1, -0.13, 0.0)
	if rubbing:
		grip += Vector3(sin(_time * 13.0) * 0.035, 0.0, cos(_time * 26.0) * 0.008)
	elif drawing:
		grip += Vector3(sin(_time * 47.0), sin(_time * 53.0 + 1.0), 0.0) * 0.0018   # chalk scraping stone
	var z = (grip - spot).normalized()          # the chalk lies along -Z: tip to the spot
	var x = Vector3.UP.cross(z).normalized()
	var y = z.cross(x).normalized()
	var reach = Transform3D(Basis(x, y, z), grip)
	right_hand.transform = rest.interpolate_with(reach, k)


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
	rubbing = can_draw and not want_draw and aim_valid and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if rubbing:
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
