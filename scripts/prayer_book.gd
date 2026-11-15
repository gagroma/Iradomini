extends Node3D

const PAGE_W := 0.105
const PAGE_H := 0.155
const BLOCK := 0.012
const COVER := 0.004
const OPEN_ANGLE := -0.16

var opened := 0.0

var _flap: Node3D

static var _pages := {}


func _ready() -> void:
	var leather = StandardMaterial3D.new()
	leather.albedo_color = Color(0.36, 0.05, 0.04)
	leather.roughness = 0.75
	var gold = StandardMaterial3D.new()
	gold.albedo_color = Color(0.85, 0.66, 0.28)
	gold.metallic = 0.8
	gold.roughness = 0.35
	var paper = StandardMaterial3D.new()
	paper.albedo_color = Color(0.82, 0.76, 0.62)
	paper.roughness = 0.95
	var rng = RandomNumberGenerator.new()
	rng.seed = 1317

	_box(Vector3(PAGE_W + 0.004, COVER, PAGE_H + 0.006), Vector3(PAGE_W * 0.5, -COVER * 0.5, 0), leather, self)
	_box(Vector3(PAGE_W, BLOCK, PAGE_H), Vector3(PAGE_W * 0.5 + 0.001, BLOCK * 0.5, 0), paper, self)
	_page(Vector3(PAGE_W * 0.5 + 0.001, BLOCK + 0.0003, 0), _page_texture(rng, false), self)
	_box(Vector3(0.006, BLOCK + COVER * 2.0, PAGE_H + 0.006), Vector3(-0.001, BLOCK * 0.5, 0), leather, self)

	_flap = Node3D.new()
	_flap.position = Vector3(0, BLOCK, 0)
	add_child(_flap)
	_box(Vector3(PAGE_W, BLOCK, PAGE_H), Vector3(-PAGE_W * 0.5 - 0.001, -BLOCK * 0.5, 0), paper, _flap)
	_page(Vector3(-PAGE_W * 0.5 - 0.001, 0.0003, 0), _page_texture(rng, true), _flap)
	_box(Vector3(PAGE_W + 0.004, COVER, PAGE_H + 0.006), Vector3(-PAGE_W * 0.5, -BLOCK - COVER * 0.5, 0), leather, _flap)
	_box(Vector3(0.008, 0.0015, 0.07), Vector3(-PAGE_W * 0.5, -BLOCK - COVER - 0.0007, -0.01), gold, _flap)
	_box(Vector3(0.042, 0.0015, 0.008), Vector3(-PAGE_W * 0.5, -BLOCK - COVER - 0.0007, -0.024), gold, _flap)
	_apply()


func _box(size: Vector3, at: Vector3, mat: Material, parent: Node3D) -> void:
	var m = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = size
	m.mesh = box
	m.material_override = mat
	m.position = at
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)


func _page(at: Vector3, tex: Texture2D, parent: Node3D) -> void:
	var m = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(PAGE_W - 0.002, PAGE_H - 0.002)
	m.mesh = plane
	var mat = StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.roughness = 0.95
	m.material_override = mat
	m.position = at
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)


func _page_texture(rng: RandomNumberGenerator, left: bool) -> ImageTexture:
	if _pages.has(left):
		return _pages[left]
	var w = 48
	var h = 70
	var img = Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			var edge = minf(minf(x, w - 1 - x), minf(y, h - 1 - y))
			var tone = 0.86 - 0.12 * clampf(1.0 - edge / 6.0, 0.0, 1.0) + rng.randf_range(-0.02, 0.02)
			if (x if left else w - 1 - x) < 3:
				tone -= 0.08
			img.set_pixel(x, y, Color(tone, tone * 0.93, tone * 0.76))
	var ink = Color(0.12, 0.08, 0.06)
	var red = Color(0.6, 0.08, 0.05)
	var margin = 5
	var y0 = 6
	if not left:
		for yy in range(y0, y0 + 9):
			for xx in range(margin, margin + 8):
				img.set_pixel(xx, yy, red if (xx + yy) % 5 != 0 else Color(0.8, 0.6, 0.2))
	var line = 0
	var yl = y0 + 1
	while yl < h - 6:
		var x = margin + (10 if not left and yl < y0 + 10 else 0)
		var rubric = line % 7 == 3
		while x < w - margin:
			var word = rng.randi_range(2, 6)
			for k in word:
				if x + k >= w - margin:
					break
				var c = red if rubric else ink
				img.set_pixel(x + k, yl, c)
				if rng.randf() < 0.45:
					img.set_pixel(x + k, yl - 1, c.lerp(Color(0.8, 0.75, 0.6), 0.4))
			x += word + rng.randi_range(1, 2)
		yl += 4
		line += 1
	_pages[left] = ImageTexture.create_from_image(img)
	return _pages[left]


func _process(_dt: float) -> void:
	_apply()


func _apply() -> void:
	var k = smoothstep(0.0, 1.0, opened)
	_flap.rotation.z = lerpf(-PI, OPEN_ANGLE, k)
