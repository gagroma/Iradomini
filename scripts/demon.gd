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

enum S { PATROL, INVESTIGATE, CHASE, BLOCKED, RECOVER, GONE }
const STATE_NAMES = ["PATROL", "INVESTIGATE", "CHASE", "BLOCKED", "RECOVER", "GONE"]
# Chalk lines are kept outside its whole body: every frame the animation
# measures where its claws, mouth, horns, elbows and feet really are (they
# move a lot - the arms are nearly two metres long), and it stands back from
# a line by as far as its body reaches towards it, plus a little.
const MIN_CLEAR := 0.42
const CLEAR_MARGIN := 0.08
const THRESHOLD_CLEAR := 0.65
# points on the body, each on its joint (model space, relative to the joint)
const BODY_POINTS := {
	"head": [Vector3(0, 0.05, 0.52), Vector3(0.34, 0.71, -0.26), Vector3(-0.34, 0.71, -0.26), Vector3(0, 0.55, 0.3)],
	"hand_l": [Vector3(0, -0.48, 0.16), Vector3(0.1, -0.48, -0.02), Vector3(-0.07, -0.48, 0.1), Vector3.ZERO],
	"hand_r": [Vector3(0, -0.48, 0.16), Vector3(-0.1, -0.48, -0.02), Vector3(0.07, -0.48, 0.1), Vector3.ZERO],
	"fore_l": [Vector3.ZERO],
	"fore_r": [Vector3.ZERO],
	"shin_l": [Vector3(0.03, -0.52, 0.0)],
	"shin_r": [Vector3(-0.03, -0.52, 0.0)],
}
const SCREAM_TIME := 1.8

var main
var state: int = S.PATROL
var pos2 := Vector2.ZERO            # where it stands on the floor (x, z)
var facing := Vector2(0.0, 1.0)     # which way it looks (x, z)
var sees_player := false

var _path := []                     # points still to walk through
var _patrol_i := 0
var _route := []                    # the patrol points that are its own (indices); with several demons each has its own stretch
var _route_dir := 1                 # it walks its stretch to the end and back
var _pause := 0.0
var _look_wait := 0.0
var _repath := 0.0
var _fail_cd := 0.0                 # after a failed route plan, wait this long before planning again
var _blocked_left := 0.0
var _ignore := 0.0                  # while > 0 it has given up on an unreachable player
var _shield_id := -1                # the circle you are hiding in that blocked it (-1 = none)
var _shield_time := -99.0           # when it was last blocked by that circle
var _retreat := 0.0                 # while > 0 it has been beaten by a circle and is leaving: no hunting, no listening
var _lost := 0.0                    # seconds since it last saw the player
var _attack_cd := 0.0
var _windup := 0.0
var _recover := 0.0
var _gone_left := 0.0
var _last_known := Vector2.ZERO
var _investigate := Vector2.ZERO
var _notice_cd := 0.0

var _moving := false
var _move_speed := 0.0
var _walk_phase := 0.0
var _walk_amount := 0.0
var _step_wait := 0.0
var _atk_t := -1.0                 # time into the current attack (-1 = none)
var _atk_kind := 0                  # 0 left claw, 1 right claw, 2 both overhead
var _scream_t := -1.0               # time into the current scream (-1 = none)
var _press := 0.0                   # 0..1 leaning on a chalk line
var _twitch := Vector3.ZERO         # a sudden jerk of the head
var _twitch_target := Vector3.ZERO
var _twitch_wait := 2.0
var _wp_best := 99999.0             # progress towards the current path point
var _body := PackedVector2Array()   # where the body points are, from where it stands (x, z)
var _reach := 1.0                   # the furthest of them
var _wp_stuck := 0.0
var _dissolve := 0.0
var _dissolve_target := 0.0
var _dissolve_speed := 0.7
var scripted_move := 0.0
var _time := 0.0

var _root: Node3D
var _parts := {}
var _material: ShaderMaterial
var _eye_light: SpotLight3D
var _breath = null


func setup(main_node, index := 0, count := 1) -> void:
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
	_eye_light.position = Vector3(0.0, 0.25, 0.45)      # at the eyes, on the head joint
	_eye_light.rotation = Vector3(-0.22, PI, 0.0)       # looking where the face looks
	_eye_light.light_color = Color(1.0, 0.3, 0.1)
	_eye_light.light_energy = 2.2
	_eye_light.spot_range = T.DEMON_VISION_RANGE
	_eye_light.spot_angle = T.DEMON_VISION_HALF_ANGLE
	_parts["head"].add_child(_eye_light)

	_breath = main.sfx.loop_at("demon_breath", self, -4.0)
	pos2 = main.level.demon_start
	# With several demons each keeps to its own stretch of the patrol route, so they cover different
	# parts of the church instead of walking the same path one behind the other.
	var points = main.level.patrol_points
	var n: int = points.size()
	var base := _nearest_patrol_index()
	if count > 1 and n >= count * 2:
		for k in range(int(n * index / float(count)), int(n * (index + 1) / float(count))):
			_route.append((base + k) % n)
	else:
		for k in n:
			_route.append((base + k + int(n * index / float(count))) % n)
	if not _route.is_empty():
		_patrol_i = _route[0]
	if index > 0 and n > 0:
		pos2 = points[_patrol_i]
	_apply_transform()


# Test helper (tuning.gd DEMON_ENABLED = false): the demon leaves for good,
# so the level can be looked at in peace.
func switch_off() -> void:
	state = S.GONE
	visible = false
	if _breath != null:
		_breath.stop()
	set_physics_process(false)


func is_active() -> bool:
	return state != S.GONE


func state_name() -> String:
	return STATE_NAMES[state]


func head_position() -> Vector3:
	return Vector3(pos2.x, 2.05, pos2.y)


func distance_to_player() -> float:
	return pos2.distance_to(main.player.pos2())


# ONLY ONE HUNTS. With several demons in a level, one of them at a time is after you (main.hunter):
# the one that heard or saw you. The others keep to their own patrol. Another takes the hunt over
# only if it sees you and is clearly closer, and then the first one lets go (call_off).
func is_hunting() -> bool:
	return state == S.INVESTIGATE or state == S.CHASE or state == S.BLOCKED or state == S.RECOVER


# Pressing on a circle or roaring after a strike: it is busy with you and deaf to noises.
func is_busy() -> bool:
	return state == S.BLOCKED or state == S.RECOVER


func can_hear(at: Vector2, radius: float) -> bool:
	return state != S.GONE and not is_busy() and _retreat <= 0.0 and pos2.distance_to(at) <= radius


# Another demon has taken up the hunt: this one walks back to its own route.
func call_off() -> void:
	if state == S.GONE:
		return
	state = S.PATROL
	_path = []
	_windup = 0.0
	_look_wait = 0.0
	_pause = 0.5
	_patrol_i = _nearest_patrol_index()


# You shut yourself in a wardrobe while it was after you: it cannot see or reach you in there.
# It comes to the doors, stands a while, and goes.
func lose_player_at(at: Vector2) -> void:
	_last_known = at
	_windup = 0.0
	if state == S.CHASE or state == S.INVESTIGATE:
		state = S.INVESTIGATE
		_investigate = at
		_path = []
		_look_wait = 0.0


# ------------------------------------------------------------------ HEARING

# Called for every noise: a footstep, the door, a falling candlestick.
# Returns true if it heard it.
func hear(at: Vector2, radius: float) -> bool:
	if state == S.GONE or state == S.RECOVER or state == S.BLOCKED:
		return false
	if _retreat > 0.0:      # leaving after a circle beat it: it does not come back for noises
		return false
	if pos2.distance_to(at) > radius:
		return false
	_last_known = at
	if state == S.CHASE:
		_lost = 0.0
		return true
	main.claim_hunt(self)
	state = S.INVESTIGATE
	_investigate = at
	_path = []
	_look_wait = 0.0
	if _notice_cd <= 0.0:
		_notice_cd = 4.0
		main.sfx.play_at("demon_notice", head_position(), -4.0)
	return true


# For the stealth eye: 0 = no idea where you are, 1 = heard something,
# 2 = sees you / hunting you.
func awareness() -> int:
	if state == S.CHASE or sees_player:
		return 2
	if state == S.INVESTIGATE:
		return 1
	return 0


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
	if p.in_wardrobe:               # shut in a wardrobe: it cannot see you at all
		return
	if main.demon_grace > 0.0:      # the first seconds of a level: it does not notice you yet
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
	# its body is kept off chalk lines, so a path point right by a line may be
	# out of reach: when it stops getting closer, take the point as reached
	if d < _wp_best - 0.02:
		_wp_best = d
		_wp_stuck = 0.0
	else:
		_wp_stuck += dt
	if _wp_stuck > 0.65:
		_wp_best = 99999.0
		_wp_stuck = 0.0
		_path.clear()
		return 2
	if d <= step_len:
		_wp_best = 99999.0
		_wp_stuck = 0.0
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


# Push the body back from any chalk line that is inside its reach: further
# in front (the head and claws), less to the sides. Only ever away from the
# line, so it can never be pushed across one.
func _keep_off_chalk() -> void:
	for i in range(3):
		var line: Dictionary = main.chalk.closest_line(pos2, _reach + CLEAR_MARGIN, THRESHOLD_CLEAR)
		if line.is_empty():
			return
		var v: Vector2 = line["point"] - pos2
		var d = v.length()
		if d < 0.001:
			return
		var to_line = v / d
		# how far the body sticks out towards that line right now
		# The spawn threshold sits next to other passages. Keep the demon back without pushing it across them.
		var need := THRESHOLD_CLEAR if line["permanent"] else MIN_CLEAR
		if not line["permanent"]:
			for b in _body:
				need = maxf(need, b.dot(to_line) + CLEAR_MARGIN)
		if d >= need:
			return
		var push = pos2 - to_line * (need - d)
		if not main.level.nav.is_free(push) or main.chalk.segment_blocked(pos2, push):
			return
		pos2 = push


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
	_wp_best = INF
	_wp_stuck = 0.0
	return main.level.nav.find_path(pos2, target, main.chalk)


# The nearest point of its own stretch of the patrol route.
func _nearest_patrol_index() -> int:
	var best = 0
	var best_d = 99999.0
	var points = main.level.patrol_points
	var own: Array = _route if not _route.is_empty() else range(points.size())
	for i in own:
		var d = pos2.distance_to(points[i])
		if d < best_d:
			best_d = d
			best = i
	return best


# The next point of its own stretch. A demon alone walks the whole route round and round; one of
# several walks its stretch to the end and back.
func _advance_patrol() -> void:
	var k := _route.find(_patrol_i)
	if k == -1:                      # it was drawn off its stretch: back to the nearest point of it
		_patrol_i = _nearest_patrol_index()
		return
	if _route.size() == main.level.patrol_points.size():
		_patrol_i = _route[(k + 1) % _route.size()]
		return
	if k + _route_dir < 0 or k + _route_dir >= _route.size():
		_route_dir = -_route_dir
	_patrol_i = _route[clampi(k + _route_dir, 0, _route.size() - 1)]


# ------------------------------------------------------------------- STATES

func _physics_process(dt: float) -> void:
	_time += dt
	_moving = scripted_move > 0.0
	if _moving:
		_move_speed = scripted_move
	_notice_cd = maxf(0.0, _notice_cd - dt)
	_attack_cd = maxf(0.0, _attack_cd - dt)
	_ignore = maxf(0.0, _ignore - dt)
	_retreat = maxf(0.0, _retreat - dt)

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
	if reachable and _retreat <= 0.0:
		_ignore = 0.0
	_update_trap(pp)

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

	_keep_off_chalk()
	_apply_transform()
	_animate(dt)
	_footsteps(dt)


func _wants_chase(reachable: bool) -> bool:
	if not sees_player:
		return false
	if _retreat > 0.0:
		# it has given up on you: only walking right into it starts a chase again
		return reachable and distance_to_player() < T.DEMON_RETREAT_NOTICE
	if not (reachable or _ignore <= 0.0):
		return false
	# a circle has just beaten another demon: this one does not come to try the same circle
	if not reachable and main.circle_calm > 0.0:
		return false
	# only one hunts at a time: leave you to the one already chasing, unless this one is clearly closer
	var h = main.hunting_demon()
	if h != null and h != self and h.state != S.INVESTIGATE:
		if distance_to_player() + T.DEMON_TAKEOVER_MARGIN >= h.distance_to_player():
			return false
	return true


func _start_chase() -> void:
	main.claim_hunt(self)
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
			if _retreat > 0.0 and not _route.has(_patrol_i):
				_pause = 1.0             # beaten by a circle: it waits it out at the far point it went to
				return
			_advance_patrol()
			# leaving after a circle beat it: skip the patrol points near you
			if _retreat > 0.0:
				var pp: Vector2 = main.player.pos2()
				for k in points.size():
					if points[_patrol_i].distance_to(pp) >= T.DEMON_RETREAT_DISTANCE:
						break
					_advance_patrol()
			_pause = 0.6
			return
		_path = _path_to(target)
		if _path.is_empty():
			_advance_patrol()
			_pause = 0.3
			return
	var result = _follow(dt, T.DEMON_PATROL_SPEED)
	if result == 2:
		_advance_patrol()
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

	# it sees you but a circle is between you, and it has walked into the line
	if sees_player and not reachable and not main.chalk.closest_line(pos2, _reach + 0.3).is_empty():
		_start_blocked()
		return
	# you are standing in a closed circle close by: no hunting round it for a way in, it goes
	# straight to the line, presses on it and screams (BLOCKED walks it up to the line)
	if sees_player and not reachable and dist < T.DEMON_SHIELD_RANGE and main.chalk.loop_containing(pp) != null:
		_start_blocked()
		return

	if _windup > 0.0:
		_turn_towards(to_p, dt, 12.0)
		main.player.pin(0.1)
		_windup -= dt
		if _windup <= 0.0:
			_strike(pp)
		return

	# close enough to strike
	if reachable and sees_player and dist < T.DEMON_ATTACK_RANGE:
		_turn_towards(to_p, dt, 12.0)
		if _attack_cd <= 0.0:
			_windup = T.DEMON_ATTACK_WINDUP
			_atk_t = 0.0
			_atk_kind = randi() % 3
			main.player.pin(0.1)
			main.sfx.play_at("swing", head_position(), -2.0)
			main.player.shake(0.25)
		return

	# the last few metres: walk straight at the player
	if reachable and sees_player and dist < 3.0 and main.level.nav.clear_line(pos2, pp):
		_turn_towards(to_p, dt, 10.0)
		if _step_direct(to_p / dist, T.DEMON_CHASE_SPEED, dt, 0.0):
			_path = []
			return

	# Re-plan the route 4 times a second. When a circle shields the player the
	# goal does not move, so the route is only planned again once it is used up.
	_repath -= dt
	_fail_cd -= dt
	var shielded = sees_player and not reachable
	if _path.is_empty() and _fail_cd > 0.0:
		# no route right now (you are pressed against a line or a prop): stare, plan again soon
		_turn_towards(to_p, dt, 8.0)
		return
	if _path.is_empty() or (_repath <= 0.0 and not shielded):
		_repath = 0.25
		_path = []
		if reachable or not sees_player:
			_path = _path_to(target)
		if _path.is_empty():
			var close = main.level.nav.closest_reachable(pos2, target, main.chalk)
			# as close as its body lets it get: it has come up against the line
			if pos2.distance_to(close) < maxf(0.8, _reach + 0.4):
				if sees_player and not reachable:
					_start_blocked()
				else:
					_lost += 1.0
					_fail_cd = 0.5
				return
			_path = _path_to(close)
			if _path.is_empty():
				if sees_player and not reachable:
					_start_blocked()
				else:
					_lost += 1.0
					_fail_cd = 0.5
				return
	var result = _follow(dt, T.DEMON_CHASE_SPEED)
	if result == 2:
		_repath = 0.0


func _strike(pp: Vector2) -> void:
	if not main.player.in_wardrobe and not main.chalk.is_separated(pos2, pp):
		main.player.take_hit(Vector3(pos2.x, 0.0, pos2.y))
	_attack_cd = T.DEMON_ATTACK_COOLDOWN
	state = S.RECOVER
	_recover = 2.0


# RECOVER: after a strike it stands and roars, which gives you time to run.
func _do_recover(dt: float, pp: Vector2) -> void:
	_turn_towards(pp - pos2, dt, 6.0)
	if not main.player.alive:
		return
	_recover -= dt
	if _recover <= 0.0:
		_start_chase()


# BLOCKED: it leans on the line, screams and stares at you.
# GDD: "This is the moment the whole game is made for."
func _start_blocked() -> void:
	state = S.BLOCKED
	_path = []
	# blocked again by the same circle soon after: carry on the same count, so going round the
	# circle and coming back does not start it over (it gives up after DEMON_BLOCKED_TIME in total)
	var loop = main.chalk.loop_containing(main.player.pos2())
	var id: int = loop["id"] if loop != null else -1
	if id != _shield_id or _time - _shield_time > 6.0:
		_blocked_left = T.DEMON_BLOCKED_TIME
		_scream()
	_shield_id = id
	_shield_time = _time


# True while you are still inside the circle that blocked it. Its own position sits right on the
# line, so "are we on different sides" flickers; asking where YOU are does not.
func _still_shielded(pp: Vector2) -> bool:
	if _shield_id < 0:
		return false
	for loop in main.chalk.loops:
		if loop["id"] == _shield_id:
			return Geometry2D.is_point_in_polygon(pp, loop["pts"])
	return false


func _do_blocked(dt: float, pp: Vector2, reachable: bool) -> void:
	var to_p = pp - pos2
	var dist = to_p.length()
	_turn_towards(to_p, dt, 10.0)
	_shield_time = _time
	if reachable and not _still_shielded(pp):
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
		# give up and really leave (GDD: "...and leaves"): walk off to the far side of the level and
		# do not hunt or listen for you for a while, even once you step out of the circle
		_ignore = T.DEMON_GIVE_UP_TIME
		_retreat = T.DEMON_GIVE_UP_TIME
		main.circle_calm = T.DEMON_GIVE_UP_TIME
		state = S.PATROL
		_patrol_i = _far_patrol_index(pp)
		_path = []
		_pause = 0.0


# The patrol point furthest from the player that it can actually walk to.
func _far_patrol_index(pp: Vector2) -> int:
	var points = main.level.patrol_points
	var order := range(points.size())
	order.sort_custom(func(a, b): return points[a].distance_to(pp) > points[b].distance_to(pp))
	for i in order.slice(0, 6):
		if not main.level.nav.find_path(pos2, points[i], main.chalk).is_empty():
			return i
	return order[0] if not order.is_empty() else 0


# ----------------------------------------------------------------- BANISHING

# Is it standing inside one of your circles while you are outside it?
# Then the circle has caught it: it is banished at once.
func _update_trap(pp: Vector2) -> void:
	var loop = main.chalk.loop_containing(pos2)
	if loop == null or Geometry2D.is_point_in_polygon(pp, loop["pts"]):
		return     # (you are in the same circle: that is not a trap, that is dinner)
	_banish(loop)


# The circle closed round it: it comes apart and is gone for a while. The
# circle stays on the floor; rub it out yourself to get its chalk back.
func _banish(loop: Dictionary) -> void:
	_scream()
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
	_retreat = 0.0
	_dissolve_target = 0.0
	_apply_transform()
	main.on_demon_returned()


func fade_away() -> void:
	state = S.GONE
	_gone_left = 99999.0
	_dissolve_target = 1.0
	_dissolve_speed = 1.2


func appear_at(at: Vector2, look: Vector2) -> void:
	visible = true
	set_physics_process(true)
	state = S.GONE
	_gone_left = 99999.0
	pos2 = at
	facing = look.normalized()
	_dissolve = 0.0
	_dissolve_target = 0.0
	_dissolve_speed = 0.7
	_atk_t = -1.0
	_apply_transform()


func run_towards(target: Vector2, speed: float, dt: float) -> float:
	var to = target - pos2
	var d = to.length()
	if d < 0.01:
		scripted_move = 0.0
		return 0.0
	_turn_towards(to, dt, 14.0)
	var step = minf(speed * dt, d)
	pos2 += to / d * step
	scripted_move = speed
	_apply_transform()
	_footsteps(dt)
	return d - step


func face(dir: Vector2, dt: float) -> void:
	_turn_towards(dir, dt, 14.0)
	_apply_transform()


func scream_now() -> void:
	_scream()


func raise_claws() -> void:
	scripted_move = 0.0
	_atk_t = 0.0
	_atk_kind = 2
	main.sfx.play_at("swing", head_position(), 0.0)


func vanish() -> void:
	scripted_move = 0.0
	_dissolve_target = 1.0
	_dissolve_speed = 5.0
	state = S.GONE
	_gone_left = 99999.0


# -------------------------------------------------------------- LOOK & SOUND

func _scream() -> void:
	_scream_t = 0.0
	main.sfx.play_at("demon_scream", head_position(), 3.0, randf_range(0.92, 1.08))
	main.on_demon_scream(distance_to_player())


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
		# heavy enough to feel when it runs at you
		var near = 1.0 - distance_to_player() / 7.0
		if near > 0.0 and state == S.CHASE:
			main.player.shake(0.12 * near)


# ----------------------------------------------------------------- ANIMATION
# All by hand, in code: every frame each joint gets a target angle made of
# layers (breathing, walking or running, looking at you, leaning on a line,
# attacking, screaming, twitching), and turns towards it.
# Angles are in the model's own space (it faces +Z): turning a limb about X
# by a negative angle swings it forward; a positive one swings it back.

func _animate(dt: float) -> void:
	# coming apart / coming back
	_dissolve = move_toward(_dissolve, _dissolve_target, dt * _dissolve_speed)
	_material.set_shader_parameter("dissolve", _dissolve)
	var shown = _dissolve < 0.98
	_root.visible = shown
	_parts["glow"].visible = _dissolve < 0.3
	_eye_light.visible = _dissolve < 0.3
	if _breath != null:
		_breath.volume_db = -4.0 if _dissolve < 0.5 else -60.0
	if not shown:
		return

	var t = _time
	# --- how it moves ---
	_walk_amount = lerpf(_walk_amount, 1.0 if _moving else 0.0, 1.0 - exp(-8.0 * dt))
	var run = clampf((_move_speed - 1.8) / 2.5, 0.0, 1.0) * _walk_amount
	_walk_phase += dt * (2.6 + _move_speed * 1.7) * _walk_amount
	var ph = _walk_phase
	var stride = (0.38 + 0.25 * run) * _walk_amount
	var walk = _walk_amount
	var aware = awareness()

	# --- what it is doing ---
	var pressing = state == S.BLOCKED
	_press = move_toward(_press, 1.0 if pressing else 0.0, dt * 3.0)
	var roar = 1.0 if state == S.RECOVER else 0.0
	if _atk_t >= 0.0:
		_atk_t += dt
		if _atk_t > T.DEMON_ATTACK_WINDUP + 0.9:
			_atk_t = -1.0
	if _scream_t >= 0.0:
		_scream_t += dt
		if _scream_t > SCREAM_TIME:
			_scream_t = -1.0

	# sudden jerks of the head - more often when it knows you are there
	_twitch_wait -= dt
	if _twitch_wait <= 0.0:
		_twitch_wait = randf_range(0.6, 1.8) if aware > 0 else randf_range(1.5, 4.0)
		_twitch_target = Vector3(randf_range(-0.3, 0.3), randf_range(-0.45, 0.45), randf_range(-0.5, 0.5))
	_twitch = _twitch.lerp(_twitch_target, 1.0 - exp(-28.0 * dt))
	_twitch_target = _twitch_target.lerp(Vector3.ZERO, 1.0 - exp(-4.0 * dt))

	var breathe = sin(t * (1.6 + 3.0 * roar))
	var r = {}
	# --- breathing, walking, running ---
	r["hips"] = Vector3(0.0, sin(ph) * 0.1 * walk, sin(ph) * 0.07 * walk)
	r["spine"] = Vector3(0.06 + 0.32 * run + breathe * (0.03 + 0.05 * roar), -sin(ph) * 0.12 * walk, 0.0)
	for side in [0, 1]:
		var s_ = "_l" if side == 0 else "_r"
		var p = ph + PI * side
		var out = -1.0 if side == 0 else 1.0
		r["leg" + s_] = Vector3(-stride * sin(p) - 0.25 * run, 0.0, 0.0)
		r["shin" + s_] = Vector3(0.9 * maxf(0.0, cos(p)) * walk + 0.45 * run, 0.0, 0.0)
		# arms hang and swing against the legs; running, they reach out, claws first
		r["arm" + s_] = Vector3(stride * 0.7 * sin(p) - 0.5 * run, 0.0, out * 0.05)
		r["fore" + s_] = Vector3(-0.15 + 0.25 * sin(p - 0.7) * walk - 0.5 * run, 0.0, 0.0)
		r["hand" + s_] = Vector3(0.12 * sin(p - 1.2) * walk + 0.05 * sin(t * 3.0 + side), 0.0, 0.0)
	# --- the head keeps level, looks at you when it knows where you are ---
	var look = Vector2.ZERO
	if aware > 0 or pressing:
		look = _look_at_player()
	elif state == S.INVESTIGATE and _look_wait > 0.0:
		look = Vector2(sin(t * 1.3) * 0.8, 0.1)
	r["head"] = Vector3(-0.5 * r["spine"].x + look.y + 0.05 * sin(ph * 2.0) * walk, look.x, 0.0)

	# --- leaning on a chalk line: palms on the air, claws scraping at it ---
	if _press > 0.0:
		var k = _press
		r["spine"].x += 0.3 * k
		r["head"].x += 0.15 * k
		for side in [0, 1]:
			var s_ = "_l" if side == 0 else "_r"
			var inward = 1.0 if side == 0 else -1.0
			var scrape = sin(t * 7.0 + PI * side)
			# elbows up and out, forearms raised, claws spread flat on the air and dragging down it
			r["arm" + s_] = r["arm" + s_].lerp(Vector3(-1.25 + 0.1 * scrape, 0.0, -inward * 0.35), k)
			r["fore" + s_] = r["fore" + s_].lerp(Vector3(-1.2 + 0.25 * scrape, 0.0, inward * 0.2), k)
			r["hand" + s_] = r["hand" + s_].lerp(Vector3(-0.5 + 0.35 * scrape, 0.0, 0.0), k)

	# --- after a strike: it straightens up and roars ---
	if roar > 0.0:
		r["head"].x -= 0.45
		r["spine"].x -= 0.1

	# --- attack: rear back with the claw high, then slash down and lunge ---
	var fast = false
	if _atk_t >= 0.0:
		var w = T.DEMON_ATTACK_WINDUP
		var raise = smoothstep(0.0, w, _atk_t)
		var strike = smoothstep(w, w + 0.1, _atk_t)
		var settle = smoothstep(w + 0.35, w + 0.9, _atk_t)
		var up = raise * (1.0 - strike)
		var down = strike * (1.0 - settle)
		fast = _atk_t > w - 0.05 and _atk_t < w + 0.2
		var twist = 0.0 if _atk_kind == 2 else (0.45 if _atk_kind == 0 else -0.45)
		r["spine"] += Vector3(-0.3 * up + 0.5 * down, twist * (up - down), 0.0)
		r["head"].x += -0.3 * up + 0.3 * down
		for side in [0, 1]:
			if _atk_kind != 2 and _atk_kind != side:
				continue
			var s_ = "_l" if side == 0 else "_r"
			var out = -1.0 if side == 0 else 1.0
			var arm_t = Vector3(lerpf(-2.7, 0.35, strike), 0.0, out * 0.3 * up)
			r["arm" + s_] = r["arm" + s_].lerp(arm_t, maxf(up, down))
			r["fore" + s_] = r["fore" + s_].lerp(Vector3(-1.1 * up, 0.0, 0.0), maxf(up, down))
			r["hand" + s_] = r["hand" + s_].lerp(Vector3(0.4 * up - 0.5 * down, 0.0, 0.0), maxf(up, down))

	# --- scream: head thrown back, then thrust at you; arms flung wide; it shudders ---
	var mouth = 1.0
	if _scream_t >= 0.0:
		var st = _scream_t
		var w = smoothstep(0.0, 0.25, st) * (1.0 - smoothstep(SCREAM_TIME - 0.5, SCREAM_TIME, st))
		var rear = 1.0 - smoothstep(0.2, 0.5, st)
		var jit = w * 0.07
		r["spine"].x += w * (-0.35 * rear + 0.25 * (1.0 - rear)) + randf_range(-jit, jit)
		r["head"] += Vector3(w * (-0.7 * rear + 0.45 * (1.0 - rear)), 0.0, 0.0) + Vector3(randf_range(-jit, jit), randf_range(-jit, jit), randf_range(-jit, jit)) * 2.0
		for side in [0, 1]:
			var s_ = "_l" if side == 0 else "_r"
			var out = -1.0 if side == 0 else 1.0
			r["arm" + s_] = r["arm" + s_].lerp(Vector3(-1.0 + randf_range(-jit, jit) * 3.0, 0.0, out * 1.1), w)
			r["fore" + s_] = r["fore" + s_].lerp(Vector3(-0.6, 0.0, 0.0), w)
			r["hand" + s_] = r["hand" + s_].lerp(Vector3(-0.5 + randf_range(-jit, jit) * 4.0, 0.0, 0.0), w)
		mouth = 1.0 + 0.8 * w
	r["head"] += _twitch * (0.6 if _scream_t >= 0.0 else 1.0)

	# --- turn every joint towards its target ---
	var rate = 40.0 if fast else 14.0
	var k_rate = 1.0 - exp(-rate * dt)
	for key in r.keys():
		var part: Node3D = _parts[key]
		part.rotation = part.rotation.lerp(r[key], k_rate)
	_parts["glow"].scale = Vector3(1.0, mouth, 1.0)
	var flip = _parts["flip"]
	var shudder = 0.02 * maxf(_press * 0.5, 1.0 if _scream_t >= 0.0 else 0.0)
	flip.position = Vector3(randf_range(-shudder, shudder), -absf(sin(ph)) * 0.05 * walk - 0.12 * run, randf_range(-shudder, shudder))
	# the eyes flare when it sees you
	var want = 3.2 if sees_player else 2.0
	_eye_light.light_energy = lerpf(_eye_light.light_energy, want, 1.0 - exp(-6.0 * dt))
	_measure_body()


# Where the body really is in this pose, for keeping it off chalk lines.
func _measure_body() -> void:
	_body = PackedVector2Array()
	_reach = MIN_CLEAR
	var here = Vector3(pos2.x, 0.0, pos2.y)
	for key in BODY_POINTS.keys():
		var part: Node3D = _parts[key]
		var xf = part.global_transform
		for p in BODY_POINTS[key]:
			var w = xf * p - here
			var flat = Vector2(w.x, w.z)
			_body.append(flat)
			_reach = maxf(_reach, flat.length())


# Where the player's head is, as (turn, nod) for the head joint, limited to
# what a neck can do.
func _look_at_player() -> Vector2:
	var spine: Node3D = _parts["spine"]
	var head: Node3D = _parts["head"]
	var target = main.player.cam.global_position
	var local = spine.global_transform.basis.inverse() * (target - head.global_position)
	var turn = atan2(local.x, local.z)
	var nod = atan2(-local.y, Vector2(local.x, local.z).length())
	return Vector2(clampf(turn, -0.9, 0.9), clampf(nod, -0.6, 0.6))
