class_name RunCodec
extends RefCounted
## Serializes the run for the between-floors save (user://run.cfg):
## everything that crosses floors is written while the floor itself is
## deterministic — it is rebuilt from `run_seed` on continue. Instances
## (weapon copies with affixes, durability, upgrades) are stored field by
## field on top of their template id.

## Format of the run save. Bump it when the dictionary changes shape and add
## the step to _migrate(): a run saved by an older game still continues.
const VERSION := 2


# ------------------------------------------------------------- whole run
## Upgrades a run saved by an older game, one format step at a time.
static func _migrate(d: Dictionary, from: int) -> Dictionary:
	if from < 2:
		d["eclipse"] = int(d.get("eclipse", 0))  # v2: the levels of the Eclipse
	d["version"] = VERSION
	return d


static func save_run() -> Dictionary:
	var hero := GameState.hero
	if hero == null:
		return {}
	var pact_ids: Array = []
	for p in GameState.pacts:
		pact_ids.append(String(p.id))
	var stats: Dictionary = GameState.run_stats.duplicate()
	var elapsed := maxi(0, (Time.get_ticks_msec() - int(stats.get("start_ms", Time.get_ticks_msec()))) / 1000)
	stats.erase("start_ms")
	return {
		"version": VERSION,
		"seed": GameState.run_seed,
		"floor": GameState.floor_number,
		"kills": GameState.kills,
		"difficulty": String(GameState.difficulty.id) if GameState.difficulty else "normal",
		"eclipse": GameState.eclipse_level,
		"pet": String(GameState.pet.id) if GameState.pet else "",
		"pacts": pact_ids,
		"stats": stats,
		"elapsed": elapsed,
		"class_name": hero.class_data.display_name,
		"hero_level": hero.level,
		"hero": save_hero(hero),
	}


## Rebuilds the run state from `d` (true = GameState is ready, switch scenes).
static func load_run(d: Dictionary) -> bool:
	var v := int(d.get("version", 0))
	if v <= 0 or v > VERSION:
		return false  # unknown or from a newer game: never half-load it
	d = _migrate(d.duplicate(true), v)
	var hero := load_hero(d.get("hero", {}))
	if hero == null:
		return false
	GameState.hero = hero
	GameState.floor_number = int(d.get("floor", 1))
	GameState.run_seed = int(d.get("seed", 0))
	GameState.kills = int(d.get("kills", 0))
	GameState.difficulty = ItemDatabase.difficulty(StringName(d.get("difficulty", "normal")))
	GameState.eclipse_level = int(d.get("eclipse", 0))
	GameState.pacts.clear()
	for pid in d.get("pacts", []):
		for p in ItemDatabase.pacts:
			if p.id == StringName(pid):
				GameState.add_pact(p)
				break
	GameState.pet = ItemDatabase.pets.get(StringName(d.get("pet", "")))
	GameState.run_stats = d.get("stats", {})
	GameState.run_stats["start_ms"] = Time.get_ticks_msec() - int(d.get("elapsed", 0)) * 1000
	GameState.combo = 0
	GameState.run_active = true
	return true


# ------------------------------------------------------------------ hero
static func save_hero(hero: Hero) -> Dictionary:
	var inv: Array = []
	for stack in hero.inventory.slots:
		inv.append(_item_to_dict(stack))
	var pouch: Array = []
	for stack in hero.inventory.pouch:
		pouch.append(_item_to_dict(stack))
	var eq: Dictionary = {}
	for slot: StringName in hero.equipment.items:
		var it: ItemData = hero.equipment.items[slot]
		if it != null:
			eq[String(slot)] = _item_to_dict(ItemStack.new(it, 1))
	var quick: Array = []
	for it in hero.quick_bar.items:
		if it == null:
			quick.append("")
		elif it.is_instance():
			# Point at the backpack copy: an id alone would lose the affixes.
			quick.append(_item_to_dict(ItemStack.new(it, 1)))
		else:
			quick.append(String(it.id))
	var ranks := {}
	for id in hero.skills.ranks:
		ranks[String(id)] = int(hero.skills.ranks[id])
	var slots: Array = []
	for s in hero.skills.skills:
		slots.append(String(s.id) if s else "")
	return {
		"race": String(hero.race.id),
		"class": String(hero.class_data.id),
		"female": hero.female,
		"level": hero.level,
		"xp": hero.xp,
		"gold": hero.gold,
		"hp": hero.stats.hp,
		"mana": hero.stats.mana,
		"inventory": inv, "pouch": pouch,
		"equipment": eq,
		"quick_bar": quick,
		"ranks": ranks,
		"points": hero.skills.skill_points,
		"branch": hero.skills.chosen_branch,
		"skill_slots": slots,
	}


static func load_hero(d: Dictionary) -> Hero:
	var race: RaceData = null
	for r in ItemDatabase.races:
		if r.id == StringName(d.get("race", "")):
			race = r
			break
	var cls: ClassData = null
	for c in ItemDatabase.classes:
		if c.id == StringName(d.get("class", "")):
			cls = c
			break
	if race == null or cls == null:
		return null
	var hero := Hero.new(race, cls, ItemDatabase.equipment_layout)
	hero.female = bool(d.get("female", false))
	hero.level = maxi(1, int(d.get("level", 1)))
	hero.xp = int(d.get("xp", 0))
	hero.gold = int(d.get("gold", 0))
	hero.stats.set_level(hero.level)
	# Skills: ranks, points, the chosen branch and the HUD slots.
	var by_id := {}
	for s in cls.skills:
		by_id[s.id] = s
	hero.skills.ranks.clear()
	for id in d.get("ranks", {}):
		var s: SkillData = by_id.get(StringName(id))
		if s:
			hero.skills.ranks[s.id] = maxi(0, int(d["ranks"][id]))
	hero.skills.skill_points = maxi(0, int(d.get("points", 0)))
	hero.skills.chosen_branch = int(d.get("branch", -1))
	var slots: Array = d.get("skill_slots", [])
	for i in mini(slots.size(), hero.skills.skills.size()):
		hero.skills.skills[i] = by_id.get(StringName(slots[i])) if slots[i] != "" else null
	# Backpack: slot for slot.
	var inv: Array = d.get("inventory", [])
	for i in mini(inv.size(), hero.inventory.capacity()):
		var st := _item_from_dict(inv[i])
		if st:
			hero.inventory.slots[i] = st
	for e in d.get("pouch", []):
		var ps := _item_from_dict(e)
		if ps:
			hero.inventory.add_item(ps.item, ps.count)
	hero.inventory.tidy_materials()
	# Worn gear.
	var eq: Dictionary = d.get("equipment", {})
	for slot in eq:
		var key := StringName(slot)
		if not hero.equipment.items.has(key):
			continue
		var st2 := _item_from_dict(eq[slot])
		if st2:
			hero.equipment.items[key] = st2.item
	# Quick bar: templates by id, instances matched back to the backpack copy.
	var quick: Array = d.get("quick_bar", [])
	for i in mini(quick.size(), hero.quick_bar.items.size()):
		var entry: Variant = quick[i]
		if String(entry) == "":
			continue
		if entry is String:
			var it2 := ItemDatabase.get_item(StringName(entry))
			if it2:
				hero.quick_bar.items[i] = it2
		else:
			hero.quick_bar.items[i] = _find_inventory_copy(hero, entry)
	# Recalculate every stat source (equipment, sets, relics, passives), then
	# restore the saved HP / mana.
	hero.equipment.changed.emit()
	hero.inventory.changed.emit()
	hero.stats.hp = clampi(int(d.get("hp", hero.stats.max_hp())), 1, hero.stats.max_hp())
	hero.stats.mana = clampi(int(d.get("mana", hero.stats.max_mana())), 0, hero.stats.max_mana())
	hero.stats.hp_changed.emit(hero.stats.hp, hero.stats.max_hp())
	hero.stats.mana_changed.emit(hero.stats.mana, hero.stats.max_mana())
	return hero


## The backpack stack that matches a serialized instance (same template,
## name, wear and affixes) — quick bar slots reference the real copy.
static func _find_inventory_copy(hero: Hero, entry: Dictionary) -> ItemData:
	var want := _item_from_dict(entry)
	if want == null:
		return null
	for stack in hero.inventory.slots:
		if stack == null or stack.item == null or stack.item.id != want.item.id:
			continue
		var a: ItemData = stack.item
		var b: ItemData = want.item
		if a.display_name == b.display_name and a.durability == b.durability \
				and a.upgrade_level == b.upgrade_level and a.cursed == b.cursed \
				and a.affixes.size() == b.affixes.size():
			return a
	return ItemDatabase.get_item(want.item.id)


# ------------------------------------------------------------------ items
## Network: a single item as a plain dictionary, and back.
static func item_to_dict(it: ItemData) -> Dictionary:
	var d: Variant = _item_to_dict(ItemStack.new(it, 1))
	return d if d is Dictionary else {}


static func item_from_dict(d: Variant) -> ItemData:
	var st: ItemStack = _item_from_dict(d)
	return st.item if st else null
static func _item_to_dict(stack: ItemStack) -> Variant:
	if stack == null or stack.item == null:
		return null
	var it: ItemData = stack.item
	var d := {"id": String(it.id), "count": stack.count}
	if stack.junk:
		d["junk"] = true
	if it.is_instance():
		var f := {
			"name": it.display_name,
			"unid": it.unidentified,
			"real": it.real_name,
			"cursed": it.cursed,
			"curse": it.curse_bonuses,
			"bon": it.stat_bonuses,
			"ench": it.enchant_bonuses,
			"up": it.upgrade_level,
			"dur": it.durability,
		}
		var affix_ids: Array = []
		for a in it.affixes:
			affix_ids.append(String(a.id))
		f["affixes"] = affix_ids
		var w := it as WeaponItemData
		if w:
			f["dmg"] = w.base_damage
		d["inst"] = f
	return d


static func _item_from_dict(d: Variant) -> ItemStack:
	if d == null or not (d is Dictionary):
		return null
	var base := ItemDatabase.get_item(StringName(d.get("id", "")))
	if base == null:
		return null
	var it := base
	if d.has("inst"):
		var f: Dictionary = d["inst"]
		it = base.make_instance() if not base.is_instance() else base
		it.display_name = String(f.get("name", it.display_name))
		it.unidentified = bool(f.get("unid", false))
		it.real_name = String(f.get("real", ""))
		it.cursed = bool(f.get("cursed", false))
		it.curse_bonuses = f.get("curse", {})
		it.stat_bonuses = f.get("bon", it.stat_bonuses.duplicate())
		it.enchant_bonuses = f.get("ench", {})
		it.upgrade_level = int(f.get("up", 0))
		it.durability = int(f.get("dur", it.durability))
		var affs: Array[AffixData] = []
		for aid in f.get("affixes", []):
			for a in ItemDatabase.affixes:
				if a.id == StringName(aid):
					affs.append(a)
					break
		it.affixes = affs
		var w := it as WeaponItemData
		if w and f.has("dmg"):
			w.base_damage = float(f["dmg"])
	var st := ItemStack.new(it, maxi(1, int(d.get("count", 1))))
	st.junk = bool(d.get("junk", false))
	return st
