extends SceneTree
## Every data resource of the game (res://data/**.tres):
## - loads (no broken ext_resource, no parse error);
## - has a unique id within its kind (items, enemies, skills, ... by script);
## - the art it names exists: icons of items, skills, achievements, meta
##   upgrades; textures and sheets of enemies and traps; portraits of races
##   and NPCs; textures of buildings and decor;
## - the data base sees what lies on disk (ItemDatabase counts).
##   godot --headless -s tools/tests/data_test.gd

const ART_FIELDS := ["icon", "texture", "sheet", "portrait", "sheet_layout"]
var fails := 0
var loaded := 0


func check(c: bool, what: String) -> void:
	if not c:
		fails += 1
		if fails < 60:
			print("FAIL: " + what)


func _walk(path: String, out: Array) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for f in dir.get_files():
		var file := f.trim_suffix(".remap")
		if file.ends_with(".tres"):
			out.append(path.path_join(file))
	for d in dir.get_directories():
		_walk(path.path_join(d), out)


func _initialize() -> void:
	await process_frame
	var files: Array = []
	_walk("res://data", files)
	check(files.size() > 300, "data files found (%d)" % files.size())
	var ids := {}  # script path -> {id: file}
	for path in files:
		var res: Resource = load(path)
		check(res != null, "%s loads" % path)
		if res == null:
			continue
		loaded += 1
		var script: Script = res.get_script()
		var kind: String = script.resource_path.get_file() if script else res.get_class()
		# items share one id space whatever their sub-class (ItemDatabase.get_item)
		var is_item := "item_type" in res and "icon" in res
		if is_item:
			kind = "item"
		if "id" in res and res.get("id") != null and String(res.get("id")) != "":
			var id := String(res.get("id"))
			var seen: Dictionary = ids.get(kind, {})
			check(not seen.has(id), "%s: id «%s» is unique (also %s)" % [path, id, seen.get(id, "")])
			seen[id] = path
			ids[kind] = seen
		for field in ART_FIELDS:
			if field in res:
				var v = res.get(field)
				var is_enemy: bool = res.get_script() != null and res.get_script().resource_path.ends_with("enemy_data.gd")
				var must: bool = (field == "icon" and is_item) or (field in ["texture", "sheet", "sheet_layout"] and is_enemy and not bool(res.get("no_rewards")))
				if must:
					check(v != null, "%s: %s is set" % [path, field])
	var idb = root.get_node("ItemDatabase")
	check(idb.items.size() == ids.get("item", {}).size(), "the data base has every item (%d of %d)" % [idb.items.size(), ids.get("item", {}).size()])
	check(idb.enemies.size() > 0 and idb.bosses.size() > 0 and idb.biomes.size() > 0, "enemies, bosses and biomes are loaded")
	var summary := []
	for k in ids:
		summary.append("%s %d" % [String(k).trim_suffix(".gd"), ids[k].size()])
	summary.sort()
	print("data files: %d loaded; ids: %s" % [loaded, ", ".join(summary)])
	print("FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)
