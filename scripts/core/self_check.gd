class_name SelfCheck
extends Node
## Release build check: `DungeonEclipse -- --selfcheck` loads the data,
## starts a run on floor 1, prints what it found and quits (exit code 1 when
## something is missing). Catches resources lost by the export (.remap,
## export filters). Lives under the root: scene changes do not free it.


func _ready() -> void:
	var counts := "items=%d enemies=%d biomes=%d bosses=%d classes=%d races=%d lore=%d" % [ItemDatabase.items.size(),
			ItemDatabase.enemies.size(), ItemDatabase.biomes.size(), ItemDatabase.bosses.size(),
			ItemDatabase.classes.size(), ItemDatabase.races.size(), ItemDatabase.lore.size()]
	var ok := ItemDatabase.items.size() > 0 and ItemDatabase.enemies.size() > 0 and ItemDatabase.biomes.size() > 0
	if ok:
		GameState.start_new_run(ItemDatabase.races[0], ItemDatabase.classes[0], 777, false, &"normal")
		GameState.next_floor()
		for i in 150:
			await get_tree().process_frame
		var g := get_tree().current_scene
		var lvl: Variant = g.get("level") if g else null
		var mobs := get_tree().get_nodes_in_group("enemies").size()
		ok = lvl != null and mobs > 0
		counts += " floor=%d level=%s mobs=%d" % [GameState.floor_number, lvl != null, mobs]
	print("SELFCHECK ", "OK " if ok else "FAIL ", counts)
	get_tree().quit(0 if ok else 1)
