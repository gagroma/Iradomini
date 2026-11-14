extends Node

const SAVE_PATH := "user://settings.cfg"
const SECTION := "settings"

var master_volume := 100.0
var mouse_sensitivity := 100.0
var fullscreen := false


func _ready() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		master_volume = clampf(float(config.get_value(SECTION, "master_volume", 100.0)), 0.0, 100.0)
		mouse_sensitivity = clampf(float(config.get_value(SECTION, "mouse_sensitivity", 100.0)), 50.0, 200.0)
		fullscreen = bool(config.get_value(SECTION, "fullscreen", false))
	_apply_volume()
	if fullscreen:
		_apply_window_mode()


func set_master_volume(value: float) -> void:
	master_volume = value
	_apply_volume()


func set_fullscreen(enabled: bool) -> void:
	fullscreen = enabled
	_apply_window_mode()


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value(SECTION, "master_volume", master_volume)
	config.set_value(SECTION, "mouse_sensitivity", mouse_sensitivity)
	config.set_value(SECTION, "fullscreen", fullscreen)
	var result := config.save(SAVE_PATH)
	if result != OK:
		push_warning("Could not save settings (%s)." % error_string(result))


func _apply_volume() -> void:
	AudioServer.set_bus_volume_linear(0, master_volume / 100.0)
	AudioServer.set_bus_mute(0, is_zero_approx(master_volume))


func _apply_window_mode() -> void:
	var window_mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(window_mode)
