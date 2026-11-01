extends SceneTree
## Road events (EventData, EventRunner): at least 15, every region has its
## own, every event has a safe answer (no requirement, no fight, no damage
## risk) and a risky one; chances add up to 1; every effect names things
## that exist (items, loot tables, pacts, people); every outcome applies
## cleanly 200 times; requirements are checked.
##   godot --headless -s tests/event_test.gd

const KNOWN := ["gold", "xp", "hp_pct", "mana_pct", "heal_full", "item", "loot", "take_item", "pact", "pact2",
		"resource", "shards", "rescue", "flag", "fight", "rumours"]

var fails := 0


func check(c: bool, what: String) -> void:
	if not c:
		print("FAIL: " + what)
		fails += 1


func _initialize() -> void:
	await process_frame
	var gs = root.get_node("GameState")
	var idb = root.get_node("ItemDatabase")
	root.get_node("MetaProgress").apply_upgrades = false
	check(idb.road_events.size() >= 15, "at least 15 road events (%d)" % idb.road_events.size())
	for reg in idb.regions:
		var own: Array = idb.road_events.filter(func(e: EventData) -> bool: return reg.id in e.regions)
		check(not own.is_empty(), "region %s has its own events" % reg.id)
	var town := TownState.new()
	Buildings.init_town(town)
	gs.town = town
	gs.expedition = true
	var applied := 0
	for e: EventData in idb.road_events:
		check(e.options.size() >= 2 and e.options.size() <= 4, "%s: 2–4 answers" % e.id)
		var safe := false
		var risky := false
		for opt: Dictionary in e.options:
			var outcomes: Array = opt.get("outcomes", [])
			check(not outcomes.is_empty(), "%s: every answer has an outcome" % e.id)
			var total := 0.0
			for oc: Dictionary in outcomes:
				total += float(oc.get("chance", 0))
				for k in oc.get("effects", {}):
					check(k in KNOWN, "%s: known effect %s" % [e.id, k])
				_check_names(e.id, oc.get("effects", {}), idb)
			check(absf(total - 1.0) < 0.001, "%s: chances add up to 1 (%.2f)" % [e.id, total])
			var harmless := outcomes.all(func(oc: Dictionary) -> bool:
				var fx: Dictionary = oc.get("effects", {})
				return not fx.has("fight") and int(fx.get("hp_pct", 0)) >= 0 and not String(fx.get("pact", "")).begins_with("c") \
						and String(fx.get("pact", "")) != "curse")
			if String(opt.get("requires", "")) == "" and harmless:
				safe = true
			if outcomes.size() >= 2 or outcomes.any(func(oc: Dictionary) -> bool: return oc.get("effects", {}).has("fight")):
				risky = true
		check(safe, "%s has a safe answer" % e.id)
		check(risky, "%s has a risky answer" % e.id)
		# every outcome applies cleanly on a fresh hero and expedition
		for opt: Dictionary in e.options:
			for oc: Dictionary in opt.get("outcomes", []):
				for i in 12:
					_fresh(gs, idb)
					var lines := EventRunner.apply(oc.get("effects", {}))
					check(gs.hero.stats.hp >= 1, "%s: an event never kills" % e.id)
					check(lines is Array, "%s: apply returns its lines" % e.id)
					applied += 1
	# requirements
	_fresh(gs, idb)
	gs.hero.gold = 10
	check(not EventRunner.check("gold:50") and EventRunner.check("gold:10"), "gold requirement")
	check(EventRunner.check("class:%s" % gs.hero.class_data.id) and not EventRunner.check("class:nobody"), "class requirement")
	check(EventRunner.check("item:health_potion") == (gs.hero.inventory.count_of(&"health_potion") > 0), "item requirement")
	check(not EventRunner.check("resident:mason"), "resident requirement")
	# the roll follows the chances
	var opt2 := {"outcomes": [{"chance": 0.3, "text": "a"}, {"chance": 0.7, "text": "b"}]}
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var a := 0
	for i in 2000:
		if EventRunner.roll(opt2, rng)["text"] == "a":
			a += 1
	check(a > 500 and a < 700, "outcomes roll by their chances (%d of 2000 ≈ 600)" % a)
	print("outcomes applied: %d" % applied)
	print("FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)


func _fresh(gs, idb) -> void:
	gs.hero = Hero.new(idb.races[0], idb.classes[0], idb.equipment_layout)
	gs.hero.give_starting_kit()
	gs.hero.gold = 500
	gs.pacts.clear()
	var run := RunState.new()
	run.map = ExpeditionMap.generate(1)
	run.node_id = 0
	gs.run = run
	gs.floor_number = 5
	gs.location = {"type": &"event", "depth": 5}


func _check_names(eid: StringName, fx: Dictionary, idb) -> void:
	for k in ["item", "take_item"]:
		if fx.has(k):
			check(idb.get_item(StringName(fx[k])) != null, "%s: item %s exists" % [eid, fx[k]])
	if fx.has("loot"):
		check(idb.get_loot_table(StringName(fx["loot"])) != null, "%s: loot table %s exists" % [eid, fx["loot"]])
	for k in ["pact", "pact2"]:
		if fx.has(k) and not String(fx[k]) in ["blessing", "curse"]:
			check(idb.pacts.any(func(p: RunPactData) -> bool: return String(p.id) == String(fx[k])), "%s: pact %s exists" % [eid, fx[k]])
	if fx.has("rescue") and not String(fx["rescue"]) in ["any", "refugee"]:
		check(idb.npcs.has(StringName(fx["rescue"])), "%s: person %s exists" % [eid, fx["rescue"]])
	if fx.has("resource"):
		for r in fx["resource"]:
			check(TownResources.ALL.has(StringName(r)), "%s: resource %s exists" % [eid, r])
