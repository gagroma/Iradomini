extends Control

const SCALE := 60.0
const SLANT := 0.2
const BASE_Y := 150.0
const SPEED := 260.0
const INK := Color(0.62, 0.03, 0.03)
const INK_HOT := Color(0.85, 0.1, 0.06)

const GLYPHS = {
	"Y": [0.55, [[[0.0, 1.0], [0.06, 0.82], [0.18, 0.6], [0.3, 0.55], [0.42, 0.75], [0.5, 1.02]],
			[[0.5, 1.02], [0.42, 0.5], [0.3, 0.05], [0.18, -0.35], [0.06, -0.5], [-0.02, -0.38]]]],
	"o": [0.5, [[[0.32, 0.48], [0.14, 0.46], [0.04, 0.26], [0.1, 0.04], [0.28, 0.02], [0.38, 0.22], [0.32, 0.48], [0.46, 0.44]]]],
	"u": [0.6, [[[0.0, 0.48], [0.02, 0.2], [0.1, 0.02], [0.26, 0.04], [0.36, 0.25], [0.4, 0.5]],
			[[0.4, 0.5], [0.38, 0.18], [0.44, 0.0], [0.56, 0.06]]]],
	"A": [0.7, [[[0.0, 0.0], [0.12, 0.35], [0.28, 0.8], [0.4, 1.08], [0.48, 0.7], [0.56, 0.3], [0.64, 0.0]],
			[[0.14, 0.42], [0.38, 0.46], [0.62, 0.5]]]],
	"r": [0.4, [[[0.02, 0.0], [0.04, 0.28], [0.06, 0.5], [0.12, 0.38], [0.22, 0.48], [0.34, 0.44]]]],
	"e": [0.46, [[[0.02, 0.2], [0.2, 0.26], [0.3, 0.38], [0.22, 0.5], [0.08, 0.42], [0.03, 0.2], [0.12, 0.02], [0.28, 0.0], [0.4, 0.1]]]],
	"D": [0.78, [[[0.08, 1.05], [0.1, 0.6], [0.06, 0.15], [0.04, -0.02]],
			[[-0.04, 0.92], [0.2, 1.06], [0.5, 0.98], [0.68, 0.66], [0.62, 0.28], [0.38, 0.04], [0.1, 0.0], [-0.04, 0.1]]]],
	"a": [0.58, [[[0.34, 0.44], [0.16, 0.5], [0.03, 0.3], [0.08, 0.04], [0.24, 0.04], [0.36, 0.26], [0.38, 0.48]],
			[[0.38, 0.48], [0.36, 0.2], [0.42, 0.0], [0.54, 0.06]]]],
	"d": [0.6, [[[0.34, 0.44], [0.16, 0.5], [0.03, 0.3], [0.08, 0.04], [0.24, 0.04], [0.36, 0.26], [0.4, 0.5]],
			[[0.52, 1.25], [0.46, 0.8], [0.4, 0.3], [0.42, 0.04], [0.5, -0.4], [0.53, -1.25]]]],
	" ": [0.4, []],
}

var writing := false
var _t := 0.0
var _strokes := []
var _drips := []
var _total := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rng.seed = 666
	_build("You Are Dead")


func done() -> bool:
	return writing and _t * SPEED >= _total + 40.0


func begin() -> void:
	writing = true
	_t = 0.0


func _build(text: String) -> void:
	var width = 0.0
	for ch in text:
		width += GLYPHS[ch][0]
	var x0 = (480.0 - width * SCALE) * 0.5 - 6.0
	var pen = 0.0
	var start = 0.0
	for ch in text:
		var g = GLYPHS[ch]
		for raw in g[1]:
			var pts = []
			for p in raw:
				var px = p[0] + pen
				pts.append(Vector2(x0 + (px + p[1] * SLANT) * SCALE, BASE_Y - p[1] * SCALE))
			var smooth = _catmull(pts)
			var lens = [0.0]
			for i in range(1, smooth.size()):
				lens.append(lens[-1] + smooth[i].distance_to(smooth[i - 1]))
			_strokes.append({"pts": smooth, "lens": lens, "start": start, "len": lens[-1], "seed": _rng.randf() * 100.0})
			for i in range(1, smooth.size() - 1):
				if smooth[i].y > smooth[i - 1].y and smooth[i].y >= smooth[i + 1].y and _rng.randf() < 0.75:
					_drips.append({"at": smooth[i], "t": start + lens[i], "max": _rng.randf_range(3.0, 16.0), "rate": _rng.randf_range(0.25, 0.7)})
			if _rng.randf() < 0.5:
				_drips.append({"at": smooth[-1], "t": start + lens[-1], "max": _rng.randf_range(4.0, 22.0), "rate": _rng.randf_range(0.2, 0.5)})
			start += lens[-1] + 4.0
		pen += g[0]
	_total = start


func _catmull(pts: Array) -> Array:
	var out = []
	for i in range(pts.size() - 1):
		var p0 = pts[maxi(i - 1, 0)]
		var p1 = pts[i]
		var p2 = pts[i + 1]
		var p3 = pts[mini(i + 2, pts.size() - 1)]
		for k in range(6):
			var t = k / 6.0
			var t2 = t * t
			var t3 = t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(pts[-1])
	return out


func _process(dt: float) -> void:
	if writing:
		_t += dt
		queue_redraw()


func _hash(x: float) -> float:
	var v = sin(x * 12.9898) * 43758.5453
	return v - floor(v)


func _draw() -> void:
	if not writing:
		return
	var ink = _t * SPEED
	for s in _strokes:
		var shown = ink - s["start"]
		if shown <= 0.0:
			continue
		var pts = s["pts"]
		var lens = s["lens"]
		for i in range(1, pts.size()):
			if lens[i - 1] > shown:
				break
			var a = pts[i - 1]
			var b = pts[i]
			if lens[i] > shown:
				b = a.lerp(b, (shown - lens[i - 1]) / maxf(lens[i] - lens[i - 1], 0.001))
			var u = lens[i] / maxf(s["len"], 1.0)
			var press = pow(sin(PI * clampf(u, 0.04, 0.96)), 0.5)
			var h = _hash(s["seed"] + i * 0.37)
			var w = 1.0 + 2.8 * press * (0.75 + 0.5 * h)
			var n = (b - a).orthogonal().normalized()
			var fresh = clampf(1.0 - (shown - lens[i]) / 120.0, 0.0, 1.0)
			var col = INK.lerp(INK_HOT, 0.35 * fresh + 0.25 * h)
			for k in range(5):
				var off = (k - 2) * w * 0.3 + (_hash(s["seed"] + i * 1.7 + k) - 0.5) * 0.9
				var c = col
				c.a = 0.95 if k == 2 else 0.55 + 0.4 * _hash(i * 3.1 + k + s["seed"])
				draw_line(a + n * off, b + n * off, c, 1.0)
			if _hash(s["seed"] + i * 5.3) > 0.9:
				draw_line(b, b + n * (w + 1.5) * (1.0 if h > 0.5 else -1.0), Color(INK, 0.5), 1.0)
	for d in _drips:
		var age = (ink - d["t"]) / SPEED
		if age <= 0.0:
			continue
		var l = d["max"] * (1.0 - exp(-age * d["rate"]))
		var top = d["at"]
		draw_line(top, top + Vector2(0.3, l), INK, 1.0)
		draw_line(top + Vector2(1, 0), top + Vector2(1.2, l * 0.7), Color(INK, 0.5), 1.0)
		draw_circle(top + Vector2(0.6, l), 1.1, INK.darkened(0.15))
