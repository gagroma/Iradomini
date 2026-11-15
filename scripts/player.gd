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
const Boons = preload("res://scripts/boons.gd")
const HandCandle = preload("res://scripts/candle.gd")
const HandChalk = preload("res://scripts/hand_chalk.gd")
const Models = preload("res://scripts/models.gd")
const HAND_RIGHT = preload("res://assets/models/hand_right.glb")   # tools/make_hands.py
const HAND_LEFT = preload("res://assets/models/hand_left.glb")
const SawnOff = preload("res://scripts/sawn_off.gd")
const GUN_POSE := Vector3(0.2, -0.205, -0.36)
const GUN_POSE_ROT := Vector3(0.02, 0.06, 0.0)
const GUN_IN_HAND := Vector3(0.0, 0.006, -0.06)
const GUN_IN_HAND_ROT := Vector3(0.0, 0.0, 0.0)
const OPEN_POSE := Vector3(0.09, -0.16, -0.32)
const OPEN_POSE_ROT := Vector3(0.38, 0.6, -0.3)
const POCKET_POSE := Vector3(0.3, -0.6, 0.02)
const POCKET_POSE_ROT := Vector3(-0.4, 0.3, 0.6)
const RELOAD_TIME := 2.6
# where the right hand rests (it holds the chalk at its back end, tip forward)
const RIGHT_REST := Vector3(0.2, -0.15, -0.33)
const RIGHT_REST_ROT := Vector3(-0.5, 0.3, 0.0)
const SHOULDER := Vector3(0.3, -0.4, 0.2)
const FINGERTIPS := Vector3(0.0, -0.005, -0.035)

const MOUSE_SENSITIVITY := 0.0022
const EYE_HEIGHT := 1.55
const CROUCH_HEIGHT := 0.8
const CANDLE_ENERGY := 2.2    # how bright the candle in your hand is

var main
var head: Node3D
var cam: Camera3D
var hands: Node3D
var left_hand: Node3D
var chalk_stick              # hand_chalk.gd: wears down unevenly as you draw
var candle                  # candle.gd: burns down, flame reacts to wind and fear
var right_hand: Node3D      # holds the chalk; reaches for the floor while you draw
var rubbing := false        # right mouse held on the floor: rubbing a circle out
var _reach := 0.0           # 0 = hand at rest, 1 = arm stretched out to the floor
var _lag := Vector2.ZERO    # the hands trail a little behind the turning head
var _breath_phase := 0.0
var _trauma := 0.0          # 0..1 camera shake (the demon's scream, its blows, its steps)
var _shake_noise := FastNoiseLite.new()

var yaw := 0.0              # where the body really looks (left/right)
var pitch := 0.0            # where the head really looks (up/down)
var yaw_target := 0.0       # where the mouse wants to look
var pitch_target := 0.0

var alive := true
var frozen := false         # true during the ending
var crouching := false
var running := false
var stamina := 5.0          # seconds of running left (tuning.gd STAMINA_MAX)
var winded := false         # ran out: no running until you get your breath back
var is_hidden_now := false  # crouched next to cover: the demon cannot see you
var wards := 0
var in_wardrobe := false
var hands_down := 0.0
var critical := false       # wounded: the next hit kills (GDD "Zdorovie")
var critical_time := 0.0
var relics_found := 0       # each one makes your steps louder
var fear := 0.0             # 0..1, set by main.gd from the demon's distance
var aim_valid := false      # true when you look at floor within chalk reach
var aim_point := Vector2.ZERO
var drawing := false
var erase_progress := 0.0
var _pinned := 0.0
var auto_move := Vector3.ZERO
var right_override: Variant = null
var gun: Node3D
var has_gun := false
var shells := 0
var weapon := 0
var _switch_to := 0
var _lower := 0.0
var _recoil := 0.0
var _fire_cd := 0.0
var _lmb_was := false
var spare := 0
var _reload_t := -1.0
var _reload_queued := false
var _reload_n := 0
var _load_count := 0
var _eject_n := 0
var _hold := Transform3D.IDENTITY
var _hand_shell: Node3D
var _hulls := []

var _time := 0.0
var _bob := 0.0
var _step_acc := 0.0
var _kick := 0.0
var _head_y := EYE_HEIGHT


func setup(main_node) -> void:
	main = main_node
	stamina = Boons.stamina_max()
	wards = Boons.wards()
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
	cam.far = 60.0
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
	left_hand = left
	candle.add_child(left)          # so it rises with the candle as the candle burns down

	right_hand = Node3D.new()
	right_hand.position = RIGHT_REST
	right_hand.rotation = RIGHT_REST_ROT
	hands.add_child(right_hand)
	chalk_stick = HandChalk.new()   # the end in your fingers at the hand's origin, tip forward
	right_hand.add_child(chalk_stick)
	right_hand.add_child(_hand_model(HAND_RIGHT, hand_mat))
	gun = SawnOff.new()
	gun.sfx = main.sfx
	gun.transform = gun_in_hand()
	gun.visible = false
	right_hand.add_child(gun)


static func gun_in_hand() -> Transform3D:
	return Transform3D(Basis.from_euler(GUN_IN_HAND_ROT), GUN_IN_HAND)


static func gun_pose() -> Transform3D:
	return Transform3D(Basis.from_euler(GUN_POSE_ROT), GUN_POSE)


func give_gun(loaded: int) -> void:
	has_gun = true
	shells = loaded
	gun.set_loaded(2)


func reloading() -> bool:
	return _reload_t >= 0.0


func reload() -> void:
	if not has_gun or reloading() or not alive or frozen or right_override != null:
		return
	if spare <= 0 or shells >= 2:
		return
	if weapon != 1 or _switching():
		_reload_queued = true
		switch_weapon(1)
		return
	_reload_t = 0.0
	_reload_n = mini(2 - shells, spare)
	_load_count = _reload_n
	_eject_n = 2 - shells
	_hold = _open_pose() * gun_in_hand()
	main.sfx.play("gun_break", -6.0)


func _open_pose() -> Transform3D:
	return Transform3D(Basis.from_euler(OPEN_POSE_ROT), OPEN_POSE)


func _pocket_pose() -> Transform3D:
	return Transform3D(Basis.from_euler(POCKET_POSE_ROT), POCKET_POSE)


func _chamber_in_hands(i: int) -> Transform3D:
	var hold_world := hands.global_transform * _hold
	var ch: Node3D = gun.chambers[i]
	var local_in_gun: Transform3D = gun.global_transform.affine_inverse() * ch.global_transform
	return hands.global_transform.affine_inverse() * (hold_world * local_in_gun)


func _update_reload(dt: float) -> Variant:
	_reload_t += dt
	var t := _reload_t
	var aim := gun_pose()
	var open := _open_pose()
	var pose: Transform3D
	var gun_free := false
	if t < 0.35:
		var u := smoothstep(0.0, 1.0, t / 0.3)
		pose = aim.interpolate_with(open, u)
		gun.open = smoothstep(0.05, 0.3, t)
		if t >= 0.22 and _eject_n > 0:
			var flick := sin(PI * clampf((t - 0.22) / 0.13, 0.0, 1.0))
			pose = Transform3D(pose.basis * Basis(Vector3.RIGHT, 0.5 * flick), pose.origin + Vector3(0, 0.03, 0.02) * flick)
			if t >= 0.27 and _hulls.is_empty():
				gun.set_loaded(2)
				_hulls = gun.eject(main, _eject_n)
				for i in range(_eject_n, 2):
					gun.chambers[i].visible = true
				_eject_n = -_eject_n
	elif t < 0.85:
		gun_free = true
		pose = open.interpolate_with(_pocket_pose(), smoothstep(0.0, 1.0, (t - 0.35) / 0.5))
		if t >= 0.7 and _hand_shell == null:
			main.sfx.play("pickup", -18.0, 1.6)
	elif t < 0.85 + 0.5 * _load_count:
		gun_free = true
		var k := int((t - 0.85) / 0.5)
		var lt := (t - 0.85) - k * 0.5
		var ch := _chamber_in_hands(k)
		var mouth := Transform3D(ch.basis, ch.origin + ch.basis.z.normalized() * 0.09)
		var shell_xf: Transform3D
		if lt < 0.3:
			var from := _pocket_pose() * Transform3D(Basis.from_euler(Vector3(-1.2, 0.0, 0.0)), FINGERTIPS)
			if k > 0:
				from = Transform3D(mouth.basis, mouth.origin + Vector3(0.04, -0.1, 0.06))
			shell_xf = from.interpolate_with(mouth, smoothstep(0.0, 1.0, lt / 0.3))
		else:
			shell_xf = mouth.interpolate_with(ch, smoothstep(0.0, 1.0, (lt - 0.3) / 0.12))
		if _hand_shell == null:
			_hand_shell = gun.make_shell(gun.material())
			hands.add_child(_hand_shell)
		_hand_shell.visible = true
		_hand_shell.transform = shell_xf
		pose = right_hand_at(shell_xf.origin + shell_xf.basis.z.normalized() * 0.004)
		if lt >= 0.42 and not gun.chambers[k].visible:
			gun.chambers[k].visible = true
			_hand_shell.visible = false
			main.sfx.play("shell_in", -4.0)
	else:
		var t2 := t - (0.85 + 0.5 * _load_count)
		if _hand_shell != null:
			_hand_shell.queue_free()
			_hand_shell = null
		if t2 < 0.3:
			gun_free = true
			pose = right_hand_at(_chamber_in_hands(maxi(_load_count - 1, 0)).origin).interpolate_with(open, smoothstep(0.0, 1.0, t2 / 0.3))
		elif t2 < 0.55:
			var snap := clampf((t2 - 0.32) / 0.08, 0.0, 1.0)
			gun.open = 1.0 - snap
			var jolt := sin(PI * clampf((t2 - 0.34) / 0.18, 0.0, 1.0))
			pose = Transform3D(open.basis * Basis(Vector3.RIGHT, -0.35 * jolt), open.origin + Vector3(0, 0.025, -0.015) * jolt)
			if snap > 0.0 and _reload_n > 0:
				main.sfx.play("gun_close", -4.0)
				shells += _reload_n
				spare -= _reload_n
				_reload_n = 0
		else:
			pose = open.interpolate_with(aim, smoothstep(0.0, 1.0, (t2 - 0.55) / 0.3))
			if t2 >= 0.85:
				_reload_t = -1.0
				_hulls_done()
	right_hand.transform = pose
	if gun_free:
		gun.transform = pose.affine_inverse() * _hold
	else:
		gun.transform = gun_in_hand()
	return pose


func _hulls_done() -> void:
	_eject_n = 0


func switch_weapon(to: int) -> void:
	if reloading():
		return
	if not has_gun or to == _switch_to or not alive or frozen or right_override != null:
		return
	_switch_to = to
	main.on_weapon_switch(to)


func holster() -> void:
	if reloading():
		_reload_t = -1.0
		gun.open = 0.0
		shells += _reload_n
		spare -= _reload_n
		_reload_n = 0
		if _hand_shell != null:
			_hand_shell.queue_free()
			_hand_shell = null
	weapon = 0
	_switch_to = 0
	_lower = 0.0
	if gun != null and not gun.top_level:
		gun.visible = false
	chalk_stick.visible = true


func _switching() -> bool:
	return _switch_to != weapon or _lower > 0.05


func _fire() -> void:
	if _fire_cd > 0.0:
		return
	_fire_cd = 0.45
	if shells <= 0:
		main.sfx.play("dry_fire", -2.0)
		_recoil = 0.12
		return
	shells -= 1
	gun.fire()
	_recoil = 1.0
	pitch_target = minf(pitch_target + 0.075, 1.4)
	yaw_target += randf_range(-0.025, 0.025)
	shake(0.55)
	main.sfx.play("shotgun", 3.0)
	main.on_shot(cam.global_position, -cam.global_transform.basis.z)


func _hand_model(scene: PackedScene, mat: Material) -> Node3D:
	var node = scene.instantiate()
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


func pos2() -> Vector2:
	return Vector2(global_position.x, global_position.z)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			switch_weapon(1 - _switch_to)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_R:
			reload()
		elif event.physical_keycode == KEY_1:
			switch_weapon(0)
		elif event.physical_keycode == KEY_2:
			switch_weapon(1)
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if alive and not frozen:
			var rel = event.screen_relative
			var sensitivity := MOUSE_SENSITIVITY * GameSettings.mouse_sensitivity / 100.0
			yaw_target -= rel.x * sensitivity
			pitch_target = clampf(pitch_target - rel.y * sensitivity, -1.5, 1.4)


func _physics_process(dt: float) -> void:
	_time += dt
	var captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var can_act = alive and not frozen

	# --- looking, with a little inertia so it feels like a head, not a cursor ---
	var k = 1.0 - exp(-22.0 * dt)
	yaw = lerpf(yaw, yaw_target, k)
	pitch = lerpf(pitch, pitch_target, k)
	rotation.y = yaw
	head.rotation.x = pitch

	# --- moving ---
	_pinned = maxf(0.0, _pinned - dt)
	var input = Vector2.ZERO
	if _pinned > 0.0:
		velocity.x = 0.0
		velocity.z = 0.0
	if can_act and _pinned <= 0.0:
		if Input.is_physical_key_pressed(KEY_W):
			input.y -= 1.0
		if Input.is_physical_key_pressed(KEY_S):
			input.y += 1.0
		if Input.is_physical_key_pressed(KEY_A):
			input.x -= 1.0
		if Input.is_physical_key_pressed(KEY_D):
			input.x += 1.0
	crouching = can_act and (Input.is_physical_key_pressed(KEY_CTRL) or Input.is_physical_key_pressed(KEY_C))
	running = can_act and not crouching and not winded and Input.is_physical_key_pressed(KEY_SHIFT) and input.length() > 0.0
	# stamina: running uses it up; out of it, you must get your breath back first
	if running:
		stamina = maxf(0.0, stamina - dt)
		if stamina <= 0.0:
			winded = true
	else:
		stamina = minf(Boons.stamina_max(), stamina + dt * Boons.stamina_regen())
		if winded and stamina >= Boons.stamina_max() * T.STAMINA_RECOVER:
			winded = false
	var speed = T.WALK_SPEED * Boons.speed_scale()
	if crouching:
		speed = T.CROUCH_SPEED
	elif running:
		speed = T.RUN_SPEED * Boons.speed_scale()
	var wish = Vector3.ZERO
	if input.length() > 0.0:
		input = input.normalized()
		wish = (transform.basis * Vector3(input.x, 0.0, input.y)) * speed
	var walking_auto = auto_move != Vector3.ZERO
	if walking_auto:
		wish = auto_move
	var accel = 30.0 if can_act else (4.0 if walking_auto else 8.0)
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
	if (can_act or walking_auto) and moved > 0.0005:
		_step_acc += moved
		_bob += moved * (TAU / (stride * 2.0))
		if _step_acc >= stride:
			_step_acc = 0.0
			main.player_step(running, crouching)
	else:
		_step_acc = minf(_step_acc, stride * 0.5)

	# --- hiding: crouch next to a pew, column or altar (GDD "Pryatatsya") ---
	is_hidden_now = in_wardrobe or (crouching and main.level.near_cover(pos2(), T.COVER_DISTANCE))

	# --- wounded timer (GDD: 20 seconds, then back to normal) ---
	if critical:
		critical_time -= dt
		if critical_time <= 0.0:
			critical = false

	_fire_cd = maxf(0.0, _fire_cd - dt)
	var flying := []
	for h in _hulls:
		if is_instance_valid(h) and gun.fly(h, dt, main.sfx):
			flying.append(h)
	_hulls = flying
	if _reload_queued and weapon == 1 and not _switching():
		_reload_queued = false
		reload()
	_recoil = move_toward(_recoil, 0.0, dt * 3.2)
	if _switch_to != weapon:
		_lower = move_toward(_lower, 1.0, dt / 0.2)
		if _lower >= 1.0:
			weapon = _switch_to
			if weapon == 1:
				main.sfx.play("gun_close", -16.0, 1.3)
	else:
		_lower = move_toward(_lower, 0.0, dt / 0.25)
	_update_camera(dt, moved)
	_update_chalk(dt, can_act and captured)


func _update_camera(dt: float, moved: float) -> void:
	var target_y = CROUCH_HEIGHT if crouching else EYE_HEIGHT
	_head_y = lerpf(_head_y, target_y, 1.0 - exp(-10.0 * dt))
	var moving = 1.0 if moved > 0.0005 else 0.0
	var bob_y = sin(_bob) * 0.035 * moving
	var bob_x = cos(_bob * 0.5) * 0.02 * moving
	# breathing: heavier and faster the more out of breath you are
	var puff = 1.0 - stamina / Boons.stamina_max()
	_breath_phase += dt * (1.4 + 2.6 * puff)
	var breath = sin(_breath_phase) * (0.008 + 0.022 * puff)
	var shake = fear * fear * 0.006
	head.position = Vector3(bob_x + randf_range(-shake, shake), _head_y + bob_y + breath + randf_range(-shake, shake), 0.0)
	_kick = move_toward(_kick, 0.0, dt * 2.2)
	# shake: strong for a moment, then dying away (the square makes small shakes subtle)
	_trauma = maxf(0.0, _trauma - dt * 0.9)
	var tr = _trauma * _trauma
	var n = _time * 30.0
	cam.rotation.x = tr * 0.07 * _shake_noise.get_noise_2d(n, 0.0)
	cam.rotation.y = tr * 0.07 * _shake_noise.get_noise_2d(n, 50.0)
	cam.rotation.z = sin(_time * 0.7) * 0.004 + _kick * 0.35 * sin(_time * 38.0) + tr * 0.1 * _shake_noise.get_noise_2d(n, 100.0)
	head.position += Vector3(_shake_noise.get_noise_2d(n, 150.0), _shake_noise.get_noise_2d(n, 200.0), 0.0) * tr * 0.04
	# GDD: FOV 62, narrowing to 50 next to the demon
	var fov_target = lerpf(T.FOV_NORMAL, T.FOV_NEAR_DEMON, fear)
	cam.fov = lerpf(cam.fov, fov_target, 1.0 - exp(-4.0 * dt))
	# hands sway a little with the walk, and trail a little behind the head
	hands.position = Vector3(-bob_x * 0.5, -bob_y * 0.5 - hands_down * 0.42, hands_down * 0.12)
	var lag_want = Vector2(clampf(pitch_target - pitch, -0.3, 0.3), clampf(yaw_target - yaw, -0.3, 0.3)) * -0.35
	_lag = _lag.lerp(lag_want, 1.0 - exp(-12.0 * dt))
	hands.rotation = Vector3(_lag.x, _lag.y, 0.0)
	_update_right_hand(dt)
	# the candle burns down; its flame leans in the wind of your movement and
	# flickers harder the closer the demon is (GDD)
	candle.tick(dt, fear)
	# GDD "Zapas bez interfeisa": the chalk stick gets shorter as you use it
	chalk_stick.set_left(clampf(main.chalk.chalk / Boons.chalk_max(), 0.0, 1.0))
	if right_override == null and weapon == 1:
		chalk_stick.visible = false


# Drawing: the right arm stretches out towards the spot on the floor you look
# at, the chalk turned tip-first to it, trembling as it scrapes the stone.
# Rubbing out: the arm reaches out and scrubs from side to side.
func _update_right_hand(dt: float) -> void:
	var want = 1.0 if (drawing and aim_valid) or rubbing else 0.0
	_reach = move_toward(_reach, want, dt * (4.5 if want > _reach else 3.0))
	var k = smoothstep(0.0, 1.0, _reach)
	var rest = Transform3D(Basis.from_euler(RIGHT_REST_ROT), RIGHT_REST)
	if right_override != null:
		right_hand.transform = right_override
		return
	if gun != null and not gun.top_level:
		gun.visible = has_gun and weapon == 1
		gun.transform = gun_in_hand()
	chalk_stick.visible = weapon == 0
	var low := Vector3(0.05, -0.34, 0.14) * smoothstep(0.0, 1.0, _lower)
	if weapon == 1 and reloading():
		_update_reload(dt)
		return
	if weapon == 1:
		var r := _recoil * _recoil
		var pose := gun_pose()
		pose.basis = pose.basis * Basis(Vector3.RIGHT, 0.5 * r + 0.02 * sin(_time * 1.3))
		pose.origin += Vector3(0.0, 0.025 * r, 0.075 * r) + low
		right_hand.transform = pose
		return
	rest.origin += low
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
		if t <= Boons.chalk_reach():
			var floor_point: Vector3 = origin + dir * t
			aim_point = Vector2(floor_point.x, floor_point.z)
			if main.level.nav.is_free(aim_point):
				# The floor has no collider. Check whether a wall or prop hides it.
				var ray := PhysicsRayQueryParameters3D.create(origin, floor_point, collision_mask)
				aim_valid = get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

	var lmb = can_draw and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if weapon == 1 or _switching():
		if drawing:
			drawing = false
			main.chalk.release()
		rubbing = false
		erase_progress = 0.0
		main.chalk.erase_cancel()
		if weapon == 1 and not _switching() and not reloading() and lmb and not _lmb_was:
			_fire()
		_lmb_was = lmb
		return
	_lmb_was = lmb
	var want_draw = lmb
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


func right_hand_at(grip: Vector3) -> Transform3D:
	var z = (SHOULDER - grip).normalized()
	var x = Vector3.UP.cross(z).normalized()
	var b = Basis(x, z.cross(x), z) * Basis.from_euler(Vector3(0.35, 0.0, 0.25))
	return Transform3D(b, grip - b * FINGERTIPS)


func aim_at(point: Vector3, rate: float, dt: float, lowest := -0.75, highest := 0.4) -> void:
	var to = point - head.global_position
	var want_yaw = atan2(-to.x, -to.z)
	var want_pitch = clampf(atan2(to.y, Vector2(to.x, to.z).length()), lowest, highest)
	var k = 1.0 - exp(-rate * dt)
	yaw_target += wrapf(want_yaw - yaw_target, -PI, PI) * k
	pitch_target = lerpf(pitch_target, want_pitch, k)


func pitch_toward(value: float, rate: float, dt: float) -> void:
	pitch_target = lerpf(pitch_target, value, 1.0 - exp(-rate * dt))


func walk_to(point: Vector3, speed: float) -> bool:
	var to = point - position
	to.y = 0.0
	var d = to.length()
	if d < 0.04:
		auto_move = Vector3.ZERO
		return true
	auto_move = to / d * speed * clampf(d / 0.45, 0.2, 1.0)
	return false


func pin(seconds: float) -> void:
	_pinned = maxf(_pinned, seconds)


# Shake the camera: amount 0..1 adds up (a scream next to you is about 0.9).
func shake(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


# Called by the demon when its claws land.
func take_hit(from: Vector3) -> void:
	if not alive or in_wardrobe:        # nothing reaches you inside a wardrobe
		return
	shake(0.7)
	_pinned = 0.0
	if wards > 0:
		wards -= 1
		_kick = 0.6
		var push = global_position - from
		push.y = 0.0
		if push.length() > 0.01:
			velocity = push.normalized() * 6.0
		main.on_ward_broken()
		return
	if critical:
		alive = false
		main.chalk.release()
		main.on_player_died()
		return
	critical = true
	critical_time = Boons.critical_time()
	_kick = 1.0
	var away = global_position - from
	away.y = 0.0
	if away.length() > 0.01:
		velocity = away.normalized() * 7.0
	main.on_player_hit()
