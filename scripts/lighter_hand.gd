extends Node3D

const Lighter = preload("res://scripts/lighter.gd")
const Models = preload("res://scripts/models.gd")
const HAND_RIGHT = preload("res://assets/models/hand_right.glb")
const REST := Vector3(0.2, -0.15, -0.33)
const REST_ROT := Vector3(-0.5, 0.3, 0.0)
const SHOULDER := Vector3(0.3, -0.4, 0.2)
const FINGERTIPS := Vector3(0.0, -0.005, -0.035)
const ROLL := 0.45
const PUT_AWAY := 0.85

var sfx
var wick := Vector3(-0.2, -0.04, -0.39)

var _hand: Node3D
var _lighter: Node3D
var _away_t := -1.0
var _struck := false
var _clicked := false


func _ready() -> void:
	_hand = Node3D.new()
	add_child(_hand)
	var mat := ShaderMaterial.new()
	mat.shader = Models.VCOLOR_SHADER
	mat.set_shader_parameter("snap", false)
	mat.set_shader_parameter("roughness", 0.7)
	var model: Node3D = HAND_RIGHT.instantiate()
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hand.add_child(model)
	_lighter = Lighter.new()
	_hand.add_child(_lighter)
	visible = false


func _ease(x: float) -> float:
	return smoothstep(0.0, 1.0, clampf(x, 0.0, 1.0))


func _low() -> Transform3D:
	return Transform3D(Basis.from_euler(REST_ROT), REST + Vector3(0.05, -0.4, 0.12))


func _hand_at(grip: Vector3) -> Transform3D:
	var z := (SHOULDER - grip).normalized()
	var x := Vector3.UP.cross(z).normalized()
	var b := Basis(x, z.cross(x), z) * Basis.from_euler(Vector3(0.35, 0.0, 0.25))
	return Transform3D(b, grip - b * FINGERTIPS)


func _pose(away: float) -> Transform3D:
	var parent_xf: Transform3D = (get_parent() as Node3D).global_transform
	var fwd := -parent_xf.basis.z
	fwd.y = 0.0
	var face := Basis(Vector3.UP, atan2(-fwd.x, -fwd.z))
	var w: Vector3 = parent_xf * wick
	var target := w + face.x * 0.016 + Vector3.UP * 0.003 + face.z * 0.004
	target += (face.x * 0.07 + Vector3.UP * -0.06 + face.z * 0.03) * away
	var basis := face * Basis(Vector3(0, 0, 1), ROLL * (1.0 - away * 0.6))
	var lighter_local := parent_xf.affine_inverse() * Transform3D(basis, target - basis * Lighter.FLAME_AT)
	var hand := _hand_at(lighter_local.origin + lighter_local.basis * Vector3(0.0, 0.025, 0.0))
	_lighter.transform = hand.affine_inverse() * lighter_local
	return hand


# u: 0..1 through the strike. The flame catches at 0.5, reaches the wick by 0.78.
func strike_progress(u: float) -> void:
	_away_t = -1.0
	visible = true
	if u < 0.05:
		_struck = false
		_clicked = false
		_lighter.snuff()
	_lighter.opened = _ease((u - 0.12) / 0.14)
	if u >= 0.5 and not _struck:
		_struck = true
		_lighter.strike()
	var pose: Transform3D
	if u < 0.28:
		pose = _low().interpolate_with(_pose(1.0), _ease(u / 0.28))
	elif u < 0.5:
		pose = _pose(1.0)
		if u > 0.44:
			pose.origin.y -= 0.006 * sin(PI * (u - 0.44) / 0.06)
	else:
		pose = _pose(1.0 - _ease((u - 0.5) / 0.28))
	_hand.transform = pose


func put_away() -> void:
	if visible and _away_t < 0.0:
		_away_t = 0.0


func cancel() -> void:
	visible = false
	_away_t = -1.0
	_lighter.snuff()
	_lighter.opened = 0.0


func _process(dt: float) -> void:
	if _away_t < 0.0:
		return
	_away_t += dt / PUT_AWAY
	var r := _away_t
	if r > 0.08:
		_lighter.snuff()
	_lighter.opened = 1.0 - _ease((r - 0.14) / 0.12)
	if r > 0.24 and not _clicked:
		_clicked = true
		if sfx != null:
			sfx.play("lighter_close", -8.0)
	if r < 0.3:
		_hand.transform = _pose(_ease(r / 0.3))
	else:
		_hand.transform = _pose(1.0).interpolate_with(_low(), _ease((r - 0.3) / 0.7))
	if r >= 1.0:
		cancel()
