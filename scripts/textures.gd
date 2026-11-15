extends RefCounted
# TEXTURES MADE IN CODE - wood, oak, cloth, light beams, the rose window.
# (Stone walls and floors are drawn in their shaders: psx_wall_paint, psx_floor.)
# Inspiration: PS1 games used tiny textures (32x32 or 64x64 pixels) with no
# smoothing. Each function paints one small picture, pixel by pixel, from a
# short palette (the same flat-palette idea as the pixel-splat models).
# The colours look light here because the dim lighting darkens them in the game.

const WOOD = ["2a1a14", "45291d", "633c28", "80512f"]
const CLOTH = ["3a0a14", "661424", "8f1d32", "b52a40"]
const OAK = ["24160f", "34211a", "442b20", "553626", "66422d", "7a5034"]


static func _ramp(hex_list: Array) -> Array:
	var out = []
	for h in hex_list:
		out.append(Color.html(str(h)))
	return out


static func _finish(img: Image) -> ImageTexture:
	img.resize(img.get_width() * 4, img.get_height() * 4, Image.INTERPOLATE_CUBIC)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# Wood: planks with a little grain.
static func wood(seed_value: int) -> ImageTexture:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	var ramp = _ramp(WOOD)
	var img = Image.create(32, 32, false, Image.FORMAT_RGB8)
	var plank = 2
	for x in range(32):
		if x % 8 == 0:
			plank = rng.randi_range(1, 3)
		for y in range(32):
			var idx = plank
			if x % 8 == 0:
				idx = 0
			elif rng.randf() < 0.18:
				idx = clampi(idx + rng.randi_range(-1, 1), 1, 3)
			img.set_pixel(x, y, ramp[idx])
	return _finish(img)


# Oak for models with UVs (the pews): the grain runs along U (x). Growth
# rings are dark wavy lines, pores are short dark dashes along the grain,
# and the light flecks are oak's medullary rays. Every wave has a whole
# number of periods across the picture, so it tiles without seams.
static func oak(seed_value: int) -> ImageTexture:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	var ramp = _ramp(OAK)
	var size = 64
	var img = Image.create(size, size, false, Image.FORMAT_RGB8)
	var ph1 = rng.randf() * TAU
	var ph2 = rng.randf() * TAU
	var rings = 5
	var row_tone = []
	for y in range(size):
		row_tone.append(rng.randf_range(-0.35, 0.35))
	var idx_map = []
	for y in range(size):
		for x in range(size):
			var u = float(x) / size
			var wob = sin(TAU * u + ph1 + y * 0.05) * 3.0 + sin(TAU * 2.0 * u + ph2) * 1.4
			var t = fposmod((y + wob) * rings / float(size), 1.0)
			var v = 3.0 + row_tone[y]
			if t < 0.16:
				v -= 1.1                      # late wood: the dark ring line
			elif t < 0.3:
				v -= 0.6
			elif t > 0.75:
				v += 0.5
			v += rng.randf_range(-0.3, 0.3)
			idx_map.append(v)
	# pores: short dark dashes along the grain
	for k in range(40):
		var px = rng.randi_range(0, size - 1)
		var py = rng.randi_range(0, size - 1)
		for d in range(rng.randi_range(2, 4)):
			idx_map[py * size + (px + d) % size] -= 0.6
	# rays: a few light flecks
	for k in range(8):
		var px = rng.randi_range(0, size - 1)
		var py = rng.randi_range(0, size - 1)
		for d in range(rng.randi_range(3, 6)):
			idx_map[py * size + (px + d) % size] += 1.4
	for y in range(size):
		for x in range(size):
			var i = clampi(int(round(idx_map[y * size + x])), 0, ramp.size() - 1)
			img.set_pixel(x, y, ramp[i])
	return _finish(img)


# Altar cloth: dark red weave.
static func cloth(seed_value: int) -> ImageTexture:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	var ramp = _ramp(CLOTH)
	var img = Image.create(16, 16, false, Image.FORMAT_RGB8)
	for y in range(16):
		for x in range(16):
			var idx = 1 + ((x + y) % 2)
			if rng.randf() < 0.1:
				idx = 3
			img.set_pixel(x, y, ramp[idx])
	return _finish(img)


# Moonlight beam: see-through, strong at the top, gone at the bottom, in steps.
static func beam() -> ImageTexture:
	var img = Image.create(8, 32, false, Image.FORMAT_RGBA8)
	for y in range(32):
		var a = 1.0 - float(y) / 31.0
		a = floor(a * 5.0) / 5.0
		for x in range(8):
			var edge = 1.0 - absf(float(x) - 3.5) / 4.0
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a * edge * 0.5))
	return _finish(img)


# The round stained-glass window behind the altar - a full circle of petals.
static func rose_window() -> ImageTexture:
	var size = 64
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var glass = [Color.html("2f6fd0"), Color.html("c8323c"), Color.html("e2b23a"), Color.html("2fa39a")]
	var lead = Color.html("0a0810")
	var centre = Vector2(31.5, 31.5)
	for y in range(size):
		for x in range(size):
			var p = Vector2(x, y) - centre
			var r = p.length()
			var col = Color(0.0, 0.0, 0.0, 0.0)
			if r <= 31.0:
				var ang = atan2(p.y, p.x)
				var petal = int(floor((ang + PI) / TAU * 12.0)) % 12
				var edge = absf(fmod((ang + PI) / TAU * 12.0, 1.0) - 0.5)
				if r > 28.0:
					col = lead
				elif r > 24.0:
					col = glass[2]
				elif r > 22.5:
					col = lead
				elif r > 9.0:
					col = glass[petal % 4]
					if edge > 0.42:
						col = lead
					elif r > 15.0 and r < 16.5:
						col = lead
					elif r <= 15.0:
						col = glass[(petal + 2) % 4]
				elif r > 7.5:
					col = lead
				else:
					col = glass[2].lightened(0.3)
			img.set_pixel(x, y, col)
	return _finish(img)
