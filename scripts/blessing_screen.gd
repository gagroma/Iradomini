extends CanvasLayer

signal picked(id: String)

const UIStyle = preload("res://scripts/ui_style.gd")
const Boons = preload("res://scripts/boons.gd")
const Card = preload("res://scripts/blessing_card.gd")
const GAP := 16.0

var sfx
var _dim: ColorRect
var _black: ColorRect
var _title: Label
var _sub: Label
var _cards := []
var _done := false


func _ready() -> void:
	layer = 6
	hide()
	_dim = ColorRect.new()
	_dim.color = Color("#09070b")
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title = _label(Rect2(0, 14, 480, 30), 22, UIStyle.BONE)
	_sub = _label(Rect2(0, 46, 480, 14), 11, UIStyle.ASH)
	_black = ColorRect.new()
	_black.color = Color(0, 0, 0, 0)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_black)
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _label(box: Rect2, font: int, color: Color) -> Label:
	var l = Label.new()
	l.position = box.position
	l.size = box.size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIStyle.style_text(l, font, color)
	add_child(l)
	return l


func reveal(level: int, total: int) -> void:
	_title.text = "LEVEL %d CLEARED" % level
	_sub.text = "Choose a blessing to carry into church %d of %d" % [level + 1, total]
	for n in [_dim, _title, _sub]:
		n.modulate.a = 0.0
	show()
	var ids = Boons.offer(3)
	var width = Card.SIZE.x * ids.size() + GAP * (ids.size() - 1)
	for i in ids.size():
		var card = Card.new()
		add_child(card)
		move_child(card, _black.get_index())
		card.setup(ids[i], i + 1, Vector2(240.0 - width * 0.5 + i * (Card.SIZE.x + GAP), 72), 1.3 + i * 0.15)
		card.chosen.connect(_choose)
		_cards.append(card)
	var tw = create_tween().set_trans(Tween.TRANS_SINE)
	tw.tween_property(_dim, "modulate:a", 0.88, 1.0)
	tw.parallel().tween_property(_title, "modulate:a", 1.0, 0.8).set_delay(0.4)
	tw.parallel().tween_property(_sub, "modulate:a", 1.0, 0.8).set_delay(0.7)
	await get_tree().create_timer(1.9).timeout
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for c in _cards:
		c.locked = false
	if not _cards.is_empty():
		_cards[0].grab_focus()


func _input(event: InputEvent) -> void:
	if not visible or _done or _cards.is_empty() or _cards[0].locked:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k = event.physical_keycode - KEY_1
		if k >= 0 and k < _cards.size():
			get_viewport().set_input_as_handled()
			_choose(_cards[k].id)
		elif event.physical_keycode in [KEY_A, KEY_LEFT, KEY_D, KEY_RIGHT]:
			get_viewport().set_input_as_handled()
			var step = -1 if event.physical_keycode in [KEY_A, KEY_LEFT] else 1
			var at = 0
			for i in _cards.size():
				if _cards[i].has_focus():
					at = i
			_cards[clampi(at + step, 0, _cards.size() - 1)].grab_focus()


func _choose(id: String) -> void:
	if _done:
		return
	_done = true
	for c in _cards:
		c.locked = true
		if c.id == id:
			c.flare()
		else:
			c.dismissed = true
	if sfx != null:
		sfx.play("banish", -6.0, 1.25)
	var tw = create_tween().set_trans(Tween.TRANS_SINE)
	tw.tween_interval(1.0)
	tw.tween_property(_black, "color:a", 1.0, 0.8)
	await tw.finished
	picked.emit(id)
