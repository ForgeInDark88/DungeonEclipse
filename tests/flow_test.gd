extends SceneTree
## The town ↔ expedition loop (GameFlow): hero creation → town → map →
## a location → back on the map → camp → home; death; a quit mid-expedition;
## the town save (round trip, broken file, newer format). Run with
##   xvfb-run -a godot --rendering-driver opengl3 -s tests/flow_test.gd
## (writes only user://test_town.save).

var fails := 0


func check(c: bool, what: String) -> void:
	print(("PASS: " if c else "FAIL: ") + what)
	if not c:
		fails += 1


func wait_scene(state: int, frames := 240) -> void:
	var flow = root.get_node("GameFlow")
	for i in frames:
		await process_frame
		if flow.state == state and not flow.is_busy() and current_scene != null:
			for k in 30:
				await process_frame
			return


func _initialize() -> void:
	await process_frame
	var sm = root.get_node("SaveManager")
	var flow = root.get_node("GameFlow")
	var gs = root.get_node("GameState")
	var idb = root.get_node("ItemDatabase")
	root.get_node("MetaProgress").apply_upgrades = false
	sm.town_path = "user://test_town.save"
	sm.clear_town()

	# ---------------------------------------------------- hero → town
	flow.create_hero(idb.races[0], idb.classes[0], false, &"normal", 0)
	await wait_scene(flow.State.TOWN)
	check(gs.expedition and gs.is_town(), "a new hero starts in the town")
	check(current_scene.scene_file_path == gs.GAME and current_scene.level.layout.is_town, "the town street is built")
	check(sm.has_town(), "the town is saved right away")

	# ---------------------------------------------------- town → map
	flow.open_map()
	await wait_scene(flow.State.EXPEDITION_MAP)
	check(gs.run != null and gs.run.map.nodes.size() > 10, "the gate opens an expedition map")
	check(sm.load_town().expedition_active, "the save knows an expedition is under way")
	var first: int = gs.run.next_choices()[0]
	check(gs.run.map.node(first)["type"] == &"level", "the road starts with a dungeon")

	# ---------------------------------------------------- map → location
	check(not flow.enter_node(9999), "a node far away cannot be entered")
	flow.enter_node(first)
	await wait_scene(flow.State.LOCATION)
	check(current_scene.scene_file_path == gs.GAME and not gs.is_town(), "a dungeon node is a platformer location")
	check(gs.floor_number == int(gs.run.map.node(first)["depth"]), "the location's depth drives the floor number")
	var gold_before: int = gs.hero.gold
	gs.hero.add_gold(40)
	gs.run.add_resource(&"wood", 3)

	# ---------------------------------------------------- location → map
	flow.location_cleared()
	await wait_scene(flow.State.EXPEDITION_MAP)
	check(gs.run.node_id == first and gs.run.path.size() == 1, "back on the map after the exit")
	# walk to a camp (or the nearest node) and go home
	var camp := -1
	for id in gs.run.next_choices():
		if gs.run.map.node(id)["type"] == &"camp":
			camp = id
	if camp < 0:
		# force one for the test
		camp = gs.run.next_choices()[0]
		gs.run.map.nodes[camp]["type"] = &"camp"
	flow.enter_node(camp)
	await wait_scene(flow.State.LOCATION)
	check(current_scene.name == "CampScreen", "a camp node opens the camp")
	flow.retreat()
	await wait_scene(flow.State.RUN_RESULT)
	check(flow.last_result["outcome"] == 2 and flow.last_result["gold"] >= 40, "retreat: the result screen counts the gold")
	check(gs.town.resource(&"wood") == 3, "retreat: resources reach the town")
	check(not sm.load_town().expedition_active, "retreat: the expedition is closed in the save")
	flow.back_to_town()
	await wait_scene(flow.State.TOWN)
	check(gs.hero.gold >= gold_before + 40, "retreat keeps the hero's gold")

	# ---------------------------------------------------- death
	var lvl: int = gs.hero.level
	flow.open_map()
	await wait_scene(flow.State.EXPEDITION_MAP)
	flow.enter_node(gs.run.next_choices()[0])
	await wait_scene(flow.State.LOCATION)
	gs.run.add_resource(&"stone", 5)
	gs.hero.add_gold(100)
	flow.hero_died()
	await wait_scene(flow.State.RUN_RESULT)
	check(gs.hero.gold == 0, "death: the gold is lost")
	check(gs.town.resource(&"stone") == 0 and gs.town.resource(&"wood") == 3, "death: found resources are lost, the town keeps its own")
	check(gs.hero.level == lvl, "death: the hero keeps the level")
	check(gs.hero.equipment.items.values().any(func(i): return i != null), "death: the class kit is handed out again")
	flow.back_to_town()
	await wait_scene(flow.State.TOWN)

	# ---------------------------------------------------- guardian arenas
	flow.open_map()
	await wait_scene(flow.State.EXPEDITION_MAP)
	var bid: int = gs.run.next_choices()[0]
	gs.run.map.nodes[bid]["type"] = &"lair"
	gs.run.map.nodes[bid]["boss"] = &"illusionist"
	gs.run.map.nodes[bid]["biome"] = &"mirror_halls"
	flow.enter_node(bid)
	await wait_scene(flow.State.LOCATION)
	var bosses := current_scene.get_tree().get_nodes_in_group("bosses")
	check(current_scene.level.layout.is_arena, "a lair node is a boss arena")
	check(bosses.size() == 1 and bosses[0].boss.id == &"illusionist", "the lair's own guardian waits there")
	check(gs.current_biome().id == &"mirror_halls", "the arena stands in the node's biome")
	flow.hero_died()
	await wait_scene(flow.State.RUN_RESULT)
	flow.back_to_town()
	await wait_scene(flow.State.TOWN)

	# ---------------------------------------------------- quit mid-expedition
	gs.hero.add_gold(77)
	flow.save_town()
	flow.open_map()
	await wait_scene(flow.State.EXPEDITION_MAP)
	flow.quit_to_menu()
	await wait_scene(flow.State.MAIN_MENU)
	check(flow.continue_game(), "continue loads the town")
	await wait_scene(flow.State.TOWN)
	check(gs.hero.gold == 0 and not gs.town.expedition_active, "a quit mid-expedition counts as lost")
	check(int(gs.town.stats.get("lost", 0)) == 1, "the town remembers the lost expedition")

	# ---------------------------------------------------- the save file
	gs.town.add_resource(&"iron", 4)
	gs.town.add_resident(&"test_npc")
	gs.town.set_flag("test_flag", 3)
	flow.save_town()
	var t2 = sm.load_town()
	check(t2 != null and t2.resource(&"iron") == 4 and t2.has_resident(&"test_npc") and t2.flag("test_flag") == 3,
		"town save round trip keeps resources, residents and flags")
	# a broken main file falls back to the backup
	flow.save_town()
	var f := FileAccess.open(sm.town_path, FileAccess.WRITE)
	f.store_string("garbage {{{")
	f.close()
	check(sm.load_town() != null, "a broken town.save falls back to the backup copy")
	# a save of a newer game is never half-loaded
	var cfg := ConfigFile.new()
	cfg.set_value("save", "format", 999)
	cfg.set_value("town", "data", {})
	cfg.save(sm.town_path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(sm.town_path + ".bak"))
	check(sm.load_town() == null, "a newer save format is refused, not crashed on")
	sm.clear_town()

	print("FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)
