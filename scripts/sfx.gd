extends Node
# SFX - plays every sound in the game.
# Source: Godot's AudioStreamPlayer (plain sound) and AudioStreamPlayer3D
# (sound that comes from a place in the world, so you can hear WHERE the
# demon is). GDD "Zvuk": no music - silence, echo and a low hum.
# The .wav files in res://audio were synthesized with a Python script; swap
# any of them for a better recording with the same file name.

const NAMES = [
	"step1", "step2", "demon_step", "demon_breath", "demon_scream", "demon_notice",
	"heartbeat", "drone", "choir_rev", "hit", "candle_out", "pickup", "place",
	"burn", "banish", "door_slam", "door_creak", "lighter_open", "lighter_strike", "lighter_close", "prayer_murmur", "sigh", "book_open", "book_close", "clatter", "ending", "swing", "chant", "record", "wind", "twig",
]

var streams := {}


func _ready() -> void:
	for n in NAMES:
		var path = "res://audio/%s.wav" % n
		if ResourceLoader.exists(path):
			streams[n] = load(path)
	# GDD: "echo (reverb)" - one reverb effect on the main audio bus
	if AudioServer.get_bus_effect_count(0) == 0:
		var reverb = AudioEffectReverb.new()
		reverb.room_size = 0.85
		reverb.damping = 0.35
		reverb.wet = 0.3
		reverb.dry = 1.0
		AudioServer.add_bus_effect(0, reverb)


func has(sound: String) -> bool:
	return streams.has(sound)


# Make a sound repeat for ever (the hum, the choir, the demon's breathing).
func _looped(sound: String):
	if not streams.has(sound):
		return null
	var s = streams[sound]
	if s is AudioStreamWAV and s.loop_mode == AudioStreamWAV.LOOP_DISABLED:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate)
	return s


# A sound with no position (heartbeat, your own steps).
func play(sound: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not streams.has(sound):
		return
	var p = AudioStreamPlayer.new()
	p.stream = streams[sound]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


# A sound at a place in the world.
func play_at(sound: String, where: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not streams.has(sound):
		return
	var p = AudioStreamPlayer3D.new()
	p.stream = streams[sound]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.unit_size = 7.0
	p.max_distance = 45.0
	add_child(p)
	p.global_position = where
	p.finished.connect(p.queue_free)
	p.play()


# A repeating sound with no position. Returns the player so the volume can change.
func loop(sound: String, volume_db: float):
	var s = _looped(sound)
	if s == null:
		return null
	var p = AudioStreamPlayer.new()
	p.stream = s
	p.volume_db = volume_db
	add_child(p)
	p.play()
	return p


# A repeating sound that follows a node (the demon's breathing).
func loop_at(sound: String, parent: Node3D, volume_db: float):
	var s = _looped(sound)
	if s == null:
		return null
	var p = AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = volume_db
	p.unit_size = 5.0
	p.max_distance = 30.0
	p.position = Vector3(0.0, 1.9, 0.0)
	parent.add_child(p)
	p.play()
	return p
