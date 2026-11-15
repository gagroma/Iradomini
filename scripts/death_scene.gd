extends Node3D

const Models = preload("res://scripts/models.gd")
const DeathText = preload("res://scripts/death_text.gd")
const UIStyle = preload("res://scripts/ui_style.gd")
const SkipHint = preload("res://scripts/skip_hint.gd")
const BODY = preload("res://assets/models/player_body.glb")

const DISH_R := 0.0575
const TILT := 0.27
const IMPACT := 2.3
const BLACK_AT := 2.75
const FADE_OUT := 0.4
const BLACK_HOLD := 0.5
const FADE_IN := 0.8
const PEW_IMPACT := 0.8
const PEW_BLACK_AT := 2.3
const ORBIT_TIME := 14.0
const BODY_LAYER := 1 << 17
const CAM_RADIUS := 0.25
const EYE := Vector3(0.0, 1.705, -0.07)

var main
var body: Node3D
var cam: Camera3D
var candle
var _skel: Skeleton3D
var _head := -1
var _eye_rel := Transform3D.IDENTITY
var _mesh: MeshInstance3D
var _fwd := Vector3.FORWARD
var _side := Vector3.RIGHT
var _origin := Vector3.ZERO
var _t := 0.0
var _away := Vector3.RIGHT
var _env_from := []
var _rim: OmniLight3D
var _key: OmniLight3D
var _text
var _black: ColorRect
var _dark := false
var _pew := false
var _impact := IMPACT
var _black_at := BLACK_AT
var _focus := Vector3.ZERO
var _retry: Button
var _retry_box: Control
var _dim := 0.0
var _retry_wait := 0.0       # the button only takes a press this long after it has fully appeared
var _hint: Node
var _start_cam: Transform3D
var _trauma := 0.0
var _thud := false
var _noise := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()

var _c_vel := Vector3.ZERO
var _c_spin := Vector3.ZERO
var _c_state := 0
var _c_land_basis := Basis.IDENTITY
var _c_land_t := 0.0
var _c_yaw := 0.0
var _c_roll := 0.0
var _c_speed := 0.0
var _c_turn := 0.0
var _c_pos := Vector3.ZERO


func start(main_node) -> void:
	main = main_node
	_rng.randomize()
	var player = main.player
	_origin = Vector3(player.global_position.x, 0.0, player.global_position.z)
	var want = -player.global_transform.basis.z
	want.y = 0.0
	want = want.normalized()
	var to_demon = main.nearest_demon().global_position - _origin
	to_demon.y = 0.0
	if to_demon.length() < 3.0 and to_demon.length() > 0.01:
		to_demon = to_demon.normalized()
		var ang = want.signed_angle_to(to_demon, Vector3.UP)
		if absf(ang) < 1.2:
			want = to_demon.rotated(Vector3.UP, -1.2 if ang >= 0.0 else 1.2)
	var pew = null
	if "pew_backs" in main.level:
		for b in main.level.pew_backs:
			if absf(_origin.x - b["x"]) < b["half"] and _origin.z > b["back_z"] - 0.05 and _origin.z < b["back_z"] + 0.75:
				pew = b
	if pew != null:
		_pew = true
		_impact = PEW_IMPACT
		_black_at = PEW_BLACK_AT
		_fwd = Vector3(0, 0, -1)
	else:
		_fwd = _clear_direction(want)
	_side = Vector3.UP.cross(_fwd).normalized()

	body = Models._glb(BODY)
	add_child(body)
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		mi.layers = 1 | BODY_LAYER
	body.global_position = _origin
	body.global_basis = Basis.looking_at(_fwd, Vector3.UP)
	_skel = body.find_children("*", "Skeleton3D", true, false)[0]
	_head = _skel.find_bone("head")
	_mesh = body.find_children("*", "MeshInstance3D", true, false)[0]
	var eye_skel = (_skel.global_transform.affine_inverse() * body.global_transform) * Transform3D(Basis.IDENTITY, EYE)
	_eye_rel = _skel.get_bone_global_rest(_head).affine_inverse() * eye_skel
	var anim = body.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	if _pew:
		anim.play("die_pew")
		anim.seek(anim.current_animation_length, true)
		var hips = _skel.global_transform * _skel.get_bone_global_pose(_skel.find_bone("hips")).origin
		body.global_position.z += pew["rail_z"] + 0.07 - hips.z
		hips.z = pew["rail_z"] + 0.07
		_focus = Vector3(hips.x, 0.35, hips.z - 0.15)
		anim.stop()
		anim.play("die_pew")
		anim.seek(0.0, true)
	else:
		anim.play("die")
		_focus = _origin + _fwd * 0.8 + _side * 0.2

	_start_cam = player.cam.global_transform
	cam = Camera3D.new()
	cam.fov = player.cam.fov
	cam.near = 0.07
	cam.far = 90.0
	add_child(cam)
	cam.global_transform = _start_cam
	cam.current = true

	candle = player.candle
	if is_instance_valid(player.left_hand):
		player.left_hand.queue_free()
	candle.reparent(self, true)
	candle.held = false
	candle.burns = false
	candle.relight()
	_c_pos = candle.global_position
	var land = _origin + _fwd * 1.05 + _side * 0.5
	if _pew:
		land = _origin + _side * 0.5 + Vector3(0, 0, 0.1)
	var vy = 1.0
	var fall_t = (vy + sqrt(vy * vy + 2.0 * 9.8 * maxf(_c_pos.y - 0.02, 0.1))) / 9.8
	_c_vel = (land - _c_pos) / fall_t
	_c_vel.y = vy
	_c_spin = Vector3(_rng.randf_range(-6, 6), _rng.randf_range(-3, 3), _rng.randf_range(-6, 6))
	player.hands.visible = false
	player.critical = false
	main.hud.visible = false

	var layer = CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_black = ColorRect.new()
	_black.color = Color(0, 0, 0, 0)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_black)
	_text = DeathText.new()
	layer.add_child(_text)
	_hint = SkipHint.attach(self, main)
	if _hint != null:
		_hint.skipped.connect(_skip)
	_retry_box = Control.new()
	_retry_box.position = Vector2(146, 190)
	_retry_box.size = Vector2(188, 54)
	_retry_box.modulate.a = 0.0
	layer.add_child(_retry_box)
	_retry_box.add_child(UIStyle.panel(Vector2.ZERO, _retry_box.size))
	_retry = UIStyle.action_button("Try Again", Rect2(19, 14, 150, 26), 17)
	_retry.disabled = true
	_retry.pressed.connect(func(): main._restart())
	_retry_box.add_child(_retry)


func _clear_direction(want: Vector3) -> Vector3:
	var space = get_world_3d().direct_space_state
	var best = want
	var best_len = -1.0
	for a in [0.0, 0.6, -0.6, 1.2, -1.2, 1.9, -1.9, PI]:
		var d = want.rotated(Vector3.UP, a)
		var q = PhysicsRayQueryParameters3D.create(_origin + Vector3(0, 0.3, 0), _origin + Vector3(0, 0.3, 0) + d * 2.0, 1)
		var hit = space.intersect_ray(q)
		var free = 2.0 if hit.is_empty() else _origin.distance_to(hit.position)
		if free >= 1.9:
			return d
		if free > best_len:
			best_len = free
			best = d
	return best


func _cast_fraction(from: Vector3, to: Vector3) -> float:
	var shape = SphereShape3D.new()
	shape.radius = CAM_RADIUS
	var q = PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, from)
	q.motion = to - from
	q.collision_mask = 1
	var res = get_world_3d().direct_space_state.cast_motion(q)
	if res.is_empty():
		return 1.0
	if res[1] <= 0.0:
		var ray = PhysicsRayQueryParameters3D.create(from, to, 1)
		var hit = get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty():
			return 1.0
		return maxf(0.0, (from.distance_to(hit.position) - CAM_RADIUS) / maxf(from.distance_to(to), 0.001))
	return res[0]


func _safe(from: Vector3, to: Vector3) -> Vector3:
	return from + (to - from) * _cast_fraction(from, to)


func _process(dt: float) -> void:
	_t += dt
	_update_candle(dt)
	if not _pew:
		_mesh.set_blend_shape_value(0, smoothstep(2.0, 2.5, _t))
	if not _thud and _t >= _impact:
		_thud = true
		_trauma = 0.85
		main.sfx.play("hit", -2.0, 0.55)
		_away = _away_from_demon()
		_add_lights()
	_trauma = maxf(0.0, _trauma - dt * 1.6)
	var reveal = _black_at + FADE_OUT + BLACK_HOLD
	var out = smoothstep(_black_at, _black_at + FADE_OUT, _t)
	var back = smoothstep(reveal, reveal + FADE_IN, _t)
	_black.color.a = maxf(out * (1.0 - back), _dim)
	if _t < _black_at + FADE_OUT:
		cam.global_transform = _eye_camera()
	else:
		if not _dark:
			_dark = true
			_darken(1.0)
			cam.fov = 55.0
			cam.near = 0.05
		var u = clampf((_t - (_black_at + FADE_OUT)) / ORBIT_TIME, 0.0, 1.0)
		cam.global_transform = _orbit(1.0 - pow(1.0 - u, 1.6))
	if _t >= reveal + 0.25 and not _text.writing:
		_text.begin()
	if _text.done():
		if _hint != null:
			_hint.queue_free()
			_hint = null
		_dim = move_toward(_dim, 0.93, dt / 1.6)
		if _dim > 0.55:
			_retry_box.modulate.a = move_toward(_retry_box.modulate.a, 1.0, dt / 0.6)
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			# Someone mashing Enter to skip would otherwise press "Try Again" the instant it gets focus,
			# and the level restarts before the death screen is ever seen. So it waits until it is fully
			# shown, plus a moment.
			if _retry_box.modulate.a >= 1.0:
				_retry_wait += dt
				if _retry.disabled and _retry_wait >= 1.0:
					_retry.disabled = false
					_retry.grab_focus()


# Enter / Space held down from the skip must not press "Try Again" by repeating.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo and _retry != null and _retry.has_focus():
		get_viewport().set_input_as_handled()


func _skip() -> void:
	_t = maxf(_t, _black_at + FADE_OUT + BLACK_HOLD + FADE_IN)
	if not _text.writing:
		_text.begin()
	_text._t = 1000.0


func _eye_camera() -> Transform3D:
	var pose = _skel.global_transform * _skel.get_bone_global_pose(_head) * _eye_rel
	pose.basis = pose.basis.orthonormalized()
	var tr = _trauma * _trauma
	var n = _t * 32.0
	pose.basis = pose.basis * Basis.from_euler(Vector3(_noise.get_noise_2d(n, 0.0), _noise.get_noise_2d(n, 40.0), _noise.get_noise_2d(n, 80.0)) * tr * 0.09)
	var k = smoothstep(0.0, 1.0, clampf(_t / 0.3, 0.0, 1.0))
	if k >= 1.0:
		return pose
	var q = _start_cam.basis.get_rotation_quaternion().slerp(pose.basis.get_rotation_quaternion(), k)
	return Transform3D(Basis(q), _start_cam.origin.lerp(pose.origin, k))


func _centre() -> Vector3:
	return _focus


func _away_from_demon() -> Vector3:
	var d = _centre() - main.nearest_demon().global_position
	d.y = 0.0
	if d.length() < 0.05:
		d = _side
	d = d.normalized()
	var best = d
	var best_score = -INF
	for k in range(24):
		var dir = d.rotated(Vector3.UP, TAU * k / 24.0)
		var room = 0.0
		for u in [0.0, 0.5, 1.0]:
			var want = _orbit_point(dir.rotated(Vector3.UP, 0.18 * u), u)
			var from = _centre() + Vector3(0, 0.4, 0)
			room += _cast_fraction(from, want)
		var score = room * 2.0 + dir.dot(d) * 1.2
		if score > best_score:
			best_score = score
			best = dir
	return best


func _orbit_point(dir: Vector3, u: float) -> Vector3:
	return _centre() + dir * lerpf(0.55, 1.45, u) + Vector3(0, lerpf(0.9, 2.25, u), 0)


func _orbit(u: float) -> Transform3D:
	var centre = _centre()
	var pos = _safe(centre + Vector3(0, 0.4, 0), _orbit_point(_away.rotated(Vector3.UP, 0.18 * u), u))
	return Transform3D(Basis.IDENTITY, pos).looking_at(centre + Vector3(0, 0.05, 0), Vector3.UP)


func _add_lights() -> void:
	var env = main._env
	_env_from = [env.ambient_light_energy, env.fog_density, env.fog_light_color, env.background_color]
	_rim = OmniLight3D.new()
	_rim.light_color = Color(0.7, 0.08, 0.05)
	_rim.light_energy = 0.0
	_rim.omni_range = 3.5
	add_child(_rim)
	_rim.global_position = _centre() - _away * 0.8 + Vector3(0, 1.4, 0)
	_key = OmniLight3D.new()
	_key.light_color = Color(0.62, 0.58, 0.7)
	_key.light_energy = 0.0
	_key.omni_range = 3.4
	_key.light_cull_mask = BODY_LAYER
	add_child(_key)
	_key.global_position = _centre() + _away * 0.7 + Vector3(0, 1.2, 0)


func _darken(k: float) -> void:
	var env = main._env
	env.ambient_light_energy = lerpf(_env_from[0], 0.0, k)
	env.fog_density = lerpf(_env_from[1], 0.2, k)
	env.fog_light_color = (_env_from[2] as Color).lerp(Color(0, 0, 0), k)
	env.background_color = (_env_from[3] as Color).lerp(Color(0, 0, 0), k)
	_rim.light_energy = 0.7 * k
	_key.light_energy = 2.2 * k


func _update_candle(dt: float) -> void:
	if _c_state == 0:
		_c_vel.y -= 9.8 * dt
		_c_pos += _c_vel * dt
		var b = candle.global_basis.rotated(_c_spin.normalized(), _c_spin.length() * dt)
		candle.global_transform = Transform3D(b.orthonormalized(), _c_pos)
		if _c_pos.y <= 0.02:
			_c_state = 1
			_c_land_basis = candle.global_basis
			_c_land_t = 0.0
			var roll_dir = (_side * 0.8 + _fwd * 0.4).normalized()
			if _pew:
				roll_dir = (_side + Vector3(0, 0, 0.15)).normalized()
			_c_speed = _rng.randf_range(0.28, 0.38)
			var axis = roll_dir.cross(Vector3.UP)
			_c_yaw = atan2(axis.z, axis.x)
			_c_turn = 1.0 / _rng.randf_range(0.9, 1.4) * (1.0 if _rng.randf() < 0.5 else -1.0)
			_c_pos.y = DISH_R
			main.sfx.play_at("clatter", _c_pos, -4.0)
		return
	_c_land_t += dt
	_c_speed = maxf(0.0, _c_speed - dt * 0.09)
	_c_roll += _c_speed / DISH_R * dt
	_c_yaw += _c_speed * _c_turn * dt
	var axis = Vector3(cos(_c_yaw), 0, sin(_c_yaw))
	var roll_dir = Vector3.UP.cross(axis).normalized()
	_c_pos += roll_dir * _c_speed * dt
	var y = (axis * cos(TILT) + Vector3.DOWN * sin(TILT)).normalized()
	var x = roll_dir.cross(y).normalized()
	var z = x.cross(y).normalized()
	var lying = Basis(x, y, z).rotated(y, -_c_roll)
	var k = smoothstep(0.0, 1.0, clampf(_c_land_t / 0.22, 0.0, 1.0))
	var bounce = absf(sin(_c_land_t * 18.0)) * exp(-_c_land_t * 9.0) * 0.04
	var b = Basis(_c_land_basis.get_rotation_quaternion().slerp(lying.get_rotation_quaternion(), k))
	candle.global_transform = Transform3D(b, _c_pos + Vector3(0, bounce, 0))


