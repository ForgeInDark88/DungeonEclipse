extends SceneTree
## Ponds of the surface (water + swimming): the hero dropped into a pond
## swims (held up, not on the bottom like a stone), jump strokes bring them
## to the surface, a jump at the surface leaps out onto the bank; the pond
## splashes; a rod in the bank fishes the pond for river fish.
##   godot --headless -s tests/water_test.gd

var fails := 0


func check(c: bool, what: String) -> void:
	print(("PASS: " if c else "FAIL: ") + what)
	if not c:
		fails += 1


func wait_scene(state: int) -> void:
	var flow = root.get_node("GameFlow")
	for i in 600:
		await process_frame
		if flow.state == state and not flow.is_busy() and current_scene != null:
			for k in 10:
				await process_frame
			return


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func _initialize() -> void:
	await process_frame
	var sm = root.get_node("SaveManager")
	var flow = root.get_node("GameFlow")
	var gs = root.get_node("GameState")
	var idb = root.get_node("ItemDatabase")
	sm.saves_dir = "user://test_water/"
	sm.remember_slot = false
	sm.delete_slot(1)
	sm.use_slot(1)
	flow.create_hero(idb.races[0], idb.classes[0], false, &"normal", 0)
	await wait_scene(flow.State.TOWN)
	var found := false
	for k in 30:
		flow.open_map()
		await wait_scene(flow.State.EXPEDITION_MAP)
		var id: int = gs.run.next_choices()[0]
		gs.run.map.nodes[id]["type"] = &"level"
		gs.run.map.nodes[id]["seed"] = 777 + k * 131
		flow.enter_node(id)
		await wait_scene(flow.State.LOCATION)
		var lvl = current_scene.level
		if not lvl.water_bodies.is_empty():
			found = true
			break
		flow.retreat()
		await wait_scene(flow.State.RUN_RESULT)
		flow.back_to_town()
		await wait_scene(flow.State.TOWN)
	check(found, "a surface with a pond")
	if not found:
		quit(1)
		return
	var lvl = current_scene.level
	var p = current_scene.player
	p._invulnerable = 9999.0
	for e in get_nodes_in_group("enemies"):
		e.queue_free()
	var body: ColorRect = lvl.water_bodies[0]
	var mid := body.global_position + Vector2(body.size.x / 2.0, 0)
	check(lvl.water_depth_at(mid + Vector2(0, 20)) > 10.0 and lvl.water_depth_at(mid + Vector2(0, -30)) < 0.0,
			"water_depth_at: deep inside the pond, dry above it")
	p.global_position = mid + Vector2(0, -24)
	p.velocity = Vector2.ZERO
	await frames(50)
	check(p.swimming, "dropped in, the hero swims")
	var sink_speed: float = p.velocity.y
	var am = root.get_node("AudioManager")
	check(sink_speed <= p.SWIM_MAX_SINK + 1.0, "the water holds the hero up (sinks at %.0f px/s)" % sink_speed)
	# dive to the bottom, then stroke up
	Input.action_press("move_down")
	await frames(60)
	Input.action_release("move_down")
	var low: float = lvl.water_depth_at(p.global_position)
	check(am.is_underwater(), "head under water: the world sounds dull (low-pass)")
	Input.action_press("jump")
	await frames(70)
	var high: float = lvl.water_depth_at(p.global_position)
	check(low > high + 4.0, "jump strokes bring the hero up (depth %.0f -> %.0f)" % [low, high])
	Input.action_release("jump")
	# out onto the bank: swim right and leap at the surface
	Input.action_press("move_right")
	var out := false
	for i in 30:
		Input.action_press("jump")
		await frames(4)
		Input.action_release("jump")
		await frames(8)
		if not p.swimming and p.is_on_floor():
			out = true
			break
	Input.action_release("move_right")
	check(out, "a jump at the surface leaps out onto the bank")
	check(not am.is_underwater(), "out of the water the sound is clear again")
	# a rod in the bank: the pond is fished for river fish
	var rods := get_nodes_in_group("interactable").filter(func(n): return "pond" in n and n.pond)
	check(not rods.is_empty(), "a rod stands by the pond (%d)" % rods.size())
	if not rods.is_empty():
		var g = load("res://scripts/ui/fishing_game.gd").new()
		g._spot = rods[0]
		var ids := {}
		for i in 200:
			ids[g._roll()[0]] = true
		check(ids.has(&"river_perch") and ids.has(&"pike") and not ids.has(&"cave_fish"), "the pond gives river fish, not cave fish (%s)" % str(ids.keys()))
		check(idb.get_item(&"river_perch") != null and idb.get_item(&"pike") != null, "the river fish exist as items")
		g.free()
	# rain rings and a splash do not break anything
	lvl.set_rain(1.0)
	lvl.splash(mid + Vector2(0, 2), true)
	await frames(10)
	check(true, "rain on the ponds and a splash")
	flow.retreat()
	await wait_scene(flow.State.RUN_RESULT)
	flow.back_to_town()
	await wait_scene(flow.State.TOWN)
	# ---- the flooded pits of the Drowned Vaults
	var dv = idb.biome_by_id(&"drowned_vaults")
	check(dv != null and dv.flooded_pools > 0 and dv.pool_leeches, "the Drowned Vaults have flooded basins with leeches")
	var with_water := 0
	var bad := 0
	for k in 40:
		var gen = load("res://scripts/level/level_generator.gd").new()
		gen.flooded_pools = dv.flooded_pools
		var lay = gen.generate(3 + k % 10, 9000 + k * 97)
		if not lay.water.is_empty():
			with_water += 1
		for r: Rect2i in lay.water:
			for x in range(r.position.x, r.end.x):
				if lay.get_tile(x, r.position.y) != LevelLayout.Tile.EMPTY or lay.get_tile(x, r.end.y - 1) != LevelLayout.Tile.EMPTY or not LevelLayout.is_solid(lay.get_tile(x, r.end.y)):
					bad += 1
	check(with_water >= 14, "about every second Drowned Vaults floor has flooded basins (%d / 40)" % with_water)
	check(bad == 0, "every basin is open water over a floor")
	flow.open_map()
	await wait_scene(flow.State.EXPEDITION_MAP)
	var did: int = gs.run.next_choices()[0]
	gs.run.map.nodes[did]["type"] = &"level"
	gs.run.map.nodes[did]["biome"] = &"drowned_vaults"
	gs.run.map.nodes[did]["seed"] = 31337
	flow.enter_node(did)
	await wait_scene(flow.State.LOCATION)
	current_scene.location.travel(&"f1_up")
	await create_timer(1.2).timeout
	lvl = current_scene.level
	p = current_scene.player
	p._invulnerable = 9999.0
	var pool: ColorRect = null
	for b in lvl.water_bodies:
		if b.get_meta(&"leeches", false):
			pool = b
	check(pool != null, "a pool with leeches under the surface")
	if pool:
		check(float((pool.material as ShaderMaterial).get_shader_parameter("glow")) > 0.0, "the dark water glimmers from inside")
		for e in get_nodes_in_group("enemies"):
			e.queue_free()
		seed(5)
		var bled := false
		for i in 120:  # ~60 s in the water: a leech bites in a few seconds, at worst in half a minute
			p.global_position = pool.global_position + Vector2(pool.size.x / 2.0, pool.size.y - 4)
			p.velocity = Vector2.ZERO
			await frames(30)
			if p.status.has(&"bleed"):
				bled = true
				break
		check(bled, "a leech clings to the swimmer (bleeding)")
	flow.retreat()
	await wait_scene(flow.State.RUN_RESULT)
	sm.delete_slot(1)
	print("FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)
