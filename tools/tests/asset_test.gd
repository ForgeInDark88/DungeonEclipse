extends SceneTree
## The asset pipeline (docs/ASSET_BUDGET.md, stage B):
## - every path constant of AssetPaths (textures, sheets, sounds, music,
##   ambience, shaders, layouts) points at a file that exists;
## - every "res://assets/..." string in scripts/ and scenes/ exists (code
##   names art only through AssetPaths; the rest are data references);
## - a missing file gives the placeholder and a warning, never a crash;
## - texture imports keep pixel art crisp: no mipmaps, lossless.
##   godot --headless -s tools/tests/asset_test.gd

var fails := 0
var checked := 0


func check(c: bool, what: String) -> void:
	checked += 1
	if not c:
		fails += 1
		if fails < 60:
			print("FAIL: " + what)


func _paths_in(v, out: Array) -> void:
	if v is String and v.begins_with("res://") and v.get_extension() != "":
		out.append(v)
	elif v is Dictionary:
		for k in v:
			_paths_in(v[k], out)
	elif v is Array:
		for e in v:
			_paths_in(e, out)


func _walk(path: String, exts: Array, out: Array) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for f in dir.get_files():
		if f.get_extension() in exts:
			out.append(path.path_join(f))
	for d in dir.get_directories():
		if not d.begins_with("."):
			_walk(path.path_join(d), exts, out)


func _initialize() -> void:
	await process_frame
	var ap: Script = load("res://scripts/core/asset_paths.gd")
	var consts: Dictionary = ap.get_script_constant_map()
	var paths: Array = []
	for k in consts:
		_paths_in(consts[k], paths)
	check(paths.size() > 150, "AssetPaths names its files (%d)" % paths.size())
	for p in paths:
		check(ResourceLoader.exists(p), "AssetPaths file exists: %s" % p)

	# Every literal asset path in code and scenes.
	var src: Array = []
	_walk("res://scripts", ["gd"], src)
	_walk("res://scenes", ["tscn"], src)
	var rx := RegEx.create_from_string("res://assets/[A-Za-z0-9_/\\.-]+\\.(png|wav|ogg|gdshader|webm|ttf)")
	var literal := 0
	for f in src:
		var text := FileAccess.get_file_as_string(f)
		for m in rx.search_all(text):
			literal += 1
			check(ResourceLoader.exists(m.get_string()), "%s names a missing file %s" % [f, m.get_string()])
	print("literal asset paths in code and scenes: %d" % literal)

	# Biome backgrounds are paths (loaded on entering the biome): they exist.
	var biomes: Array = []
	for d in ["res://data/biomes", "res://data/surface", "res://data/town"]:
		_walk(d, ["tres"], biomes)
	var layers := 0
	for f in biomes:
		var b = load(f)
		if b == null or not ("parallax_far" in b):
			continue
		for k in ["parallax_far", "parallax_mid", "parallax_near"]:
			var path: String = b.get(k)
			if path != "":
				layers += 1
				check(ResourceLoader.exists(path), "%s %s exists: %s" % [f, k, path])
		check(not FileAccess.get_file_as_string(f).contains("backgrounds/") or b.parallax_far != "",
			"%s does not load its backgrounds with the data" % f)
	check(layers >= 50, "biome background layers named (%d)" % layers)

	# A missing file: placeholder + one warning, no crash.
	var t: Texture2D = ap.tex("res://assets/sprites/__nope__.png")
	check(t != null and t.get_width() == 16, "missing texture -> 16x16 placeholder")
	check(ap.tex("res://assets/sprites/__nope__.png") == t, "the placeholder is shared")
	check(ap.tex_or_null("res://assets/sprites/__nope__.png") == null, "tex_or_null stays null")
	check(ap.shader("res://assets/shaders/__nope__.gdshader") == null, "missing shader -> null")
	check(ap.missing_count() >= 2, "missing paths are counted (%d)" % ap.missing_count())
	check(ap.tex(ap.SLOT) != t, "a present texture is not the placeholder")

	# Imports: pixel art, no mipmaps, lossless.
	var imports: Array = []
	_walk("res://assets", ["import"], imports)
	var bad := 0
	for f in imports:
		if not f.ends_with(".png.import"):
			continue
		var text := FileAccess.get_file_as_string(f)
		if text.contains("mipmaps/generate=true") or not text.contains("compress/mode=0"):
			bad += 1
			if bad < 10:
				print("FAIL: import of %s: mipmaps or lossy compression" % f)
	check(bad == 0, "png imports lossless without mipmaps (%d bad of %d)" % [bad, imports.size()])
	check(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter") == 0,
		"canvas texture filter is Nearest")

	# 47-variant wall tiles: every biome atlas has its _blob atlas of the
	# size Autotile expects, and the mask table has 47 distinct tiles.
	var at: Script = load("res://scripts/level/autotile.gd")
	var seen := {}
	for m in 256:
		seen[at.index_of(m)] = true
	check(seen.size() == 47 and at.index_of(0) == 0 and at.index_of(255) == 46, "47 blob tiles, isolated = 0, interior = 46")
	var tilesets: Array = []
	_walk("res://assets/sprites/tiles", ["png"], tilesets)
	var blobs := 0
	for f in tilesets:
		if f.ends_with("_blob.png"):
			continue
		var bp: String = f.get_basename() + "_blob.png"
		check(ResourceLoader.exists(bp), "%s has its 47-variant atlas (tools/art/gen_autotiles.py)" % f)
		if ResourceLoader.exists(bp):
			blobs += 1
			var bt: Texture2D = load(bp)
			check(bt.get_width() == 16 * at.COLUMNS and bt.get_height() == 16 * at.ROWS_PER_VARIANT * at.VARIANTS,
				"%s is %dx%d" % [bp, 16 * at.COLUMNS, 16 * at.ROWS_PER_VARIANT * at.VARIANTS])
	check(blobs >= 18, "blob atlases (%d)" % blobs)

	# Every dungeon biome: 50+ decorations (hand-made + its decor pack,
	# tools/art/gen_decor_pack.py), each with a texture.
	var dungeon_biomes: Array = []
	_walk("res://data/biomes", ["tres"], dungeon_biomes)
	for f in dungeon_biomes:
		var b = load(f)
		if b == null or not b.has_method("all_decorations"):
			continue
		var all: Array = b.all_decorations()
		check(all.size() >= 50, "%s has 50+ decorations (%d)" % [f, all.size()])
		for d in all:
			if d.texture == null:
				check(false, "%s: a decoration without a texture" % f)
				break

	# The town: every building looks different at levels 1, 2, 3
	# (tools/art/gen_building_levels.py); every passer-by has both sheets.
	var buildings: Array = []
	_walk("res://data/buildings", ["tres"], buildings)
	for f in buildings:
		var bd = load(f)
		var ts := []
		for lvl in [1, 2, 3]:
			ts.append(ap.building_texture(bd, lvl))
		check(ts[0] != ts[1] and ts[1] != ts[2] and ts[2] != null and ts[2] != ap.placeholder(),
			"%s: its own sprite at levels 1, 2, 3" % f)
	var pb: Script = load("res://scripts/world/town_passerby.gd")
	check(pb.ROLES.size() >= 25, "25+ passers-by (%d)" % pb.ROLES.size())
	for role in pb.ROLES:
		for anim in ["idle", "walk"]:
			check(ResourceLoader.exists("res://assets/sprites/npc/folk_%s_%s.png" % [role, anim]), "passer-by %s has its %s sheet" % [role, anim])
	check(pb.count_for(0, false) >= 2 and pb.count_for(30, false) > pb.count_for(3, false) and pb.count_for(30, true) <= 3,
		"more passers-by as the town prospers, a few at night")

	# The interface font (docs/CREDITS.md): the theme uses it, and it draws
	# every character of every Russian and English string of the game.
	var theme: Theme = load(ProjectSettings.get_setting("gui/theme/custom"))
	var font: Font = theme.default_font if theme else null
	check(font != null and font.resource_path == "res://assets/fonts/game_font.res", "theme font is the game font")
	if font:
		var chars := {}
		for f in ["res://locale/messages.json", "res://locale/en.po"]:
			for ch in FileAccess.get_file_as_string(f):
				chars[ch] = true
		var missing := ""
		for ch in chars:
			var code: int = ch.unicode_at(0)
			if code > 32 and code != 0xFEFF and not font.has_char(code):
				missing += ch
		check(missing == "", "the font draws every character of the strings (missing: %s)" % missing)

	print("asset checks: %d" % checked)
	print("FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)
