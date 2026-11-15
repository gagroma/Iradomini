extends Node3D
# PASSAGE - the road from one church to the next (played between levels, not before the first).
#
# A graveyard road at night, in full darkness: the only light is the candle in your hand and, far
# ahead, a warm glow under the door of the next church. You can only walk forward (hold W) and look.
# Something walks the graveyard with you - the stalker. You almost never see it. You HEAR it:
# it carries an old hymn, playing like a worn gramophone record. The sound comes from where it is
# (left, right, ahead, behind), muffled when far, clear and warped when close.
#
# What it does, in no fixed order:
#   pass    it walks by among the graves. Stand still while the music is beside you.
#   listen  it comes to the edge of the road next to you. The record slows down and STOPS. In the
#           silence it listens (you hear it breathe). Move and it has you. Then the record winds
#           back up and it goes.
#   feint   it comes part of the way, stops out in the dark, and turns back. Or does not.
#   stand   no music at all. It simply stands on the road ahead of you, and you see its eyes at the
#           edge of your light. Stop and wait until it walks off. Walk into it and it has you.
# It reacts only to you MOVING while it is close. Looking around is always safe.
#
# The wind never quite stops. Now and then a gust rises and takes your light, and when the stalker comes
# to listen its breath puts it out too. Then there is nothing at all, until you press F and strike a
# light yourself. That takes a moment, you cannot walk while you do it, and it is a SOUND: strike it
# while the music is near and it turns and comes for you; strike it while it stands over you and it
# has you. Once, when the flame catches, it may already be standing on the road in front of you.
#
# Harder each level: a longer road, shorter quiet spells, a faster stalker that listens longer, more wind.
# Flow: main.tscn (level N) -> altar finished -> passage -> main.tscn (level N+1) -> ...
# Getting caught restarts this road. Every number is in the PASSAGE section of tuning.gd.

const T = preload("res://scripts/tuning.gd")
const Sfx = preload("res://scripts/sfx.gd")
const Models = preload("res://scripts/models.gd")
const HandCandle = preload("res://scripts/candle.gd")
const UIStyle = preload("res://scripts/ui_style.gd")
const POST_SHADER = preload("res://shaders/post.gdshader")
const GROUND_SHADER = preload("res://shaders/exterior_ground.gdshader")
const STONE = preload("res://materials/kit/kit_stone.tres")
const HAND_LEFT = preload("res://assets/models/hand_left.glb")
const STALKER = preload("res://assets/models/demon_stalker.glb")
const GAME_SCENE := "res://main.tscn"

const K_WALL = preload("res://assets/kit/wall_2m.glb")
const K_WALL_W = preload("res://assets/kit/wall_2m_window.glb")
const K_DOORWAY = preload("res://assets/kit/wall_2m_door.glb")
const K_PILASTER = preload("res://assets/kit/pilaster.glb")
const P_DOOR = preload("res://assets/props/door.glb")
const P_WINDOW = preload("res://assets/props/window.glb")

const CELL := 2.0
const EYE := 1.55
const LANE_FAR := 6.5         # where it walks, out among the graves
const LANE_NEAR := 2.3        # the edge of the road, where it comes to listen
const CANDLE_ENERGY := 3.2
const CANDLE_REACH := 7.0
const EYE_COLOR := Color(1.0, 0.35, 0.15)
const GUST_LEN := 2.8

# (kept for flame_transition.gd, in case the menu ever opens straight into a passage)
var candle_intro := false

var level := 2
var length := 48.0            # metres from the start to the church door
var events := []              # what happened on this walk, in order (read by the test tool)

var sfx
var cam: Camera3D
var head: Node3D
var candle
var post: ShaderMaterial
var _hint: Label
var _title: Label
var _prompt: Label
var _bark: StandardMaterial3D

var _z := -1.0
var _speed := 0.0
var _yaw := 0.0
var _pitch := -0.05
var _bob := 0.0
var _step_acc := 0.0
var _state := "walk"          # "walk", "caught", "done"
var _state_t := 0.0
var _fade := 1.0
var _fade_target := 0.0
var _flash := 0.0
var _fear := 0.0
var _time := 0.0
var _heart_wait := 0.0
var _rng := RandomNumberGenerator.new()

# the candle and the wind
var _strike := 0.0            # > 0 while you strike a light
var _out_time := 0.0          # how long the candle has been out
var _gust_wait := 0.0
var _gust_t := 0.0            # > 0 while a gust blows
var _gust_done := false
var _gust := 0.0              # 0..1 strength of the gust right now
var _twig_wait := 0.0
var _wind

# the stalker
var _t_state := "away"        # "away", "come", "wait", "close", "listen", "back", "go", "stand", "leave"
var _t_plan := ""             # "pass", "listen", "feint", "stand"
var _t_x := LANE_FAR
var _t_z := 0.0
var _t_side := 1.0
var _t_dir := 1.0
var _t_wait := 0.0            # quiet time left before its next visit
var _t_timer := 0.0
var _t_turn := 10.0           # a feint turns back this far from you
var _t_moving := 0.0          # 0..1, how much it is walking (for the gait)
var _t_phase := 0.0
var _t_step := 0
var _visits := 0
var _last_plan := ""
var _had_stand := false
var _scare_done := false
var _noise := 0.0             # seconds you have walked within its hearing
var _glow: OmniLight3D
var _figure: Node3D
var _parts := {}
var _eyes: MeshInstance3D
var _eye_mat: StandardMaterial3D
var _rec: AudioStreamPlayer3D
var _rec_filter: AudioEffectLowPassFilter
var _rec_speed := 0.0         # 0 = the record has stopped, 1 = full speed
var _rec_target := 0.0
var _breath


func _ready() -> void:
	level = T.level_number()
	_rng.randomize()
	length = (T.PASSAGE_CELLS + T.PASSAGE_CELLS_PER_LEVEL * maxi(level - 2, 0)) * CELL
	sfx = Sfx.new()
	add_child(sfx)
	_environment()
	_build()
	_make_viewer()
	_make_stalker()
	_make_sound()
	_make_screen()
	_t_wait = T.PASSAGE_FIRST_QUIET
	_gust_wait = _rng.randf_range(T.PASSAGE_GUST_MIN, T.PASSAGE_GUST_MAX)
	_twig_wait = _rng.randf_range(6.0, 12.0)
	if not candle_intro:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	candle.tick(1.0 / 60.0, 0.0)


func candle_flame_uv() -> Vector2:
	return cam.unproject_position(candle.flame_center()) / get_viewport().get_visible_rect().size


func finish_candle_intro() -> void:
	candle_intro = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ------------------------------------------------------------------------ WORLD

# Full darkness: no moon, almost no ambient light, black fog. What your candle does not reach is not there.
func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.003, 0.002, 0.006)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.2, 0.16, 0.3)
	env.ambient_light_energy = 0.03
	env.fog_enabled = true
	env.fog_light_color = Color(0.004, 0.003, 0.008)
	env.fog_density = 0.075
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.03
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _put(scene: PackedScene, pos: Vector3, yaw_deg: float) -> Node3D:
	var n: Node3D = scene.instantiate()
	add_child(n)
	n.position = pos
	n.rotation.y = deg_to_rad(yaw_deg)
	return n


func _prop(name: String, pos: Vector3, yaw_deg: float) -> Node3D:
	return _put(load("res://assets/props/%s.glb" % name), pos, yaw_deg)


func _box(size: Vector3, xf: Transform3D, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = mat
	add_child(mi)
	mi.transform = xf


func _side() -> float:
	return -1.0 if _rng.randf() < 0.5 else 1.0


# One road through the graveyard, from the door of the church you left to the door of the next.
func _build() -> void:
	_bark = StandardMaterial3D.new()
	_bark.albedo_color = Color(0.1, 0.08, 0.07)
	_bark.roughness = 1.0
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(22.0, length + 8.0)
	pm.subdivide_width = 11
	pm.subdivide_depth = int(length / 2.0)
	g.mesh = pm
	var mat := ShaderMaterial.new()
	mat.shader = GROUND_SHADER
	mat.set_shader_parameter("road_start", Vector2(0.0, 2.0))
	mat.set_shader_parameter("road_dir", Vector2(0.0, -1.0))
	mat.set_shader_parameter("road_length", length + 4.0)
	mat.set_shader_parameter("road_half", 0.9)
	g.material_override = mat
	add_child(g)
	g.position = Vector3(0, -0.005, -length * 0.5)

	# graves on both sides of the road
	var placed := []
	for k in int(length * 1.4):
		var p := Vector2(_side() * _rng.randf_range(1.7, 8.5), -_rng.randf_range(1.5, length - 1.5))
		var ok := true
		for q in placed:
			if q.distance_to(p) < 1.25:
				ok = false
		if not ok:
			continue
		placed.append(p)
		var b := Basis(Vector3.UP, _rng.randf_range(-0.3, 0.3)) * Basis(Vector3.RIGHT, _rng.randf_range(-0.14, 0.1)) * Basis(Vector3.FORWARD, _rng.randf_range(-0.12, 0.12))
		var h := _rng.randf_range(0.55, 1.05)
		match _rng.randi_range(0, 3):
			0, 1:                                   # headstone
				var w := _rng.randf_range(0.42, 0.62)
				_box(Vector3(w, h, 0.12), Transform3D(b, Vector3(p.x, h * 0.5 - 0.06, p.y)), STONE)
			2:                                      # grave cross
				_box(Vector3(0.1, h + 0.3, 0.1), Transform3D(b, Vector3(p.x, (h + 0.3) * 0.5 - 0.05, p.y)), STONE)
				_box(Vector3(0.5, 0.09, 0.09), Transform3D(b, Vector3(p.x, h * 0.75, p.y)), STONE)
			3:                                      # a sunken slab
				_box(Vector3(0.75, 0.12, 1.5), Transform3D(b, Vector3(p.x, 0.0, p.y)), STONE)

	# stone figures by the roadside: in candlelight every one of them is, for a moment, the stalker
	var z := -_rng.randf_range(6.0, 9.0)
	var s := _side()
	while z > -length + 6.0:
		_prop("statue", Vector3(s * _rng.randf_range(1.6, 2.4), 0, z), -s * 90.0 + _rng.randf_range(-25.0, 25.0))
		s = -s
		z -= _rng.randf_range(9.0, 15.0)
	# dead trees, their branches over the road
	z = -_rng.randf_range(3.0, 6.0)
	while z > -length + 3.0:
		_tree(Vector3(_side() * _rng.randf_range(2.2, 5.5), 0, z))
		z -= _rng.randf_range(6.0, 11.0)
	# lantern posts whose lamps went out long ago
	z = -_rng.randf_range(8.0, 12.0)
	while z > -length + 5.0:
		var ls := _side()
		_box(Vector3(0.12, 2.2, 0.12), Transform3D(Basis.IDENTITY, Vector3(ls * 1.4, 1.1, z)), STONE)
		_prop("lantern", Vector3(ls * 1.4, 2.2, z), 0)
		z -= _rng.randf_range(12.0, 18.0)
	# halfway: the graveyard wall, and its gate standing open
	var zg := -snappedf(length * 0.5, CELL)
	for x in [-4.0, -2.0, 0.0, 2.0, 4.0]:
		_put(K_DOORWAY if x == 0.0 else K_WALL, Vector3(x, 0, zg), 0)
	for x in [-5.0, -3.0, -1.0, 1.0, 3.0, 5.0]:
		_put(K_PILASTER, Vector3(x, 0, zg), 0)

	_facade(0.0, true)                   # the church behind you (its door shut)
	_facade(-length, false)              # the next church


func _tree(pos: Vector3) -> void:
	var lean := Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.RIGHT, _rng.randf_range(-0.12, 0.12))
	var h := _rng.randf_range(3.0, 4.6)
	_box(Vector3(0.28, h, 0.28), Transform3D(lean, pos + lean * Vector3(0, h * 0.5, 0)), _bark)
	for i in _rng.randi_range(3, 5):
		var from := pos + lean * Vector3(0, h * _rng.randf_range(0.5, 0.97), 0)
		var b := Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.RIGHT, _rng.randf_range(0.6, 1.25))
		var l := _rng.randf_range(1.1, 2.4)
		_box(Vector3(0.09, l, 0.09), Transform3D(b, from + b * Vector3(0, l * 0.5, 0)), _bark)
		if _rng.randf() < 0.6:                               # a twig off the branch
			var b2 := b * Basis(Vector3.FORWARD, _rng.randf_range(-0.9, 0.9))
			var l2 := l * 0.5
			_box(Vector3(0.05, l2, 0.05), Transform3D(b2, from + b * Vector3(0, l * 0.7, 0) + b2 * Vector3(0, l2 * 0.5, 0)), _bark)


# The front of a church across the road: walls, a door, and (ahead) a little warm light from inside.
func _facade(z: float, behind: bool) -> void:
	var yaw := 180.0 if behind else 0.0
	for x in [-4.0, -2.0, 0.0, 2.0, 4.0]:
		if x == 0.0:
			_put(K_DOORWAY, Vector3(x, 0, z), yaw)
			_put(P_DOOR, Vector3(x, 0, z), yaw)
		elif absf(x) == 2.0:
			_put(K_WALL_W, Vector3(x, 0, z), yaw)
			_put(P_WINDOW, Vector3(x, 1.0, z), yaw)
		else:
			_put(K_WALL, Vector3(x, 0, z), yaw)
	for x in [-5.0, -3.0, -1.0, 1.0, 3.0, 5.0]:
		_put(K_PILASTER, Vector3(x, 0, z), 0)
	if not behind:
		for x in [-2.0, 0.0, 2.0]:
			var warm := OmniLight3D.new()
			warm.light_color = Color(1.0, 0.55, 0.25)
			warm.light_energy = 1.3 if x == 0.0 else 0.8
			warm.omni_range = 4.0
			warm.position = Vector3(x, 0.4 if x == 0.0 else 2.0, z + 0.45)
			add_child(warm)


# ----------------------------------------------------------------------- YOU

func _make_viewer() -> void:
	head = Node3D.new()
	add_child(head)
	head.position = Vector3(0, EYE, _z)
	cam = Camera3D.new()
	cam.fov = 62.0
	cam.near = 0.05
	cam.far = 45.0
	head.add_child(cam)
	cam.current = true
	var hands := Node3D.new()
	cam.add_child(hands)
	candle = HandCandle.new()
	candle.energy = CANDLE_ENERGY
	candle.reach = CANDLE_REACH
	candle.burns = false                 # the walk is short; only the wind and the stalker put it out
	candle.position = Vector3(-0.2, -0.2, -0.39)
	candle.rotation.y = -2.36
	hands.add_child(candle)
	var hand_mat := ShaderMaterial.new()
	hand_mat.shader = Models.VCOLOR_SHADER
	hand_mat.set_shader_parameter("snap", false)
	hand_mat.set_shader_parameter("roughness", 0.7)
	var left: Node3D = HAND_LEFT.instantiate()
	for mi in left.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = hand_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	left.rotation.y = 2.36
	candle.add_child(left)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and _state == "walk":
		_yaw = clampf(_yaw - event.relative.x * 0.0022, -1.3, 1.3)
		_pitch = clampf(_pitch - event.relative.y * 0.0022, -1.0, 0.9)
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F:
		_strike_light()
	elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and not candle_intro:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ---------------------------------------------------------- THE CANDLE AND THE WIND

# Your light dies, and stays dead until you strike it again.
func _blow_out(why: String) -> void:
	if not candle.lit:
		return
	candle.blow_out()
	_out_time = 0.0
	sfx.play("candle_out", -3.0)
	events.append("dark (%s)" % why)


# F: strike a light. It takes a moment, you cannot walk while you do it, and it makes a sound.
func _strike_light() -> void:
	if _state != "walk" or candle.lit or _strike > 0.0 or candle_intro:
		return
	_strike = T.PASSAGE_RELIGHT_TIME
	sfx.play("lighter_open", -6.0)


func _update_strike(dt: float) -> void:
	if _strike <= 0.0:
		return
	var half: float = T.PASSAGE_RELIGHT_TIME * 0.5
	var before := _strike
	_strike -= dt
	if before > half and _strike <= half:
		sfx.play("lighter_strike", -2.0)
		_heard_strike()
	if _strike <= 0.0 and _state == "walk":
		candle.relight()
		events.append("relit")
		# once: the flame catches, and it is already standing there
		if _t_state == "away" and not _scare_done and -_z < length - 16.0 and _rng.randf() < T.PASSAGE_RELIGHT_SCARE:
			_scare_done = true
			events.append("stand (as the flame catches)")
			_start_stand(6.0)


# The scrape and flare of a light being struck carries in the quiet.
func _heard_strike() -> void:
	if _t_state == "away":
		return
	var d := cam.global_position.distance_to(_figure.position + Vector3(0, EYE, 0))
	if _t_state in ["listen", "close"] or (_t_state == "stand" and d < T.PASSAGE_MATCH_HEARING * 0.5):
		_caught()
	elif d < T.PASSAGE_MATCH_HEARING and _t_state != "stand":
		events.append("it heard the light")
		sfx.play_at("demon_notice", _figure.position + Vector3(0, 2.0, 0), -2.0)
		_t_plan = "listen"                # it turns and comes to you
		_t_dir = 1.0 if _t_z < _z else -1.0
		_t_state = "come"
		_rec_target = 1.0


func _update_wind(dt: float) -> void:
	var lvl := float(maxi(level - 2, 0))
	_gust = 0.0
	if _gust_t > 0.0:
		_gust_t -= dt
		var k := 1.0 - maxf(_gust_t, 0.0) / GUST_LEN
		_gust = sin(k * PI)
		if k >= 0.5 and not _gust_done:
			_gust_done = true
			if _rng.randf() < T.PASSAGE_GUST_BLOWOUT:        # this one takes your light; the others only shake it
				_blow_out("wind")
	elif _state == "walk":
		_gust_wait -= dt
		if _gust_wait <= 0.0 and not (_t_state in ["stand", "leave", "close", "listen"]) and _strike <= 0.0 and candle.lit:
			_gust_t = GUST_LEN
			_gust_done = false
			_gust_wait = maxf(8.0, _rng.randf_range(T.PASSAGE_GUST_MIN, T.PASSAGE_GUST_MAX) - T.PASSAGE_GUST_PER_LEVEL * lvl)
			events.append("gust")
	if _wind:
		_wind.volume_db = lerpf(_wind.volume_db, lerpf(-25.0, -4.0, _gust), 1.0 - exp(-5.0 * dt))
		_wind.pitch_scale = 1.0 + 0.3 * _gust
	# small sounds out in the dark that are not it
	_twig_wait -= dt
	if _twig_wait <= 0.0 and _state == "walk":
		_twig_wait = _rng.randf_range(11.0, 24.0)
		var a := _rng.randf() * TAU
		sfx.play_at("twig", Vector3(cos(a), 0.0, sin(a)) * _rng.randf_range(6.0, 12.0) + Vector3(0, 0.3, _z), -6.0, _rng.randf_range(0.8, 1.2))


# -------------------------------------------------------------- THE STALKER

func _make_stalker() -> void:
	_glow = OmniLight3D.new()            # only lit at the end, so you see what has you even if your candle is out
	_glow.light_color = Color(1.0, 0.35, 0.2)
	_glow.light_energy = 0.0
	_glow.omni_range = 4.5
	add_child(_glow)
	_figure = STALKER.instantiate()       # assets/models/demon_stalker.glb: rigid parts on pivots, faces +Z
	add_child(_figure)
	for n in ["Neck", "Hip_L", "Hip_R", "Knee_L", "Knee_R", "Shoulder_L", "Shoulder_R", "Torso"]:
		var p := _figure.find_child(n, true, false)
		if p:
			_parts[n] = p
			p.set_meta("rest", p.rotation)
	# the eyes burn in the dark - but only when it is near
	_eyes = _figure.find_child("Eyes", true, false) as MeshInstance3D
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_eye_mat.disable_fog = true
	_eye_mat.albedo_color = EYE_COLOR
	if _eyes:
		_eyes.material_override = _eye_mat
	_figure.visible = false


# The record plays from the stalker itself, so you hear WHERE it is. Its own audio bus has a
# low-pass filter: far away the music is a dull murmur, close by it is clear.
func _make_sound() -> void:
	var bus := AudioServer.get_bus_index("Stalker")
	if bus == -1:
		AudioServer.add_bus()
		bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus, "Stalker")
		AudioServer.set_bus_send(bus, "Master")
		AudioServer.add_bus_effect(bus, AudioEffectLowPassFilter.new())
	_rec_filter = AudioServer.get_bus_effect(bus, 0)
	_rec = AudioStreamPlayer3D.new()
	_rec.stream = sfx._looped("record") if sfx.has("record") else sfx._looped("chant")
	_rec.bus = "Stalker"
	_rec.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED      # loudness is set below, by hand
	_rec.attenuation_filter_cutoff_hz = 20500.0
	_rec.volume_db = -80.0
	_rec.position = Vector3(0, 1.9, 0)
	_figure.add_child(_rec)
	_rec.play()
	_breath = sfx.loop_at("demon_breath", _figure, -60.0)
	_wind = sfx.loop("wind", -25.0)


# How far it is from you for hearing your steps: mostly the distance along the road.
func _distance() -> float:
	return Vector2(_t_z - _z, _t_x * 0.4).length()


func _begin_visit() -> void:
	_visits += 1
	var plan := "listen"                 # the first time it always comes and listens: the lesson
	if _visits > 1:
		var r := _rng.randf()
		plan = "pass" if r < 0.25 else ("listen" if r < 0.55 else ("feint" if r < 0.75 else "stand"))
		if not _had_stand and -_z > length * 0.4:
			plan = "stand"
		if plan == "stand" and (_last_plan == "stand" or not candle.lit or -_z > length - 16.0):
			plan = "listen"
		if plan == "feint" and _last_plan == "feint":
			plan = "pass"
	_last_plan = plan
	events.append(plan)
	if plan == "stand":
		_start_stand(_rng.randf_range(11.0, 14.0))
		return
	_t_plan = plan
	var ahead := _rng.randf() < 0.65
	var off := _rng.randf_range(22.0, 27.0)
	_t_z = _z - off if ahead else _z + off
	_t_dir = 1.0 if ahead else -1.0
	_t_side = _side()
	_t_x = _t_side * LANE_FAR
	_t_turn = _rng.randf_range(9.0, 13.0)
	_t_state = "come"
	_rec_target = 1.0
	_rec_speed = 1.0


# No music. It stands on the road, this far ahead of you, facing you.
func _start_stand(ahead: float) -> void:
	_had_stand = true
	_t_plan = "stand"
	_t_state = "stand"
	_t_x = 0.0
	_t_z = _z - ahead
	_t_dir = 1.0
	_t_side = _side()
	_t_timer = T.PASSAGE_STAND_WAIT + _rng.randf_range(0.0, 1.5)
	_rec_target = 0.0
	_rec_speed = 0.0
	_figure.rotation.y = 0.0


func _end_visit() -> void:
	var lvl := float(maxi(level - 2, 0))
	_t_state = "away"
	_t_wait = maxf(2.5, _rng.randf_range(T.PASSAGE_QUIET_MIN, T.PASSAGE_QUIET_MAX) - T.PASSAGE_QUIET_PER_LEVEL * lvl)


func _update_stalker(dt: float) -> void:
	var lvl := float(maxi(level - 2, 0))
	var speed: float = T.PASSAGE_THING_SPEED + T.PASSAGE_THING_SPEED_PER_LEVEL * lvl
	var moving := false
	var gap := absf(_z - _t_z)
	match _t_state:
		"away":
			_t_wait -= dt
			if _t_wait <= 0.0 and _strike <= 0.0:
				_begin_visit()
		"come":
			_t_z += _t_dir * speed * dt
			_t_x = move_toward(_t_x, _t_side * LANE_FAR, 1.3 * dt)
			moving = true
			if _t_plan == "feint" and gap < _t_turn:
				_t_state = "wait"
				_t_timer = _rng.randf_range(1.5, 3.5)
			elif gap < 1.3 or (1.0 if _t_z < _z else -1.0) != _t_dir:
				if _t_plan == "listen":
					_t_state = "close"
					_rec_target = 0.0             # the record begins to slow
				else:
					_t_state = "go"
					_t_timer = 0.0
		"wait":                                   # stopped out in the dark, turned towards you
			_t_timer -= dt
			if _t_timer <= 0.0:
				if _rng.randf() < 0.25:
					_t_plan = "listen"            # it comes after all
					_t_state = "come"
				else:
					_t_dir = -_t_dir
					_t_state = "go"
					_t_timer = 0.0
		"close":                                  # steps in to the edge of the road, a little ahead of you
			_t_x = move_toward(_t_x, _t_side * LANE_NEAR, 1.3 * dt)
			_t_z = move_toward(_t_z, _z - 2.0, 1.0 * dt)
			moving = true
			if absf(_t_x) <= LANE_NEAR + 0.02:
				_t_state = "listen"
				_t_timer = _rng.randf_range(T.PASSAGE_LISTEN_MIN, T.PASSAGE_LISTEN_MAX) + T.PASSAGE_LISTEN_PER_LEVEL * lvl
				if _rng.randf() < T.PASSAGE_LISTEN_BLOWOUT:
					_blow_out("its breath")
		"listen":
			_t_timer -= dt
			if _t_timer <= 0.0:
				_t_state = "back"
				_rec_target = 1.0                 # the record winds up again
		"back":
			_t_x = move_toward(_t_x, _t_side * LANE_FAR, 1.3 * dt)
			moving = true
			if absf(_t_x) >= LANE_FAR - 0.02:
				_t_state = "go"
				_t_timer = 0.0
		"go":
			_t_z += _t_dir * speed * 0.8 * dt
			_t_timer += dt
			moving = true
			if gap > 27.0 or (_t_timer > 12.0 and gap > 15.0):
				_end_visit()
		"stand":
			if gap < T.PASSAGE_STAND_CATCH:
				_caught()
				return
			# it goes when you have stood still long enough
			if _speed < 0.1 and gap < 10.0:
				_t_timer -= dt
			if _t_timer <= 0.0:
				_t_state = "leave"
				_rec_target = 1.0
		"leave":                                  # walks off the road into the graves
			_t_x = move_toward(_t_x, _t_side * LANE_FAR, 1.5 * dt)
			moving = true
			if absf(_t_x) >= LANE_FAR - 0.02:
				_t_dir = _side()
				_t_state = "go"
				_t_timer = 0.0
	var present := _t_state != "away"
	_figure.visible = present
	_figure.position = Vector3(_t_x, 0.0, _t_z)
	var dist := cam.global_position.distance_to(_figure.position + Vector3(0, EYE, 0))

	# --- which way it faces
	var look := Vector2(0.0, _t_dir)
	if _t_state in ["wait", "close", "listen", "stand"]:
		look = Vector2(-_t_x, _z - _t_z)                       # turned to you
	elif _t_state in ["back", "leave"]:
		look = Vector2(_t_side, 0.0)
	if present and look.length() > 0.01:
		_figure.rotation.y = lerp_angle(_figure.rotation.y, atan2(look.x, look.y), 1.0 - exp(-5.0 * dt))
	_t_moving = move_toward(_t_moving, 1.0 if moving else 0.0, dt * 3.0)
	_animate(dt, speed, _t_state in ["listen", "wait"])

	# --- the record: where it is, how far, and whether it is turning
	var heard := clampf(1.0 - (dist - 2.0) / 27.0, 0.0, 1.0) if present else 0.0
	_rec_speed = move_toward(_rec_speed, _rec_target, dt * (0.7 if _rec_target < _rec_speed else 0.55))
	var vol := lerpf(-44.0, -2.0, pow(heard, 0.7)) + lerpf(-34.0, 0.0, _rec_speed)
	if not present or _rec_speed <= 0.002:
		vol = -80.0
	_rec.volume_db = lerpf(_rec.volume_db, vol, 1.0 - exp(-6.0 * dt))
	# close by, the disc warps
	_rec.pitch_scale = maxf(0.05, lerpf(0.32, 1.0, _rec_speed) * (1.0 + 0.03 * heard * heard * sin(_time * 2.1) + 0.008 * heard * sin(_time * 11.0)))
	_rec_filter.cutoff_hz = lerpf(350.0, 6000.0, pow(heard, 1.8))
	# in the silence you hear it breathe
	if _breath:
		var b := -60.0
		if _t_state == "listen":
			b = -5.0
		elif _t_state == "close" or (_t_state == "stand" and dist < 6.0):
			b = -12.0
		_breath.volume_db = lerpf(_breath.volume_db, b, 1.0 - exp(-2.5 * dt))
	# its steps, when they are near enough to hear
	var st := int(_t_phase / PI)
	if st != _t_step:
		_t_step = st
		if moving and dist < 18.0:
			sfx.play_at("demon_step", _figure.position, -7.0, _rng.randf_range(0.78, 0.92))

	# --- its eyes: seen only when near, brighter while yours are on them
	var eye_k := smoothstep(11.0, 6.0, dist) if present else 0.0
	_eye_mat.albedo_color = Color(EYE_COLOR.r * eye_k, EYE_COLOR.g * eye_k, EYE_COLOR.b * eye_k)
	if _eyes:
		_eyes.visible = eye_k > 0.02

	# --- your candle shrinks and your heart goes as it comes close
	var near := clampf(1.0 - (dist - 2.0) / (9.0 if _t_state == "stand" else 20.0), 0.0, 1.0) if present else 0.0
	_fear = maxf(near, _fear - dt * 0.5)

	# --- it hears you walk
	var danger: bool = present and _t_state != "stand" and _distance() < T.PASSAGE_DANGER_DISTANCE
	if danger and _speed > 0.25:
		_noise += dt
	else:
		_noise = maxf(0.0, _noise - dt * 0.5)
	if _noise > T.PASSAGE_NOTICE_TIME:
		_caught()
		return


# A slow, heavy gait done in code (the model has no animations): hips and knees swing, shoulders
# hang and sway; listening, its head bows and tilts; at the scare it rears and spreads its arms.
func _animate(dt: float, speed: float, listening: bool, scare := 0.0) -> void:
	_t_phase += dt * (1.6 + speed * 1.1) * _t_moving
	var s := sin(_t_phase)
	var w := _t_moving
	var k := 1.0 - exp(-12.0 * dt)
	var want := {
		"Hip_L": Vector3(-0.42 * s * w, 0, 0), "Hip_R": Vector3(0.42 * s * w, 0, 0),
		"Knee_L": Vector3(0.6 * maxf(0.0, -cos(_t_phase)) * w, 0, 0), "Knee_R": Vector3(0.6 * maxf(0.0, cos(_t_phase)) * w, 0, 0),
		"Shoulder_L": Vector3(0.3 * s * w + 0.06 * sin(_time * 1.3), 0, 0.05), "Shoulder_R": Vector3(-0.3 * s * w + 0.06 * sin(_time * 1.1), 0, -0.05),
		"Torso": Vector3(0.02 * w + 0.012 * sin(_time * 1.7), 0.04 * s * w, 0),
		"Neck": Vector3(0.1 * w, 0, 0),
	}
	if listening:
		want["Neck"] = Vector3(0.35, 0.0, 0.25 * sin(_time * 0.8))
		want["Torso"] = Vector3(0.05, 0, 0)
	if scare > 0.0:
		want["Neck"] = Vector3(0.55 * scare, 0, 0)
		want["Torso"] = Vector3(-0.06 * scare, 0, 0)
		want["Shoulder_L"] = Vector3(-1.9 * scare, 0, 0.6 * scare)
		want["Shoulder_R"] = Vector3(-1.9 * scare, 0, -0.6 * scare)
	for n in want.keys():
		if _parts.has(n):
			var rest: Vector3 = _parts[n].get_meta("rest")
			_parts[n].rotation = _parts[n].rotation.lerp(rest + want[n], k)


# ------------------------------------------------------------------------ SCREEN

func _label(ui: CanvasLayer, text: String, size: int, preset: Control.LayoutPreset, y: float) -> Label:
	var l := Label.new()
	UIStyle.style_text(l, size, UIStyle.BONE * Color(1, 1, 1, 0.85))
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui.add_child(l)
	l.set_anchors_and_offsets_preset(preset)
	l.position.y += y
	return l


func _make_screen() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 1
	add_child(canvas)
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(rect)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	post = ShaderMaterial.new()
	post.shader = POST_SHADER
	rect.material = post
	var ui := CanvasLayer.new()
	ui.layer = 2
	add_child(ui)
	_title = _label(ui, "THE ROAD TO THE NEXT CHURCH  ·  LEVEL %d" % level, 16, Control.PRESET_CENTER_TOP, 34)
	_prompt = _label(ui, "F  -  strike a light", 9, Control.PRESET_CENTER_BOTTOM, -30)
	_prompt.modulate.a = 0.0
	_hint = _label(ui, "Hold W to walk.   When the music is near, stand still.\nIf it stands in your way, wait.", 9, Control.PRESET_CENTER_BOTTOM, -44)


# ------------------------------------------------------------------------ EVERY FRAME

func _process(dt: float) -> void:
	_time += dt
	_state_t += dt
	var walking := false
	if _state == "walk" and not candle_intro and _strike <= 0.0:
		walking = Input.is_physical_key_pressed(KEY_W)
	var want := T.PASSAGE_WALK_SPEED if walking else 0.0
	_speed = move_toward(_speed, want, dt * (4.0 if walking else 6.0))
	_z -= _speed * dt
	if _speed > 0.25:
		_step_acc += _speed * dt
		if _step_acc > 0.72:
			_step_acc = 0.0
			sfx.play("step1" if _rng.randf() < 0.5 else "step2", -16.0, _rng.randf_range(0.9, 1.1))
	_bob += dt * _speed * 5.5
	var bob := sin(_bob) * 0.035 * clampf(_speed / T.PASSAGE_WALK_SPEED, 0.0, 1.0)
	head.position = Vector3(0, EYE + bob, _z)
	head.rotation.y = _yaw
	cam.rotation.x = _pitch
	if _state == "walk":
		_update_strike(dt)
		_update_wind(dt)
		_update_stalker(dt)
		if _state == "walk" and _z <= -length + 1.6:
			_arrive()
	# the candle shrinks to an ember as it comes close, and shudders in the wind
	var dim := clampf(_fear, 0.0, 1.0)
	candle.energy = CANDLE_ENERGY * lerpf(1.0, T.PASSAGE_CANDLE_DIM, dim) * (1.0 - 0.55 * _gust)
	candle.reach = CANDLE_REACH * lerpf(1.0, 0.45, dim)
	candle.tick(dt, clampf(maxf(_fear, _gust * 0.9), 0.0, 1.0))
	if not candle.lit:
		_out_time += dt
	if _fear > 0.35 and _state == "walk":
		_heart_wait -= dt
		if _heart_wait <= 0.0:
			_heart_wait = lerpf(1.1, 0.45, _fear)
			sfx.play("heartbeat", lerpf(-22.0, -4.0, _fear))
	if _state == "caught":
		var fwd := -cam.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		_figure.visible = true
		_figure.global_position = Vector3(cam.global_position.x, 0.0, cam.global_position.z) + fwd * 1.8
		_figure.rotation.y = atan2(-fwd.x, -fwd.z)
		_glow.position = cam.global_position + Vector3(0, 0.4, 0)
		_animate(dt, 0.0, false, clampf(_state_t * 3.0, 0.0, 1.0))
		_pitch = lerpf(_pitch, 0.55, 1.0 - exp(-10.0 * dt))      # your eyes go up to its face
		_rec.pitch_scale = maxf(0.25, 0.6 - _state_t * 0.15)     # the record drags
		if _state_t > 1.4:
			_fade_target = 1.0
		if _state_t > 2.5:
			get_tree().reload_current_scene()
	if _state == "done" and _state_t > 1.6:
		_go_to_church()
	_title.modulate.a = clampf(1.0 - (_time - 3.5) / 1.5, 0.0, 1.0)
	_hint.modulate.a = clampf(1.0 - (_time - 11.0) / 2.0, 0.0, 1.0)
	var show_prompt: bool = _state == "walk" and not candle.lit and _out_time > 1.2 and _strike <= 0.0
	_prompt.modulate.a = move_toward(_prompt.modulate.a, 0.85 if show_prompt else 0.0, dt * 2.0)
	_flash = move_toward(_flash, 0.0, dt * 1.5)
	_fade = move_toward(_fade, _fade_target, dt * 0.8)
	post.set_shader_parameter("fear", _fear)
	post.set_shader_parameter("flash", _flash)
	post.set_shader_parameter("fade", _fade)


func _caught() -> void:
	if _state != "walk":
		return
	_state = "caught"
	_state_t = 0.0
	_speed = 0.0
	_strike = 0.0
	_fear = 1.0
	_flash = 0.3
	_glow.light_energy = 0.7
	_eye_mat.albedo_color = EYE_COLOR * 1.6
	if _eyes:
		_eyes.visible = true
	_rec.volume_db = 0.0
	_rec_filter.cutoff_hz = 8000.0
	if _breath:
		_breath.volume_db = -60.0
	events.append("caught")
	sfx.play("demon_scream", 4.0)
	sfx.play("hit", 0.0)


func _arrive() -> void:
	_state = "done"
	_state_t = 0.0
	_fade_target = 1.0
	sfx.play("door_creak", -4.0)
	create_tween().tween_property(_rec, "volume_db", -80.0, 1.0)


func _go_to_church() -> void:
	set_process(false)
	Engine.set_meta("ira_seed", randi())
	get_tree().change_scene_to_file(GAME_SCENE)
