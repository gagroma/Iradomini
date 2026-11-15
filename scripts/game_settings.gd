extends Node

const SAVE_PATH := "user://settings.cfg"
const SECTION := "settings"
const BASE := Vector2i(480, 270)
const MODES := ["Windowed", "Fullscreen", "Exclusive"]
const FPS_LIMITS := [0, 30, 60, 120, 144, 240]
const RESOLUTIONS := [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1440, 810), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(2880, 1620), Vector2i(3200, 1800), Vector2i(3840, 2160)]

var master_volume := 100.0
var mouse_sensitivity := 100.0
var display_mode := 0
var window_size := Vector2i.ZERO
var pixel_perfect := true
var sharp := true
var vsync := true
var max_fps := 0
var screen := -1

var fullscreen: bool:
	get:
		return display_mode != 0


func _ready() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		master_volume = clampf(float(config.get_value(SECTION, "master_volume", 100.0)), 0.0, 100.0)
		mouse_sensitivity = clampf(float(config.get_value(SECTION, "mouse_sensitivity", 100.0)), 50.0, 200.0)
		display_mode = clampi(int(config.get_value(SECTION, "display_mode", 1 if config.get_value(SECTION, "fullscreen", false) else 0)), 0, 2)
		var legacy := maxi(0, int(config.get_value(SECTION, "window_scale", 0)))
		window_size = config.get_value(SECTION, "window_size", BASE * legacy)
		if not window_size in RESOLUTIONS:
			window_size = Vector2i.ZERO
		pixel_perfect = bool(config.get_value(SECTION, "pixel_perfect", true))
		sharp = bool(config.get_value(SECTION, "sharp", true))
		vsync = bool(config.get_value(SECTION, "vsync", true))
		max_fps = int(config.get_value(SECTION, "max_fps", 0))
		screen = int(config.get_value(SECTION, "screen", -1))
	_apply_volume()
	apply_display()


func set_master_volume(value: float) -> void:
	master_volume = value
	_apply_volume()


func set_fullscreen(enabled: bool) -> void:
	display_mode = 1 if enabled else 0
	apply_display()


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value(SECTION, "master_volume", master_volume)
	config.set_value(SECTION, "mouse_sensitivity", mouse_sensitivity)
	config.set_value(SECTION, "display_mode", display_mode)
	config.set_value(SECTION, "window_size", window_size)
	config.set_value(SECTION, "pixel_perfect", pixel_perfect)
	config.set_value(SECTION, "sharp", sharp)
	config.set_value(SECTION, "vsync", vsync)
	config.set_value(SECTION, "max_fps", max_fps)
	config.set_value(SECTION, "screen", screen)
	var result := config.save(SAVE_PATH)
	if result != OK:
		push_warning("Could not save settings (%s)." % error_string(result))


func can_control_window() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	return not Engine.is_embedded_in_editor()


func current_screen() -> int:
	if screen >= 0 and screen < DisplayServer.get_screen_count():
		return screen
	return DisplayServer.window_get_current_screen()


func auto_size() -> Vector2i:
	var room := DisplayServer.screen_get_usable_rect(current_screen()).size
	var best := BASE * 2
	for k in range(2, 13):
		if BASE.x * k <= room.x * 0.8 and BASE.y * k <= room.y * 0.8:
			best = BASE * k
	return best


func effective_size() -> Vector2i:
	return window_size if window_size != Vector2i.ZERO else auto_size()


func apply_display() -> void:
	var root := get_tree().root
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS if sharp else Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_INTEGER if pixel_perfect else Window.CONTENT_SCALE_STRETCH_FRACTIONAL
	Engine.max_fps = max_fps
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	if not can_control_window():
		return
	var target := current_screen()
	if DisplayServer.window_get_current_screen() != target:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_current_screen(target)
	match display_mode:
		0:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			var size := effective_size()
			var area := DisplayServer.screen_get_usable_rect(target)
			DisplayServer.window_set_size(size)
			DisplayServer.window_set_position(area.position + ((area.size - size) / 2).max(Vector2i.ZERO))
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		2:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)


func _apply_volume() -> void:
	AudioServer.set_bus_volume_linear(0, master_volume / 100.0)
	AudioServer.set_bus_mute(0, is_zero_approx(master_volume))
