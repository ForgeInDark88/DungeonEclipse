extends SceneTree
## The town ↔ expedition loop (GameFlow): hero creation → town → map →
## a location → back on the map → camp → home; death; a quit mid-expedition;
## the town save (round trip, broken file, newer format). Run with
##   xvfb-run -a godot --rendering-driver opengl3 -s tests/flow_test.gd
## (writes only user://test_saves/).

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
	sm.saves_dir = "user://test_saves/"
	sm.remember_slot = false
	sm.delete_slot(1)
	sm.use_slot(1)

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
	gs.hero.stats.hp = 10
	var g0: int = gs.hero.gold
	current_scene._rest()
	check(gs.hero.stats.hp > 10 and gs.hero.gold == g0, "the first rest at the fire is free and heals")
	var hp1: int = gs.hero.stats.hp
	gs.hero.add_gold(500)
	current_scene._rest()
	check(gs.hero.gold == g0 + 500 - current_scene.rest_price(), "the next rest costs gold")
	check(current_scene._merchant != null and not current_scene._merchant.stock.is_empty(), "the camp has a trader with goods")
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

	# ---------------------------------------------------- a rescue
	flow.open_map()
	await wait_scene(flow.State.EXPEDITION_MAP)
	var rid: int = gs.run.next_choices()[0]
	gs.run.map.nodes[rid]["type"] = &"rescue"
	gs.run.map.nodes[rid]["npc"] = &"blacksmith"
	flow.enter_node(rid)
	await wait_scene(flow.State.LOCATION)
	var cages := current_scene.get_tree().get_nodes_in_group("rescue_cages")
	check(cages.size() == 1, "a rescue node has the prisoner's cage")
	if cages.size() == 1:
		var cage = cages[0]
		check(cage.guards_left() > 0, "the cage is guarded")
		cage.interact(current_scene.player)
		check(gs.run.rescued.is_empty(), "the lock holds while the guards live")
		for g in cage._guards:
			g.queue_free()
		await process_frame
		cage.interact(current_scene.player)
		check(&"blacksmith" in gs.run.rescued, "the guards are down: the blacksmith is freed")
		for b in current_scene.get_children():
			if b is DialogBook:
				b.close()
	current_scene.finish_location()
	await process_frame
	flow.location_cleared()
	await wait_scene(flow.State.EXPEDITION_MAP)

	# ---------------------------------------------------- an event
	var eid: int = gs.run.next_choices()[0]
	gs.run.map.nodes[eid]["type"] = &"event"
	flow.enter_node(eid)
	await wait_scene(flow.State.LOCATION)
	check(current_scene.scene_file_path == gs.GAME and current_scene.level.layout.is_event_room, "an event node is a room on the road")
	var spots := current_scene.get_tree().get_nodes_in_group("event_spots")
	check(spots.size() == 1 and spots[0].event != null, "the event's scenery waits in the room")
	var gold_e: int = gs.hero.gold
	spots[0].interact(current_scene.player)
	var dlg: EventDialog = null
	for c in current_scene.get_children():
		if c is EventDialog:
			dlg = c
	check(dlg != null, "walking up to it opens the choice")
	if dlg:
		dlg.choose({"outcomes": [{"chance": 1.0, "text": "t", "effects": {"gold": 10, "resource": {"herbs": 2}, "fight": "level"}}]})
		dlg.close()
	await process_frame
	check(gs.hero.gold > gold_e and int(gs.run.resources.get("herbs", 0)) >= 2, "the choice's outcome is applied")
	check(current_scene.level.is_sealed() and current_scene.get_tree().get_nodes_in_group("enemies").size() > 0,
		"a fight answer brings monsters into the room and seals the exit")
	check(not spots[0].can_interact(), "the event is spent once answered")
	flow.retreat()
	await wait_scene(flow.State.RUN_RESULT)
	check(gs.town.has_resident(&"blacksmith"), "home alive: the freed blacksmith moves into the town")
	flow.back_to_town()
	await wait_scene(flow.State.TOWN)
	var people := current_scene.get_tree().get_nodes_in_group("town_npcs")
	check(people.any(func(n): return n.data.id == &"blacksmith"), "the blacksmith walks the street")

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
	check(current_scene.level.location_mode and int(current_scene.level.layout.bands[-1]["kind"]) == 2, "a lair node ends in a boss arena")
	check(bosses.size() == 1 and bosses[0].boss.id == &"illusionist", "the lair's own guardian waits there")
	check(gs.current_biome().id == &"mirror_halls", "the arena stands in the node's biome")
	flow.hero_died()
	await wait_scene(flow.State.RUN_RESULT)
	flow.back_to_town()
	await wait_scene(flow.State.TOWN)

	# ---------------------------------------------------- save and continue
	gs.hero.add_gold(77)
	flow.save_town()
	flow.open_map()
	await wait_scene(flow.State.EXPEDITION_MAP)
	flow.enter_node(gs.run.next_choices()[0])
	await wait_scene(flow.State.LOCATION)
	gs.hero.add_gold(5)
	flow.location_cleared()
	await wait_scene(flow.State.EXPEDITION_MAP)
	var node_q: int = gs.run.node_id
	var gold_q: int = gs.hero.gold
	flow.save_and_quit()
	await wait_scene(flow.State.MAIN_MENU)
	check(flow.continue_game(1), "continue loads the world")
	await wait_scene(flow.State.EXPEDITION_MAP)
	check(gs.run != null and gs.run.node_id == node_q and gs.hero.gold == gold_q, "the expedition goes on from its save on the map")
	# a crash before the next save point: the used run.save is not loaded twice
	flow._leave_to_menu()
	await wait_scene(flow.State.MAIN_MENU)
	check(flow.continue_game(1), "continue loads the world again")
	await wait_scene(flow.State.TOWN)
	check(gs.run == null and gs.hero.gold == 0 and not gs.town.expedition_active, "a used expedition save is lost, not replayed")
	check(int(gs.town.stats.get("lost", 0)) == 1, "the town remembers the lost expedition")
	# a location of layers: down a portal, a chest, a monster, save and back
	flow.open_map()
	await wait_scene(flow.State.EXPEDITION_MAP)
	var lnode: int = gs.run.next_choices()[0]
	gs.run.map.nodes[lnode]["type"] = &"level"
	flow.enter_node(lnode)
	await wait_scene(flow.State.LOCATION)
	var lm = current_scene.location
	check(lm != null and current_scene.level.location_mode, "a level node is a location of layers")
	if lm:
		check(lm.band == 0 and current_scene.level.layout.bands[0]["kind"] == 0, "the hero starts on the surface")
		check(current_scene.get_tree().get_nodes_in_group("layer_portals").size() >= 4, "the portals between the layers stand")
		lm.travel(&"f1_up")
		await create_timer(1.0).timeout
		check(lm.band == 1, "the main entrance leads to the first floor")
		check(lm.instance.save_portal == &"f1_up", "a portal is a save point")
		var chest_id := -1
		for c in current_scene.get_tree().get_nodes_in_group("chests"):
			if current_scene.level.band_index_at(c.global_position) == 1 and not c.opened:
				c.open()
				chest_id = int(c.get_meta(&"loc"))
				break
		var foe_id := -1
		for e in current_scene.get_tree().get_nodes_in_group("enemies"):
			if current_scene.level.band_index_at(e.global_position) == 1 and e.has_meta(&"loc"):
				foe_id = int(e.get_meta(&"loc"))
				e.remove_from_group("enemies")
				e.queue_free()
				break
		await create_timer(0.8).timeout
		var node_l: int = gs.run.node_id
		flow.save_and_quit()
		await wait_scene(flow.State.MAIN_MENU)
		check(flow.continue_game(1), "continue loads the world inside a location")
		await wait_scene(flow.State.LOCATION)
		var lm2 = current_scene.location
		check(lm2 != null and gs.run.node_id == node_l, "back in the same location")
		if lm2:
			check(lm2.band == 1, "the hero is back at the last save point, down on the first floor")
			var reopened := false
			for c in current_scene.get_tree().get_nodes_in_group("chests"):
				if c.has_meta(&"loc") and int(c.get_meta(&"loc")) == chest_id:
					reopened = c.opened
			check(chest_id < 0 or reopened, "the opened chest stays open after the load")
			var back := false
			for e in current_scene.get_tree().get_nodes_in_group("enemies"):
				if e.has_meta(&"loc") and int(e.get_meta(&"loc")) == foe_id:
					back = true
			check(foe_id < 0 or not back, "the fallen monster of the dungeon stays dead")
			lm2.travel(&"main")
			await create_timer(1.0).timeout
			check(lm2.band == 0, "the way up leads to the entrance it went down")
	flow._leave_to_menu()
	await wait_scene(flow.State.MAIN_MENU)
	flow.continue_game(1)
	await wait_scene(flow.State.LOCATION)
	check(gs.run != null and current_scene.location != null and current_scene.location.band == 0,
			"a quit without saving: back at the last save point (the main entrance)")
	flow.retreat()
	await wait_scene(flow.State.RUN_RESULT)
	check(not sm.has_expedition(), "the end of an expedition deletes its save")
	flow.back_to_town()
	await wait_scene(flow.State.TOWN)

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
	sm.delete_slot(1)

	print("FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)
