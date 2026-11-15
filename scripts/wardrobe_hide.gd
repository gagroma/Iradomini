extends Node
# WARDROBE - hiding inside a wardrobe (E in front of one, E again to come out).
# Getting in and out takes a few seconds and cannot be skipped: that is the risk.
# From the moment you step inside nothing can see or hurt you. If a demon was chasing you it comes
# to the doors, stands there a while (you watch it through the gap), and goes back to its patrol.

const OPEN := 1.75
const AJAR := 0.22
const OUTSIDE := 0.8
const PEEK_YAW := 0.45
const PEEK_PITCH := 0.3

var main
var player
var wardrobe: Node3D

var _door_l: Node3D
var _door_r: Node3D
var _front := Vector3.BACK
var _out_point := Vector3.ZERO
var _in_point := Vector3.ZERO
var _phase := ""
var _t := 0.0
var _from := Vector3.ZERO
var _yaw_from := 0.0
var _yaw_to := 0.0
var _open := 0.0
var _out_yaw := 0.0
var _energy := 2.2


func start(main_node, w: Node3D) -> void:
	main = main_node
	player = main.player
	wardrobe = w
	_door_l = w.find_child("WardrobeDoorL", true, false)
	_door_r = w.find_child("WardrobeDoorR", true, false)
	_front = w.global_basis.z
	_front.y = 0.0
	_front = _front.normalized()
	var base = Vector3(w.global_position.x, 0.0, w.global_position.z)
	_out_point = base + _front * OUTSIDE
	_in_point = base + _front * 0.0
	_out_yaw = atan2(-_front.x, -_front.z)
	player.frozen = true
	player.collision_mask = 0
	_energy = player.candle.energy
	_go("approach")


func is_inside() -> bool:
	return _phase == "hidden"


func leave() -> void:
	if _phase != "hidden":
		return
	_set_doors(AJAR)
	main.sfx.play_at("door_creak", wardrobe.global_position + Vector3(0, 1.2, 0), -14.0, 1.4)
	_go("open_out")


func _go(phase: String) -> void:
	_phase = phase
	_t = 0.0


func _ease(x: float) -> float:
	return smoothstep(0.0, 1.0, clampf(x, 0.0, 1.0))


func _set_doors(open: float) -> void:
	_open = open
	if _door_l != null:
		_door_l.rotation.y = -open
	if _door_r != null:
		_door_r.rotation.y = open


func _physics_process(dt: float) -> void:
	if main == null:
		return
	if not player.alive:
		_end(false)
		return
	_t += dt
	match _phase:
		"approach":
			player.aim_at(wardrobe.global_position + Vector3(0, 1.25, 0), 5.0, dt)
			if player.walk_to(_out_point, 1.6):
				main.sfx.play_at("door_creak", wardrobe.global_position + Vector3(0, 1.2, 0), -12.0, 1.35)
				_go("open")
		"open":
			player.aim_at(wardrobe.global_position + Vector3(0, 1.25, 0), 5.0, dt)
			_set_doors(OPEN * _ease(_t / 0.45))
			if _t >= 0.45:
				_from = player.position
				_yaw_from = player.yaw_target
				_yaw_to = _yaw_from + wrapf(_out_yaw - _yaw_from, -PI, PI)
				if absf(_yaw_to - _yaw_from) < 2.5:
					_yaw_to = _yaw_from + PI
				# you step in: from now on you are out of sight and out of reach. The one that was
				# chasing you comes to the doors to look.
				var h = main.hunting_demon()
				if h != null and h.awareness() == 2:
					h.lose_player_at(Vector2(_out_point.x, _out_point.z))
				player.in_wardrobe = true
				_go("enter")
		"enter":
			var u = _ease(_t / 0.9)
			player.position = _from.lerp(_in_point, u)
			player.hands_down = u
			player.candle.energy = lerpf(_energy, _energy * 0.3, u)
			player.yaw_target = lerpf(_yaw_from, _yaw_to, _ease((_t - 0.25) / 0.65))
			player.pitch_target = lerpf(player.pitch_target, -0.05, dt * 4.0)
			if _t >= 0.9:
				_go("close")
		"close":
			_set_doors(lerpf(OPEN, AJAR, _ease(_t / 0.5)))
			if _t >= 0.5:
				main.sfx.play_at("place", wardrobe.global_position + Vector3(0, 1.2, 0), -6.0, 0.55)
				_settle_inside()
		"hidden":
			pass
		"open_out":
			_set_doors(lerpf(AJAR, OPEN, _ease(_t / 0.4)))
			if _t >= 0.4:
				_from = player.position
				_go("step_out")
		"step_out":
			var u = _ease(_t / 0.7)
			player.position = _from.lerp(_out_point, u)
			player.hands_down = 1.0 - u
			player.candle.energy = lerpf(_energy * 0.3, _energy, u)
			if _t >= 0.7:
				_go("close_out")
		"close_out":
			_set_doors(lerpf(OPEN, 0.0, _ease(_t / 0.45)))
			if _t >= 0.45:
				main.sfx.play_at("place", wardrobe.global_position + Vector3(0, 1.2, 0), -8.0, 0.6)
				_end(true)


func _settle_inside() -> void:
	_set_doors(AJAR)
	player.hands_down = 1.0
	player.candle.energy = _energy * 0.3
	player.position = _in_point
	player.in_wardrobe = true
	_go("hidden")


func _input(event: InputEvent) -> void:
	if _phase != "hidden" or not (event is InputEventMouseMotion) or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var sens: float = player.MOUSE_SENSITIVITY * GameSettings.mouse_sensitivity / 100.0
	player.yaw_target = clampf(player.yaw_target - event.screen_relative.x * sens, _yaw_to - PEEK_YAW, _yaw_to + PEEK_YAW)
	player.pitch_target = clampf(player.pitch_target - event.screen_relative.y * sens, -PEEK_PITCH, PEEK_PITCH)


func _end(closed: bool) -> void:
	if closed:
		_set_doors(0.0)
	player.in_wardrobe = false
	player.hands_down = 0.0
	player.candle.energy = _energy
	player.auto_move = Vector3.ZERO
	player.collision_mask = 1
	player.frozen = false
	var m = main
	main = null
	m.wardrobe_done()
	queue_free()
