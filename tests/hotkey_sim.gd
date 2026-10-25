extends Node
## Regression: skill/quick hotkeys must fire while the HUD (with its
## mouse-filter-stop slots) is on screen. Learned skill + potion on quick_1,
## injects real key events through the full input pipeline.


func _ready() -> void:
	var game := (load("res://scenes/game/game.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().create_timer(1.0).timeout
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null:
		print("HOTKEY CHECK: no player")
		get_tree().quit(1)
		return
	var hero: Hero = player.hero
	if hero.skills.get_skill(0) == null and hero.skills.skill_points > 0:
		for s in hero.skills.all:
			if not s.is_passive() and hero.skills.learn(s, 1):
				break
	var s0: SkillData = hero.skills.get_skill(0)
	print("skill slot 0: ", s0.id if s0 else "EMPTY")
	var potion := ItemDatabase.get_item(&"health_potion")
	var potions_before := 0
	if potion:
		hero.inventory.add_item(potion, 2)
		hero.quick_bar.assign(0, potion)
		potions_before = hero.inventory.count_of(potion.id)
	print("quick_1: ", hero.quick_bar.get_item(0).id if hero.quick_bar.get_item(0) else "none")

	# --- skill hotkey Q (skill_1 default: physical_keycode 81)
	var mana_before: int = hero.stats.mana
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_Q
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame
	ev.pressed = false
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame
	var skill_fired := hero.stats.mana != mana_before
	print("Q fired the skill: ", skill_fired, " (mana ", mana_before, " -> ", hero.stats.mana, ")")

	# --- quick hotkey 1 (quick_1 default: physical_keycode 49)
	var potion_used := 0
	if potion:
		# The potion only works on a wounded hero (HealEffect refuses at full
		# hp) - wound first so the key press has a real effect to fire.
		hero.stats.lose_hp(20)
		ev = InputEventKey.new()
		ev.physical_keycode = KEY_1
		ev.pressed = true
		Input.parse_input_event(ev)
		await get_tree().process_frame
		await get_tree().process_frame
		ev.pressed = false
		Input.parse_input_event(ev)
		await get_tree().process_frame
		await get_tree().process_frame
		potion_used = potions_before - hero.inventory.count_of(potion.id)
	print("1 fired the potion: ", potion_used == 1, " (used ", potion_used, ")")
	var ok := skill_fired and potion_used == 1
	print("HOTKEY CHECK: ", "OK" if ok else "PROBLEM")
	get_tree().quit(0 if ok else 1)
