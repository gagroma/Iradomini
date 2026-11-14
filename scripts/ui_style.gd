extends RefCounted

const FONT_PATH := "res://assets/fonts/Tinos-Regular.ttf"
const TEXT_SHADER = preload("res://shaders/ui_text.gdshader")
const PANEL_SHADER = preload("res://shaders/ui_panel.gdshader")
const BONE := Color("#f4ead6")
const ASH := Color("#a49e98")


static func style_text(control: Control, size: int, color := BONE) -> void:
	var font: Font
	if ResourceLoader.exists(FONT_PATH):
		font = load(FONT_PATH) as Font
	if font == null:
		var serif := SystemFont.new()
		serif.font_names = PackedStringArray(["Tinos", "Times New Roman", "Liberation Serif", "Georgia"])
		font = serif
	control.add_theme_font_override("font", font)
	control.add_theme_font_size_override("font_size", size)
	control.add_theme_color_override("font_color", color)
	control.add_theme_color_override("font_shadow_color", Color("#080609ee"))
	control.add_theme_constant_override("shadow_offset_x", 1)
	control.add_theme_constant_override("shadow_offset_y", 1)
	# Buttons lack a shadow style, so their dark edge uses the font outline.
	if control is BaseButton:
		control.add_theme_color_override("font_outline_color", Color("#080609ee"))
		control.add_theme_constant_override("outline_size", 2)
	var material := ShaderMaterial.new()
	material.shader = TEXT_SHADER
	control.material = material


static func panel(at: Vector2, dimensions: Vector2, opacity := 0.95) -> ColorRect:
	var rect := ColorRect.new()
	rect.position = at
	rect.size = dimensions
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = PANEL_SHADER
	material.set_shader_parameter("panel_size", dimensions)
	material.set_shader_parameter("opacity", opacity)
	rect.material = material
	return rect


static func action_button(caption: String, bounds: Rect2, size: int, hover_only := false) -> Button:
	var button := Button.new()
	button.text = caption
	button.position = bounds.position
	button.size = bounds.size
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	style_text(button, size)
	button.add_theme_color_override("font_hover_color", BONE)
	button.add_theme_color_override("font_pressed_color", BONE)
	button.add_theme_color_override("font_focus_color", BONE)
	var highlight := StyleBoxFlat.new()
	highlight.bg_color = Color("#eee1be19")
	highlight.border_color = ASH
	highlight.border_width_bottom = 1
	var empty := StyleBoxEmpty.new()
	button.add_theme_stylebox_override("normal", empty)
	button.add_theme_stylebox_override("hover", highlight)
	for state in ["pressed", "focus"]:
		button.add_theme_stylebox_override(state, empty if hover_only else highlight)
	if hover_only:
		button.add_theme_stylebox_override("hover_pressed", highlight)
	return button
