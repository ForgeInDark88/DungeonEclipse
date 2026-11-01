extends SceneTree
## Relic powers check (RelicPowers): run with
##   xvfb-run godot --rendering-driver opengl3 -s tests/relic_test.gd
var fails := 0
func check(c: bool, what: String) -> void:
	print(("PASS: " if c else "FAIL: ") + what)
	if not c: fails += 1

func give(pl: Player, id: StringName) -> void:
	pl.hero.inventory.add_item(root.get_node("ItemDatabase").get_item(id), 1)

func take(pl: Player, id: StringName) -> void:
	pl.hero.inventory.remove_by_id(id, 1)

func _initialize() -> void:
	await process_frame
	var idb = root.get_node("ItemDatabase")
	var gs = root.get_node("GameState")
	gs.hero = Hero.new(idb.races[0], idb.classes[0], idb.equipment_layout)
	gs.hero.give_starting_kit()
	gs.run_seed = 5
	gs.run_active = true
	gs.reset_run_stats()
	gs.floor_number = 4
	change_scene_to_file("res://scenes/game/game.tscn")
	for i in 60: await process_frame
	var pl: Player = current_scene.player
	var rp := pl.relic_powers
	check(rp != null, "relic powers on the hero")
	for id in ["chain_lightning", "blood_pact", "glass_heart", "volcano", "corpse_bomb", "war_drum", "mirror_shard", "storm_crown"]:
		check(idb.get_item(StringName(id)) is RelicItemData, "relic %s loaded" % id)
	# put three monsters next to each other in front of the hero
	var mobs: Array = []
	for e in root.get_tree().get_nodes_in_group("enemies"):
		if mobs.size() < 3 and not e.is_dead():
			mobs.append(e)
	var base: Vector2 = pl.global_position
	for k in mobs.size():
		mobs[k].global_position = base + Vector2(30 + k * 20, 0)
		mobs[k].set_physics_process(false)
		mobs[k].max_hp = 500
		mobs[k].hp = 500
	await process_frame
	give(pl, &"glass_heart")
	await process_frame
	check(is_equal_approx(rp.damage_mult(), 1.8), "glass heart: x1.8 damage (%.2f)" % rp.damage_mult())
	check(is_equal_approx(rp.hurt_mult(), 1.5), "glass heart: x1.5 damage taken")
	take(pl, &"glass_heart")
	give(pl, &"blood_pact")
	await process_frame
	pl.hero.stats.hp = 20
	pl.hero.stats.heal(50)
	check(pl.hero.stats.hp == 20, "blood pact: no healing (%d)" % pl.hero.stats.hp)
	rp.on_kill(base)
	check(pl.hero.stats.hp > 20, "blood pact: a kill heals (%d)" % pl.hero.stats.hp)
	take(pl, &"blood_pact")
	await process_frame
	pl.hero.stats.heal(5)
	check(pl.hero.stats.hp > 21, "healing back without the pact")
	give(pl, &"chain_lightning")
	await process_frame
	var before: Array = mobs.map(func(m): return m.hp)
	for k in 4:
		rp.on_hit(mobs[0], 40)
	var hurt := 0
	for k in range(1, mobs.size()):
		if mobs[k].hp < before[k]: hurt += 1
	check(hurt >= 1, "chain lightning: 4th hit jumps to the others (%d hurt)" % hurt)
	give(pl, &"corpse_bomb")
	await process_frame
	var hp1: int = mobs[1].hp
	rp.on_kill(mobs[1].global_position + Vector2(-5, 0))
	check(mobs[1].hp < hp1, "corpse bomb: the blast hurts nearby (%d -> %d)" % [hp1, mobs[1].hp])
	give(pl, &"volcano")
	await process_frame
	pl.global_position = mobs[0].global_position + Vector2(-10, 0)
	var hp0: int = mobs[0].hp
	rp.on_land(400.0)
	check(mobs[0].hp < hp0, "volcano: landing blast (%d -> %d)" % [hp0, mobs[0].hp])
	give(pl, &"war_drum")
	await process_frame
	var iv := pl.hero.attack_interval()
	for k in 3: rp.on_kill(Vector2(-9999, -9999))
	check(pl.hero.attack_interval() < iv, "war drum: faster attacks (%.3f -> %.3f)" % [iv, pl.hero.attack_interval()])
	give(pl, &"mirror_shard")
	await process_frame
	var dodged := 0
	for k in 400:
		if rp.dodge(): dodged += 1
	check(dodged > 25 and dodged < 100, "mirror shard: ~15%% dodge (%d/400)" % dodged)
	print("RESULT: ", "OK" if fails == 0 else "%d FAILURES" % fails)
	quit()
