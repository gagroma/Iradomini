extends OmniLight3D
## Makes a candle light breathe and flicker. Each light gets its own random phase.

@export var flicker_amount := 0.18
@export var speed := 1.0

var _base_energy := 1.0
var _base_range := 1.0
var _t := 0.0


func _ready() -> void:
	_base_energy = light_energy
	_base_range = omni_range
	_t = randf() * 100.0


func _process(delta: float) -> void:
	_t += delta * speed
	var n := sin(_t * 7.3) * 0.5 + sin(_t * 13.1 + 1.7) * 0.3 + sin(_t * 23.7 + 4.1) * 0.2
	light_energy = _base_energy * (1.0 + n * flicker_amount)
	omni_range = _base_range * (1.0 + n * flicker_amount * 0.15)
