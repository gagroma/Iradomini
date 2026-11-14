extends Node

const PlayerScript = preload("res://scripts/player.gd")
const Lighter = preload("res://scripts/lighter.gd")

const OUTSIDE := 9.5
const STAND := 1.85
const WALK := 1.3
const OPEN := 1.7
const SIDE := 0.35
const TURN_TIME := 1.15
const REACH_TIME := 0.4
const CLOSE_TIME := 0.62
const BACK_TIME := 1.4
const CRATE_GAP := 0.74
const LIGHTER_ROLL := 0.45

var main
var player
var leaf: Node3D
var running := false

var _closed_r := 0.0
var _open_sign := 1.0
var _inn := Vector3.ZERO
var _door := Vector3.ZERO
var _stand := Vector3.ZERO
var _phase := ""
var _t := 0.0
var _yaw_from := 0.0
var _yaw_to := 0.0
var _pitch_from := 0.0
var _pitch_to := 0.0
var _enter_yaw := 0.0
var _creak: AudioStreamPlayer3D
var _has_crates := false
var _crate_top := Vector3.ZERO
var _approach := Vector3.ZERO
var _candle_spot := Transform3D.IDENTITY
var _chalk_spot := Transform3D.IDENTITY
var _candle_rest := Transform3D.IDENTITY
var _left_rest := Transform3D.IDENTITY
var _chalk_rest := Transform3D.IDENTITY
var _wick_local := Vector3.ZERO
var _lighter: Node3D
var _flags := {}


func setup(main_node) -> void:
	main = main_node
	player = main.player
	leaf = main.level.entrance_leaf
	_door = Vector3(main.level.door_pos.x, 0.0, main.level.door_pos.z)
	var to_room = main.level.player_start - _door
	to_room.y = 0.0
	_inn = to_room.normalized()
	var side = (-_inn).cross(Vector3.UP)
	var parent_basis = leaf.get_parent().global_basis
	var hs = 1.0 if parent_basis.x.dot(side) > 0.0 else -1.0
	leaf.position.x = 0.75 * hs
	_closed_r = PI if hs > 0.0 else 0.0
	leaf.position.z = 0.069 if hs > 0.0 else -0.01
	var test = parent_basis * Vector3(cos(_closed_r + 1.0), 0.0, -sin(_closed_r + 1.0))
	_open_sign = 1.0 if test.dot(_inn) > 0.0 else -1.0
	_set_leaf(1.0)
	_stand = _door + _inn * STAND + side * SIDE
	player.position = _door - _inn * OUTSIDE
	var yaw = atan2(-_inn.x, -_inn.z)
	_enter_yaw = yaw
	player.yaw = yaw
	player.yaw_target = yaw
	player.rotation.y = yaw
	player.pitch_target = -0.2
	player.pitch = -0.2
	player.collision_mask = 0
	player.right_override = _low_right()
	player.right_hand.visible = false
	_setup_crates()


func _setup_crates() -> void:
	var crates: Node3D = main.level.get("intro_crates")
	if crates == null or not crates.is_visible_in_tree():
		return
	_has_crates = true
	var origin = crates.global_position
	_crate_top = crates.global_transform * Vector3(0.0, 1.06, 0.0)
	var centre = Vector3(main.level.rooms[0]["pos"].x, 0.0, main.level.rooms[0]["pos"].y)
	var to_room = centre - origin
	to_room.y = 0.0
	to_room = to_room.normalized()
	_approach = origin + to_room * CRATE_GAP
	_approach.y = 0.0
	var facing = -to_room
	var right = facing.cross(Vector3.UP)
	var face_yaw = atan2(-facing.x, -facing.z)
	var candle = player.candle
	_candle_rest = candle.transform
	_left_rest = player.left_hand.transform
	_chalk_rest = player.chalk_stick.transform
	_candle_spot = Transform3D(Basis(Vector3.UP, face_yaw - 2.36), _crate_top + to_room * 0.13 - right * 0.11)
	_chalk_spot = Transform3D(Basis(Vector3.UP, face_yaw + 1.15), _crate_top + to_room * 0.17 + right * 0.1 + Vector3.UP * 0.006)
	candle.held = false
	candle.top_level = true
	candle.global_transform = _candle_spot
	candle.lit = false
	candle._size = 0.0
	candle._ember = 0.0
	candle._out_time = 100.0
	player.left_hand.top_level = true
	player.left_hand.visible = false
	player.chalk_stick.top_level = true
	player.chalk_stick.global_transform = _chalk_spot


func play() -> void:
	running = true
	_go("wait")


func _go(phase: String) -> void:
	_phase = phase
	_t = 0.0


func _set_leaf(open: float) -> void:
	leaf.rotation.y = _closed_r + _open_sign * OPEN * open


func _contact() -> Vector3:
	return leaf.global_transform * Vector3(1.04, 1.12, 0.0)


func _ease(x: float) -> float:
	return smoothstep(0.0, 1.0, clampf(x, 0.0, 1.0))


func _hands() -> Transform3D:
	return player.hands.global_transform


func _to_hands(g: Transform3D) -> Transform3D:
	return _hands().affine_inverse() * g


func _rest_right() -> Transform3D:
	return Transform3D(Basis.from_euler(PlayerScript.RIGHT_REST_ROT), PlayerScript.RIGHT_REST)


func _low_right() -> Transform3D:
	return Transform3D(Basis.from_euler(PlayerScript.RIGHT_REST_ROT), PlayerScript.RIGHT_REST + Vector3(0.05, -0.4, 0.12))


func _pressed() -> Transform3D:
	var spot = _hands().affine_inverse() * _contact()
	var grip = spot.normalized() * minf(spot.length() - 0.06, 0.52)
	return Transform3D(Basis.from_euler(Vector3(0.2, 0.6, 0.0)), grip + Vector3(0.0, -0.04, 0.0))


func _right(pose: Transform3D) -> void:
	player.right_hand.visible = true
	player.right_override = pose


func _hide_right() -> void:
	player.right_hand.visible = false
	player.right_override = _low_right()


func _lighter_pose(away: float) -> Transform3D:
	var wick = _hands() * _wick_local
	var face = Basis(Vector3.UP, player.yaw)
	var target = wick + face.x * 0.016 + Vector3.UP * 0.003 + face.z * 0.004
	target += (face.x * 0.07 + Vector3.UP * -0.06 + face.z * 0.03) * away
	var basis = face * Basis(Vector3(0, 0, 1), LIGHTER_ROLL * (1.0 - away * 0.6))
	var lighter_local = _to_hands(Transform3D(basis, target - basis * Lighter.FLAME_AT))
	var hand = player.right_hand_at(lighter_local.origin + lighter_local.basis * Vector3(0.0, 0.025, 0.0))
	_lighter.transform = hand.affine_inverse() * lighter_local
	return hand


func _once(key: String) -> bool:
	if _flags.has(key):
		return false
	_flags[key] = true
	return true


func _process(dt: float) -> void:
	if not running:
		return
	_t += dt
	match _phase:
		"wait":
			if _t > 0.45:
				_go("walk_in")
		"walk_in":
			var look_down = smoothstep(0.5, 7.0, _t)
			player.pitch_target = lerpf(-0.2, -0.04, look_down) + 0.14 * sin(PI * clampf((_t - 2.5) / 3.5, 0.0, 1.0)) + sin(_t * 1.7) * 0.02
			player.yaw_target = _enter_yaw + sin(_t * 0.6) * 0.06 * (1.0 - look_down)
			if player.walk_to(_stand, WALK):
				_begin_turn(_contact(), -1)
				_go("turn_door")
		"turn_door":
			var u = _ease(_t / TURN_TIME)
			player.yaw_target = lerpf(_yaw_from, _yaw_to, u)
			player.pitch_target = lerpf(_pitch_from, _pitch_to, u)
			if _t >= TURN_TIME * 0.8:
				_right(_low_right().interpolate_with(_pressed(), _ease((_t - TURN_TIME * 0.8) / REACH_TIME)))
			if _t >= TURN_TIME:
				_go("push")
		"push":
			_right(_low_right().interpolate_with(_pressed(), _ease((_t + TURN_TIME * 0.2) / REACH_TIME)))
			if _t >= REACH_TIME - TURN_TIME * 0.2:
				_play_creak()
				_go("close")
		"close":
			var u = clampf(_t / CLOSE_TIME, 0.0, 1.0)
			_set_leaf(1.0 - pow(u, 2.2))
			_right(_low_right().interpolate_with(_pressed(), _ease(1.0 - (u - 0.3) / 0.45)))
			if u >= 1.0:
				_slam()
				_go("hold")
		"hold":
			_set_leaf(0.025 * exp(-_t * 9.0) * absf(sin(_t * 30.0)))
			_hide_right()
			if _t >= 0.7:
				_set_leaf(0.0)
				_go("to_crates" if _has_crates else "turn_exit_begin")
		"to_crates":
			player.aim_at(_crate_top, 3.5, dt)
			var there = false
			if _t > 0.45:
				there = player.walk_to(_approach, 1.0)
			if there:
				_go("look")
		"look":
			player.aim_at(_candle_spot.origin, 4.0, dt)
			if _t >= 0.45:
				player.left_hand.visible = true
				_go("reach_candle")
		"reach_candle":
			player.aim_at(_candle_spot.origin, 4.0, dt)
			var low = Transform3D(_candle_rest.basis, _candle_rest.origin + Vector3(-0.05, -0.4, 0.1))
			var u = _ease(_t / 0.55)
			player.left_hand.global_transform = (_hands() * low * _left_rest).interpolate_with(_candle_spot * _left_rest, u)
			if _t >= 0.55:
				_go("lift_candle")
		"lift_candle":
			player.pitch_toward(-0.3, 3.0, dt)
			var u = _ease(_t / 0.7)
			var g = _candle_spot.interpolate_with(_hands() * _candle_rest, u)
			g.origin.y += sin(PI * u) * 0.05
			player.candle.global_transform = g
			player.left_hand.global_transform = g * _left_rest
			if _t >= 0.7:
				_attach_candle()
				_go("lighter_in")
		"lighter_in":
			player.pitch_toward(-0.3, 3.0, dt)
			if _once("lighter"):
				_lighter = Lighter.new()
				_lighter.transform = Transform3D(Basis.from_euler(PlayerScript.RIGHT_REST_ROT).inverse(), Vector3(0.0, -0.005, -0.035))
				player.right_hand.add_child(_lighter)
				_wick_local = _hands().affine_inverse() * player.candle.flame_center()
			_right(_low_right().interpolate_with(_lighter_pose(1.0), _ease(_t / 0.6)))
			if _t >= 0.6:
				main.sfx.play("lighter_open", -8.0)
				_go("lid")
		"lid":
			_right(_lighter_pose(1.0))
			_lighter.opened = clampf(_t / 0.16, 0.0, 1.0)
			if _t >= 0.3:
				_lighter.strike()
				main.sfx.play("lighter_strike", -6.0)
				_go("strike")
		"strike":
			var jolt = Transform3D(Basis.IDENTITY, Vector3(0.0, -0.006 * sin(PI * clampf(_t / 0.12, 0.0, 1.0)), 0.0))
			_right(jolt * _lighter_pose(1.0))
			if _t >= 0.35:
				_go("to_wick")
		"to_wick":
			_right(_lighter_pose(1.0 - _ease(_t / 0.45)))
			if _t >= 0.45:
				_go("catch")
		"catch":
			_right(_lighter_pose(0.0))
			if _t >= 0.25 and _once("lit"):
				player.candle.relight()
			if _t >= 0.75:
				_go("lighter_off")
		"lighter_off":
			_right(_lighter_pose(_ease(_t / 0.35)))
			if _t >= 0.15 and _once("snuff"):
				_lighter.snuff()
			_lighter.opened = 1.0 - clampf((_t - 0.2) / 0.12, 0.0, 1.0)
			if _t >= 0.3 and _once("click"):
				main.sfx.play("lighter_close", -8.0)
			if _t >= 0.45:
				_go("lighter_away")
		"lighter_away":
			_right(_lighter_pose(1.0).interpolate_with(_low_right(), _ease(_t / 0.5)))
			if _t >= 0.5:
				_lighter.queue_free()
				_lighter = null
				_hide_right()
				_go("reach_chalk")
		"reach_chalk":
			player.aim_at(_chalk_spot.origin, 4.0, dt)
			var grab = _to_hands(_chalk_spot * _chalk_rest.affine_inverse())
			_right(_low_right().interpolate_with(grab, _ease(_t / 0.6)))
			if _t >= 0.6:
				player.chalk_stick.top_level = false
				player.chalk_stick.transform = _chalk_rest
				main.sfx.play("pickup", -16.0, 1.4)
				_go("take_chalk")
		"take_chalk":
			player.pitch_toward(-0.05, 3.0, dt)
			var grab = _to_hands(_chalk_spot * _chalk_rest.affine_inverse())
			_right(grab.interpolate_with(_rest_right(), _ease(_t / 0.6)))
			if _t >= 0.6:
				player.right_override = null
				_go("turn_exit_begin")
		"turn_exit_begin":
			var yaw = _exit_yaw()
			_yaw_from = player.yaw_target
			_yaw_to = _yaw_from + wrapf(yaw - _yaw_from, -PI, PI)
			_pitch_from = player.pitch_target
			_pitch_to = 0.0
			_go("turn_exit")
		"turn_exit":
			var u = _ease(_t / BACK_TIME)
			player.yaw_target = lerpf(_yaw_from, _yaw_to, u)
			player.pitch_target = lerpf(_pitch_from, _pitch_to, u)
			if _t >= BACK_TIME:
				_finish()


func _exit_yaw() -> float:
	for d in main.level.rooms[0]["doors"]:
		if d["link"] >= 0 and not d["entrance"]:
			var to = Vector3(d["pos"].x, 0.0, d["pos"].y) - player.position
			return atan2(-to.x, -to.z)
	return main.level.player_yaw


func _attach_candle() -> void:
	var candle = player.candle
	candle.top_level = false
	candle.transform = _candle_rest
	candle.held = true
	player.left_hand.top_level = false
	player.left_hand.transform = _left_rest


func _begin_turn(point: Vector3, direction: int) -> void:
	var to = point - player.cam.global_position
	var want = atan2(-to.x, -to.z)
	_yaw_from = player.yaw_target
	var delta = fposmod(want - _yaw_from, TAU)
	if direction < 0:
		delta -= TAU
	_yaw_to = _yaw_from + delta
	_pitch_from = player.pitch_target
	_pitch_to = clampf(atan2(to.y, Vector2(to.x, to.z).length()), -0.4, 0.2)


func _play_creak() -> void:
	if not main.sfx.has("door_creak"):
		return
	_creak = AudioStreamPlayer3D.new()
	_creak.stream = main.sfx.streams["door_creak"]
	_creak.volume_db = -6.0
	main.add_child(_creak)
	_creak.global_position = _door + Vector3(0, 1.5, 0)
	_creak.play()


func _slam() -> void:
	_set_leaf(0.0)
	main.sfx.play_at("door_slam", main.level.door_pos, 4.0)
	player.shake(0.35)
	main.demon.hear(Vector2(main.level.door_pos.x, main.level.door_pos.z), 200.0)


func _finish() -> void:
	running = false
	_set_leaf(0.0)
	if player.candle.top_level:
		_attach_candle()
	if player.chalk_stick.top_level:
		player.chalk_stick.top_level = false
		player.chalk_stick.transform = _chalk_rest
	if not player.candle.lit:
		player.candle.relight()
	player.right_override = null
	player.right_hand.visible = true
	player.left_hand.visible = true
	player.auto_move = Vector3.ZERO
	player.collision_mask = 1
	if _creak != null:
		_creak.queue_free()
	main.end_intro()
	queue_free()
