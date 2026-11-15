extends Node

const PlayerScript = preload("res://scripts/player.gd")
const PrayerBook = preload("res://scripts/prayer_book.gd")
const UIStyle = preload("res://scripts/ui_style.gd")

const SPOTS := {
	"cross": Vector2(0.0, -0.22),
	"chalice": Vector2(-0.5, -0.04),
	"censer": Vector2(0.5, -0.04),
	"book": Vector2(0.0, 0.2),
}
const GRIP_Y := {"chalice": 0.12, "cross": 0.14, "censer": 0.43, "book": 0.016}
const HELD := Vector3(0.07, -0.3, -0.42)
const READ_POSE := Vector3(0.0, -0.15, -0.36)
const READ_TILT := 1.15
const WALK := 1.5
const RUSH_SPEED := 6.5
const LINES := [
	"Sancte Michael Archangele, defende nos in proelio;",
	"contra nequitiam et insidias diaboli esto praesidium.",
	"Imperet illi Deus, supplices deprecamur:",
	"tuque, Princeps militiae caelestis,",
	"Satanam aliosque spiritus malignos,",
	"qui ad perditionem animarum pervagantur in mundo,",
	"divina virtute, in infernum detrude.",
]
const LINE_TIME := 2.1

var main
var player
var relic: Dictionary
var praying := false

var _phase := ""
var _t := 0.0
var _route := []
var _spot := Transform3D.IDENTITY
var _front := Vector3.BACK
var _lateral := Vector3.RIGHT
var _altar := Vector3.ZERO
var _book: Node3D
var _book_relic: Dictionary
var _read_t := 0.0
var _line := -1
var _rush_at := 0.0
var _rush := []
var _strike_t := -1.0
var _amen := false
var _murmur: AudioStreamPlayer
var _subs: Label
var _canvas: CanvasLayer
var _flags := {}
var _turn_from := 0.0
var _turn_to := 0.0


static func spot_of(level, kind: String) -> Transform3D:
	var front: Vector3 = level.get("altar_front") if level.get("altar_front") != null else Vector3.BACK
	var lateral = front.cross(Vector3.UP)
	var s: Vector2 = SPOTS[kind]
	return Transform3D(Basis(lateral, Vector3.UP, -front), level.altar_top + lateral * s.x + front * s.y)


func place(main_node, r: Dictionary) -> void:
	_begin(main_node)
	relic = r
	_spot = spot_of(main.level, r["kind"])
	_plan_route(_spot.origin)
	_go("walk")


func pray(main_node) -> void:
	_begin(main_node)
	praying = true
	for r in main.relics:
		if r["kind"] == "book":
			_book_relic = r
	_spot = spot_of(main.level, "book")
	_plan_route(_spot.origin)
	_make_subtitles()
	_go("walk")


func _begin(main_node) -> void:
	main = main_node
	player = main.player
	_front = main.level.get("altar_front") if main.level.get("altar_front") != null else Vector3.BACK
	_lateral = _front.cross(Vector3.UP)
	_altar = Vector3(main.level.altar_pos.x, 0.0, main.level.altar_pos.y)
	player.frozen = true
	player.collision_mask = 0


func _plan_route(at: Vector3) -> void:
	var stand = _altar + _lateral * _lateral.dot(at - _altar) * 0.8 + _front * 0.9
	stand.y = 0.0
	var rel = player.position - _altar
	if rel.dot(_front) < 0.35:
		var side = 1.0 if rel.dot(_lateral) >= 0.0 else -1.0
		_route.append(_altar + _lateral * side * 1.45 + _front * maxf(rel.dot(_front), -0.2))
		_route.append(_altar + _lateral * side * 1.35 + _front * 0.75)
	_route.append(stand)


func _go(phase: String) -> void:
	_phase = phase
	_t = 0.0


func _ease(x: float) -> float:
	return smoothstep(0.0, 1.0, clampf(x, 0.0, 1.0))


func _hands() -> Transform3D:
	return player.hands.global_transform


func _to_hands(g: Transform3D) -> Transform3D:
	return _hands().affine_inverse() * g


func _rest() -> Transform3D:
	return Transform3D(Basis.from_euler(PlayerScript.RIGHT_REST_ROT), PlayerScript.RIGHT_REST)


func _low() -> Transform3D:
	return Transform3D(Basis.from_euler(PlayerScript.RIGHT_REST_ROT), PlayerScript.RIGHT_REST + Vector3(0.05, -0.4, 0.12))


func _right(pose: Transform3D) -> void:
	player.right_hand.visible = true
	player.right_override = pose


func _held_world(lift: float) -> Transform3D:
	var at = _hands() * (HELD + Vector3(0.0, -0.3, 0.1) * (1.0 - lift))
	return Transform3D(Basis(Vector3.UP, player.yaw), at)


func _hand_on(relic_world: Transform3D) -> Transform3D:
	var grip = relic_world.origin + Vector3.UP * GRIP_Y[relic["kind"]]
	return player.right_hand_at(_hands().affine_inverse() * grip)


func _once(key: String) -> bool:
	if _flags.has(key):
		return false
	_flags[key] = true
	return true


func _walk(dt: float, look: Vector3) -> bool:
	player.aim_at(look, 4.0, dt)
	if _route.is_empty():
		return true
	if player.walk_to(_route[0], WALK):
		_route.pop_front()
	return _route.is_empty()


func _physics_process(dt: float) -> void:
	if main == null:
		return
	if not player.alive:
		_abort()
		return
	_t += dt
	if praying:
		_pray_step(dt)
	else:
		_place_step(dt)


func _place_step(dt: float) -> void:
	var node: Node3D = relic["node"]
	match _phase:
		"walk":
			if _t < 0.4:
				_right(_rest().interpolate_with(_low(), _ease(_t / 0.4)))
			else:
				player.chalk_stick.visible = false
				_right(_low())
			if _walk(dt, _spot.origin) and _t >= 0.4:
				node.visible = true
				_go("raise")
		"raise":
			player.aim_at(_spot.origin, 4.0, dt)
			var g = _held_world(_ease(_t / 0.45))
			node.global_transform = g
			_right(_hand_on(g))
			if _t >= 0.45:
				_go("set")
		"set":
			player.aim_at(_spot.origin, 4.0, dt)
			var u = _ease(_t / 0.8)
			var g = _held_world(1.0).interpolate_with(_spot, u)
			g.origin.y += sin(PI * u) * 0.08
			node.global_transform = g
			_right(_hand_on(g))
			if _t >= 0.8:
				node.global_transform = _spot
				main.sfx.play_at("place", _spot.origin, -2.0)
				relic["light"].global_position = _spot.origin + Vector3(0.0, 0.35, 0.0) + _front * 0.2
				relic["light"].light_energy = 0.35
				relic["light"].visible = true
				_go("settle")
		"settle":
			_right(_hand_on(_spot))
			if _t >= 0.25:
				_go("back")
		"back":
			_right(_hand_on(_spot).interpolate_with(_low(), _ease(_t / 0.45)))
			if _t >= 0.45:
				player.chalk_stick.visible = true
				_go("rest")
		"rest":
			_right(_low().interpolate_with(_rest(), _ease(_t / 0.35)))
			if _t >= 0.35:
				_finish()


func _pray_step(dt: float) -> void:
	match _phase:
		"walk":
			if _t < 0.4:
				_right(_rest().interpolate_with(_low(), _ease(_t / 0.4)))
			else:
				player.chalk_stick.visible = false
				_right(_low())
			if _walk(dt, _spot.origin) and _t >= 0.4:
				_go("reach")
		"reach":
			player.aim_at(_spot.origin, 4.0, dt)
			_right(_low().interpolate_with(_hand_on_book(_book_on_altar()), _ease(_t / 0.55)))
			if _t >= 0.55:
				_book_relic["node"].visible = false
				_book_relic["light"].visible = false
				_book = PrayerBook.new()
				player.hands.add_child(_book)
				_go("lift")
		"lift":
			player.pitch_toward(-0.22, 3.0, dt)
			var u = _ease(_t / 0.8)
			var g = _book_on_altar().interpolate_with(_hands() * _read_pose(), u)
			g.origin.y += sin(PI * u) * 0.06
			_book.transform = _to_hands(g)
			_right(_hand_on_book(g))
			if _t >= 0.8:
				_go("open")
		"open":
			player.pitch_toward(-0.22, 3.0, dt)
			_hold_book(0.0)
			if _once("open"):
				main.sfx.play("book_open", -6.0)
			_book.opened = _ease(_t / 0.8)
			if _t >= 0.9:
				_start_reading()
				_go("read")
		"read":
			_read(dt)
		"vanish":
			_hold_book(0.0)
			if _t >= 1.0:
				_turn_from = player.yaw_target
				var to = _spot.origin - player.head.global_position
				_turn_to = _turn_from + wrapf(atan2(-to.x, -to.z) - _turn_from, -PI, PI)
				_go("turn_back")
		"turn_back":
			_hold_book(0.0)
			player.yaw_target = lerpf(_turn_from, _turn_to, _ease(_t / 1.3))
			player.pitch_toward(-0.22, 2.5, dt)
			if _t >= 1.3:
				_go("close")
		"close":
			_hold_book(0.0)
			_book.opened = 1.0 - _ease(_t / 0.6)
			if _t >= 0.55 and _once("shut"):
				main.sfx.play("book_close", -4.0)
			if _t >= 0.75:
				_go("lower")
		"lower":
			var u = _ease(_t / 0.7)
			_hold_book(u)
			if _t >= 0.7:
				_book.queue_free()
				_book = null
				player.right_hand.visible = false
				_go("sigh")
		"sigh":
			if _once("sigh"):
				main.sfx.play("sigh", -2.0)
			var k = sin(PI * clampf((_t - 0.8) / 1.4, 0.0, 1.0))
			player.pitch_target = -0.12 - 0.22 * k
			if _t >= 2.4:
				_go("done")
		"done":
			if _once("win"):
				main.show_win()


func _book_on_altar() -> Transform3D:
	var r: Transform3D = _book_relic["node"].global_transform
	return r * Transform3D(Basis.IDENTITY, Vector3(-PrayerBook.PAGE_W * 0.5, PrayerBook.COVER, 0.0))


func _read_pose() -> Transform3D:
	return Transform3D(Basis.from_euler(Vector3(READ_TILT, 0.0, 0.0)), READ_POSE)


func _hand_on_book(book_world: Transform3D) -> Transform3D:
	var grip = book_world * Vector3(PrayerBook.PAGE_W * 0.55, -0.02, PrayerBook.PAGE_H * 0.32)
	return player.right_hand_at(_hands().affine_inverse() * grip)


func _hold_book(down: float) -> void:
	var pose = _read_pose()
	pose.origin += Vector3(0.05, -0.4, 0.1) * down
	_book.transform = pose
	_right(_hand_on_book(_hands() * pose))


func _make_subtitles() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = 3
	main.add_child(_canvas)
	_subs = Label.new()
	_subs.position = Vector2(10, 232)
	_subs.size = Vector2(460, 30)
	_subs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subs.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIStyle.style_text(_subs, 11, UIStyle.BONE)
	_subs.modulate.a = 0.0
	_canvas.add_child(_subs)


func _show_line(text: String) -> void:
	_subs.text = text
	_subs.modulate.a = 0.0
	create_tween().tween_property(_subs, "modulate:a", 1.0, 0.35)


func _start_reading() -> void:
	_read_t = 0.0
	_line = -1
	if main.sfx.has("prayer_murmur"):
		_murmur = AudioStreamPlayer.new()
		_murmur.stream = main.sfx.streams["prayer_murmur"]
		_murmur.volume_db = -9.0
		main.add_child(_murmur)
		_murmur.play()
	var level = main.level
	var way: Vector2 = level.get("altar_way_in") if level.get("altar_way_in") != null else level.altar_pos + Vector2(_front.x, _front.z) * 6.0
	var out: Vector2 = level.get("altar_way_dir") if level.get("altar_way_dir") != null else Vector2(_front.x, _front.z)
	var me = player.pos2()
	var to_me = (me - way).normalized()
	_rush = [way + out * 3.0, way, me - to_me * 1.15]
	var length = _rush[0].distance_to(_rush[1]) + _rush[1].distance_to(_rush[2])
	var amen_at = LINES.size() * LINE_TIME
	_rush_at = maxf(LINE_TIME * 3.0, amen_at - (0.7 + length / RUSH_SPEED + 0.35))


func _read(dt: float) -> void:
	_read_t += dt
	_hold_book(0.0)
	var want = mini(int(_read_t / LINE_TIME), LINES.size() - 1)
	if want != _line:
		_line = want
		_show_line(LINES[_line])
	var demon = main.demon
	if _read_t >= _rush_at:
		if _once("appear"):
			demon.appear_at(_rush[0], _rush[1] - _rush[0])
			demon.scream_now()
			main.scripted_fear = 1.0
		var since = _read_t - _rush_at
		if since > 0.35:
			player.aim_at(demon.head_position() - Vector3(0, 0.4, 0), 3.0, dt, -0.2, 0.2)
		else:
			player.pitch_toward(-0.22, 3.0, dt)
		if since > 0.7 and _strike_t < 0.0:
			while _rush.size() > 1 and demon.pos2.distance_to(_rush[1]) < 0.05:
				_rush.pop_front()
			if _rush.size() > 1:
				demon.run_towards(_rush[1], RUSH_SPEED, dt)
			if _rush.size() <= 1 or demon.pos2.distance_to(_rush[-1]) < 0.05:
				_strike_t = 0.0
				demon.raise_claws()
				player.shake(0.3)
		if _strike_t >= 0.0:
			_strike_t += dt
			demon.face(player.pos2() - demon.pos2, dt)
			if _strike_t >= 0.3:
				_amen_now()
	else:
		player.pitch_toward(-0.22, 3.0, dt)


func _amen_now() -> void:
	_show_line("Amen.")
	main.demon.vanish()
	main.scripted_fear = 0.0
	main.flash(0.9)
	main.sfx.play("banish", 0.0)
	main.sfx.play("ending", -4.0)
	player.shake(0.5)
	main.chalk.close_decor()
	if _murmur != null:
		create_tween().tween_property(_murmur, "volume_db", -60.0, 0.6)
	create_tween().tween_property(_subs, "modulate:a", 0.0, 1.2).set_delay(1.4)
	_go("vanish")


func _abort() -> void:
	if not praying and relic.has("node"):
		relic["node"].global_transform = _spot
		relic["node"].visible = true
	player.chalk_stick.visible = true
	player.right_override = null
	player.auto_move = Vector3.ZERO
	player.collision_mask = 1
	if _murmur != null:
		_murmur.queue_free()
	if _canvas != null:
		_canvas.queue_free()
	main = null
	queue_free()


func _finish() -> void:
	player.right_override = null
	player.right_hand.visible = true
	player.chalk_stick.visible = true
	player.auto_move = Vector3.ZERO
	player.collision_mask = 1
	player.frozen = false
	var m = main
	main = null
	m.altar_done()
	queue_free()
