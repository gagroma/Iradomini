extends Node3D
# CANDLE - the candle you carry in your left hand, and (with held = false)
# every candle standing on the shelves, chapel tables and the altar.
#
# Sources:
#  - Model: assets/models/candle.glb, built in Blender by
#    tools/make_candle.py (brass chamberstick, wax with drips, melted top, wick).
#  - Flame: shaders/candle_flame.gdshader (glowing gas inside a small box).
#  - GDD: "the candle in your hand flickers harder the closer the demon is".
#
# What it does:
#  - The candle burns down. The top moves down, the drips below stay. When
#    the wax is gone the flame drowns in the last of it, sputters and goes out.
#  - Moving through the air is wind: the flame leans away from where you go,
#    shrinks, gets ragged and sheds sparks and soot. Running is the worst,
#    and it also makes the wax burn faster. Turning your head sweeps the
#    candle through the air too, so the flame whips and swings back.
#  - The demon nearby makes it shrink and shudder.
#  - The light follows the flame: smaller flame, dimmer and redder light.
#
# Standing candles (level.gd) do not burn down and start at different
# lengths. They burn in still air with a slow draft, shudder as the demon
# comes near, and blow_out() / relight() when it passes (level.gd decides).
#
# player.gd / level.gd call tick() every frame, after moving the candle.

const T = preload("res://scripts/tuning.gd")
const MODEL = preload("res://assets/models/candle.glb")
const FLAME_SHADER = preload("res://shaders/candle_flame.gdshader")
const WAX_SHADER = preload("res://shaders/candle_wax.gdshader")
const WICK_SHADER = preload("res://shaders/candle_wick.gdshader")
const BRASS_SHADER = preload("res://shaders/candle_brass.gdshader")

const WAX_FULL := 0.160     # model height of a fresh candle top (make_candle.py WAX_TOP)
const WAX_STUB := 0.037     # just above the socket lip: nothing left to burn
const FLAME_BASE := Vector3(0.0012, 0.0035, 0.0)   # flame base, from the melted top
const FLAME_HEIGHT := 0.03
const LIGHT_COLOR := Color(1.0, 0.64, 0.32)
const LIGHT_COLOR_LOW := Color(1.0, 0.42, 0.16)    # a small flame gives redder light
const WIND_PER_SPEED := 0.24   # how far the tip leans per m/s of movement (in flame heights)
const MAX_LEAN := 1.3
const MAX_PARTICLES := 64
const GUTTER_PART := 0.04      # the last 4% of the candle: the flame sputters

var energy := 2.2           # light energy of a calm, full flame
var reach := 7.5            # light range of a full flame, metres
var attenuation := 1.1
var held := true            # in your hand: lifted as it shortens
var burns := true           # false: the wax never gets shorter
var self_layer := 1 << 19  # render layer of this candle's own wax and brass: its own
							# lamp skips it (from 2 cm away it would burn them white)
							# and lights them in the shaders instead; other lamps
							# light it as usual. level.gd gives each candle its own.
var light_lift := 0.0       # lamp this far above the flame: a point light right in
							# the flame would burn the shelf under it to flat orange
var left := 1.0             # 1 = fresh candle, 0 = burnt out
var lit := true
var sfx                     # optional: plays "candle_out" when it dies
var light: OmniLight3D

var _cap: Node3D
var _wick: Node3D
var _wax_mat: ShaderMaterial
var _cap_mat: ShaderMaterial
var _wick_mat: ShaderMaterial
var _brass_mat: ShaderMaterial
var _flame_root: Node3D
var _flame_mat: ShaderMaterial

var _time := 0.0
var _prev := Vector3.ZERO
var _has_prev := false
var _vel := Vector3.ZERO    # smoothed speed of the flame through the air
var _lean := Vector2.ZERO
var _lean_v := Vector2.ZERO
var _size := 1.0
var _turb := 0.15
var _ember := 1.0
var _out_time := 0.0
var _noise := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()
var _hold_y := 0.0          # where the hand holds it when the candle is fresh

# soot and sparks: little squares that stay in the world while you walk on
var _parts := []
var _smoke_mm: MultiMesh
var _spark_mm: MultiMesh
var _smoke_acc := 0.0
var _spark_acc := 0.0


func _ready() -> void:
	_hold_y = position.y
	_rng.randomize()
	_noise.seed = _rng.randi()
	_noise.frequency = 1.0
	_noise.fractal_octaves = 2

	var model = MODEL.instantiate()
	add_child(model)
	var holder = model.find_child("Holder", true, false) as MeshInstance3D
	var wax = model.find_child("Wax", true, false) as MeshInstance3D
	var spill = model.find_child("Spill", true, false) as MeshInstance3D
	_cap = model.find_child("Cap", true, false)
	_wick = model.find_child("Wick", true, false)

	_brass_mat = ShaderMaterial.new()
	_brass_mat.shader = BRASS_SHADER
	holder.material_override = _brass_mat

	_wax_mat = _wax_material(WAX_FULL)
	wax.material_override = _wax_mat
	_cap_mat = _wax_material(0.0006)
	(_cap as MeshInstance3D).material_override = _cap_mat
	var spill_mat = _wax_material(0.0)
	spill_mat.set_shader_parameter("glow", 0.0)
	spill.material_override = spill_mat
	_wick_mat = ShaderMaterial.new()
	_wick_mat.shader = WICK_SHADER
	(_wick as MeshInstance3D).material_override = _wick_mat
	for m in [holder, wax, spill, _cap, _wick]:
		(m as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the candle gets its own flame light from its shaders, not from the lamp
	for m in [holder, wax, _cap, _wick]:
		(m as VisualInstance3D).layers = self_layer

	# the flame lives in world space, so it always burns upwards
	_flame_root = Node3D.new()
	_flame_root.top_level = true
	add_child(_flame_root)
	var box = BoxMesh.new()
	box.size = Vector3(0.1, 0.1, 0.1)
	var flame = MeshInstance3D.new()
	flame.mesh = box
	flame.position = Vector3(0.0, 0.025, 0.0)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flame_mat = ShaderMaterial.new()
	_flame_mat.shader = FLAME_SHADER
	_flame_mat.set_shader_parameter("wick_offset", Vector3(0.0, -0.025, 0.0))
	_flame_mat.set_shader_parameter("box_half", box.size * 0.5)
	_flame_mat.set_shader_parameter("height", FLAME_HEIGHT)
	_flame_mat.set_shader_parameter("seed", _rng.randf() * 10.0)
	flame.material_override = _flame_mat
	_flame_root.add_child(flame)

	light = OmniLight3D.new()
	light.top_level = true
	light.light_color = LIGHT_COLOR
	light.light_energy = energy
	light.omni_range = reach
	light.omni_attenuation = attenuation
	light.light_cull_mask = 0xFFFFF & ~self_layer
	add_child(light)

	_smoke_mm = _particle_layer(false)
	_spark_mm = _particle_layer(true)


func _wax_material(top: float) -> ShaderMaterial:
	var m = ShaderMaterial.new()
	m.shader = WAX_SHADER
	m.set_shader_parameter("top_y", top)
	return m


func _particle_layer(additive: bool) -> MultiMesh:
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var quad = QuadMesh.new()
	quad.size = Vector2.ONE
	mm.mesh = quad
	mm.instance_count = MAX_PARTICLES
	mm.visible_instance_count = 0
	var grad = Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var tex = GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 16
	tex.height = 16
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = tex
	var mmi = MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.top_level = true
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 16.0
	add_child(mmi)
	mmi.global_transform = Transform3D.IDENTITY
	return mm


# Called by player.gd every physics frame. fear: 0..1 from the demon.
func tick(dt: float, fear: float) -> void:
	if dt <= 0.0:
		return
	_time += dt

	# --- where the candle top is now ---
	var top = lerpf(WAX_STUB, WAX_FULL, clampf(left, 0.0, 1.0))
	_cap.position = Vector3(_cap.position.x, top, _cap.position.z)
	_wick.position = Vector3(_wick.position.x, top, _wick.position.z)
	# you lift a shorter candle higher, to keep the light in front of your eyes
	if held:
		position.y = _hold_y + (WAX_FULL - top) * 0.75
	_wax_mat.set_shader_parameter("cut_height", top - 0.0004)
	_wax_mat.set_shader_parameter("top_y", top)
	var base = _cap.global_transform * FLAME_BASE

	# --- wind: how fast the flame moves through the air ---
	if _has_prev:
		var v = (base - _prev) / dt
		if v.length() > 30.0:      # a teleport (restart), not a movement
			v = Vector3.ZERO
		_vel = _vel.lerp(v, 1.0 - exp(-12.0 * dt))
	_prev = base
	_has_prev = true
	var flat = Vector2(_vel.x, _vel.z)
	var wind = clampf(flat.length() / T.RUN_SPEED, 0.0, 1.5)

	# the tip leans away from the movement, on a spring: when you stop it
	# swings past upright and settles
	var target = -flat * WIND_PER_SPEED
	# a slow draft in the old building, even when nothing moves
	target += Vector2(_noise.get_noise_1d(_time * 0.6 + 300.0), _noise.get_noise_1d(_time * 0.5 + 700.0)) * 0.22
	if target.length() > MAX_LEAN:
		target = target.normalized() * MAX_LEAN
	var acc = (target - _lean) * 140.0 - _lean_v * 15.0
	_lean_v += acc * dt
	_lean += _lean_v * dt

	# --- burning down ---
	if lit and burns:
		left -= dt / T.CANDLE_BURN_TIME * (1.0 + T.CANDLE_WIND_BURN * minf(wind, 1.0))
		if left <= 0.0:
			left = 0.0
			_go_out(base)
	else:
		_out_time += dt
	var gutter = 0.0
	if lit and burns:
		gutter = 1.0 - smoothstep(0.0, GUTTER_PART, left)

	# --- flame size and flicker ---
	var restless = 0.05 + 0.45 * minf(wind, 1.2) + 0.6 * fear + 0.6 * gutter
	var flick = _noise.get_noise_1d(_time * 9.0) * 0.7 + _noise.get_noise_1d(_time * 23.0 + 50.0) * 0.3
	var want = 0.0
	if lit:
		want = (1.0 - 0.3 * minf(wind, 1.0)) * (1.0 - 0.3 * fear)
		if gutter > 0.0:
			# drowning in molten wax: it shrinks and gasps
			var gasp = absf(_noise.get_noise_1d(_time * 4.0 + 200.0))
			want *= lerpf(1.0, 0.25 + 0.9 * gasp, gutter)
	_size = lerpf(_size, want, 1.0 - exp(-(10.0 if lit else 25.0) * dt))
	var size_now = maxf(0.0, _size * (1.0 + 0.4 * restless * flick))
	var turb_want = 0.12 + 0.85 * minf(wind, 1.3) + 0.7 * fear + 0.9 * gutter
	_turb = lerpf(_turb, turb_want, 1.0 - exp(-6.0 * dt))

	_flame_root.global_transform = Transform3D(Basis.IDENTITY, base)
	_flame_root.visible = size_now > 0.01
	_flame_mat.set_shader_parameter("lean", _lean)
	_flame_mat.set_shader_parameter("size", size_now)
	_flame_mat.set_shader_parameter("turbulence", _turb)
	var flame_mid = base + Vector3(_lean.x * 0.3, 0.4, _lean.y * 0.3) * FLAME_HEIGHT * size_now
	for m in [_wax_mat, _cap_mat, _brass_mat]:
		m.set_shader_parameter("glow", clampf(size_now, 0.0, 1.2))
		m.set_shader_parameter("flame_world", flame_mid)

	# --- the light follows the flame ---
	var mid = base + Vector3(_lean.x * 0.35, 0.45, _lean.y * 0.35) * FLAME_HEIGHT * size_now
	light.global_position = mid + Vector3(0.0, light_lift, 0.0)
	var s = clampf(size_now, 0.0, 1.3)
	light.light_energy = energy * pow(s, 1.3)
	light.omni_range = reach * (0.33 + 0.67 * minf(s, 1.0))
	light.light_color = LIGHT_COLOR_LOW.lerp(LIGHT_COLOR, minf(s, 1.0))
	light.visible = s > 0.005

	# the wick tip glows while burning and cools down after
	_ember = 1.0 if lit else maxf(0.0, _ember - dt / 8.0)
	_wick_mat.set_shader_parameter("ember", _ember * (0.85 + 0.15 * flick))

	var tip = base + Vector3(_lean.x, 1.0, _lean.y) * FLAME_HEIGHT * maxf(size_now, 0.3)
	_update_particles(dt, base, tip, wind, gutter)


func _go_out(where: Vector3) -> void:
	lit = false
	_out_time = 0.0
	if sfx != null:
		sfx.play_at("candle_out", where, -6.0)


# Relight it (if any wax is left). The flame grows back from a spark.
func relight() -> void:
	if left > 0.0:
		lit = true
		_ember = 1.0


# Put out by a gust (the demon passing). Leaves a wisp of smoke.
func blow_out() -> void:
	if lit:
		lit = false
		_out_time = 0.0


# ---------------------------------------------------------------- soot, sparks

func _update_particles(dt: float, base: Vector3, tip: Vector3, wind: float, gutter: float) -> void:
	if lit:
		# a calm flame barely smokes; a disturbed or drowning one gives soot
		_smoke_acc += dt * (maxf(0.0, _turb - 0.4) * 16.0 + gutter * 12.0)
		_spark_acc += dt * maxf(0.0, wind - 0.5) * 9.0
	else:
		# the long wisp from a candle that just went out
		_smoke_acc += dt * (30.0 * exp(-_out_time * 0.9) + (2.0 if _out_time < 6.0 else 0.0))
	while _smoke_acc >= 1.0:
		_smoke_acc -= 1.0
		var from = tip if lit else base + Vector3(0.0, 0.009, 0.0)
		_spawn(from, false)
	while _spark_acc >= 1.0:
		_spark_acc -= 1.0
		_spawn(base.lerp(tip, _rng.randf_range(0.4, 1.0)), true)

	var keep := []
	for p in _parts:
		p["age"] += dt
		if p["age"] >= p["life"]:
			continue
		var v: Vector3 = p["vel"]
		if p["spark"]:
			v += Vector3(0.0, -0.6, 0.0) * dt
			v *= exp(-2.5 * dt)
		else:
			# warm soot rises, slows down and curls
			var curl = _noise.get_noise_2d(p["seed"], _time * 2.0)
			v += Vector3(curl * 0.25, 0.32, _noise.get_noise_2d(_time * 2.0, p["seed"]) * 0.25) * dt
			v *= exp(-1.8 * dt)
		p["vel"] = v
		p["pos"] += v * dt
		keep.append(p)
	_parts = keep

	var ns := 0
	var nk := 0
	for p in _parts:
		var k = p["age"] / p["life"]
		if p["spark"]:
			if nk >= MAX_PARTICLES:
				continue
			var sz = 0.0022 * (1.0 - k * 0.6)
			_spark_mm.set_instance_transform(nk, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * sz), p["pos"]))
			var c = Color(1.0, 0.78, 0.35).lerp(Color(0.9, 0.2, 0.04), k)
			c.a = 1.0 - k * k
			_spark_mm.set_instance_color(nk, c)
			nk += 1
		else:
			if ns >= MAX_PARTICLES:
				continue
			var sz = lerpf(0.004, 0.028, sqrt(k))
			_smoke_mm.set_instance_transform(ns, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * sz), p["pos"]))
			var a = smoothstep(0.0, 0.12, k) * (1.0 - k) * p["alpha"]
			_smoke_mm.set_instance_color(ns, Color(0.42, 0.4, 0.39, a))
			ns += 1
	_smoke_mm.visible_instance_count = ns
	_spark_mm.visible_instance_count = nk


func _spawn(at: Vector3, spark: bool) -> void:
	if _parts.size() >= MAX_PARTICLES * 2:
		return
	var v = Vector3(_rng.randf_range(-1, 1), 0.0, _rng.randf_range(-1, 1))
	var p = {
		"pos": at,
		"age": 0.0,
		"spark": spark,
		"seed": _rng.randf() * 100.0,
	}
	if spark:
		# flung off the tip, with some of the candle's own speed
		p["vel"] = v * 0.25 + Vector3(0.0, _rng.randf_range(0.15, 0.45), 0.0) + _vel * 0.25
		p["life"] = _rng.randf_range(0.25, 0.7)
	else:
		p["vel"] = v * 0.02 + Vector3(0.0, 0.06, 0.0) + _vel * 0.15
		p["life"] = _rng.randf_range(1.2, 2.4)
		p["alpha"] = _rng.randf_range(0.18, 0.35) if lit else _rng.randf_range(0.3, 0.5)
	_parts.append(p)
