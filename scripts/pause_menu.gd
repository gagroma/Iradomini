extends CanvasLayer

signal resume_requested
signal restart_requested
signal title_requested

const UIStyle = preload("res://scripts/ui_style.gd")
const SettingsPanel = preload("res://scripts/settings_panel.gd")
const PANEL_SIZE := Vector2(188, 150)

var _actions: Control
var _settings: SettingsPanel
var _resume: Button
var _settings_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	layer = 4
	hide()

	var dim := ColorRect.new()
	dim.color = Color("#09070bb3")
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_actions = Control.new()
	_actions.custom_minimum_size = PANEL_SIZE
	center.add_child(_actions)
	_actions.add_child(UIStyle.panel(Vector2.ZERO, PANEL_SIZE))
	_resume = _button("Resume", 19, func(): resume_requested.emit())
	_settings_button = _button("Settings", 47, _open_settings)
	_button("Restart Seed", 75, func(): restart_requested.emit())
	_button("Quit to Title", 103, func(): title_requested.emit())

	_settings = SettingsPanel.new()
	_settings.custom_minimum_size = SettingsPanel.DIMENSIONS
	center.add_child(_settings)
	_settings.hide()
	_settings.back_requested.connect(_close_settings)


func open() -> void:
	_settings.hide()
	_actions.show()
	show()
	_resume.grab_focus()


func _input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _settings.visible:
			_close_settings()
		else:
			resume_requested.emit()
	elif event.physical_keycode == KEY_F11:
		get_viewport().set_input_as_handled()
		_settings.toggle_fullscreen()


func _open_settings() -> void:
	_actions.hide()
	_settings.open()


func _close_settings() -> void:
	_settings.hide()
	_actions.show()
	_settings_button.grab_focus()


func _button(caption: String, y: float, action: Callable) -> Button:
	var button := UIStyle.action_button(caption, Rect2(19, y, 150, 26), 17, true)
	button.pressed.connect(action)
	_actions.add_child(button)
	return button
