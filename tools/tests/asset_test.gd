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

	print("asset checks: %d" % checked)
	print("FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)
