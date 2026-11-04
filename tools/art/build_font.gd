extends SceneTree
## Builds the game font assets/fonts/game_font.res from Tiny5-Regular.ttf
## (OFL, docs/CREDITS.md). Tiny5 is drawn on an 8-unit em: crisp only at
## sizes 8, 16, ... So the font is fixed at 8 and scales by whole steps
## (INTEGER_ONLY): every size the UI asks for (6..15) draws at 8, 16+ at 16.
## No antialiasing, no hinting, no subpixel offsets: hard pixels that the
## canvas then scales with the rest of the art (Nearest).
##   godot --headless -s tools/art/build_font.gd

const SRC := "res://assets/fonts/Tiny5-Regular.ttf"
const OUT := "res://assets/fonts/game_font.res"


func _initialize() -> void:
	var src := load(SRC) as FontFile
	if src == null:
		push_error("no %s" % SRC)
		quit(1)
		return
	var f := FontFile.new()
	f.data = src.data
	f.fixed_size = 8
	f.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_INTEGER_ONLY
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	f.hinting = TextServer.HINTING_NONE
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	f.generate_mipmaps = false
	# Glyphs at the base 640x360 resolution, scaled with the canvas; the
	# global oversampling (window / base) would draw them at 2x and break
	# the fixed-size advances.
	f.oversampling = 1.0
	f.allow_system_fallback = true
	var err := ResourceSaver.save(f, OUT, ResourceSaver.FLAG_COMPRESS)
	print("font -> %s (%s)" % [OUT, "ok" if err == OK else error_string(err)])
	quit(0 if err == OK else 1)
