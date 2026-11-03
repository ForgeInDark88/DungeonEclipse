extends SceneTree
## The town (Buildings, TownState, Dialogs): a new town, building and
## upgrading, requirements (resident, guardian, blueprint), the mason's
## discount, prices, the warehouse and the hall, talks, save / load.
##   godot --headless -s tests/town_test.gd   (writes user://test_town2.save)

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
	sm.town_path = "user://test_town2.save"
	var town := TownState.new()
	Buildings.init_town(town)
	gs.town = town
	gs.expedition = true
	gs.hero = Hero.new(idb.races[0], idb.classes[0], idb.equipment_layout)
	gs.hero.give_starting_kit()
	check(idb.buildings.size() >= 10, "at least ten buildings in data")
	check(town.building_level(&"shop") == 1 and town.building_level(&"sanctum") == 1, "the shop and the Sanctum stand from day one")
	check(town.building_level(&"smithy") == 0, "the smithy starts as ruins")
	check(town.has_resident(&"elder") and not town.has_resident(&"blacksmith"), "only the elder lives here at first")

	# ------------------------------------------------ build with resources
	var lib = idb.building(&"library")
	check(Buildings.block_reason(lib) != "", "no materials: the library cannot be built")
	check(not Buildings.build(lib), "build() refuses without materials")
	# ------------------------------------------------ districts (stage 18)
	var TD = load("res://scripts/core/town_districts.gd")
	check(idb.districts.size() >= 6, "the town has its districts (%d)" % idb.districts.size())
	var by_id := {}
	for d in idb.districts:
		by_id[d.id] = d
	check(TD.is_open(by_id[&"market"], town) and TD.is_open(by_id[&"square"], town), "the market and the square are open from the start")
	check(TD.is_open(by_id[&"temple"], town), "the temple hill is open: the Sanctum stands there from day one")
	check(not TD.is_open(by_id[&"residential"], town) and not TD.is_open(by_id[&"crafts"], town), "the houses and the craftsmen wait for the town to grow")
	for b in idb.buildings:
		var bd = TD.of_building(b)
		check(bd != null and b.slot + b.width <= bd.x_to, "%s stands inside its district" % b.id)
	check(Buildings.block_reason(lib).contains(by_id[&"residential"].display_name) or Buildings.block_reason(lib).contains(tr(by_id[&"residential"].display_name)),
			"a building of a closed district says which district and why (%s)" % Buildings.block_reason(lib))
	town.prosperity = 20
	check(TD.is_open(by_id[&"residential"], town) and TD.is_open(by_id[&"crafts"], town), "a prosperous town opens its districts")
	var lay = load("res://scripts/level/town_builder.gd").build_hub(town)
	check(lay.width >= 160, "the town is wide: %d cells (%.1f screens)" % [lay.width, lay.width / 40.0])
	var raised := false
	for x in lay.width:
		if load("res://scripts/level/town_builder.gd").ground_at(x) < load("res://scripts/level/town_builder.gd").HUB_GROUND:
			raised = true
	check(raised, "the town has a terrace (several heights)")
	var nav := LevelNav.new(lay)
	for info in lay.town_buildings:
		var c: Vector2i = info["cell"]
		check(not nav.ground_path(lay.start_cell, c, 2).is_empty(), "the hero walks from the gate to %s" % info["id"])
	gs.hero.gold = 1000
	for r in ["wood", "stone", "iron", "herbs", "crystal"]:
		town.add_resource(StringName(r), 30)
	var cost: Dictionary = Buildings.cost(lib, 1)
	check(Buildings.build(lib) and town.building_level(&"library") == 1, "the library is built")
	check(town.resource(&"wood") == 30 - int(cost.get("wood", 0)) and gs.hero.gold == 1000 - int(cost["gold"]), "building pays gold and materials")
	check(Buildings.build(lib) and town.building_level(&"library") == 2, "and upgraded to level 2")
	check(Buildings.requirement_missing(lib, 3) != "", "level 3 of the library needs a blueprint / guardian")

	# ------------------------------------------------ requirements
	var smithy = idb.building(&"smithy")
	check(Buildings.block_reason(smithy).contains(idb.npcs[&"blacksmith"].display_name), "the smithy waits for its blacksmith")
	town.add_resident(&"blacksmith")
	check(Buildings.build(smithy), "with the blacksmith home the smithy is built")
	var hall = idb.building(&"hall")
	check(not Buildings.build(hall), "the hall of fame needs the first guardian beaten")
	town.bosses_defeated.append(&"bone_king")
	check(Buildings.build(hall), "after the Bone King the hall stands")
	var shop = idb.building(&"shop")
	Buildings.build(shop)
	check(town.building_level(&"shop") == 2 and not Buildings.build(shop), "shop level 3 needs a blueprint")
	town.blueprints.append(&"shop")
	check(Buildings.build(shop) and town.building_level(&"shop") == 3, "with the blueprint the shop reaches level 3")
	check(Buildings.block_reason(shop) != "" and not Buildings.build(shop), "nothing above the last level")

	# ------------------------------------------------ discounts and effects
	var wh = idb.building(&"warehouse")
	var before: int = int(Buildings.cost(wh, 1)["gold"])
	town.add_resident(&"mason")
	check(int(Buildings.cost(wh, 1)["gold"]) < before, "the mason makes building cheaper")
	var potion = idb.get_item(&"health_potion")
	var p0: int = potion.shop_price()
	town.add_resident(&"innkeeper")
	check(potion.shop_price() < potion.buy_price() and potion.shop_price() <= p0, "residents and the big shop lower prices")
	check(Buildings.warehouse_slots() == 0, "no warehouse, no safe")
	town.add_resource(&"wood", 20)
	gs.hero.gold += 500
	Buildings.build(wh)
	check(Buildings.warehouse_slots() == 4, "warehouse level 1 keeps 4 items")
	check(Buildings.trophy_slots() == 3, "hall level 1 shows 3 trophies")
	town.trophies.append(RunCodec.item_to_dict(ItemFactory.create(idb.get_item(&"iron_sword"))))
	var hp0: int = gs.hero.stats.max_hp()
	Buildings.apply_trophies(gs.hero)
	check(gs.hero.stats.max_hp() == hp0 + Buildings.TROPHY_HP, "a trophy adds health to the hero")
	check(Buildings.prosperity(town) > 0, "prosperity grows with the town")

	# ------------------------------------------------ talks
	var elder = idb.npcs[&"elder"]
	check(Dialogs.current(elder).get("id") == "intro" and Dialogs.has_news(elder), "the elder greets the hero with news")
	Dialogs.mark_read(elder, Dialogs.current(elder))
	check(Dialogs.current(elder).get("id") == "bone_king", "after the Bone King the elder talks about the hall")
	check(Dialogs.condition("building:library:2 & resident:mason & !flag:nope"), "conditions: building, resident, not-flag")
	check(not Dialogs.condition("boss:eclipse"), "conditions: an unbeaten guardian")

	# ------------------------------------------------ save / load
	town.warehouse.append(RunCodec.item_to_dict(ItemFactory.create(idb.get_item(&"iron_sword"))))
	town.hero = RunCodec.save_hero(gs.hero)
	check(sm.save_town(town) == OK, "the town is saved")
	var back = sm.load_town()
	check(back != null and var_to_str(back.to_dict()) == var_to_str(town.to_dict()), "load gives back exactly the saved town")
	var st := RunCodec._item_from_dict(back.warehouse[0])
	check(st != null and st.item.id == &"iron_sword", "warehouse items come back as items")
	sm.clear_town()

	print("FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)
