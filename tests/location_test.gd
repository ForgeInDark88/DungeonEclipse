extends SceneTree
## Layered locations (LocationInstance + LocationBuilder): 200 seeds × every
## node type with layers.
## - the same node gives the same plan and the same tiles;
## - every portal of the plan has a cell in its own layer, on firm ground;
## - inside each layer every portal is reachable from every other one and
##   from the layer's start (LevelNav ground paths, the monsters' graph);
## - the layers do not touch (an empty gap between their bedrock rims);
## - a boss location ends in the guardian's arena, its ways out locked.
##   godot --headless -s tests/location_test.gd

const CLEARANCE := 2

var LB = null
var LI = null
var fails := 0
var stats := {"objects": 0, "locks": 0, "lifts": 0, "side_floors": 0, "pois": 0, "locations": 0, "layers": 0, "portals": 0, "paths": 0, "build_ms": 0}


func check(c: bool, what: String) -> void:
	if not c:
		fails += 1
		if fails < 40:
			print("FAIL: " + what)


func _initialize() -> void:
	await process_frame
	LB = load("res://scripts/level/location_builder.gd")
	LI = load("res://scripts/core/location_instance.gd")
	var idb = root.get_node("ItemDatabase")
	check(idb.locations.size() >= 6, "location definitions are loaded (%d)" % idb.locations.size())
	var types: Array = idb.locations.keys()
	types.sort()
	var count := int(OS.get_environment("SEEDS")) if OS.get_environment("SEEDS") != "" else 200
	if OS.get_environment("TYPE") != "":
		types = [StringName(OS.get_environment("TYPE"))]
	for t in types:
		for i in count:
			var node := {"type": t, "depth": 1 + i % 24, "biome": idb.biomes[i % idb.biomes.size()].id,
					"seed": 5000 + i * 7919, "region": 0, "boss": &"", "sub": &""}
			_check_location(node, "%s seed %d" % [t, node["seed"]])
	# the same node twice: the same plan and the same tiles
	var n := {"type": &"level", "depth": 5, "biome": &"catacombs", "seed": 777, "region": 0}
	var a = LI.plan(n)
	var b = LI.plan(n)
	check(var_to_str(a.to_dict()) == var_to_str(b.to_dict()), "the same node gives the same plan")
	var la = LB.build(a)
	var lb = LB.build(b)
	check(la.tiles == lb.tiles and var_to_str(la.portal_cells) == var_to_str(lb.portal_cells), "the same plan gives the same tiles")
	var c = LI.from_dict(a.to_dict())
	check(LB.build(c).tiles == la.tiles, "a saved plan builds the same location")
	print("locations: %d, layers: %d, portals: %d, points of interest: %d, paths checked: %d, avg build %.1f ms" % [
		stats["locations"], stats["layers"], stats["portals"], stats["pois"], stats["paths"],
		float(stats["build_ms"]) / maxf(1.0, stats["locations"])])
	print("locked ways down: %d, lifts: %d, side floors: %d, objects checked: %d" % [stats["locks"], stats["lifts"], stats["side_floors"], stats["objects"]])
	print("FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)


func _check_location(node: Dictionary, tag: String) -> void:
	var li = LI.plan(node)
	check(li != null, "%s: planned" % tag)
	if li == null:
		return
	var t0 := Time.get_ticks_msec()
	var layout = LB.build(li)
	stats["build_ms"] += Time.get_ticks_msec() - t0
	stats["locations"] += 1
	stats["layers"] += layout.bands.size()
	check(layout.bands.size() == li.layers.size(), "%s: every layer is built" % tag)
	var def = root.get_node("ItemDatabase").locations[StringName(node["type"])]
	# a key-locked way down: its key lies on the surface; every lift has two ends
	for p in li.portals:
		if p.get("lock", &"") == &"key":
			stats["locks"] += 1
			var surf = layout.bands[0]["layout"]
			check(surf.specials.any(func(sp): return sp["type"] == &"key_drop"), "%s: the key of %s lies on the surface" % [tag, p["id"]])
		if p["kind"] == &"lift":
			stats["lifts"] += 1
			check(not li.portal(p["to"]).is_empty() and int(li.portal(p["to"])["layer"]) == 0, "%s: lift %s leads to the surface" % [tag, p["id"]])
	for l in li.layers:
		if l.has("special"):
			stats["side_floors"] += 1
	if def.boss_arena:
		var main_floors: Array = li.layers.filter(func(l): return not l.has("special"))
		check(int(main_floors[-1]["kind"]) == 2, "%s: the last floor is the arena" % tag)
		check(not li.is_open(&"map") and not li.is_open(&"arena_exit"), "%s: the ways out wait for the guardian" % tag)
		li.boss_beaten = true
		check(li.is_open(&"map") and li.is_open(&"arena_exit"), "%s: a beaten guardian opens them" % tag)
		li.boss_beaten = false
	# layers do not touch
	for i in range(1, layout.bands.size()):
		var prev: Rect2i = layout.bands[i - 1]["rect"]
		var cur: Rect2i = layout.bands[i]["rect"]
		check(cur.position.y - prev.end.y >= LB.GAP, "%s: a gap between layers %d and %d" % [tag, i - 1, i])
	for i in layout.bands.size():
		var band: Dictionary = layout.bands[i]
		var rect: Rect2i = band["rect"]
		var origin: Vector2i = band["origin"]
		var sub = band["layout"]
		var cells: Array[Vector2i] = []
		for p in li.portals_of(i):
			var pid := StringName(p["id"])
			stats["portals"] += 1
			check(layout.portal_cells.has(pid), "%s: portal %s has a cell" % [tag, pid])
			if not layout.portal_cells.has(pid):
				continue
			var c: Vector2i = layout.portal_cells[pid]
			check(rect.has_point(c), "%s: portal %s lies in its layer" % [tag, pid])
			check(layout.get_tile(c.x, c.y) == LevelLayout.Tile.EMPTY and LevelLayout.is_ground(layout.get_tile(c.x, c.y + 1)),
					"%s: portal %s stands on firm ground" % [tag, pid])
			cells.append(c)
		if int(band["kind"]) == 2:
			continue  # the arena: one room, the guardian's own checks (map/flow tests)
		# a layer is closed in rock: its own graph is the whole story
		var nav := LevelNav.new(sub)
		var start: Vector2i = sub.start_cell
		# nothing stands inside the rock
		for ch in sub.chests:
			var cc: Vector2i = ch["cell"]
			check(sub.get_tile(cc.x, cc.y) == LevelLayout.Tile.EMPTY, "%s: layer %d, chest %s in the open" % [tag, i, cc])
		for ec: Vector2i in sub.enemy_cells:
			check(sub.get_tile(ec.x, ec.y) != LevelLayout.Tile.BRICK and sub.get_tile(ec.x, ec.y) != LevelLayout.Tile.BEDROCK,
					"%s: layer %d, monster %s in the open" % [tag, i, ec])
		if int(band["kind"]) == 0:
			# the surface: every point of interest and every chest is reachable
			stats["pois"] += sub.pois.size()
			check(sub.pois.size() >= 2, "%s: the surface has points of interest (%d)" % [tag, sub.pois.size()])
			var surface_nav := LevelNav.new(sub)
			for poi in sub.pois:
				stats["paths"] += 1
				check(not surface_nav.ground_path(sub.start_cell, poi["cell"], CLEARANCE).is_empty(),
						"%s: point of interest %s at %s is reachable" % [tag, poi["type"], poi["cell"]])
			for ch in sub.chests:
				if ch.get("secret", false):
					continue  # behind a cracked wall: a pickaxe or a bomb first
				stats["paths"] += 1
				check(not surface_nav.ground_path(sub.start_cell, ch["cell"], 1).is_empty(),
						"%s: surface chest at %s is reachable" % [tag, ch["cell"]])
		# stage 20: nothing else stands in the rock either, and what the hero
		# walks up to on the surface is reachable from its start
		var things: Array = []
		for r in sub.resources:
			things.append(["resource " + String(r["kind"]), r["cell"], r["kind"] != &"tree"])
		for b in sub.breakables:
			things.append(["breakable " + String(b["look"]), b["cell"], true])
		for sp in sub.specials:
			things.append(["special " + String(sp["type"]), sp["cell"], true])
		if sub.lore_cell.x >= 0:
			things.append(["lore", sub.lore_cell, false])
		for th in things:
			var tc: Vector2i = th[1]
			stats["objects"] += 1
			var tt: int = sub.get_tile(tc.x, tc.y)
			check(tt != LevelLayout.Tile.BRICK and tt != LevelLayout.Tile.BEDROCK,
					"%s: layer %d, %s at %s stands in the open" % [tag, i, th[0], tc])
			if int(band["kind"]) == 0 and th[2]:
				stats["paths"] += 1
				check(not nav.ground_path(start, tc, 1).is_empty(),
						"%s: layer %d, %s at %s is reachable" % [tag, i, th[0], tc])
		for k in cells.size():
			var c: Vector2i = cells[k] - origin
			if c == start:
				continue
			stats["paths"] += 1
			var path: Array = nav.ground_path(start, c, CLEARANCE)
			if path.is_empty():
				var p1: Array = nav.ground_path(start, c, 1)
				check(false, "%s: layer %d, from the start to %s %s (clearance 1: %s)" % [tag, i, li.portals_of(i)[k]["id"], c, not p1.is_empty()])
