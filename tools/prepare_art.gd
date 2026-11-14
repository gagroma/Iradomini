extends SceneTree
# PREPARE_ART - turns the downloaded paintings into small PS1-style textures.
#
# Run from the project folder:
#   godot --headless --path . --script res://tools/prepare_art.gd
#
# Sources: tools/art_src/*.jpg, downloaded from The Metropolitan Museum of Art
# Open Access (images.metmuseum.org). Every one of them is a public-domain
# work the museum releases under CC0 (no rights reserved, free for any use,
# commercial too). The list with object numbers goes to assets/art/CREDITS.md.
#
# Each picture is cropped to the painted surface (the game draws its own
# frames), shrunk so its longest side is SIZE pixels, and cut down to the
# PlayStation's 15-bit colour (32 steps per channel) with a 4x4 ordered
# dither, like PS1 textures were.

const SRC := "res://tools/art_src/"
const OUT := "res://assets/art/"
const SIZE := 128

# name: [source file, crop (left, top, right, bottom as fractions), title, artist, date, Met object]
const ART := {
	"van_eyck_crucifixion": ["met436282_van_eyck_crucifixion_last_judgment.jpg", [0.082, 0.066, 0.452, 0.94],
		"The Crucifixion (left wing of The Crucifixion; The Last Judgment)", "Jan van Eyck", "ca. 1436-38", 436282],
	"van_eyck_last_judgment": ["met436282_van_eyck_crucifixion_last_judgment.jpg", [0.566, 0.066, 0.935, 0.94],
		"The Last Judgment (right wing of The Crucifixion; The Last Judgment)", "Jan van Eyck", "ca. 1436-38", 436282],
	"saint_michael_dragon": ["met437742_saint_michael_dragon_valencian.jpg", [0.02, 0.02, 0.98, 0.98],
		"Saint Michael and the Dragon", "Spanish (Valencian) Painter", "ca. 1405", 437742],
	"ries_saint_michael": ["met437729_ries_saint_michael.jpg", [0.015, 0.012, 0.985, 0.988],
		"Saint Michael the Archangel", "Ignacio de Ries", "1640s", 437729],
	"fra_angelico_crucifixion": ["met435577_fra_angelico_crucifixion.jpg", [0.035, 0.085, 0.965, 0.9],
		"The Crucifixion", "Fra Angelico (Guido di Pietro)", "possibly ca. 1440", 435577],
	"christus_lamentation": ["met435898_christus_lamentation.jpg", [0.02, 0.025, 0.98, 0.975],
		"The Lamentation", "Petrus Christus", "ca. 1450", 435898],
	"murillo_crucifixion": ["met437172_murillo_crucifixion.jpg", [0.02, 0.015, 0.98, 0.985],
		"The Crucifixion", "Bartolome Esteban Murillo", "ca. 1675", 437172],
	"daddi_crucifixion": ["met438423_daddi_crucifixion.jpg", [0.02, 0.012, 0.98, 0.988],
		"The Crucifixion", "Bernardo Daddi", "ca. 1325-30", 438423],
	"duccio_madonna": ["met438754_duccio_madonna.jpg", [0.125, 0.09, 0.875, 0.925],
		"Madonna and Child", "Duccio di Buoninsegna", "ca. 1290-1300", 438754],
}

const BAYER := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var credits = "# Paintings used in the game\n\n"
	credits += "All images: The Metropolitan Museum of Art, New York, Open Access.\n"
	credits += "The works are in the public domain and the museum releases these images under\n"
	credits += "Creative Commons Zero (CC0): free to use for any purpose, including commercial.\n"
	credits += "https://www.metmuseum.org/policies/image-resources\n\n"
	credits += "The game uses cropped, shrunk, colour-reduced copies (tools/prepare_art.gd).\n\n"
	credits += "| Texture | Work | Artist | Date | Met object |\n|---|---|---|---|---|\n"
	for key in ART.keys():
		var a = ART[key]
		var img = Image.load_from_file(ProjectSettings.globalize_path(SRC + a[0]))
		if img == null:
			push_error("missing " + a[0])
			continue
		img.convert(Image.FORMAT_RGB8)
		var c = a[1]
		var w = img.get_width()
		var h = img.get_height()
		var rect = Rect2i(int(c[0] * w), int(c[1] * h), int((c[2] - c[0]) * w), int((c[3] - c[1]) * h))
		img = img.get_region(rect)
		var scale = float(SIZE) / maxf(img.get_width(), img.get_height())
		img.resize(maxi(1, int(round(img.get_width() * scale))), maxi(1, int(round(img.get_height() * scale))), Image.INTERPOLATE_LANCZOS)
		_ps1_colour(img)
		img.save_png(ProjectSettings.globalize_path(OUT + key + ".png"))
		print("prepare_art: ", key, " ", img.get_size())
		credits += "| %s.png | %s | %s | %s | [%d](https://www.metmuseum.org/art/collection/search/%d) |\n" % [key, a[2], a[3], a[4], a[5], a[5]]
	var f = FileAccess.open(OUT + "CREDITS.md", FileAccess.WRITE)
	f.store_string(credits)
	f.close()
	quit()


# 15-bit colour with an ordered dither.
func _ps1_colour(img: Image) -> void:
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var col = img.get_pixel(x, y)
			var d = (BAYER[(y % 4) * 4 + (x % 4)] / 16.0 - 0.5) / 31.0
			col.r = clampf(round((col.r + d) * 31.0) / 31.0, 0.0, 1.0)
			col.g = clampf(round((col.g + d) * 31.0) / 31.0, 0.0, 1.0)
			col.b = clampf(round((col.b + d) * 31.0) / 31.0, 0.0, 1.0)
			img.set_pixel(x, y, col)
