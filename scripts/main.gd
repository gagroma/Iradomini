extends Node3D
# MAIN - starts the game and connects the parts.
#   level.gd  builds the cathedral        chalk.gd  drawing and THE RULE
#   player.gd you                         demon.gd  it
#   hud.gd    words on screen             sfx.gd    sound
#   tuning.gd every number from the GDD - change numbers there first
#
# Sources: GDD v6 ("Gnev Gospoden" / "Mel i Sol") for all rules; the fear
# effects follow its "Kamera i oshchushchenie" section; the look is PS1 low
# resolution (480x270, see project settings) plus the pixel-splat models.
#
# Extra keys for testing: R = restart with a new level, F3 = debug numbers,
# F4 = lights on / fog off, F11 = full screen, Esc = pause.

const T = preload("res://scripts/tuning.gd")
const Boons = preload("res://scripts/boons.gd")
const Level = preload("res://scripts/level.gd")
const RoomLevel = preload("res://scripts/room_level.gd")
const Chalk = preload("res://scripts/chalk.gd")
const Player = preload("res://scripts/player.gd")
const Demon = preload("res://scripts/demon.gd")
const Hud = preload("res://scripts/hud.gd")
const Sfx = preload("res://scripts/sfx.gd")
const Models = preload("res://scripts/models.gd")
const PauseMenu = preload("res://scripts/pause_menu.gd")
const WinScreen = preload("res://scripts/win_screen.gd")
const BlessingScreen = preload("res://scripts/blessing_screen.gd")
const AltarScene = preload("res://scripts/altar_scene.gd")
const DeathScene = preload("res://scripts/death_scene.gd")
const DoorIntro = preload("res://scripts/door_intro.gd")
const Warmup = preload("res://scripts/warmup.gd")
const WardrobeHide = preload("res://scripts/wardrobe_hide.gd")
const TITLE_SCENE := "res://menu.tscn"
const INTERACTION_AIM_DOT := 0.95
const USE_ROOM_LEVEL := T.ROOM_LEVEL and not T.CATHEDRAL_SCENARIO
const POST_SHADER = preload("res://shaders/post.gdshader")

const RELIC_NAMES = {"chalice": "Chalice", "cross": "Cross", "censer": "Censer", "book": "Prayer Book"}

var level
var chalk
var player
var demon
var demons := []
var level_no := 1
var hud
var sfx
var post: ShaderMaterial

var game_state := "play"        # "play", "dead", "prayer" or "won"
var fear := 0.0                 # 0..1 from how close the demon is
var _hide := 0.0                # 0..1 screen effect while you hide
var _alert := 0.0               # 0..1 red edge while the demon sees you
var relics := []                # {"node", "light", "pos", "kind", "taken", "chapel"}
var carried := 0                # relics in your hands
var placed := 0                 # relics already on the altar
var candle_intro := false
var intro := false

var _seed := 0
var _time := 0.0
var _flash := 0.0
var _fade := 1.0
var _fade_target := 0.0
var _hurt := 0.0
var _heart_wait := 0.0
var _door_done := false
var _clatter_done := false
var _clatter_wait := -1.0
var _clatter_pos := Vector3.ZERO
var _debug := false
var _drone = null
var _choir = null
var _circle_hint_done := false
var _env: Environment
var _bright := false
var _interaction_target: Variant
var _pause_menu: PauseMenu
var _win: WinScreen
var _blessings: BlessingScreen
var wardrobes := []
var hiding = null
var altar_busy := false
var scripted_fear := -1.0
const PLACE_ORDER := ["cross", "chalice", "censer", "book"]
var _intro = null


func _ready() -> void:
	# Sample interaction targets after the player's camera has moved this tick.
	process_physics_priority = 1
	# The seed decides the level layout. It is kept in the Engine object so it
	# survives a scene reload; a new one is rolled after every death (GDD).
	if not Engine.has_meta("ira_seed"):
		randomize()
		Engine.set_meta("ira_seed", randi())
	_seed = Engine.get_meta("ira_seed")

	sfx = Sfx.new()
	add_child(sfx)
	_make_environment()

	level_no = clampi(Engine.get_meta("ira_level", 1), 1, T.LEVELS)
	level = RoomLevel.new() if USE_ROOM_LEVEL else Level.new()
	level.extra_rooms = T.LEVEL_EXTRA_ROOMS[level_no - 1]
	level.relic_hardness = float(level_no - 1) / float(T.LEVELS - 1)
	add_child(level)
	if USE_ROOM_LEVEL:
		level.build(_seed)
	else:
		level.build(_seed, T.CATHEDRAL_SCENARIO)

	chalk = Chalk.new()
	add_child(chalk)
	chalk.setup(level.nav)
	chalk.add_permanent(level.narthex_poly)
	chalk.add_decor(level.altar_circle, T.CATHEDRAL_SCENARIO)
	chalk.loop_closed.connect(_on_loop_closed)
	chalk.stroke_burned.connect(_on_stroke_burned)

	player = Player.new()
	add_child(player)
	player.setup(self)
	player.position = level.player_start
	if "player_yaw" in level:
		player.yaw = level.player_yaw
		player.yaw_target = level.player_yaw
		player.rotation.y = level.player_yaw
	if level.get("entrance_leaf") != null:
		_intro = DoorIntro.new()
		add_child(_intro)
		_intro.setup(self)
		intro = true
		_door_done = true

	var count: int = T.LEVEL_DEMONS[level_no - 1]
	for i in count:
		var d = Demon.new()
		add_child(d)
		demons.append(d)
		d.setup(self, i, count)
		if not T.DEMON_ENABLED:
			d.switch_off()
	demon = demons[0]

	_make_post()
	hud = Hud.new()
	add_child(hud)
	hud.setup()
	_spawn_relics()
	for n in level.find_children("*", "Node3D", true, false):
		if n.scene_file_path.ends_with("wardrobe.glb") and n.is_visible_in_tree():
			wardrobes.append(n)
	_pause_menu = PauseMenu.new()
	add_child(_pause_menu)
	_pause_menu.resume_requested.connect(_resume)
	_pause_menu.restart_requested.connect(_restart.bind(false))
	_pause_menu.title_requested.connect(_return_to_title)
	_win = WinScreen.new()
	add_child(_win)
	_win.again_requested.connect(_after_win)
	_win.title_requested.connect(_return_to_title)
	_blessings = BlessingScreen.new()
	_blessings.sfx = sfx
	add_child(_blessings)
	_blessings.picked.connect(_after_win)

	_drone = sfx.loop("drone", -30.0 if candle_intro else -13.0)
	_choir = sfx.loop("choir_rev", -60.0)
	if candle_intro or intro:
		player.frozen = true
		hud.hide()
	if candle_intro:
		player.candle.tick(1.0 / 60.0, 0.0)
		_fade = 0.0
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if intro:
			_intro.play()
	var warm = Warmup.new()
	add_child(warm)
	warm.run(self)


func candle_flame_uv() -> Vector2:
	return player.cam.unproject_position(player.candle.flame_center()) / get_viewport().get_visible_rect().size


func finish_candle_intro() -> void:
	candle_intro = false
	if _drone != null:
		create_tween().tween_property(_drone, "volume_db", -13.0, 0.65)
	if intro:
		_intro.play()
	else:
		end_intro()


func end_intro() -> void:
	intro = false
	_intro = null
	player.frozen = false
	hud.show()
	if T.CATHEDRAL_SCENARIO:
		hud.show_note("Level %d of %d  ·  Find the altar, then seek four relics in the side passages." % [level_no, T.LEVELS], 8.0)
	else:
		hud.show_note("Level %d of %d" % [level_no, T.LEVELS], 5.0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# GDD "Vizualnyi stil": thick fog, two light colours (cold moon, warm candles).
func _make_environment() -> void:
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.012, 0.014, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.36, 0.56)
	env.ambient_light_energy = 0.7
	env.fog_enabled = true
	env.fog_light_color = Color(0.02, 0.025, 0.05)
	env.fog_density = 0.055
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	if T.ROOM_LEVEL:
		# the room levels' look: a dark purplish night (violet moon, rosy candles, purple haze)
		env.background_color = Color(0.018, 0.006, 0.03)
		env.ambient_light_color = Color(0.4, 0.26, 0.6)
		env.ambient_light_energy = 0.6
		env.fog_light_color = Color(0.035, 0.014, 0.06)
		env.fog_density = 0.06
		env.glow_enabled = true
		env.glow_intensity = 0.6
		env.glow_bloom = 0.03
	if T.CATHEDRAL_SCENARIO:
		env.fog_density = 0.031
	_env = env
	var world = WorldEnvironment.new()
	world.environment = env
	add_child(world)


# One full-screen rectangle that runs post.gdshader over the finished picture.
func _make_post() -> void:
	var canvas = CanvasLayer.new()
	canvas.layer = 1
	add_child(canvas)
	var rect = ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(rect)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	post = ShaderMaterial.new()
	post.shader = POST_SHADER
	rect.material = post


func _spawn_relics() -> void:
	for spot in level.relic_spots:
		var node = Models.relic(spot["kind"])
		node.position = spot["pos"]
		add_child(node)
		var light = OmniLight3D.new()
		light.position = spot["pos"] + Vector3(0.0, 0.3, 0.0)
		light.light_color = Color(1.0, 0.85, 0.5)
		light.light_energy = lerpf(0.5, 0.14, level.relic_hardness)
		light.omni_range = lerpf(2.2, 1.1, level.relic_hardness)
		add_child(light)
		relics.append({
			"node": node,
			"light": light,
			"pos": spot["pos"],
			"kind": spot["kind"],
			"chapel": spot["chapel"],
			"taken": false,
			"placed": false,
		})


# ------------------------------------------------------------------- INPUT

func _unhandled_input(event: InputEvent) -> void:
	if candle_intro or intro:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_E:
			_interact()
		elif event.physical_keycode == KEY_R and game_state == "play":
			_restart()
		elif event.physical_keycode == KEY_F3:
			_debug = not _debug
		elif event.physical_keycode == KEY_F4:
			# test helper: lights on, fog off - to look at the level itself
			_bright = not _bright
			_env.ambient_light_energy = 3.0 if _bright else 0.7
			_env.fog_enabled = not _bright
		elif event.physical_keycode == KEY_F11:
			GameSettings.set_fullscreen(not GameSettings.fullscreen)
			GameSettings.save_settings()
		elif event.physical_keycode == KEY_ESCAPE:
			if game_state == "play":
				get_viewport().set_input_as_handled()
				_pause()


func _pause() -> void:
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.hide()
	_pause_menu.open()


func _resume() -> void:
	_pause_menu.hide()
	hud.show()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().paused = false


func _physics_process(_dt: float) -> void:
	_interaction_target = _find_target()


# What would E do right now? Returns a Dictionary, or null for "nothing".
func _find_target() -> Variant:
	if candle_intro or intro or altar_busy or hiding != null or game_state != "play" or not player.alive:
		return null
	var eye = player.cam.global_position
	var forward = -player.cam.global_transform.basis.z
	var pp = player.pos2()
	var best = null
	var best_d = 2.3
	for r in relics:
		if r["taken"]:
			continue
		var flat = Vector2(r["pos"].x, r["pos"].z).distance_to(pp)
		var to = (r["pos"] - eye).normalized()
		if flat < best_d and forward.dot(to) > INTERACTION_AIM_DOT and _can_see_target(eye, r["pos"]):
			best = r
			best_d = flat
	if best != null:
		return {"type": "relic", "relic": best}
	for w in wardrobes:
		var front: Vector3 = w.global_basis.z
		var door = w.global_position + Vector3(front.x, 0.0, front.z).normalized() * 0.45
		if pp.distance_to(Vector2(door.x, door.z)) < 1.5:
			var to_w: Vector3 = (w.global_position + Vector3(0.0, 1.2, 0.0) - eye).normalized()
			if forward.dot(to_w) > 0.9 and front.dot(Vector3(eye.x - w.global_position.x, 0.0, eye.z - w.global_position.z)) > 0.0:
				return {"type": "wardrobe", "w": w}
	var can_pray = placed >= T.RELICS_NEEDED
	if (carried > 0 or can_pray) and pp.distance_to(level.altar_pos) < 2.7:
		var to_altar: Vector3 = (level.altar_top - eye).normalized()
		if forward.dot(to_altar) > INTERACTION_AIM_DOT and _can_see_target(eye, level.altar_top):
			return {"type": "altar" if carried > 0 else "pray"}
	return null


func _can_see_target(eye: Vector3, point: Vector3) -> bool:
	# The target origins sit on their pedestals.
	var ray := PhysicsRayQueryParameters3D.create(eye, point + Vector3.UP * 0.08, player.collision_mask)
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()


func _interact() -> void:
	if hiding != null:
		hiding.leave()
		return
	if game_state != "play" or not player.alive or _interaction_target == null:
		return
	var target = _interaction_target
	_interaction_target = null
	if target["type"] == "relic":
		_take_relic(target["relic"])
	elif target["type"] == "altar":
		_place_next()
	elif target["type"] == "wardrobe":
		hiding = WardrobeHide.new()
		add_child(hiding)
		hiding.start(self, target["w"])
	else:
		_begin_prayer()


func _take_relic(r: Dictionary) -> void:
	r["taken"] = true
	r["node"].visible = false
	r["light"].visible = false
	carried += 1
	# GDD: every relic you pick up makes your steps louder ("the relics whisper")
	player.relics_found = carried + placed
	sfx.play("pickup", -6.0)
	hud.show_note("%s  (%d/%d)  ·  Your steps grow louder" % [RELIC_NAMES[r["kind"]], carried + placed, T.RELICS_NEEDED])
	# GDD key moment 3: in a chapel a candlestick falls and the demon comes running
	if r["chapel"] and not _clatter_done:
		_clatter_done = true
		_clatter_wait = 0.7
		_clatter_pos = r["pos"]


# GDD "Final": each relic goes to its own place on the altar, one at a time.
func _next_relic() -> Variant:
	for kind in PLACE_ORDER:
		for r in relics:
			if r["kind"] == kind and r["taken"] and not r["placed"]:
				return r
	return null


func _place_next() -> void:
	var r = _next_relic()
	if r == null:
		return
	r["placed"] = true
	carried -= 1
	placed += 1
	altar_busy = true
	var scene = AltarScene.new()
	add_child(scene)
	scene.place(self, r)


func altar_done() -> void:
	altar_busy = false
	if T.CATHEDRAL_SCENARIO:
		level.advance_ritual(placed)
		chalk.show_altar_progress(placed)
	if placed >= T.RELICS_NEEDED:
		hud.show_note("All relics are in place  ·  Read the prayer", 5.0)
		if T.CATHEDRAL_SCENARIO:
			var front: Vector3 = level.altar_front
			hear_all(level.altar_pos + Vector2(front.x, front.z) * 3.8, 200.0)
		return
	hud.show_note("Relics on the altar  %d/%d" % [placed, T.RELICS_NEEDED])


func _begin_prayer() -> void:
	altar_busy = true
	game_state = "prayer"
	chalk.release()
	hud.hide()
	for d in demons:
		if d.is_active():
			d.fade_away()
	var scene = AltarScene.new()
	add_child(scene)
	scene.pray(self)


func show_win() -> void:
	game_state = "won"
	hud.hide()
	if level_no < T.LEVELS:
		_blessings.reveal(level_no, T.LEVELS)
	else:
		_win.reveal()


func _after_win(pick := "") -> void:
	if level_no < T.LEVELS:
		if pick != "":
			Boons.add(pick)
		Engine.set_meta("ira_level", level_no + 1)
	else:
		Boons.clear()
		Engine.set_meta("ira_level", 1)
	_restart()


func on_ward_broken() -> void:
	_flash = 0.6
	sfx.play("hit", -2.0, 1.3)
	sfx.play("banish", -10.0, 1.5)
	var left: int = player.wards
	hud.show_note("The medallion takes the blow" + ("" if left == 0 else "  ·  %d left" % left), 4.0)


func hear_all(at: Vector2, radius: float) -> bool:
	var heard := false
	for d in demons:
		if d.hear(at, radius):
			heard = true
	return heard


func nearest_demon():
	var best = demons[0]
	for d in demons:
		if d.is_active() and (not best.is_active() or d.distance_to_player() < best.distance_to_player()):
			best = d
	return best


func flash(amount: float) -> void:
	_flash = maxf(_flash, amount)


func wardrobe_done() -> void:
	hiding = null


func _prompt_text(target: Variant) -> String:
	if hiding != null:
		return "E  ·  Leave the wardrobe" if hiding.is_inside() else ""
	if target != null:
		if target["type"] == "wardrobe":
			return "E  ·  Hide in the wardrobe"
		if target["type"] == "relic":
			return "E  ·  Take " + RELIC_NAMES[target["relic"]["kind"]]
		if target["type"] == "pray":
			return "E  ·  Read the prayer"
		var next = _next_relic()
		return "E  ·  Place the " + RELIC_NAMES[next["kind"]] if next != null else ""
	if game_state == "play" and player.aim_valid and not player.drawing:
		if chalk.loop_at(player.aim_point) != null:
			return "Hold RMB  ·  Erase circle"
	return ""


# ------------------------------------------------- CALLED BY PLAYER / DEMON

# One footstep. GDD "Vospriyatie": step 2 m, run 10 m, more with every relic.
func player_step(running: bool, crouching: bool) -> void:
	var radius = (T.NOISE_STEP + T.NOISE_PER_RELIC_STEP * player.relics_found) * Boons.noise_scale()
	var volume = -20.0
	if running:
		radius = (T.NOISE_RUN + T.NOISE_PER_RELIC_RUN * player.relics_found) * Boons.noise_scale()
		volume = -9.0
	elif crouching:
		radius = T.NOISE_CROUCH
		volume = -30.0
	sfx.play("step1" if randf() < 0.5 else "step2", volume, randf_range(0.9, 1.1))
	var heard = hear_all(player.pos2(), radius)
	# arcs on screen: crouch 1, walk 2, run 4, a relic or two more
	hud.stealth.step(clampi(int(round(sqrt(radius) * 1.25)), 1, 5), heard)


func on_player_hit() -> void:
	_flash = 0.9
	sfx.play("hit", 2.0)
	hud.show_note("WOUNDED  ·  The next hit will kill you", 5.0)


func on_player_died() -> void:
	game_state = "dead"
	sfx.play("hit", 3.0)
	sfx.play("demon_scream", 6.0, 0.85)
	var death = DeathScene.new()
	add_child(death)
	death.start(self)


func on_banished(loop) -> void:
	chalk.on_banish(loop)
	_flash = 0.7
	sfx.play("banish", 0.0)
	player.shake(0.4)
	hud.show_note("Demon banished  ·  Hold RMB to erase the circle and recover chalk", 6.0)


func on_demon_returned() -> void:
	sfx.play("demon_notice", -12.0, 0.7)    # a far-off warning that it is back
	hud.show_note("It has returned", 3.0)


func on_demon_scream(distance: float) -> void:
	fear = maxf(fear, 0.8)
	# the scream shakes the world: hard up close, a tremor from across the church
	var near = clampf(1.0 - distance / 16.0, 0.0, 1.0)
	player.shake(0.15 + 0.75 * near)


func _on_loop_closed(_loop) -> void:
	if not _circle_hint_done:
		_circle_hint_done = true
		hud.show_note("Circle sealed  ·  Hold RMB to recover chalk", 5.0)


func _on_stroke_burned() -> void:
	sfx.play("burn", -14.0)


# ------------------------------------------------------------------ ENDING

func _restart(new_seed := true) -> void:
	if new_seed:
		Engine.set_meta("ira_seed", randi())
	get_tree().paused = false
	get_tree().reload_current_scene()


func _return_to_title() -> void:
	var tree := get_tree()
	var result := tree.change_scene_to_file(TITLE_SCENE)
	if result == OK:
		tree.paused = false
		Engine.remove_meta("ira_seed")
		if Engine.has_meta("ira_level"):
			Engine.remove_meta("ira_level")
		Boons.clear()
	else:
		push_error("Could not return to the title (%s)." % error_string(result))


# ----------------------------------------------------------------- EVERY FRAME

func _process(dt: float) -> void:
	_time += dt

	# GDD: effects grow from 0 to 1 with how close the demon is
	var target_fear = 0.0
	var closest = nearest_demon()
	if closest.is_active() and game_state == "play":
		target_fear = clampf(1.0 - closest.distance_to_player() / T.FEAR_DISTANCE, 0.0, 1.0)
	if scripted_fear >= 0.0:
		target_fear = scripted_fear
	fear = lerpf(fear, target_fear, 1.0 - exp(-3.0 * dt))
	player.fear = fear
	chalk.jitter = fear

	# the first scripted moment: the door slams, the demon comes to look,
	# walks into the salt line and learns you the rule without a word
	if not _door_done and _time > 2.5:
		_door_done = true
		sfx.play_at("door_slam", level.door_pos, 4.0)
		hear_all(Vector2(level.door_pos.x, level.door_pos.z) if USE_ROOM_LEVEL else Vector2(0.0, 1.0), 200.0)

	if _clatter_wait > 0.0:
		_clatter_wait -= dt
		if _clatter_wait <= 0.0:
			sfx.play_at("clatter", _clatter_pos, 4.0)
			hear_all(Vector2(_clatter_pos.x, _clatter_pos.z), 200.0)

	# GDD "Serdtsebienie": louder and faster with fear
	var beat = fear
	if player.critical:
		beat = maxf(beat, 0.6)
	if beat > 0.08 and game_state == "play":
		_heart_wait -= dt
		if _heart_wait <= 0.0:
			_heart_wait = lerpf(1.15, 0.42, beat)
			sfx.play("heartbeat", lerpf(-20.0, -3.0, beat), lerpf(0.9, 1.15, beat))

	# GDD: a quiet reversed choir in the crossing
	if _choir != null:
		var in_crossing = level.crossing_rect.has_point(player.pos2())
		var want = -19.0 if in_crossing else -60.0
		_choir.volume_db = lerpf(_choir.volume_db, want, 1.0 - exp(-1.2 * dt))

	var prowling := PackedVector2Array()
	for d in demons:
		if d.is_active():
			prowling.append(d.pos2)
	level.update_candles(prowling, dt, sfx, player.pos2())

	# screen effects
	_flash = move_toward(_flash, 0.0, dt * 1.6)
	_fade = move_toward(_fade, _fade_target, dt * 0.7)
	_hurt = lerpf(_hurt, 1.0 if player.critical else 0.0, 1.0 - exp(-5.0 * dt))
	post.set_shader_parameter("fear", fear)
	post.set_shader_parameter("hurt", _hurt)
	post.set_shader_parameter("flash", _flash)
	post.set_shader_parameter("fade", _fade)
	# hiding narrows and cools the view; being seen puts a red edge round it
	var playing = game_state == "play"
	_hide = lerpf(_hide, 1.0 if player.is_hidden_now and playing else 0.0, 1.0 - exp(-6.0 * dt))
	var aware = 0
	if playing:
		for d in demons:
			if d.is_active():
				aware = maxi(aware, d.awareness())
	_alert = lerpf(_alert, 1.0 if aware == 2 else 0.0, 1.0 - exp(-4.0 * dt))
	post.set_shader_parameter("hide", _hide)
	post.set_shader_parameter("alert", _alert)
	hud.stealth.set_state(aware, player.crouching and playing, player.is_hidden_now and playing)
	hud.stealth.set_stamina(player.stamina / Boons.stamina_max(), player.winded)
	hud.set_chalk_supply(chalk.chalk, playing)

	# words on screen
	hud.set_prompt(_prompt_text(_interaction_target) if playing else "")
	hud.update_reticle(playing, player.aim_valid, _interaction_target != null, player.erase_progress, dt)
	var words = "Level %d/%d  ·  Relics %d/%d" % [level_no, T.LEVELS, carried + placed, T.RELICS_NEEDED]
	if player.critical:
		words += "  ·  WOUNDED %d" % int(ceil(player.critical_time))
	if game_state != "play":
		words = ""
	hud.set_status(words)
	hud.set_debug(_debug, _debug_text())


func _debug_text() -> String:
	if not _debug:
		return ""
	var lines = []
	lines.append("fps %d   seed %d" % [Engine.get_frames_per_second(), _seed])
	var closest = nearest_demon()
	lines.append("level %d  demons %d" % [level_no, demons.size()])
	lines.append("demon %s  %.1f m" % [closest.state_name(), closest.distance_to_player()])
	lines.append("sees you: %s" % str(closest.sees_player))
	lines.append("chalk %.1f m  (+%.1f on floor)" % [chalk.chalk, chalk.locked()])
	lines.append("circles %d   line %.1f m" % [chalk.loops.size() - 1, chalk.stroke_len])
	lines.append("fear %.2f   hidden %s" % [fear, str(player.is_hidden_now)])
	return "\n".join(lines)
