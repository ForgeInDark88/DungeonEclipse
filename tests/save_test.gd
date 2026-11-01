extends SceneTree
## World slots (SaveManager): slots and their info, rename, delete, the
## checksum and the backup, a damaged slot, format migration, the old
## town.save moving into slot 1, the expedition save (map, hero, finds)
## round trip without losses.   godot --headless -s tests/save_test.gd
## (writes only user://test_saves_s/)

var fails := 0


func check(c: bool, what: String) -> void:
	print(("PASS: " if c else "FAIL: ") + what)
	if not c:
		fails += 1


func _initialize() -> void:
	await process_frame
	var sm = root.get_node("SaveManager")
	var gs = root.get_node("GameState")
	var idb = root.get_node("ItemDatabase")
	root.get_node("MetaProgress").apply_upgrades = false
	sm.saves_dir = "user://test_saves_s/"
	sm.remember_slot = false
	for n in range(1, sm.SLOT_COUNT + 1):
		sm.delete_slot(n)
	check(sm.SLOT_COUNT >= 5, "at least five slots")
	check(sm.free_slot() == 1 and not sm.slot_info(1)["exists"], "all slots start empty")

	# ---------------------------------------------------- a world in slot 2
	sm.use_slot(2)
	var town := TownState.new()
	Buildings.init_town(town)
	gs.town = town
	gs.expedition = true
	var hero := Hero.new(idb.races[0], idb.classes[1], idb.equipment_layout)
	hero.give_starting_kit()
	hero.add_gold(321)
	town.hero = RunCodec.save_hero(hero)
	town.add_resource(&"stone", 9)
	town.prosperity = 7
	check(sm.save_town(town, {"name": "Аурелия", "created": 1, "playtime": 3725}) == OK, "a world is saved into its slot")
	var info: Dictionary = sm.slot_info(2)
	check(info["exists"] and info["name"] == "Аурелия" and int(info["playtime"]) == 3725 and int(info["prosperity"]) == 7,
		"the slot tells its name, playtime and prosperity")
	check(int(info["updated"]) > 0 and info.has("region") and int(info["heroes"]) >= 1, "the slot tells the date, region and heroes")
	check(sm.free_slot() == 1, "the free slot skips the taken one")
	check(sm.rename_slot(2, "Новая Аурелия") and sm.slot_info(2)["name"] == "Новая Аурелия", "a slot can be renamed")
	var back = sm.load_town()
	check(back != null and back.resource(&"stone") == 9 and RunCodec.load_hero(back.hero).gold == 321, "the world loads back with its hero")

	# ---------------------------------------------------- checksum and backup
	sm.save_town(town, {"name": "Аурелия"})
	var cfg := ConfigFile.new()
	cfg.load(sm.town_path)
	var data: Dictionary = cfg.get_value("town", "data")
	data["resources"] = {"stone": 999}  # edited by hand, checksum left alone
	cfg.set_value("town", "data", data)
	cfg.save(sm.town_path)
	var t2 = sm.load_town()
	check(t2 != null and t2.resource(&"stone") == 9 and sm.used_backup, "a wrong checksum: the backup copy is loaded")
	var f := FileAccess.open(sm.town_path, FileAccess.WRITE)
	f.store_string("§§ not a save §§")
	f.close()
	var f2 := FileAccess.open(sm.town_path + ".bak", FileAccess.WRITE)
	f2.store_string("also broken")
	f2.close()
	check(sm.load_town() == null and sm.last_error == "damaged", "both copies broken: no crash, the slot reports damage")
	check(sm.slot_info(2).get("broken", false), "the load screen sees the broken slot")
	sm.delete_slot(2)
	check(not sm.slot_exists(2), "a slot can be deleted")

	# ---------------------------------------------------- format migration
	sm.use_slot(3)
	var old := ConfigFile.new()
	old.set_value("save", "format", 1)
	var od := town.to_dict()
	od.erase("world_seed")
	old.set_value("town", "data", od)
	old.save(sm.town_path)
	var mig = sm.load_town()
	check(mig != null and mig.world_seed != 0 and mig.resource(&"stone") == 9, "a format-1 world is migrated on load")
	var newer := ConfigFile.new()
	newer.set_value("save", "format", 999)
	newer.set_value("town", "data", {})
	newer.save(sm.town_path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(sm.town_path + ".bak"))
	check(sm.load_town() == null and sm.last_error == "newer", "a world of a newer game is refused")
	sm.delete_slot(3)

	# ---------------------------------------------------- the old town.save
	sm.use_slot(0)
	sm.legacy_town_path = "user://test_saves_s/old_town.save"
	sm.town_path = sm.legacy_town_path
	sm.save_town(town)
	sm.migrate_legacy_town()
	check(sm.slot_exists(1) and not FileAccess.file_exists(sm.legacy_town_path), "the old town.save moves into slot 1")
	sm.use_slot(1)
	var moved = sm.load_town()
	check(moved != null and moved.resource(&"stone") == 9, "slot 1 holds the old town")

	# ---------------------------------------------------- the expedition
	var run := RunState.new()
	run.seed_value = 4242
	run.map = ExpeditionMap.generate(4242, 0)
	run.node_id = run.map.start_nodes()[0]
	run.path.append(run.node_id)
	run.add_resource(&"wood", 3)
	run.rescued.append(&"healer")
	run.finds.append(&"iron_sword")
	sm.save_expedition({"used": false, "at": "map", "run": run.to_dict(), "hero": RunCodec.save_hero(hero)})
	var e: Dictionary = sm.load_expedition()
	var r2 := RunState.from_dict(e.get("run", {}))
	check(var_to_str(r2.map.nodes) == var_to_str(run.map.nodes) and r2.node_id == run.node_id, "the expedition's map and position come back")
	check(r2.resources.get("wood", 0) == 3 and &"healer" in r2.rescued and &"iron_sword" in r2.finds, "found resources, people and items come back")
	check(r2.next_choices() == run.next_choices(), "the next forks are the same")
	var h2 := RunCodec.load_hero(e.get("hero", {}))
	check(h2 != null and h2.gold == hero.gold and h2.class_data == hero.class_data, "the expedition's hero comes back")
	sm.clear_expedition()
	check(not sm.has_expedition(), "an expedition save can be deleted (death)")
	for n in range(1, sm.SLOT_COUNT + 1):
		sm.delete_slot(n)

	# ------------------------------------------- network settings, profiles
	NetSettings.path = "user://test_net_settings.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(NetSettings.path))
	check(int(NetSettings.get_value("port")) == 7777 and NetSettings.rules()["path"] == "vote", "network settings start at the defaults")
	NetSettings.set_value("port", 7801)
	NetSettings.set_value("friendly_fire", "off")
	NetSettings.set_value("nick", "Тест")
	check(int(NetSettings.get_value("port")) == 7801 and NetSettings.rules()["friendly_fire"] == "off"
			and String(NetSettings.get_value("nick")) == "Тест", "network settings are kept")
	var pp = root.get_node("PlayerProfiles")
	pp.identity_path = "user://test_identity.cfg"
	var tok: String = pp.local_token()
	check(tok != "" and pp.local_token() == tok, "the token stays the same")
	pp.reset_token()
	check(pp.local_token() != tok, "a reset gives a new token")
	var book = load("res://scripts/ui/multiplayer_book.gd").new()
	root.add_child(book)
	await process_frame
	check(book.get_child_count() > 0, "the multiplayer screen opens")
	book.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(NetSettings.path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(pp.identity_path))
	print("FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)
