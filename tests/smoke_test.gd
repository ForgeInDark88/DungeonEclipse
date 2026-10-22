extends Node
## End-to-end smoke test: data, generator, inventory, weapons, audio and a
## scripted play-through with screenshots (saved to user://smoke_shots/).
## Run: godot --path . res://tests/smoke_test.tscn  (exit code 0 = all passed).
## Note: it records one finished run in user://meta.cfg.

const OUT := "user://smoke_shots/"
var failures: Array[String] = []
var _finished := false


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)
		printerr("FAIL: ", msg)
	else:
		print("ok: ", msg)


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img:
		img.save_png(OUT + name + ".png")


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func press(action: String, hold_frames: int = 1) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(hold_frames)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await frames(2)


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	await frames(1)
	# Survive change_scene_to_file: hand the "current scene" role to a dummy.
	var dummy := Node.new()
	get_tree().root.add_child(dummy)
	get_tree().current_scene = dummy
	await frames(2)
	_test_data()
	_test_generator()
	_test_inventory()
	_test_weapons()
	_test_audio()
	_test_statuses()
	# The player's real Sanctum progress must neither affect nor be changed by the test.
	var meta_backup := [MetaProgress.shards, MetaProgress.gold, MetaProgress.levels.duplicate(), MetaProgress.unlocked.duplicate()]
	_test_meta()
	MetaProgress.apply_upgrades = false
	await _test_scenes()
	MetaProgress.shards = meta_backup[0]
	MetaProgress.gold = meta_backup[1]
	MetaProgress.levels = meta_backup[2]
	MetaProgress.unlocked = meta_backup[3]
	MetaProgress.apply_upgrades = true
	MetaProgress.save_progress()
	if not _finished:
		failures.append("scenario did not reach the end (script error?)")
	print("FAILURES: ", failures.size())
	for f in failures:
		print("  - ", f)
	get_tree().quit(1 if failures.size() > 0 else 0)


func _test_data() -> void:
	check(ItemDatabase.items.size() >= 30, "items loaded: %d" % ItemDatabase.items.size())
	check(ItemDatabase.races.size() == 4, "4 races")
	check(ItemDatabase.classes.size() == 4, "4 classes")
	check(ItemDatabase.enemies.size() >= 8, "monster types: %d" % ItemDatabase.enemies.size())
	check(ItemDatabase.elites.size() >= 5, "elite affixes: %d" % ItemDatabase.elites.size())
	check(ItemDatabase.loot_tables.size() >= 5, "loot tables loaded: %d" % ItemDatabase.loot_tables.size())
	check(ItemDatabase.equipment_layout.slots.size() == 8, "8 equip slots")
	for c in ItemDatabase.classes:
		check(c.skills.size() == 4, "class %s has 4 skills" % c.id)
		for id in c.starting_items:
			check(ItemDatabase.items.has(id), "start item %s exists" % id)
	var t: LootTable = ItemDatabase.get_loot_table(&"chest_common")
	var rarities := [0, 0, 0]
	for i in 500:
		for e in t.roll(5):
			rarities[e["item"].rarity] += 1
	print("rarity distribution chest_common floor 5: ", rarities)
	check(rarities[0] > 0 and rarities[1] > 0 and rarities[2] > 0, "all rarities can drop")


func _test_meta() -> void:
	MetaProgress.reset()
	check(MetaProgress.upgrades.size() >= 8, "sanctum upgrades: %d" % MetaProgress.upgrades.size())
	var orc: RaceData = null
	for r in ItemDatabase.races:
		if r.id == &"orc":
			orc = r
	check(orc != null and not MetaProgress.is_unlocked(orc), "orc is locked at first")
	check(not MetaProgress.unlock(orc), "cannot unlock without shards")
	var vit: MetaUpgradeData = null
	for up in MetaProgress.upgrades:
		if up.id == &"vitality":
			vit = up
	var race: RaceData = ItemDatabase.races[0]
	var cls: ClassData = ItemDatabase.classes[0]
	var plain := Hero.new(race, cls, ItemDatabase.equipment_layout)
	plain.give_starting_kit()
	var base_hp := plain.stats.max_hp()
	# A run with a seal and two shards in the backpack, 2 bosses, floor 13, 200 gold.
	plain.inventory.add_item(ItemDatabase.get_item(&"guardian_seal"), 1)
	plain.inventory.add_item(ItemDatabase.get_item(MetaProgress.SHARD_ITEM), 2)
	var reward := MetaProgress.finish_run(plain, 13, {"bosses": 2, "gold": 200})
	check(reward["shards"] == 5 + 2 + 6 + 6 and reward["gold"] == 50, "run rewards: %s" % reward)
	check(MetaProgress.shards == 19 and MetaProgress.gold == 50, "rewards banked")
	check(MetaProgress.buy_upgrade(vit) and MetaProgress.level_of(&"vitality") == 1, "bought vitality 1")
	check(MetaProgress.unlock(orc) and MetaProgress.is_unlocked(orc), "orc unlocked for shards")
	check(not MetaProgress.unlock(orc), "no double unlock")
	var h := Hero.new(race, cls, ItemDatabase.equipment_layout)
	h.give_starting_kit()
	MetaProgress.apply_to(h)
	check(h.stats.max_hp() == base_hp + 8 and h.stats.hp == h.stats.max_hp(), "meta HP bonus applied (%d -> %d)" % [base_hp, h.stats.max_hp()])
	var cfg := ConfigFile.new()
	check(cfg.load(SaveManager.META_PATH) == OK and cfg.get_value("sanctum", "levels", {}).get(&"vitality", 0) == 1, "sanctum saved to meta.cfg")
	check(cfg.has_section_key("meta", "total_runs") or SaveManager.total_runs == 0, "meta section kept")
	MetaProgress.reset()


func _test_generator() -> void:
	var T = LevelLayout.Tile
	for floor_n in range(1, 9):
		for s in 25:
			var lay := LevelGenerator.new().generate(floor_n, s * 7919 + floor_n)
			var st := lay.start_cell
			var ex := lay.exit_cell
			if lay.get_tile(st.x, st.y) != T.EMPTY or lay.get_tile(ex.x, ex.y) != T.EMPTY:
				check(false, "start/exit empty floor %d seed %d" % [floor_n, s])
				return
			if not LevelLayout.is_ground(lay.get_tile(ex.x, ex.y + 1)):
				check(false, "exit on ground f%d s%d" % [floor_n, s])
				return
			# flood fill through non-solid cells
			var seen := {st: true}
			var q: Array[Vector2i] = [st]
			while not q.is_empty():
				var c: Vector2i = q.pop_back()
				for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var n: Vector2i = c + d
					if not seen.has(n) and not LevelLayout.is_solid(lay.get_tile(n.x, n.y)):
						seen[n] = true
						q.append(n)
			if not seen.has(ex):
				check(false, "exit reachable f%d s%d" % [floor_n, s])
				return
	check(true, "generator: 200 levels have reachable exits")
	var lay := LevelGenerator.new().generate(1, 12345)
	var lines: PackedStringArray = []
	for y in lay.height:
		var line := ""
		for x in lay.width:
			var ch := ".#=-HT"[lay.get_tile(x, y)]
			if Vector2i(x, y) == lay.start_cell:
				ch = "S"
			elif Vector2i(x, y) == lay.exit_cell:
				ch = "X"
			line += ch
		lines.append(line)
	print("\n".join(lines))
	print("chests: ", lay.chests.size(), " enemies: ", lay.enemy_cells.size())


func _test_inventory() -> void:
	var hero := Hero.new(ItemDatabase.races[0], ItemDatabase.classes[0], ItemDatabase.equipment_layout)
	check(hero.class_data.id == &"warrior", "classes sorted: warrior first")
	hero.give_starting_kit()
	var dmg_before := hero.stats.damage()
	check(hero.equipment.get_item(&"weapon") != null, "weapon equipped from kit")
	check(hero.quick_bar.get_item(0) != null, "quick bar filled")
	var axe := ItemDatabase.get_item(&"war_axe")
	hero.inventory.add_item(axe)
	var idx := hero.inventory.find_index(&"war_axe")
	hero.equip_from_inventory(idx)
	check(hero.equipment.get_item(&"weapon") == axe, "axe equipped")
	check(hero.stats.damage() > dmg_before, "damage grows with axe (%f > %f)" % [hero.stats.damage(), dmg_before])
	check(hero.inventory.count_of(&"rusty_sword") == 1, "old sword back in backpack")
	var ring := ItemDatabase.get_item(&"ruby_ring")
	hero.inventory.add_item(ring)
	hero.inventory.add_item(ring)
	hero.equip_from_inventory(hero.inventory.find_index(&"ruby_ring"))
	hero.equip_from_inventory(hero.inventory.find_index(&"ruby_ring"))
	check(hero.equipment.get_item(&"ring_1") == ring and hero.equipment.get_item(&"ring_2") == ring, "two rings")
	hero.unequip_to_inventory(&"ring_2")
	check(hero.equipment.get_item(&"ring_2") == null and hero.inventory.count_of(&"ruby_ring") == 1, "unequip ring")
	var potion := ItemDatabase.get_item(&"health_potion")
	var left := hero.inventory.add_item(potion, 25)
	check(left == 0 and hero.inventory.count_of(&"health_potion") == 28, "potion stacking (%d)" % hero.inventory.count_of(&"health_potion"))
	var hp_before := hero.stats.max_hp()
	hero.add_xp(500)
	check(hero.level > 1 and hero.stats.max_hp() > hp_before, "level up raises hp (lvl %d)" % hero.level)
	check(hero.skills.skill_points == hero.level - 1, "skill points")
	check(hero.skills.upgrade(0) and hero.skills.get_level(0) == 2, "skill upgrade")
	# fill backpack
	var filler := ItemDatabase.get_item(&"iron_sword")
	var rest := hero.inventory.add_item(filler, 100)
	check(rest > 0 and hero.inventory.is_full(), "backpack limit")


func _test_weapons() -> void:
	var per_type := {}
	for item: ItemData in ItemDatabase.items.values():
		if item is WeaponItemData:
			per_type[item.weapon_type] = per_type.get(item.weapon_type, 0) + 1
	for t in 7:
		check(per_type.get(t, 0) >= 2, "weapon type %s has >= 2 items (%d)" % [WeaponItemData.WEAPON_TYPE_NAMES[t], per_type.get(t, 0)])
	check(ItemDatabase.affixes.size() >= 10, "affixes loaded: %d" % ItemDatabase.affixes.size())
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var tmpl: WeaponItemData = ItemDatabase.get_item(&"knight_sword")
	var inst := ItemFactory.create(tmpl, 3, rng) as WeaponItemData
	check(inst != tmpl and inst.template == tmpl and inst.affixes.size() == 1, "rare weapon instance with 1 affix: %s" % inst.display_name)
	check(tmpl.affixes.is_empty() and tmpl.display_name == "Рыцарский меч", "template untouched")
	var epic := ItemFactory.create(ItemDatabase.get_item(&"eclipse_blade"), 1, rng) as WeaponItemData
	check(epic.affixes.size() == 2, "epic weapon has 2 affixes: %s" % epic.display_name)
	var common := ItemFactory.create(ItemDatabase.get_item(&"iron_sword"), 1, rng)
	check(common.is_instance() and common.durability == common.max_durability and common.affixes.is_empty(), "common weapon: instance with durability, no affixes")
	var potion := ItemFactory.create(ItemDatabase.get_item(&"health_potion"))
	check(not potion.is_instance(), "stackables stay templates")
	var hero := Hero.new(ItemDatabase.races[0], ItemDatabase.classes[2], ItemDatabase.equipment_layout)  # mage
	hero.give_starting_kit()
	check(hero.weapon() != null and hero.weapon().weapon_type == WeaponItemData.WeaponType.STAFF, "mage starts with a staff")
	var dmg_staff := hero.stats.damage()
	var axe := ItemFactory.create(ItemDatabase.get_item(&"war_axe"))
	hero.inventory.add_item(axe)
	hero.equip_from_inventory(hero.inventory.find_item(axe))
	check(hero.stats.weapon_penalty < 1.0, "mage with axe gets a class penalty")
	var tip := TooltipText.item(axe, hero, true)
	check("DPS" in tip and "плохо владеет" in tip, "weapon tooltip shows DPS and class penalty")
	hero.wear_weapon(axe.max_durability)
	check(axe.is_broken() and hero.stats.weapon_base == axe.base_damage * 0.5, "broken weapon hits for half")
	var tbl := ItemDatabase.get_loot_table(&"chest_epic")
	var got_affix := false
	for i in 30:
		for e in tbl.roll(5, rng):
			if e["item"] is WeaponItemData and not e["item"].affixes.is_empty():
				got_affix = true
	check(got_affix, "epic chests drop weapons with affixes")
	print("sample names: ", inst.display_name, " | ", epic.display_name)


func _test_audio() -> void:
	for b in [&"Music", &"SFX", &"UI"]:
		check(AudioServer.get_bus_index(b) >= 0, "audio bus %s exists" % b)
	var missing := []
	for id in AssetPaths.SFX:
		if not ResourceLoader.exists(AssetPaths.SFX[id]):
			missing.append(id)
	for id in AssetPaths.MUSIC:
		if not ResourceLoader.exists(AssetPaths.MUSIC[id]):
			missing.append(id)
	check(missing.is_empty(), "all sound files exist %s" % str(missing))
	for item: ItemData in ItemDatabase.items.values():
		if item is UsableItemData and not AssetPaths.SFX.has(item.use_sound):
			missing.append(item.use_sound)
	for e in ItemDatabase.enemies:
		for snd in [e.sound_hurt, e.sound_death]:
			if not AssetPaths.SFX.has(snd):
				missing.append(snd)
	check(missing.is_empty(), "data sound ids are known %s" % str(missing))
	AudioManager.play_sfx(&"explosion")
	AudioManager.play_ui(&"ui_click")


func _test_statuses() -> void:
	var st := StatusEffects.new()
	st.apply(&"slow", 3.0, 0.5)
	check(is_equal_approx(st.speed_multiplier(), 0.5), "slow halves speed")
	st.apply(&"burn", 3.0, 2.0)
	check(st.has(&"burn") and not st.has(&"slow"), "fire melts ice (slow removed by burn)")
	st.apply(&"slow", 3.0, 0.5)
	check(st.has(&"slow") and not st.has(&"burn"), "ice puts out fire")
	st.apply(&"shield", 5.0, 30.0)
	check(st.absorb(20) == 0 and st.absorb(20) == 10 and not st.has(&"shield"), "shield absorbs 30 then breaks")
	st.immunities = [&"poison"]
	st.apply(&"poison", 3.0, 2.0)
	check(not st.has(&"poison"), "immunity blocks poison")
	st.free()
	var skel: EnemyData = load("res://data/enemies/skeleton.tres")
	check(&"poison" in skel.status_immunities, "skeletons are immune to poison")


func _test_scenes() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
	await frames(10)
	await shot("01_main_menu")
	get_tree().change_scene_to_file("res://scenes/ui/character_creation.tscn")
	await frames(10)
	await shot("02_character_creation")
	# Unlocked race + class from the Sanctum are selectable.
	MetaProgress.unlocked.assign([&"orc", &"paladin"])
	get_tree().change_scene_to_file("res://scenes/ui/character_creation.tscn")
	await frames(10)
	var cc := get_tree().current_scene
	cc._select_race(ItemDatabase.races[3])
	cc._select_class(ItemDatabase.classes[3])
	check(not cc._race_buttons[3].disabled and cc._class.id == &"paladin", "unlocked orc paladin selectable")
	await frames(3)
	await shot("02a_orc_paladin")
	MetaProgress.unlocked.clear()
	MetaProgress.shards = 25
	MetaProgress.gold = 320
	get_tree().change_scene_to_file("res://scenes/ui/sanctum.tscn")
	await frames(10)
	await shot("02b_sanctum")
	# Fixed seeds: the scripted play-through is reproducible (variety is
	# covered by the generator test above).
	seed(4242)
	GameState.start_new_run(ItemDatabase.races[1], ItemDatabase.classes[0], 777)
	await frames(30)
	var game := get_tree().current_scene
	check(game != null and game.name == "Game", "game scene loaded")
	await frames(10)
	check(AudioManager._music_id == &"catacombs", "biome music plays (%s)" % AudioManager._music_id)
	var player := get_tree().get_first_node_in_group("player") as Player
	check(player != null and player.level != null, "player in level")
	await frames(30)
	check(player.is_on_floor(), "player standing on floor (pos %s, start %s, tile below %d, vel %s, climbing %s)" % [player.global_position,
			player.level.start_position(), player.level.kind_at(player.global_position + Vector2(0, 4)), player.velocity, player.climbing])
	await shot("03_game_start")
	var x0 := player.global_position.x
	Input.action_press("move_right")
	await frames(30)
	Input.action_release("move_right")
	Input.action_press("move_left")
	await frames(30)
	Input.action_release("move_left")
	check(absf(player.global_position.x - x0) > 1.0 or player.is_on_wall(), "player moves")
	var y0 := player.global_position.y
	Input.action_press("jump")
	await frames(10)
	check(player.global_position.y < y0 - 10.0, "player jumps")
	Input.action_release("jump")
	await frames(60)
	# --- stage 11: animation checks (enemies frozen so no hit-stop interferes)
	print("time_scale before anim checks: ", Engine.time_scale, " hp ", player.hero.stats.hp)
	for e in get_tree().get_nodes_in_group("enemies"):
		e.set_physics_process(false)
	await frames(10)
	check(player.visual.layout != null and player.visual.layout.has_animation("run"), "hero layout loaded")
	check(player.visual.get_child(0).sprite_frames != null, "hero body layer has frames")
	Input.action_press("move_right")
	await frames(12)
	check(player.animator.state in [HeroAnimator.State.RUN, HeroAnimator.State.FALL, HeroAnimator.State.JUMP, HeroAnimator.State.LAND] or player.is_on_wall(), "animator leaves IDLE while moving (%d)" % player.animator.state)
	Input.action_release("move_right")
	await frames(20)
	var ev := InputEventAction.new()
	ev.action = "jump"
	ev.pressed = true
	Input.parse_input_event(ev)
	var air_states := []
	for i in 20:
		await get_tree().physics_frame
		air_states.append(player.animator.state)
	var up := InputEventAction.new()
	up.action = "jump"
	Input.parse_input_event(up)
	check(HeroAnimator.State.JUMP in air_states or HeroAnimator.State.FALL in air_states, "animator JUMP/FALL in air %s" % str(air_states))
	await frames(60)
	check(player.animator.state in [HeroAnimator.State.IDLE, HeroAnimator.State.LAND], "animator idle/land after landing (%d)" % player.animator.state)
	player.camera.zoom = Vector2(4, 4)
	player._attack_cooldown = 0.0
	player.attack()
	check(player.animator.state == HeroAnimator.State.ACTION, "attack plays action anim (state %d, climbing %s)" % [player.animator.state, player.climbing])
	await frames(3)
	await shot("11a_hero_attack_zoom")
	await frames(30)
	var helm := ItemDatabase.get_item(&"iron_helm")
	player.hero.inventory.add_item(helm)
	player.hero.equip_from_inventory(player.hero.inventory.find_index(&"iron_helm"))
	await frames(2)
	check(player.visual._layers[&"head"].sprite_frames == player.visual.layout.build_frames(helm.visual_sheet), "helmet changes head layer")
	await shot("11b_hero_helmet_zoom")
	player.camera.zoom = Vector2.ONE
	for e in get_tree().get_nodes_in_group("enemies"):
		e.set_physics_process(true)
	var some_enemy := get_tree().get_nodes_in_group("enemies")[0] as Enemy
	check(some_enemy.sprite.sprite_frames.has_animation("idle") and some_enemy.sprite.is_playing(), "enemy animated")
	# --- stage 12: weapon in hand + real hits
	check(player.visual._held_default == player.hero.weapon().icon, "weapon drawn in hand")
	# Fresh target monster right in front of the hero.
	var target: Enemy = (load("res://scenes/enemies/enemy.tscn") as PackedScene).instantiate()
	target.setup(load("res://data/enemies/skeleton.tres"), 1)
	player.level.add_entity(target, player.global_position)
	await frames(1)
	target.set_physics_process(false)
	target.global_position = player.global_position + Vector2(player.facing * 14.0, 0)
	var hp_before := target.hp
	var dur_before := player.hero.weapon().durability
	player._attack_cooldown = 0.0
	player.attack()
	await frames(25)
	check(target.hp < hp_before, "melee swing damages enemy in front (%d -> %d)" % [hp_before, target.hp])
	check(player.hero.weapon().durability < dur_before, "weapon wears on hit")
	target.queue_free()
	var bow := ItemFactory.create(ItemDatabase.get_item(&"short_bow"))
	player.hero.inventory.add_item(bow)
	player.hero.equip_from_inventory(player.hero.inventory.find_item(bow))
	await frames(2)
	check(player.visual._held_default == bow.icon, "bow in hand after equip")
	player._attack_cooldown = 0.0
	player.attack()
	var arrows := 0
	for i in 30:
		await frames(1)
		for n in player.level.entities.get_children():
			if n is Projectile:
				arrows += 1
	check(arrows > 0, "bow shoots an arrow")
	player.camera.zoom = Vector2(4, 4)
	await shot("12a_bow_zoom")
	player.camera.zoom = Vector2.ONE
	# --- 15.7 minimap
	var minimap: Minimap = game.get_node("Minimap")
	var explored := 0
	for v in player.level.explored:
		explored += v
	check(explored > 20, "minimap reveals around the hero (%d cells)" % explored)
	await press("minimap")
	check(minimap.is_big_open(), "M opens the big map")
	player.level.reveal_all()
	await frames(3)
	await shot("15_7_minimap")
	await press("minimap")
	check(not minimap.is_big_open(), "M closes the big map")
	# --- 15.6 random events
	check(ItemDatabase.room_events.size() >= 5, "room events: %d" % ItemDatabase.room_events.size())
	var ev_count := 0
	for k in 10:
		var lay := LevelGenerator.new().generate(3, 1000 + k)
		for sp in lay.specials:
			if sp["type"] == &"event":
				ev_count += 1
	check(ev_count >= 10, "every floor has event rooms (%d in 10 floors)" % ev_count)
	for e in get_tree().get_nodes_in_group("enemies"):
		e.set_physics_process(false)
	var lv2 := player.level
	var here := lv2.world_to_cell(player.global_position)
	var fountain: Node = (load("res://scenes/events/fountain.tscn") as PackedScene).instantiate()
	fountain.setup_event(lv2, {"cell": here})
	lv2.add_entity(fountain, player.global_position + Vector2(30, 0))
	player.hero.stats.lose_hp(40)
	var hp_f := player.hero.stats.hp
	await frames(2)
	fountain.interact(player)
	check(player.hero.stats.hp > hp_f and fountain.used, "fountain heals once")
	var altar: Node = (load("res://scenes/events/altar.tscn") as PackedScene).instantiate()
	altar.setup_event(lv2, {"cell": here})
	lv2.add_entity(altar, player.global_position + Vector2(-30, 0))
	await frames(2)
	var hp_a := player.hero.stats.hp
	altar.interact(player)
	check(altar.used and player.hero.stats.hp < hp_a, "altar takes blood for a gift")
	var enemies_before := get_tree().get_nodes_in_group("enemies").size()
	var cursed: Node = (load("res://scenes/events/cursed_chest.tscn") as PackedScene).instantiate()
	cursed.setup_event(lv2, {"cell": here})
	lv2.add_entity(cursed, player.global_position + Vector2(50, 0))
	await frames(2)
	cursed.interact(player)
	await frames(2)
	check(player.status.has(&"curse") and get_tree().get_nodes_in_group("enemies").size() > enemies_before, "cursed chest curses and summons an ambush")
	player.camera.zoom = Vector2(2, 2)
	await shot("15_6_events")
	player.camera.zoom = Vector2.ONE
	var cage: Node = (load("res://scenes/events/prisoner.tscn") as PackedScene).instantiate()
	cage.setup_event(lv2, {"cell": here})
	lv2.add_entity(cage, player.global_position + Vector2(70, 0))
	await frames(2)
	cage.interact(player)
	check(cage.used, "prisoner can be freed")
	var puzzle: Node2D = (load("res://scenes/events/puzzle.tscn") as PackedScene).instantiate()
	var room_rect := Rect2i(here - Vector2i(8, 6), Vector2i(17, 7))
	puzzle.setup_event(lv2, {"cell": here, "room": room_rect})
	lv2.add_entity(puzzle, player.global_position)
	await frames(2)
	check(puzzle.levers.size() >= 2 and puzzle.chest.sealed, "puzzle: levers placed, chest sealed (%d levers)" % puzzle.levers.size())
	if puzzle.levers.size() >= 2:
		for rune in puzzle.order:
			for l in puzzle.levers:
				if l.rune == rune:
					puzzle.pull(l, player)
		check(puzzle.solved and not puzzle.chest.sealed, "right rune order opens the barrier")
	for n in [fountain, altar, cursed, cage, puzzle]:
		n.queue_free()
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.global_position.distance_to(player.global_position) < 120.0:
			e.queue_free()
		else:
			e.set_physics_process(true)
	player.status.clear()
	player.hero.stats.heal(9999)
	# --- 15.5 new monsters and elites
	var showcase := []
	var x_off := 30.0
	for id in ["spider", "golem", "ghost", "summoner"]:
		var m: Enemy = (load("res://scenes/enemies/enemy.tscn") as PackedScene).instantiate()
		var elite: EliteAffixData = ItemDatabase.elites[showcase.size() % ItemDatabase.elites.size()] if id == "golem" else null
		var d: EnemyData = load("res://data/enemies/%s.tres" % id)
		if d.ceiling_ambush:
			d = d.duplicate()
			d.ceiling_ambush = false
		m.setup(d, 3, elite)
		player.level.add_entity(m, player.global_position + Vector2(x_off, 0))
		x_off += 26.0
		showcase.append(m)
	await frames(3)
	for m in showcase:
		m.set_physics_process(false)
	check(showcase[2].collision_mask == 0, "ghost flies through walls")
	check(showcase[1].elite != null and showcase[1].max_hp > 80 and " " in showcase[1].display_name(), "elite golem: %s, %d HP" % [showcase[1].display_name(), showcase[1].max_hp])
	showcase[3]._raise_summons()
	await frames(2)
	check(showcase[3]._alive_summons() >= 1, "necromancer raises skeletons")
	player.camera.zoom = Vector2(2.5, 2.5)
	player.camera.reset_smoothing()
	await frames(2)
	await shot("15_5_monsters")
	player.camera.zoom = Vector2.ONE
	for m in showcase:
		for sm in m._summons:
			if is_instance_valid(sm):
				sm.queue_free()
		m.queue_free()
	# --- 15.3 gold and merchant
	var gold0 := player.hero.gold
	var victim: Enemy = (load("res://scenes/enemies/enemy.tscn") as PackedScene).instantiate()
	victim.setup(load("res://data/enemies/cultist.tres"), 1)
	player.level.add_entity(victim, player.global_position)
	await frames(2)
	victim.take_damage(99999)
	await frames(60)
	for pk in get_tree().get_nodes_in_group("pickups"):
		if pk.item.id == &"gold_coin":
			pk.collect(player.hero)
	check(player.hero.gold > gold0, "monsters drop gold (%d -> %d)" % [gold0, player.hero.gold])
	var merchant: Merchant = (load("res://scenes/npc/merchant.tscn") as PackedScene).instantiate()
	merchant.floor_number = 2
	player.level.add_entity(merchant, player.global_position + Vector2(20, 0))
	await frames(2)
	check(merchant.stock.size() >= 4, "merchant has stock: %d" % merchant.stock.size())
	player.hero.add_gold(500)
	merchant.interact(player)
	await frames(5)
	var shop: ShopBook = null
	for n in game.get_children():
		if n is ShopBook:
			shop = n
	check(shop != null and get_tree().paused, "shop opens and pauses")
	if shop:
		await shot("15_3_shop")
		var g := player.hero.gold
		var potions := player.hero.inventory.count_of(&"health_potion")
		shop.buy(0)
		check(player.hero.gold < g and player.hero.inventory.count_of(&"health_potion") == potions + 1, "buying a potion costs gold")
		var idx := player.hero.inventory.find_index(&"health_potion")
		var g2 := player.hero.gold
		shop.sell(idx)
		check(player.hero.gold > g2, "selling gives gold")
		shop.close()
		await frames(2)
	check(not get_tree().paused, "shop closes")
	merchant.queue_free()
	# --- 15.2 traps
	var traps := get_tree().get_nodes_in_group("traps")
	check(traps.size() > 0, "traps placed: %d" % traps.size())
	var spike: Trap = null
	for t in traps:
		if t.data.kind == TrapData.Kind.SPIKES:
			spike = t
	if spike == null:
		# Floor 1 may roll only rocks: put a spike trap next to the hero.
		spike = (load("res://scenes/traps/trap.tscn") as PackedScene).instantiate()
		spike.setup(load("res://data/traps/spikes.tres"), 1)
		player.level.add_entity(spike, player.global_position)
	for e in get_tree().get_nodes_in_group("enemies"):
		e.set_physics_process(false)
	player.global_position = spike.global_position
	player.status.clear()
	player._invulnerable = 0.0
	var hp_t := player.hero.stats.hp
	await get_tree().create_timer(1.0).timeout
	check(player.hero.stats.hp < hp_t, "spikes hurt the hero (%d -> %d)" % [hp_t, player.hero.stats.hp])
	player.camera.zoom = Vector2(3, 3)
	await shot("15_2_trap_zoom")
	player.camera.zoom = Vector2.ONE
	var plate: Trap = (load("res://scenes/traps/trap.tscn") as PackedScene).instantiate()
	plate.setup(load("res://data/traps/pressure_plate.tres"), 1)
	player.level.add_entity(plate, player.global_position + Vector2(40, 0))
	await frames(2)
	var hits_before := player.hero.stats.hp
	plate.interact(player)
	check(plate.disarmed or plate._cooldown >= 0.0, "disarm attempt resolves (disarmed=%s)" % plate.disarmed)
	for e in get_tree().get_nodes_in_group("enemies"):
		e.set_physics_process(true)
	player.hero.stats.heal(9999)
	# --- 15.1 statuses on the hero
	var hp0 := player.hero.stats.hp
	player.status.apply(&"poison", 1.2, 3.0)
	await get_tree().create_timer(1.3).timeout
	check(player.hero.stats.hp < hp0, "poison ticks on the hero (%d -> %d)" % [hp0, player.hero.stats.hp])
	player.velocity = Vector2.ZERO
	await frames(20)
	player.velocity = Vector2.ZERO
	player.status.apply(&"stun", 3.0)
	# Time-based: on slow (software) rendering one frame can be several physics ticks.
	await get_tree().create_timer(0.2).timeout  # leftover knockback slides out
	var px := player.global_position.x
	Input.action_press("move_right")
	await get_tree().create_timer(0.4).timeout
	Input.action_release("move_right")
	check(player.status.is_stunned() and absf(player.global_position.x - px) < 2.0, "stunned hero cannot move (%f -> %f)" % [px, player.global_position.x])
	player.status.remove(&"stun")
	await get_tree().create_timer(0.6).timeout
	player.status.apply(&"shield", 5.0, 999.0)
	var hp1 := player.hero.stats.hp
	player._invulnerable = 0.0
	player.take_damage(50, player.global_position + Vector2(10, 0))
	check(player.hero.stats.hp == hp1, "shield absorbs the hit")
	player.status.clear()
	player.hero.stats.heal(9999)
	# attack + skills + items
	await press("attack")
	for i in 4:
		player.hero.stats.restore_mana(999)
		player.use_skill(i)
		await frames(20)
	check(player.hero.skills.cooldowns.max() > 0.0, "skills on cooldown after use")
	await shot("04_after_skills")
	player.hero.stats.take_damage(30)
	var hp := player.hero.stats.hp
	player.use_item(ItemDatabase.get_item(&"health_potion"))
	check(player.hero.stats.hp > hp, "potion heals")
	var bombs := player.hero.inventory.count_of(&"bomb")
	await press("quick_3")
	check(player.hero.inventory.count_of(&"bomb") == bombs - 1, "quick slot 3 throws bomb")
	await frames(120)
	# damage enemies
	var enemies := get_tree().get_nodes_in_group("enemies")
	check(enemies.size() > 0, "enemies spawned: %d" % enemies.size())
	var xp_before := player.hero.xp + player.hero.level * 10000
	for e in enemies.slice(0, 3):
		e.take_damage(9999, false, player.global_position)
	await frames(5)
	check(player.hero.xp + player.hero.level * 10000 > xp_before, "xp from kills")
	# chest
	var chests := get_tree().get_nodes_in_group("chests")
	check(chests.size() > 0, "chests spawned: %d" % chests.size())
	for c in chests:
		if not c.locked:
			player.global_position = c.global_position
			break
	# Nothing else interactable next to the chest (traps, merchant).
	for t in get_tree().get_nodes_in_group("traps"):
		if t.global_position.distance_to(player.global_position) < 40.0:
			t.queue_free()
	player.velocity = Vector2.ZERO
	await frames(5)
	check(player.try_interact(), "interact with chest")
	await frames(3)
	var opened_chest: Chest = null
	for c in chests:
		if c.opened:
			opened_chest = c
	check(opened_chest != null and opened_chest.sprite.animation in [&"opening", &"open"], "chest lid animates")
	await frames(40)
	var pickups := get_tree().get_nodes_in_group("pickups")
	check(pickups.size() > 0, "chest dropped loot: %d" % pickups.size())
	await shot("05_chest_loot")
	if pickups.size() > 0:
		player.global_position = pickups[0].global_position
		await frames(3)
		var count_before := player.hero.gold
		for st in player.hero.inventory.slots:
			if st:
				count_before += st.count
		check(player.try_interact(), "pickup interact")
		await frames(3)
		var count_after := player.hero.gold
		for st in player.hero.inventory.slots:
			if st:
				count_after += st.count
		check(count_after > count_before, "picked up items")
	# inventory book
	await press("inventory")
	await frames(5)
	check(get_tree().paused, "inventory pauses game")
	await shot("06_inventory")
	var book: InventoryBook = game.get_node("InventoryBook")
	var slot := book._inv_slots[0]
	Tooltip.show_text(TooltipText.item(slot.get_item(), player.hero), slot)
	get_viewport().warp_mouse(slot.get_global_rect().get_center())
	await frames(3)
	await shot("07_inventory_tooltip")
	Tooltip.hide_tip()
	# drag & drop handlers
	var hero := player.hero
	hero.unequip_to_inventory(&"helmet")
	hero.inventory.remove_by_id(&"iron_helm", 9)
	hero.inventory.add_item(ItemDatabase.get_item(&"iron_helm"))
	var helm_idx := hero.inventory.find_index(&"iron_helm")
	var helm_data: Dictionary = book._inv_slots[helm_idx]._get_drag_data(Vector2.ZERO)
	var helm_slot: ItemSlot = null
	for es in book._equip_slots:
		if es.slot_id == &"helmet":
			helm_slot = es
	check(helm_slot._can_drop_data(Vector2.ZERO, helm_data), "helm can drop on helmet slot")
	check(not book._equip_slots[2]._can_drop_data(Vector2.ZERO, helm_data) or book._equip_slots[2].slot_id == &"helmet", "helm rejected by other slot")
	var armor_before := hero.stats.armor()
	helm_slot._drop_data(Vector2.ZERO, helm_data)
	check(hero.equipment.get_item(&"helmet") != null and hero.stats.armor() > armor_before, "drag helm -> equipped, armor up")
	var hud: HUD = game.get_node("HUD")
	var potion_idx := hero.inventory.find_index(&"health_potion")
	var pdata: Dictionary = book._inv_slots[potion_idx]._get_drag_data(Vector2.ZERO)
	hud._quick_slots[6]._drop_data(Vector2.ZERO, pdata)
	check(hero.quick_bar.get_item(6).id == &"health_potion", "drag potion -> quick slot 7")
	var bone_count := hero.inventory.count_of(&"bone")
	hero.inventory.add_item(ItemDatabase.get_item(&"bone"), 2)
	var bdata: Dictionary = book._inv_slots[hero.inventory.find_index(&"bone")]._get_drag_data(Vector2.ZERO)
	var catcher := book.get_child(0) as DropCatcher
	catcher._drop_data(Vector2.ZERO, bdata)
	check(hero.inventory.count_of(&"bone") == 0, "drop outside throws item away (had %d)" % (bone_count + 2))
	await frames(2)
	await shot("06b_inventory_after_dnd")
	await press("inventory")
	check(not get_tree().paused, "closing inventory unpauses")
	# portrait tooltip
	Tooltip.show_text(TooltipText.hero_stats(player.hero))
	get_viewport().warp_mouse(Vector2(130, 300))
	await frames(3)
	await shot("08_stats_tooltip")
	Tooltip.hide_tip()
	# ladder: find a ladder top and climb down
	var lvl := player.level
	var found := false
	for y in lvl.layout.height:
		for x in lvl.layout.width:
			if lvl.layout.get_tile(x, y) == LevelLayout.Tile.LADDER_TOP and not found:
				found = true
				player.global_position = lvl.cell_bottom(Vector2i(x, y - 1))
				player.velocity = Vector2.ZERO
				player._invulnerable = 2.0
	if found:
		await frames(20)
		var ly := player.global_position.y
		Input.action_press("move_down")
		await frames(40)
		Input.action_release("move_down")
		check(player.global_position.y > ly + 16.0, "climb down ladder (%f -> %f)" % [ly, player.global_position.y])
		Input.action_press("move_up")
		await frames(80)
		Input.action_release("move_up")
		await frames(20)
		check(absf(player.global_position.y - ly) < 4.0 and player.is_on_floor(), "climb back up onto ladder top (%f vs %f)" % [player.global_position.y, ly])
	# --- stage 13: biomes
	check(ItemDatabase.biomes.size() == 4, "4 biomes loaded")
	var ids := []
	for f in [1, 4, 7, 10, 13]:
		ids.append(ItemDatabase.biome_for_floor(f).id)
	check(ids == [&"catacombs", &"fungal", &"ruins", &"lava", &"catacombs"], "biome rotation every 3 floors: %s" % str(ids))
	var lv := player.level
	check(lv.ore_cells.size() > 0, "ore veins placed: %d" % lv.ore_cells.size())
	var decos := 0
	for n in lv.entities.get_children():
		if n is Decoration:
			decos += 1
	check(decos > 0, "decorations placed: %d" % decos)
	# Autotile: digging a brick turns the one below into a "top edge" tile.
	var dug := false
	for y in range(2, lv.layout.height - 3):
		for x in range(2, lv.layout.width - 2):
			if dug:
				break
			if lv.layout.get_tile(x, y) == LevelLayout.Tile.BRICK and lv.layout.get_tile(x, y + 1) == LevelLayout.Tile.BRICK \
					and LevelLayout.is_solid(lv.layout.get_tile(x, y - 1)) and LevelLayout.is_solid(lv.layout.get_tile(x, y + 2)) \
					and not lv.ore_cells.has(Vector2i(x, y)) and not lv.ore_cells.has(Vector2i(x, y + 1)):
				lv.break_tile(Vector2i(x, y))
				check(lv.tiles.get_cell_atlas_coords(Vector2i(x, y + 1)).y == AssetPaths.TILE_ROW_BRICK_TOP, "autotile: exposed brick becomes top edge")
				dug = true
	for f in [4, 7, 10]:
		GameState.floor_number = f
		game._load_floor()
		await frames(25)
		player.camera.reset_smoothing()
		await frames(2)
		await shot("13_biome_%s" % GameState.current_biome().id)
	# --- 15.4 bosses
	for f in [5, 10]:
		GameState.floor_number = f
		game._load_floor()
		await frames(5)
		var boss_nodes := get_tree().get_nodes_in_group("bosses")
		check(boss_nodes.size() == 1 and player.level.layout.is_arena, "floor %d is a boss arena" % f)
		if boss_nodes.is_empty():
			continue
		var b: Boss = boss_nodes[0]
		var boss_hud: HUD = game.get_node("HUD")
		check(boss_hud._boss_box.visible, "boss bar shown for %s" % b.boss.display_name)
		player.status.apply(&"shield", 30.0, 99999.0)
		await get_tree().create_timer(3.5).timeout
		player.camera.reset_smoothing()
		await shot("15_4_boss_%d" % f)
		b.take_damage(roundi(b.max_hp * 0.5), false, Vector2.INF, 0)
		await frames(3)
		check(b.phase_index >= 1, "boss enters phase 2 at half HP (phase %d)" % b.phase_index)
		b.take_damage(999999)
		await frames(60)
		var boss_doors := 0
		var boss_chests := 0
		for n in player.level.entities.get_children():
			if n is ExitDoor:
				boss_doors += 1
			if n is Chest and n.tier == 2 and not n.locked:
				boss_chests += 1
		check(boss_doors == 1 and boss_chests == 1, "boss death opens the door and drops an epic chest")
		player.status.clear()
	GameState.floor_number = 1
	game._load_floor()
	await frames(5)
	player = get_tree().get_first_node_in_group("player") as Player
	# next floor
	GameState.next_floor()
	await frames(10)
	check(GameState.floor_number == 2, "floor 2")
	player = get_tree().get_first_node_in_group("player") as Player
	check(player.level != null and player.level.floor_number == 2, "level rebuilt for floor 2")
	await frames(20)
	await shot("09_floor2")
	# death
	player.hero.stats.take_damage(99999)
	await frames(100)
	check(player.dead, "player died")
	await shot("10_death")
	GameState.go_to_menu()
	await frames(10)
	check(get_tree().current_scene.name == "MainMenu", "back to menu after death")
	check(SaveManager.total_runs >= 1, "run recorded")
	check(MetaProgress.shards > 25, "death paid sanctum shards (%d)" % MetaProgress.shards)
	_finished = true
