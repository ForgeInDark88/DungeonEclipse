class_name EventRunner
extends RefCounted
## Plays the road events (EventData): picks one for a node, checks what an
## answer needs, rolls its outcome and applies the effects to the hero, the
## expedition (RunState) and the town's flags. See EventData for the keys.


## An event for this node: fits the region and depth, not seen this
## expedition (when possible), weighted, deterministic per node seed.
static func pick(region_id: StringName, depth: int, seed_value: int) -> EventData:
	var seen: Array = GameState.run.flags.get("events_seen", []) if GameState.run else []
	var pool: Array[EventData] = []
	for e: EventData in ItemDatabase.road_events:
		if (e.regions.is_empty() or region_id in e.regions) and depth >= e.min_depth and depth <= e.max_depth:
			pool.append(e)
	var fresh := pool.filter(func(e: EventData) -> bool: return not String(e.id) in seen)
	if not fresh.is_empty():
		pool.assign(fresh)
	if pool.is_empty():
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var total := 0.0
	for e in pool:
		total += e.weight
	var r := rng.randf() * total
	for e in pool:
		r -= e.weight
		if r <= 0.0:
			return e
	return pool.back()


## Whether the hero meets `requires` ("class:a|b", "stat:x>=n", "item:id",
## "gold:n", "resident:id", "flag:id", "run_resource:id:n"; " & " joins).
static func check(requires: String) -> bool:
	if requires.strip_edges() == "":
		return true
	var hero := GameState.hero
	for part in requires.split("&"):
		var bits := part.strip_edges().split(":")
		var ok := false
		match bits[0]:
			"class":
				ok = hero != null and String(hero.class_data.id) in bits[1].split("|")
			"stat":
				var m := bits[1].split(">=")
				ok = hero != null and hero.stats.get_value(m[0]) >= float(m[1])
			"item":
				ok = hero != null and hero.inventory.count_of(StringName(bits[1])) > 0
			"gold":
				ok = hero != null and hero.gold >= int(bits[1])
			"resident":
				ok = GameState.town != null and GameState.town.has_resident(StringName(bits[1]))
			"flag":
				ok = GameState.town != null and GameState.town.flag(bits[1], false) == true
			"run_resource":
				ok = GameState.run != null and int(GameState.run.resources.get(bits[1], 0)) >= int(bits[2])
		if not ok:
			return false
	return true


## Rolls one outcome of an answer by the outcomes' chances.
static func roll(option: Dictionary, rng: RandomNumberGenerator = null) -> Dictionary:
	var outcomes: Array = option.get("outcomes", [])
	if outcomes.is_empty():
		return {}
	var r := (rng.randf() if rng else randf())
	for oc: Dictionary in outcomes:
		r -= float(oc.get("chance", 1.0))
		if r <= 0.0:
			return oc
	return outcomes.back()


## Applies `effects`; returns the lines telling what happened.
## `party_member`: the effects reach another hero of a co-op party - only
## what happens to a hero (no costs paid by the chooser, nothing of the
## expedition: resources, rescues and flags are the host's).
static func apply(effects: Dictionary, party_member := false) -> Array[String]:
	if party_member:
		effects = effects.duplicate()
		for k in ["take_item", "resource", "rescue", "flag", "rumours", "fight"]:
			effects.erase(k)
		if int(effects.get("gold", 0)) < 0:
			effects.erase("gold")
	var lines: Array[String] = []
	var hero := GameState.hero
	var run := GameState.run
	var depth := maxi(1, GameState.depth())
	var scale := 1.0 + depth * 0.08
	if hero == null:
		return lines
	if effects.has("gold"):
		var g := int(effects["gold"])
		if g > 0:
			g = roundi(g * scale)
			hero.add_gold(g)
			lines.append(TranslationServer.translate("+%d золота") % g)
		elif g < 0:
			hero.spend_gold(-g)
			lines.append(TranslationServer.translate("−%d золота") % -g)
	if effects.has("xp"):
		var x := roundi(int(effects["xp"]) * scale)
		hero.add_xp(x)
		lines.append(TranslationServer.translate("+%d опыта") % x)
	if effects.get("heal_full", false):
		hero.stats.heal(hero.stats.max_hp())
		lines.append(TranslationServer.translate("Здоровье восстановлено"))
	if effects.has("hp_pct"):
		var p := int(effects["hp_pct"])
		var amount := roundi(hero.stats.max_hp() * absf(p) / 100.0)
		if p > 0:
			hero.stats.heal(amount)
			lines.append(TranslationServer.translate("+%d здоровья") % amount)
		else:
			hero.stats.hp = maxi(1, hero.stats.hp - amount)  # an event never kills
			hero.stats.hp_changed.emit(hero.stats.hp, hero.stats.max_hp())
			lines.append(TranslationServer.translate("−%d здоровья") % amount)
	if effects.has("mana_pct"):
		var mp := roundi(hero.stats.max_mana() * float(effects["mana_pct"]) / 100.0)
		hero.stats.mana = clampi(hero.stats.mana + mp, 0, hero.stats.max_mana())
		hero.stats.mana_changed.emit(hero.stats.mana, hero.stats.max_mana())
		lines.append(TranslationServer.translate("%+d маны") % mp)
	if effects.has("take_item"):
		hero.inventory.remove_by_id(StringName(effects["take_item"]), 1)
		var it0 := ItemDatabase.get_item(StringName(effects["take_item"]))
		lines.append(TranslationServer.translate("Отдано: %s") % (it0.display_name if it0 else String(effects["take_item"])))
	if effects.has("item"):
		var it := ItemDatabase.get_item(StringName(effects["item"]))
		if it:
			hero.inventory.add_item(it if it.is_stackable() else ItemFactory.create(it, depth), 1)
			lines.append(TranslationServer.translate("Получено: %s") % it.display_name)
	if effects.has("loot"):
		var table := ItemDatabase.get_loot_table(StringName(effects["loot"]))
		if table:
			for e: Dictionary in table.roll(depth):
				var item: ItemData = e["item"]
				if item.currency_value > 0:
					hero.add_gold(item.currency_value * int(e["count"]))
					continue
				var inst := item if item.is_stackable() else ItemFactory.create(item, depth)
				hero.inventory.add_item(inst, int(e["count"]))
				EventBus.item_collected.emit(inst, Vector2.ZERO)
				lines.append(TranslationServer.translate("Найдено: %s") % inst.display_name)
	if effects.has("shards"):
		var shard := ItemDatabase.get_item(MetaProgress.SHARD_ITEM)
		if shard:
			hero.inventory.add_item(shard, int(effects["shards"]))
			lines.append(TranslationServer.translate("+%d осколков Затмения") % int(effects["shards"]))
	for key in ["pact", "pact2"]:
		if effects.has(key):
			var pact := _pact(String(effects[key]))
			if pact:
				GameState.add_pact(pact)
				lines.append((TranslationServer.translate("Проклятие: %s") if pact.is_curse() else TranslationServer.translate("Благословение: %s")) % pact.display_name)
	if effects.has("resource"):
		var res: Dictionary = effects["resource"]
		for k in res:
			var n := int(res[k])
			if n > 0:
				GameFlow.gain_resource(StringName(k), n)
			elif run:
				run.resources[k] = maxi(0, int(run.resources.get(k, 0)) + n)
		lines.append(TranslationServer.translate("Ресурсы: %s") % TownResources.describe(res))
	if effects.has("rescue"):
		var who := _rescue_target(String(effects["rescue"]))
		if effects.has("fight") and run:
			run.flags["after_fight_rescue"] = String(who)  # freed when the fight is won
		else:
			GameFlow.rescue(who)
			var n: NpcData = ItemDatabase.npcs.get(who)
			lines.append(TranslationServer.translate("Спасён: %s") % (n.display_name if n else TranslationServer.translate("горожанин")))
	if effects.has("flag") and run:
		run.flags[String(effects["flag"])] = true
	if effects.get("rumours", false) and run:
		run.flags["rumours"] = true
		lines.append(TranslationServer.translate("Знаки на карте теперь понятны"))
	return lines


static func _pact(id: String) -> RunPactData:
	var want_curse := id == "curse"
	if id == "blessing" or id == "curse":
		var pool := ItemDatabase.pacts.filter(func(p: RunPactData) -> bool:
			return p.is_curse() == want_curse and p.min_floor <= GameState.depth())
		return pool.pick_random() if not pool.is_empty() else null
	for p in ItemDatabase.pacts:
		if String(p.id) == id:
			return p
	return null


## "any": the next person of the town still waiting somewhere; else a
## nameless townsman.
static func _rescue_target(what: String) -> StringName:
	if what != "any":
		return StringName(what)
	var town := GameState.town
	var taken: Array = GameState.run.rescued if GameState.run else []
	var people: Array = ItemDatabase.npcs.values().filter(func(n: NpcData) -> bool:
		return not n.resident_from_start and not (town and town.has_resident(n.id)) and not n.id in taken \
				and n.depth_min <= GameState.depth())
	people.sort_custom(func(a: NpcData, b: NpcData) -> bool: return a.order < b.order)
	return (people[0] as NpcData).id if not people.is_empty() else RescueCage.REFUGEE
