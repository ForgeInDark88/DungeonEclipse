extends SceneTree
## Every layer of real locations loads and unloads in the game scene
## (stage 20). For SEEDS seeds × the node types with layers the hero enters
## the location and goes through every portal of its plan (LocationManager
## .travel, as E on a portal does). At each one:
## - the hero arrives in the portal's own layer and stands in the open on
##   firm ground; the camera is bounded by that layer;
## - monsters of the layers with no hero sleep (PROCESS_MODE_DISABLED),
##   the hero's layer is awake;
## after the round the location is left (retreat) and its nodes are freed:
## no monster, portal or chest of it stays in the tree.
##   godot --headless -s tests/layer_load_test.gd   (SEEDS=n, default 6)

var fails := 0
var visits := 0


func check(c: bool, what: String) -> void:
	if not c:
		fails += 1
		if fails < 40:
			print("FAIL: " + what)


func wait_scene(state: int) -> void:
	var flow = root.get_node("GameFlow")
	for i in 600:
		await process_frame
		if flow.state == state and not flow.is_busy() and current_scene != null:
			for k in 10:
				await process_frame
			return
	check(false, "the scene %d came up" % state)


func _initialize() -> void:
	await process_frame
	var sm = root.get_node("SaveManager")
	var flow = root.get_node("GameFlow")
	var gs = root.get_node("GameState")
	var idb = root.get_node("ItemDatabase")
	sm.saves_dir = "user://test_layer_load/"
	sm.remember_slot = false
	sm.delete_slot(1)
	sm.use_slot(1)
	flow.create_hero(idb.races[0], idb.classes[0], false, &"normal", 0)
	await wait_scene(flow.State.TOWN)
	var seeds := int(OS.get_environment("SEEDS")) if OS.get_environment("SEEDS") != "" else 6
	var types := [&"level", &"elite", &"rescue", &"lair", &"special", &"boss"]
	var LB = load("res://scripts/level/location_builder.gd")
	for s in seeds:
		var t: StringName = types[s % types.size()]
		flow.open_map()
		await wait_scene(flow.State.EXPEDITION_MAP)
		var id: int = gs.run.next_choices()[0]
		var node: Dictionary = gs.run.map.nodes[id]
		node["type"] = t
		node["seed"] = 31337 + s * 7717
		node["depth"] = 1 + (s * 5) % 20
		node["biome"] = idb.biomes[s % idb.biomes.size()].id
		if t == &"boss":
			node["boss"] = idb.bosses[s % idb.bosses.size()].id
		flow.enter_node(id)
		await wait_scene(flow.State.LOCATION)
		var tag := "%s seed %d" % [t, node["seed"]]
		var lm = current_scene.location
		check(lm != null, "%s: a location of layers" % tag)
		if lm == null:
			continue
		var lvl = current_scene.level
		var p = current_scene.player
		p._invulnerable = 9999.0
		var ids: Array = []
		for q in lm.instance.portals:
			ids.append(StringName(q["id"]))
		check(lvl.layout.bands.size() == lm.instance.layers.size(), "%s: every layer is in the level" % tag)
		for pid in ids:
			if not lvl.layout.portal_cells.has(pid):
				check(false, "%s: portal %s has a cell" % [tag, pid])
				continue
			lm.travel(pid)
			for i in 90:
				await process_frame
				if not lm._busy:
					break
			await create_timer(lm.TICK + 0.15).timeout  # one LocationManager tick
			visits += 1
			var want: int = int(lm.instance.portal(pid)["layer"])
			check(lm.band == want, "%s: through %s into layer %d (got %d)" % [tag, pid, want, lm.band])
			var cell: Vector2i = lvl.world_to_cell(p.global_position + Vector2(0, -2))
			var tile: int = lvl.layout.get_tile(cell.x, cell.y)
			check(tile != LevelLayout.Tile.BRICK and tile != LevelLayout.Tile.BEDROCK, "%s: at %s the hero is in the open" % [tag, pid])
			check(LevelLayout.is_ground(lvl.layout.get_tile(cell.x, cell.y + 1)) or p.is_on_floor() or lvl.layout.get_tile(cell.x, cell.y + 1) == LevelLayout.Tile.LADDER,
					"%s: at %s the hero stands on firm ground" % [tag, pid])
			var rect: Rect2 = lvl.band_rect_px(p.global_position)
			check(p.camera.limit_top >= int(rect.position.y) - 1 and p.camera.limit_bottom <= int(rect.end.y) + 71,
					"%s: at %s the camera keeps to the layer" % [tag, pid])
			for e in get_nodes_in_group("enemies"):
				var en := e as Node2D
				if en == null or not is_instance_valid(en):
					continue
				var bi: int = lvl.band_index_at(en.global_position)
				if bi < 0:
					continue
				if bi == lm.band:
					check(en.process_mode != Node.PROCESS_MODE_DISABLED, "%s: at %s a monster of the hero's layer is awake" % [tag, pid])
				else:
					check(en.process_mode == Node.PROCESS_MODE_DISABLED, "%s: at %s a monster of layer %d sleeps" % [tag, pid, bi])
		flow.retreat()
		await wait_scene(flow.State.RUN_RESULT)
		for i in 10:
			await process_frame
		check(get_nodes_in_group("layer_portals").is_empty() and get_nodes_in_group("enemies").is_empty(),
				"%s: leaving frees the location (portals %d, monsters %d)" % [tag, get_nodes_in_group("layer_portals").size(), get_nodes_in_group("enemies").size()])
		flow.back_to_town()
		await wait_scene(flow.State.TOWN)
	sm.delete_slot(1)
	print("locations: %d, portals visited: %d" % [seeds, visits])
	print("FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)
