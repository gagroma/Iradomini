extends CanvasLayer

signal closed

const UIStyle = preload("res://scripts/ui_style.gd")
const Journal = preload("res://scripts/journal.gd")
const PAPER_SHADER = preload("res://shaders/journal_paper.gdshader")
const COVER := Rect2(20, 10, 440, 236)
const LEFT := Rect2(31, 18, 205, 220)
const RIGHT := Rect2(244, 18, 205, 220)
const INK := Color(0.16, 0.1, 0.06)
const LEATHER := Color(0.2, 0.12, 0.07)
const TURN_TIME := 0.5

var sfx

var _book: Control
var _left: Dictionary
var _right: Dictionary
var _turning: Dictionary
var _hint: Label
var _spread := 0
var _turn := -1.0
var _dir := 1
var _front := 0
var _back := 0
var _was_paused := false
var _opened_at := 0


func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.02, 0.8)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_book = Control.new()
	_book.size = Vector2(480, 270)
	_book.pivot_offset = COVER.get_center()
	_book.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_book)
	var cover := Panel.new()
	cover.position = COVER.position
	cover.size = COVER.size
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = LEATHER
	style.border_color = LEATHER.darkened(0.45)
	style.set_border_width_all(2)
	style.set_corner_radius_all(5)
	cover.add_theme_stylebox_override("panel", style)
	_book.add_child(cover)
	var spine := ColorRect.new()
	spine.color = LEATHER.darkened(0.35)
	spine.position = Vector2(LEFT.end.x, COVER.position.y + 3)
	spine.size = Vector2(RIGHT.position.x - LEFT.end.x, COVER.size.y - 6)
	spine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_book.add_child(spine)
	for k in [3, 2, 1]:
		_edge(Rect2(LEFT.position + Vector2(-k * 1.5, k * 0.8), LEFT.size), k)
		_edge(Rect2(RIGHT.position + Vector2(k * 1.5, k * 0.8), RIGHT.size), k)
	_left = _make_page(LEFT, -1.0)
	_right = _make_page(RIGHT, 1.0)
	_turning = _make_page(RIGHT, 1.0)
	_turning["root"].hide()
	_hint = Label.new()
	_hint.position = Vector2(0, 251)
	_hint.size = Vector2(480, 12)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.text = "A / D  turn the page      Z  close"
	UIStyle.style_text(_hint, 9, UIStyle.ASH)
	add_child(_hint)


func _edge(rect: Rect2, k: int) -> void:
	var e := ColorRect.new()
	e.color = Color(0.72, 0.64, 0.5).darkened(0.12 * k)
	e.position = rect.position
	e.size = rect.size
	e.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_book.add_child(e)


func _make_page(rect: Rect2, side: float) -> Dictionary:
	var root := Control.new()
	root.position = rect.position
	root.size = rect.size
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_book.add_child(root)
	var paper := ColorRect.new()
	paper.size = rect.size
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = PAPER_SHADER
	mat.set_shader_parameter("page_size", rect.size)
	mat.set_shader_parameter("side", side)
	paper.material = mat
	root.add_child(paper)
	var title := _text(root, 13)
	var body := _text(root, 10)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_constant_override("line_spacing", -1)
	var num := _text(root, 9)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var page := {"root": root, "mat": mat, "title": title, "body": body, "num": num}
	_layout(page, side)
	return page


func _text(parent: Control, size: int) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIStyle.style_text(l, size, INK)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	parent.add_child(l)
	return l


func _layout(page: Dictionary, side: float) -> void:
	var w: float = LEFT.size.x
	var inner := 17.0
	var outer := 12.0
	var x0 := inner if side > 0.0 else outer
	page["title"].position = Vector2(x0, 12)
	page["title"].size = Vector2(w - inner - outer, 18)
	page["body"].position = Vector2(x0, 34)
	page["body"].size = Vector2(w - inner - outer, LEFT.size.y - 52)
	page["num"].position = Vector2(0, LEFT.size.y - 15)
	page["num"].size = Vector2(w, 12)
	page["mat"].set_shader_parameter("side", side)


func _fill(page: Dictionary, index: int) -> void:
	if index >= 0 and index < Journal.PAGES.size():
		page["title"].text = Journal.PAGES[index][0]
		page["body"].text = Journal.PAGES[index][1]
		page["num"].text = "— %d —" % (index + 1)
	else:
		page["title"].text = ""
		page["body"].text = ""
		page["num"].text = ""
	page["mat"].set_shader_parameter("seed", float(index) * 0.37 + 1.0)


func _spreads() -> int:
	return int(ceil(Journal.PAGES.size() / 2.0))


func is_open() -> bool:
	return visible


func open(page: int = -1) -> void:
	if visible:
		return
	if page >= 0:
		_spread = clampi(page / 2, 0, _spreads() - 1)
	_turn = -1.0
	_turning["root"].hide()
	_fill(_left, _spread * 2)
	_fill(_right, _spread * 2 + 1)
	_was_paused = get_tree().paused
	get_tree().paused = true
	_opened_at = Time.get_ticks_msec()
	show()
	_book.modulate.a = 0.0
	_book.scale = Vector2.ONE * 0.94
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT).set_parallel()
	tw.tween_property(_book, "modulate:a", 1.0, 0.25)
	tw.tween_property(_book, "scale", Vector2.ONE, 0.3)
	if sfx != null:
		sfx.play("book_open", -10.0)


func close() -> void:
	hide()
	get_tree().paused = _was_paused
	if sfx != null:
		sfx.play("book_close", -12.0)
	closed.emit()


func _flip(dir: int) -> void:
	if _turn >= 0.0:
		return
	var next := _spread + dir
	if next < 0 or next >= _spreads():
		return
	_dir = dir
	_turn = 0.0
	if dir > 0:
		_front = _spread * 2 + 1
		_back = next * 2
		_fill(_right, next * 2 + 1)
	else:
		_front = _spread * 2
		_back = next * 2 + 1
		_fill(_left, next * 2)
	_spread = next
	_fill(_turning, _front)
	_turning["showing"] = _front
	_turning["root"].show()
	if sfx != null:
		sfx.play("book_open", -14.0, 1.35)


func _process(dt: float) -> void:
	if _turn < 0.0:
		return
	_turn = minf(1.0, _turn + dt / TURN_TIME)
	var t := smoothstep(0.0, 1.0, _turn)
	var root: Control = _turning["root"]
	var first := t < 0.5
	var on_right := (_dir > 0) == first
	var rect := RIGHT if on_right else LEFT
	root.position = rect.position
	root.pivot_offset = Vector2(0.0 if on_right else rect.size.x, rect.size.y * 0.5)
	var w := absf(cos(PI * t))
	root.scale = Vector2(maxf(w, 0.01), 1.0 + 0.04 * sin(PI * t))
	if not first and _turning.get("showing", -1) != _back:
		_fill(_turning, _back)
		_turning["showing"] = _back
	_layout(_turning, 1.0 if on_right else -1.0)
	_turning["mat"].set_shader_parameter("shade", (1.0 - w) * 0.45)
	if _turn >= 1.0:
		_fill(_left, _spread * 2)
		_fill(_right, _spread * 2 + 1)
		root.hide()
		root.scale = Vector2.ONE
		_turning["showing"] = -1
		_turning["mat"].set_shader_parameter("shade", 0.0)
		_turn = -1.0


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		_flip(1 if event.position.x > get_viewport().get_visible_rect().size.x * 0.5 else -1)
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k: int = event.physical_keycode
	get_viewport().set_input_as_handled()
	if k in [KEY_A, KEY_LEFT]:
		_flip(-1)
	elif k in [KEY_D, KEY_RIGHT]:
		_flip(1)
	elif k in [KEY_Z, KEY_E, KEY_ESCAPE, KEY_ENTER] and Time.get_ticks_msec() - _opened_at > 250:
		close()
