extends Control

signal back_requested

const UIStyle = preload("res://scripts/ui_style.gd")
const BRASS := Color("#b48c5a")
const SIZE := Vector2(384, 238)
const COL_W := 174.0
const ROW_H := 17.0
const ROW_STEP := 20.0

const LEFT := [
	["Movement", [
		["Move", ["W", "A", "S", "D"], false],
		["Run", ["Shift"], true],
		["Crouch  ·  hide near cover", ["Ctrl"], true],
	]],
	["Chalk", [
		["Draw a chalk line", ["LMB"], true],
		["Erase a circle", ["RMB"], true],
	]],
]
const RIGHT := [
	["Actions", [
		["Interact  ·  take relic", ["E"], false],
		["Read the journal", ["Z"], false],
		["Relight the candle", ["F"], false],
		["Skip cutscene", ["Enter"], false],
	]],
	["System", [
		["Pause", ["Esc"], false],
		["Restart level", ["R"], false],
		["Fullscreen", ["F11"], false],
	]],
]

var _back: Button


func _ready() -> void:
	top_level = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	position = ((Vector2(480, 270) - SIZE) * 0.5).floor()
	size = SIZE
	add_child(UIStyle.panel(Vector2.ZERO, SIZE, 0.97))
	var title := Label.new()
	title.text = "CONTROLS"
	title.position = Vector2(0, 7)
	title.size = Vector2(SIZE.x, 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIStyle.style_text(title, 16)
	add_child(title)
	for side in [-1.0, 1.0]:
		var line := ColorRect.new()
		line.color = Color(BRASS, 0.55)
		line.size = Vector2(108, 1)
		line.position = Vector2(SIZE.x * 0.5 + (60.0 if side > 0.0 else -168.0), 17)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(line)
	_column(LEFT, Vector2(12, 34))
	_column(RIGHT, Vector2(SIZE.x - 12 - COL_W, 34))
	_back = UIStyle.action_button("Back", Rect2(12, SIZE.y - 30, 62, 22), 15)
	_back.pressed.connect(func(): back_requested.emit())
	add_child(_back)
	var note := Label.new()
	note.text = "The demon cannot cross a closed circle"
	note.position = Vector2(84, SIZE.y - 26)
	note.size = Vector2(SIZE.x - 96, 14)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UIStyle.style_text(note, 9, UIStyle.ASH)
	add_child(note)
	hide()


func open() -> void:
	show()
	_back.grab_focus()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		back_requested.emit()


func _column(groups: Array, at: Vector2) -> void:
	var y := at.y
	for group in groups:
		var head := Label.new()
		head.text = String(group[0]).to_upper()
		head.position = Vector2(at.x + 2, y)
		UIStyle.style_text(head, 9, BRASS)
		add_child(head)
		var rule := ColorRect.new()
		rule.color = Color(BRASS, 0.25)
		rule.position = Vector2(at.x + 2, y + 13)
		rule.size = Vector2(COL_W - 4, 1)
		rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(rule)
		y += 17.0
		for row in group[1]:
			_row(at.x, y, row[0], row[1], row[2])
			y += ROW_STEP
		y += 6.0


func _row(x: float, y: float, action: String, keys: Array, hold: bool) -> void:
	var row := Panel.new()
	row.position = Vector2(x, y)
	row.size = Vector2(COL_W, ROW_H)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var calm := StyleBoxFlat.new()
	calm.bg_color = Color(0.045, 0.035, 0.045, 0.78)
	calm.border_color = Color(BRASS, 0.45)
	calm.border_width_left = 2
	calm.set_corner_radius_all(1)
	var lit := calm.duplicate() as StyleBoxFlat
	lit.bg_color = Color(0.13, 0.09, 0.07, 0.85)
	lit.border_color = BRASS
	row.add_theme_stylebox_override("panel", calm)
	row.mouse_entered.connect(func(): row.add_theme_stylebox_override("panel", lit))
	row.mouse_exited.connect(func(): row.add_theme_stylebox_override("panel", calm))
	add_child(row)
	var label := Label.new()
	label.text = action
	label.position = Vector2(8, -1.5)
	label.size = Vector2(COL_W * 0.6, ROW_H)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIStyle.style_text(label, 10)
	row.add_child(label)
	var right := COL_W - 5.0
	for i in range(keys.size() - 1, -1, -1):
		var cap := KeyCap.new()
		cap.text = String(keys[i])
		cap.size = Vector2(maxf(15.0, KeyCap.width_of(cap.text) + 10.0), ROW_H - 4.0)
		right -= cap.size.x
		cap.position = Vector2(right, 2)
		row.add_child(cap)
		right -= 3.0
	if hold:
		var tag := KeyCap.new()
		tag.text = "HOLD"
		tag.plain = true
		tag.size = Vector2(KeyCap.width_of("HOLD", 7) + 2.0, ROW_H - 4.0)
		tag.position = Vector2(right - tag.size.x - 1.0, 2)
		row.add_child(tag)


class KeyCap extends Control:
	const FONT = preload("res://assets/fonts/Tinos-Regular.ttf")
	const BRASS := Color("#b48c5a")
	var text := ""
	var plain := false

	static func width_of(t: String, font_size := 9) -> float:
		return FONT.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var fs := 7 if plain else 9
		if not plain:
			draw_rect(Rect2(Vector2.ZERO, size), Color("#1b1519"))
			draw_rect(Rect2(Vector2(0, size.y - 2), Vector2(size.x, 2)), Color(BRASS, 0.9))
			draw_rect(Rect2(Vector2.ZERO, size), Color(BRASS, 0.85), false, 1.0)
		var w := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var asc := FONT.get_ascent(fs)
		var desc := FONT.get_descent(fs)
		var base := Vector2((size.x - w) * 0.5, (size.y - (2.0 if not plain else 0.0) + asc - desc) * 0.5)
		draw_string(FONT, base + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.7))
		draw_string(FONT, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#a49e98") if plain else Color("#f4ead6"))


