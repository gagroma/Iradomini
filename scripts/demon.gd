extends Node3D
# DEMON - one enemy with a small "state machine": at any moment it is in
# exactly one state, and each state has its own short rule.
#
# Sources:
#  - GDD v6 "Demon": Patrol, Investigate, Chase, Blocked, banishing, respawn.
#  - State machines are the classic way to write simple game enemies (the
#    ghosts in Pac-Man switch between "scatter" and "chase" the same way).
#  - Path finding comes from nav.gd (Godot's AStarGrid2D).
#
# THE RULE is enforced in two places: the demon never plans a path through a
# closed circle (nav.gd), and every single step is checked again with
# chalk.segment_blocked(), so no bug in the planning can break the rule.

const T = preload("res://scripts/tuning.gd")
const Models = preload("res://scripts/models.gd")

enum S { PATROL, INVESTIGATE, CHASE, BLOCKED, RECOVER, TRAPPED, GONE }
const STATE_NAMES = ["PATROL", "INVESTIGATE", "CHASE", "BLOCKED", "RECOVER", "TRAPPED", "GONE"]

var main
var state: int = S.PATROL
var pos2 := Vector2.ZERO            # where it stands on the floor (x, z)
var facing := Vector2(0.0, 1.0)     # which way it looks (x, z)
var sees_player := false
var banish_time := 0.0              # seconds spent trapped in a circle

var _path := []                     # points still to walk through
var _patrol_i := 0
var _pause := 0.0
var _look_wait := 0.0
var _repath := 0.0
var _blocked_left := 0.0
var _ignore := 0.0                  # while > 0 it has given up on an unreachable player
var _lost := 0.0                    # seconds since it last saw the player
var _attack_cd := 0.0
var _windup := 0.0
var _recover := 0.0
var _gone_left := 0.0
var _trap_id := -1
var _trap_loop = null
var _last_known := Vector2.ZERO
var _investigate := Vector2.ZERO
var _notice_cd := 0.0
var _scream_cd := 0.0

var _moving := false
var _move_speed := 0.0
var _walk_phase := 0.0
var _walk_amount := 0.0
var _step_wait := 0.0
var _attack_anim := 0.0
var _scream_anim := 0.0
var _dissolve := 0.0
var _dissolve_target := 0.0
var _time := 0.0

var _root: Node3D
var _parts := {}
var _material: ShaderMaterial
var _eye_light: SpotLight3D
var _breath = null


func setup(main_node) -> void:
	main = main_node
	var model = Models.wailer()
	_root = model["root"]
	_parts = model["parts"]
	_material = model["material"]
	add_child(_root)
	# GDD "Vneshnii vid": barely show it - a dark shape, long arms, glowing eyes
	_material.set_shader_parameter("brightness", 0.5)

	# Its eyes throw a red cone of light: that cone IS its field of view, so
	# players can see where it is looking (GDD risk: "stealth feels random").
	_eye_light = SpotLight3D.new()
	_eye_light.position = Vector3(0.0, 2.15, -0.8)
	_eye_light.rotation.x = -0.22
	_eye_light.light_color = Color(1.0, 0.3, 0.1)
	_eye_light.light_energy = 2.2
	_eye_light.spot_range = T.DEMON_VISION_RANGE
	_eye_light.spot_angle = T.DEMON_VISION_HALF_ANGLE
	add_child(_eye_light)

	_breath = main.sfx.loop_at("demon_breath", self, -4.0)
	pos2 = main.level.demon_start
	_patrol_i = _nearest_patrol_index()
	_apply_transform()


func is_active() -> bool:
	return state != S.GONE


func state_name() -> String:
	return STATE_NAMES[state]


func head_position() -> Vector3:
	return Vector3(pos2.x, 2.05, pos2.y)


func distance_to_player() -> float:
	return pos2.distance_to(main.player.pos2())


# ------------------------------------------------------------------ HEARING

# Called for every noise: a footstep, the door, a falling candlestick.
func hear(at: Vector2, radius: float) -> void:
	if state == S.GONE or state == S.TRAPPED or state == S.RECOVER or state == S.BLOCKED:
		return
	if pos2.distance_to(at) > radius:
		return
	_last_known = at
	if state == S.CHASE:
		_lost = 0.0
		return
	state = S.INVESTIGATE
	_investigate = at
	_path = []
	_look_wait = 0.0
	if _notice_cd <= 0.0:
		_notice_cd = 4.0
		main.sfx.play_at("demon_notice", head_position(), -4.0)


# ------------------------------------------------------------------- SEEING

func _line_of_sight() -> bool:
	var from = Vector3(pos2.x, 2.0, pos2.y)
	var to = main.player.cam.global_position
	var query = PhysicsRayQueryParameters3D.create(from, to, 1)   # 1 = walls and furniture
	var hit = get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty()


func _sense(pp: Vector2) -> void:
	sees_player = false
	var p = main.player
	if not p.alive:
		return
	var to_p = pp - pos2
	var dist = to_p.length()
	var near_radius = T.DEMON_CHASE_RADIUS
	if p.is_hidden_now:
		near_radius = T.DEMON_CHASE_RADIUS_HIDDEN
	var in_cone = false
	if not p.is_hidden_now and dist < T.DEMON_VISION_RANGE and dist > 0.01:
		var angle = rad_to_deg(absf(facing.angle_to(to_p)))
		in_cone = angle < T.DEMON_VISION_HALF_ANGLE
	if (in_cone or dist < near_radius) and _line_of_sight():
		sees_player = true
		_last_known = pp
		_lost = 0.0


# ------------------------------------------------------------------- MOVING

# Walk along _path. Returns 0 = still walking, 1 = arrived, 2 = a chalk line is in the way.
func _follow(dt: float, speed: float) -> int:
	if _path.is_empty():
		return 1
	var target = _path[0]
	var to = target - pos2
	var d = to.length()
	var step_len = speed * dt
	_moving = true
	_move_speed = speed
	if d <= step_len:
		if main.chalk.segment_blocked(pos2, target):
			_path = []
			return 2
		pos2 = target
		_path.remove_at(0)
		if _path.is_empty():
			return 1
		return 0
	var next_pos = pos2 + to / d * step_len
	if main.chalk.segment_blocked(pos2, next_pos):
		_path = []
		return 2
	pos2 = next_pos
	_turn_towards(to / d, dt, 8.0)
	return 0


func _turn_towards(dir: Vector2, dt: float, rate: float) -> void:
	if dir.length() < 0.001:
		return
	var mixed = facing.lerp(dir.normalized(), 1.0 - exp(-rate * dt))
	if mixed.length() > 0.001:
		facing = mixed.normalized()


# A small direct step that respects walls and chalk. "margin" keeps the body
# that far back from a chalk line.
func _step_direct(dir: Vector2, speed: float, dt: float, margin: float) -> bool:
	var next_pos = pos2 + dir * speed * dt
	if not main.level.nav.is_free(next_pos):
		return false
	if main.chalk.segment_blocked(pos2, next_pos + dir * margin):
		return false
	pos2 = next_pos
	_moving = true
	_move_speed = speed
	return true


func _path_to(target: Vector2) -> Array:
	return main.level.nav.find_path(pos2, target, main.chalk)


func _nearest_patrol_index() -> int:
	var best = 0
	var best_d = 99999.0
	var points = main.level.patrol_points
	for i in range(points.size()):
		var d = pos2.distance_to(points[i])
		if d < best_d:
			best_d = d
			best = i
	return best


# ------------------------------------------------------------------- STATES

func _physics_process(dt: float) -> void:
	_time += dt
	_moving = false
	_notice_cd = maxf(0.0, _notice_cd - dt)
	_scream_cd = maxf(0.0, _scream_cd - dt)
	_attack_cd = maxf(0.0, _attack_cd - dt)
	_ignore = maxf(0.0, _ignore - dt)

	if state == S.GONE:
		_gone_left -= dt
		if _gone_left <= 0.0 and main.game_state == "play":
			_respawn()
		_animate(dt)
		return
	if main.game_state != "play":
		_animate(dt)
		return

	var pp = main.player.pos2()
	_sense(pp)
	var reachable = not main.chalk.is_separated(pos2, pp)
	if reachable:
		_ignore = 0.0
	_update_trap(dt, pp)

	if state == S.PATROL:
		_do_patrol(dt, reachable)
	elif state == S.INVESTIGATE:
		_do_investigate(dt, reachable)
	elif state == S.CHASE:
		_do_chase(dt, pp, reachable)
	elif state == S.BLOCKED:
		_do_blocked(dt, pp, reachable)
	elif state == S.RECOVER:
		_do_recover(dt, pp)
	elif state == S.TRAPPED:
		_do_trapped(dt, pp)

	_apply_transform()
	_animate(dt)
	_footsteps(dt)


func _wants_chase(reachable: bool) -> bool:
	return sees_player and (reachable or _ignore <= 0.0)


func _start_chase() -> void:
	state = S.CHASE
	_path = []
	_repath = 0.0
	_lost = 0.0
	_windup = 0.0
	if _notice_cd <= 0.0:
		_notice_cd = 4.0
		main.sfx.play_at("demon_notice", head_position(), 0.0)


# PATROL: walk the fixed route. If a circle blocks the way, skip to the next point.
func _do_patrol(dt: float, reachable: bool) -> void:
	if _wants_chase(reachable):
		_start_chase()
		return
	if _pause > 0.0:
		_pause -= dt
		return
	var points = main.level.patrol_points
	if _path.is_empty():
		var target = points[_patrol_i]
		if pos2.distance_to(target) < 0.7:
			_patrol_i = (_patrol_i + 1) % points.size()
			_pause = 0.6
			return
		_path = _path_to(target)
		if _path.is_empty():
			_patrol_i = (_patrol_i + 1) % points.size()
			_pause = 0.3
			return
	var result = _follow(dt, T.DEMON_PATROL_SPEED)
	if result == 2:
		_patrol_i = (_patrol_i + 1) % points.size()
		_pause = 0.5


# INVESTIGATE: go to where the noise was, wait about 3 seconds, look around.
func _do_investigate(dt: float, reachable: bool) -> void:
	if _wants_chase(reachable):
		_start_chase()
		return
	if _look_wait > 0.0:
		_look_wait -= dt
		_turn_towards(facing.rotated(1.2), dt, 1.5)
		if _look_wait <= 0.0:
			state = S.PATROL
			_path = []
			_patrol_i = _nearest_patrol_index()
		return
	if _path.is_empty():
		if pos2.distance_to(_investigate) < 0.9:
			_look_wait = T.DEMON_INVESTIGATE_WAIT
			return
		_path = _path_to(_investigate)
		if _path.is_empty():
			# cannot get there: go as close as possible instead
			var close = main.level.nav.closest_reachable(pos2, _investigate, main.chalk)
			_investigate = close
			if pos2.distance_to(close) < 0.9:
				_look_wait = T.DEMON_INVESTIGATE_WAIT
				return
			_path = _path_to(close)
			if _path.is_empty():
				_look_wait = T.DEMON_INVESTIGATE_WAIT
				return
	var result = _follow(dt, T.DEMON_INVESTIGATE_SPEED)
	if result == 2:
		_look_wait = T.DEMON_INVESTIGATE_WAIT


# CHASE: run at the player. If a circle is in the way, go as close as possible.
func _do_chase(dt: float, pp: Vector2, reachable: bool) -> void:
	if not sees_player:
		_lost += dt
		if _lost > T.DEMON_LOSE_TIME:
			state = S.INVESTIGATE
			_investigate = _last_known
			_path = []
			_look_wait = 0.0
			return
	var target = _last_known
	if sees_player:
		target = pp
	var to_p = pp - pos2
	var dist = to_p.length()

	# close enough to strike
	if reachable and sees_player and dist < T.DEMON_ATTACK_RANGE:
		_turn_towards(to_p, dt, 12.0)
		if _windup > 0.0:
			_windup -= dt
			if _windup <= 0.0:
				_strike(pp)
		elif _attack_cd <= 0.0:
			_windup = T.DEMON_ATTACK_WINDUP
			_attack_anim = 1.0
			main.sfx.play_at("swing", head_position(), -2.0)
		return
	_windup = 0.0

	# the last few metres: walk straight at the player
	if reachable and sees_player and dist < 3.0 and main.level.nav.clear_line(pos2, pp):
		_turn_towards(to_p, dt, 10.0)
		if _step_direct(to_p / dist, T.DEMON_CHASE_SPEED, dt, 0.0):
			_path = []
			return

	# Re-plan the route 4 times a second. When a circle shields the player the
	# goal does not move, so the route is only planned again once it is used up.
	_repath -= dt
	var shielded = sees_player and not reachable
	if _path.is_empty() or (_repath <= 0.0 and not shielded):
		_repath = 0.25
		_path = []
		if reachable or not sees_player:
			_path = _path_to(target)
		if _path.is_empty():
			var close = main.level.nav.closest_reachable(pos2, target, main.chalk)
			if pos2.distance_to(close) < 0.8:
				if sees_player and not reachable:
					_start_blocked()
				else:
					_lost += 1.0
				return
			_path = _path_to(close)
			if _path.is_empty():
				if sees_player and not reachable:
					_start_blocked()
				else:
					_lost += 1.0
				return
	var result = _follow(dt, T.DEMON_CHASE_SPEED)
	if result == 2:
		_repath = 0.0


func _strike(pp: Vector2) -> void:
	var still_close = pos2.distance_to(pp) < T.DEMON_ATTACK_RANGE + 0.5
	if still_close and not main.chalk.is_separated(pos2, pp):
		main.player.take_hit(Vector3(pos2.x, 0.0, pos2.y))
	_attack_cd = T.DEMON_ATTACK_COOLDOWN
	state = S.RECOVER
	_recover = 2.0


# RECOVER: after a strike it stands and roars, which gives you time to run.
func _do_recover(dt: float, pp: Vector2) -> void:
	_turn_towards(pp - pos2, dt, 6.0)
	_recover -= dt
	if _recover <= 0.0:
		_start_chase()


# BLOCKED: it leans on the line, screams and stares at you.
# GDD: "This is the moment the whole game is made for."
func _start_blocked() -> void:
	state = S.BLOCKED
	_blocked_left = T.DEMON_BLOCKED_TIME
	_path = []
	_scream()


func _do_blocked(dt: float, pp: Vector2, reachable: bool) -> void:
	var to_p = pp - pos2
	var dist = to_p.length()
	_turn_towards(to_p, dt, 10.0)
	if reachable:
		# the line is gone, or you stepped out
		if sees_player:
			_start_chase()
		else:
			state = S.PATROL
		return
	if dist > 0.9:
		_step_direct(to_p / dist, 1.6, dt, 0.3)    # press right up to the line
	_blocked_left -= dt
	if _blocked_left <= 0.0:
		# give up for a while and walk away (GDD: "...and leaves")
		_ignore = T.DEMON_IGNORE_TIME
		state = S.PATROL
		_path = []
		_pause = 0.0


# ----------------------------------------------------------------- BANISHING

# Is it standing inside one of your circles while you are outside it?
func _update_trap(dt: float, pp: Vector2) -> void:
	var loop = main.chalk.loop_containing(pos2)
	if loop != null and Geometry2D.is_point_in_polygon(pp, loop["pts"]):
		loop = null     # you are in the same circle: that is not a trap, that is dinner
	if loop == null:
		if _trap_loop != null:
			_trap_loop["trap"] = 0.0
		_trap_loop = null
		_trap_id = -1
		banish_time = 0.0
		if state == S.TRAPPED:
			state = S.PATROL
			_path = []
			_patrol_i = _nearest_patrol_index()
		return
	if loop["id"] != _trap_id:
		if _trap_loop != null:
			_trap_loop["trap"] = 0.0
		_trap_loop = loop
		_trap_id = loop["id"]
		banish_time = 0.0
		_scream()
	state = S.TRAPPED
	banish_time += dt
	loop["trap"] = clampf(banish_time / T.BANISH_TIME, 0.0, 1.0)
	if banish_time >= T.BANISH_TIME:
		_banish()


func _do_trapped(dt: float, pp: Vector2) -> void:
	var to_p = pp - pos2
	var dist = to_p.length()
	_turn_towards(to_p, dt, 8.0)
	if dist > 0.9:
		_step_direct(to_p / dist, 1.4, dt, 0.35)
	if _scream_cd <= 0.0:
		_scream()


# GDD "Izgnanie": the circle held until the timer ran out.
func _banish() -> void:
	var loop = _trap_loop
	_trap_loop = null
	_trap_id = -1
	banish_time = 0.0
	state = S.GONE
	_gone_left = T.BANISH_COOLDOWN
	_dissolve_target = 1.0
	_path = []
	main.on_banished(loop)


# GDD "Respaun": come back in a far place the player cannot see.
func _respawn() -> void:
	var pp = main.player.pos2()
	var points = main.level.patrol_points
	var good = []
	var far_i = 0
	var far_d = -1.0
	for i in range(points.size()):
		var d = points[i].distance_to(pp)
		if d > far_d:
			far_d = d
			far_i = i
		if d >= T.RESPAWN_MIN_DISTANCE and main.chalk.loop_containing(points[i]) == null:
			pos2 = points[i]
			if not _line_of_sight():
				good.append(i)
	var pick = far_i
	if not good.is_empty():
		pick = good[randi() % good.size()]
	pos2 = points[pick]
	_patrol_i = pick
	state = S.PATROL
	_path = []
	_pause = 1.5
	_ignore = 0.0
	_dissolve_target = 0.0
	_apply_transform()
	main.on_demon_returned()


# Used by the ending: it comes apart for good.
func end_dissolve() -> void:
	_dissolve_target = 1.0
	if state != S.GONE:
		_scream()
	state = S.GONE
	_gone_left = 99999.0


# -------------------------------------------------------------- LOOK & SOUND

func _scream() -> void:
	_scream_cd = randf_range(6.0, 9.0)
	_scream_anim = 1.0
	main.sfx.play_at("demon_scream", head_position(), 3.0, randf_range(0.92, 1.08))
	main.on_demon_scream()


func _apply_transform() -> void:
	position = Vector3(pos2.x, 0.0, pos2.y)
	rotation.y = atan2(-facing.x, -facing.y)


# GDD "Vsegda sebya vydayot": heavy steps, slower on patrol, fast in a chase.
func _footsteps(dt: float) -> void:
	if not _moving:
		_step_wait = minf(_step_wait, 0.2)
		return
	_step_wait -= dt
	if _step_wait <= 0.0:
		_step_wait = clampf(1.15 / maxf(_move_speed, 0.5), 0.26, 0.8)
		main.sfx.play_at("demon_step", Vector3(pos2.x, 0.1, pos2.y), 2.0, randf_range(0.85, 1.1))


func _animate(dt: float) -> void:
	# coming apart / coming back
	_dissolve = move_toward(_dissolve, _dissolve_target, dt * 0.7)
	_material.set_shader_parameter("dissolve", _dissolve)
	var shown = _dissolve < 0.98
	_root.visible = shown
	_parts["glow"].visible = _dissolve < 0.3
	_eye_light.visible = _dissolve < 0.3
	if _breath != null:
		_breath.volume_db = -4.0 if _dissolve < 0.5 else -60.0
	if not shown:
		return

	# walking: legs swing, arms swing the other way, the body bobs
	var target_amount = 1.0 if _moving else 0.0
	_walk_amount = lerpf(_walk_amount, target_amount, 1.0 - exp(-8.0 * dt))
	_walk_phase += dt * (3.0 + _move_speed * 1.9) * _walk_amount
	var swing = sin(_walk_phase) * 0.55 * _walk_amount
	_attack_anim = move_toward(_attack_anim, 0.0, dt * 1.6)
	_scream_anim = move_toward(_scream_anim, 0.0, dt * 0.6)
	var tense = 0.0
	if state == S.BLOCKED or state == S.TRAPPED:
		tense = 0.5
	var spread = maxf(_scream_anim, tense)
	var raise = -1.5 * _attack_anim - 0.5 * spread
	_parts["leg_l"].rotation.x = swing
	_parts["leg_r"].rotation.x = -swing
	_parts["arm_l"].rotation.x = -swing * 0.5 + raise
	_parts["arm_r"].rotation.x = swing * 0.5 + raise
	_parts["arm_l"].rotation.z = 0.5 * spread
	_parts["arm_r"].rotation.z = -0.5 * spread
	var shake = spread * 0.02
	var flip = _parts["flip"]
	flip.position = Vector3(randf_range(-shake, shake), absf(sin(_walk_phase)) * 0.05 * _walk_amount, randf_range(-shake, shake))
	flip.rotation.x = 0.12 * spread + 0.25 * _attack_anim
	# the eyes flare when it sees you
	var want = 3.2 if sees_player else 2.0
	_eye_light.light_energy = lerpf(_eye_light.light_energy, want, 1.0 - exp(-6.0 * dt))
