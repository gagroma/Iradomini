extends Control

const UIStyle = preload("res://scripts/ui_style.gd")
const TEXT := "IRA DOMINI"
const FONT_SIZE := 44


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := Label.new()
	title.text = TEXT
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIStyle.style_text(title, FONT_SIZE)
	add_child(title)

	var font := title.get_theme_font("font")
	var first_width := font.get_string_size("I", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var o_left := font.get_string_size("IRA D", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var o_width := font.get_string_size("O", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var baseline := font.get_ascent(FONT_SIZE)
	title.draw.connect(func():
		var bar := Rect2(Vector2(first_width * 0.5 - 10.0, baseline - 21.0), Vector2(20.0, 3.0))
		title.draw_rect(Rect2(bar.position + Vector2.ONE, bar.size), Color("#080609ee"))
		title.draw_rect(bar, UIStyle.BONE)
		var dot := Vector2(o_left + o_width * 0.5, baseline - 14.0)
		title.draw_circle(dot + Vector2.ONE, 3.4, Color("#080609ee"), true, -1.0, true)
		title.draw_circle(dot, 3.4, UIStyle.BONE, true, -1.0, true)
	)
