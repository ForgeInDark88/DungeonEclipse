extends Node
## Headless check of the guild quest chain and the town return flow.
## Run: godot --headless --path . res://tests/quest_sim.tscn

var _fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("PASS: ", what)
	else:
		_fails += 1
		print("FAIL: ", what)


func _ready() -> void:
	await get_tree().process_frame
	_test_chain()
	_test_town_return()
	print("RESULT: ", "OK" if _fails == 0 else "%d FAILURES" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


func _test_chain() -> void:
	var log := GameState.quests
	log.reset()
	# Pretend a run is on.
	GameState.run_active = true
	var hero := Hero.new(ItemDatabase.races[0], ItemDatabase.classes[0], ItemDatabase.equipment_layout)
	hero.gold = 0

	check(log.index == 0, "chain starts at the first quest")
	check(not log.current().is_empty(), "first quest exists")

	# KILL quest: 10 kills finish it, 9 don't.
	for i in 9:
		EventBus.enemy_killed.emit(ItemDatabase.enemies[0], Vector2.ZERO)
	check(not log.is_done(), "9 kills keep the quest open")
	EventBus.enemy_killed.emit(ItemDatabase.enemies[0], Vector2.ZERO)
	check(log.is_done(), "10 kills finish the kill quest")

	# Claim pays the reward and unlocks the next quest.
	var reward := log.claim(hero)
	check(not reward.is_empty(), "claim returns a reward")
	check(hero.gold == 60, "gold reward credited (got %d)" % hero.gold)
	check(log.index == 1, "next quest unlocked")
	check(log.claim(hero).is_empty(), "claiming twice returns nothing")

	# REACH quest: floor 2 does not finish target 3; deeper floor counts.
	EventBus.floor_changed.emit(2)
	check(not log.is_done(), "floor 2 below target 3")
	EventBus.floor_changed.emit(3)
	check(log.is_done(), "reaching floor 3 finishes the reach quest")
	EventBus.floor_changed.emit(1)
	check(log.is_done(), "returning shallower keeps it done")

	# LOOT quest skips gold piles (claim the reach quest first: progress resets).
	check(not log.claim(hero).is_empty(), "reach quest claimed")
	EventBus.item_collected.emit(_gold_pile(), Vector2.ZERO)
	check(log.progress == 0, "gold pile is not loot")
	for i in 7:
		EventBus.item_collected.emit(_normal_item(), Vector2.ZERO)
	EventBus.item_collected.emit(_normal_item(), Vector2.ZERO)
	check(log.is_done(), "8 items finish the loot quest")

	# ELITE quest counts elite kills.
	for i in 3:
		EventBus.elite_killed.emit(ItemDatabase.enemies[0])
	check(log.is_done(), "3 elites finish the elite hunt")

	# BOSS quest: instant on defeat.
	EventBus.boss_defeated.emit(null, Vector2.ZERO)
	check(log.is_done(), "boss kill finishes the boss quest")

	# Run through the rest of the chain to the end.
	var guard := 0
	while not log.all_done() and guard < 64:
		guard += 1
		var q := log.current()
		match int(q["type"]):
			QuestLog.Type.KILL:
				for i in int(q["target"]):
					EventBus.enemy_killed.emit(ItemDatabase.enemies[0], Vector2.ZERO)
			QuestLog.Type.ELITE:
				for i in int(q["target"]):
					EventBus.elite_killed.emit(ItemDatabase.enemies[0])
			QuestLog.Type.LOOT:
				for i in int(q["target"]):
					EventBus.item_collected.emit(_normal_item(), Vector2.ZERO)
			QuestLog.Type.REACH:
				EventBus.floor_changed.emit(int(q["target"]))
			QuestLog.Type.BOSS:
				for i in int(q["target"]):
					EventBus.boss_defeated.emit(null, Vector2.ZERO)
		var r2 := log.claim(hero)
		check(not r2.is_empty(), "claimed '%s'" % q["title"])
	check(log.all_done(), "the whole chain is complete")
	check(log.current().is_empty(), "no quest beyond the chain")

	GameState.run_active = false
	log.reset()


func _gold_pile() -> ItemData:
	var it := ItemData.new()
	it.currency_value = 5
	return it


func _normal_item() -> ItemData:
	var it := ItemData.new()
	it.id = &"test_item"
	it.display_name = "Test"
	it.item_type = ItemData.ItemType.MATERIAL
	return it


func _test_town_return() -> void:
	GameState.run_active = true
	GameState.floor_number = 7
	GameState.town_return_floor = 0
	GameState.return_to_town()
	check(GameState.floor_number == GameState.TOWN_FLOOR, "return_to_town lands on the town floor")
	check(GameState.town_return_floor == 7, "the left floor is remembered")
	GameState.return_to_town()
	check(GameState.town_return_floor == 7, "returning from town does nothing")

	GameState.resume_from_town()
	check(GameState.floor_number == 7, "the gate leads back to the left floor")
	check(GameState.town_return_floor == 0, "resume clears the memory")

	# run_active = false blocks the whole flow.
	GameState.run_active = false
	GameState.floor_number = 5
	GameState.return_to_town()
	check(GameState.floor_number == 5, "return needs an active run")
	GameState.floor_number = GameState.TOWN_FLOOR
