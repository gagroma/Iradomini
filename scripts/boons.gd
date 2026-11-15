extends RefCounted

const T = preload("res://scripts/tuning.gd")
const META := "ira_boons"
const MAX_STACK := 3

const POOL := {
	"ward": ["Blessed Medallion", "The first blow in each church only staggers you."],
	"chalk_max": ["Deep Pockets", "Carry 3 more metres of chalk."],
	"chalk_regen": ["Chalk Dust", "Your chalk grows back a third faster."],
	"stamina": ["Iron Lungs", "Run 2 seconds longer before you tire."],
	"breath": ["Second Wind", "Get your breath back half again as fast."],
	"quiet": ["Soft Soles", "Your footsteps carry a quarter less far."],
	"candle": ["Beeswax Candle", "Your candle burns half again as long."],
	"swift": ["Fleet Foot", "Walk and run a tenth faster."],
	"mend": ["Quick Mending", "Wounds close in half the time."],
	"reach": ["Long Arm", "Draw chalk almost a metre further away."],
}


static func all() -> Dictionary:
	return Engine.get_meta(META, {})


static func n(id: String) -> int:
	return all().get(id, 0)


static func add(id: String) -> void:
	var b = all().duplicate()
	b[id] = b.get(id, 0) + 1
	Engine.set_meta(META, b)


static func clear() -> void:
	if Engine.has_meta(META):
		Engine.remove_meta(META)


static func offer(count: int) -> Array:
	var ids := []
	for id in POOL:
		if n(id) < MAX_STACK:
			ids.append(id)
	ids.shuffle()
	return ids.slice(0, count)


static func chalk_max() -> float:
	return T.CHALK_MAX + 3.0 * n("chalk_max")


static func chalk_regen_time() -> float:
	return T.CHALK_REGEN_TIME * pow(0.67, n("chalk_regen"))


static func stamina_max() -> float:
	return T.STAMINA_MAX + 2.0 * n("stamina")


static func stamina_regen() -> float:
	return T.STAMINA_REGEN * (1.0 + 0.5 * n("breath"))


static func noise_scale() -> float:
	return pow(0.75, n("quiet"))


static func candle_burn_time() -> float:
	return T.CANDLE_BURN_TIME * (1.0 + 0.5 * n("candle"))


static func speed_scale() -> float:
	return 1.0 + 0.1 * n("swift")


static func critical_time() -> float:
	return T.CRITICAL_TIME * pow(0.5, n("mend"))


static func chalk_reach() -> float:
	return T.CHALK_REACH + 0.8 * n("reach")


static func wards() -> int:
	return n("ward")
