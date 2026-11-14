extends CanvasLayer

const EMBER_SHADER = preload("res://shaders/flame_transition.gdshader")

var _surface: ShaderMaterial
var _crackle: AudioStreamPlayer


func _ready() -> void:
	layer = 5
	var veil := ColorRect.new()
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_surface = ShaderMaterial.new()
	_surface.shader = EMBER_SHADER
	veil.material = _surface


func open_game(scene: PackedScene, ember_uv: Vector2, burn_sound: AudioStream) -> void:
	# Keep the last crackle on the same reverb bus as the cathedral as scenes swap.
	if burn_sound != null:
		_crackle = AudioStreamPlayer.new()
		_crackle.stream = burn_sound
		_crackle.pitch_scale = 0.56
		_crackle.volume_db = -11.0
		add_child(_crackle)
		_crackle.play()

	_surface.set_shader_parameter("point", ember_uv)
	var focus := create_tween().set_parallel()
	focus.tween_method(_set_cover, 0.0, 1.0, 0.21).set_trans(Tween.TRANS_SINE)
	focus.tween_method(_set_ember, 0.0, 1.0, 0.16)
	await focus.finished

	var tree := get_tree()
	var game = scene.instantiate()
	game.candle_intro = true
	var result := tree.change_scene_to_node(game)
	if result != OK:
		game.free()
		push_error("Could not start the game (%s)." % error_string(result))
		tree.reload_current_scene()
		queue_free()
		return
	await tree.scene_changed

	var drift := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	drift.tween_method(_move_ember.bind(ember_uv, game.candle_flame_uv()), 0.0, 1.0, 0.26)
	await drift.finished

	var reveal := create_tween().set_parallel()
	reveal.tween_method(_set_reveal, 0.0, 1.0, 0.49).set_trans(Tween.TRANS_SINE)
	reveal.tween_method(_set_ember, 1.0, 0.0, 0.30)
	await reveal.finished
	game.finish_candle_intro()
	queue_free()


func _set_cover(amount: float) -> void:
	_surface.set_shader_parameter("cover", amount)


func _set_ember(amount: float) -> void:
	_surface.set_shader_parameter("ember", amount)


func _set_reveal(amount: float) -> void:
	_surface.set_shader_parameter("reveal", amount)


func _move_ember(amount: float, from: Vector2, to: Vector2) -> void:
	var drift := from.lerp(to, amount)
	drift.y -= sin(amount * PI) * 0.10
	_surface.set_shader_parameter("point", drift)
