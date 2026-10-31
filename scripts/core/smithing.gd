class_name Smithing
extends RefCounted
## Blacksmith rules (used by the SmithBook UI): upgrade +1…+5, enchant with an
## essence, smelt gear into materials, repair. Costs are {"gold": int,
## "mats": {item_id: count}}. Works on item instances; templates are copied
## first (ensure_instance), so a .tres never changes.

const MAX_UPGRADE := 5
## Each upgrade level: stat bonuses ×1.15, weapon damage +12% of the base.
const UPGRADE_STAT_MULT := 1.15
const UPGRADE_DAMAGE := 0.12
## Essence -> possible enchantments (one is picked at random).
const ENCHANTS := {
	&"ember_essence": [{"damage": 2}, {"res_fire": 0.15}, {"strength": 2}],
	&"frost_essence": [{"res_ice": 0.15}, {"armor": 3}, {"vitality": 2}],
	&"moon_crystal": [{"intellect": 3}, {"max_mana": 15}, {"crit_chance": 0.04}, {"agility": 2}],
}


static func is_smithable(item: ItemData) -> bool:
	return item is EquipmentItemData


static func upgrade_cost(item: ItemData) -> Dictionary:
	var n := item.upgrade_level + 1
	var mats := {&"iron_ore": n}
	if n >= 3:
		mats[&"gold_ore"] = n - 2
	return {"gold": 40 * n * (1 + item.rarity), "mats": mats}


static func enchant_cost(item: ItemData, essence: StringName) -> Dictionary:
	return {"gold": 100 * (1 + item.rarity), "mats": {essence: 1}}


static func repair_cost(item: ItemData) -> Dictionary:
	if not (item.has_durability and item.is_instance()) or item.durability >= item.max_durability:
		return {"gold": 0, "mats": {}}
	return {"gold": ceili((item.max_durability - item.durability) * 0.2 * (1 + item.rarity)), "mats": {}}


## Materials (and a little gold) from smelting.
static func smelt_result(item: ItemData) -> Dictionary:
	var mats := {&"iron_ore": 1 + item.upgrade_level + item.rarity}
	if item.rarity >= ItemData.Rarity.RARE:
		mats[&"gold_ore"] = item.rarity
	if item.rarity >= ItemData.Rarity.EPIC:
		mats[&"moon_crystal"] = 1
	return {"gold": maxi(1, item.sell_price() / 2), "mats": mats}


static func can_afford(hero: Hero, cost: Dictionary) -> bool:
	if hero.gold < int(cost["gold"]):
		return false
	for id in cost["mats"]:
		if hero.inventory.count_of(id) < int(cost["mats"][id]):
			return false
	return true


static func pay(hero: Hero, cost: Dictionary) -> bool:
	if not can_afford(hero, cost):
		return false
	hero.spend_gold(int(cost["gold"]))
	for id in cost["mats"]:
		hero.inventory.remove_by_id(id, int(cost["mats"][id]))
	return true


static func cost_text(cost: Dictionary) -> String:
	var parts: Array[String] = []
	if int(cost["gold"]) > 0:
		parts.append(TranslationServer.translate("%d з.") % cost["gold"])
	for id in cost["mats"]:
		var it := ItemDatabase.get_item(id)
		parts.append("%s ×%d" % [it.display_name if it else String(id), cost["mats"][id]])
	return ", ".join(parts)


## Essence the hero has for enchanting (&"" = none).
static func available_essence(hero: Hero) -> StringName:
	for id in [&"moon_crystal", &"ember_essence", &"frost_essence"]:
		if hero.inventory.count_of(id) > 0:
			return id
	return &""


## Replaces a template in the equipment / backpack by its own copy.
static func ensure_instance(hero: Hero, item: ItemData) -> ItemData:
	if item.is_instance():
		return item
	var inst := item.make_instance()
	for slot_id in hero.equipment.items:
		if hero.equipment.items[slot_id] == item:
			hero.equipment.items[slot_id] = inst
			hero.equipment.changed.emit()
			return inst
	for stack in hero.inventory.slots:
		if stack and stack.item == item:
			stack.item = inst
			hero.inventory.changed.emit()
			return inst
	return inst


static func upgrade(hero: Hero, item: ItemData) -> ItemData:
	if not is_smithable(item) or item.upgrade_level >= MAX_UPGRADE or not pay(hero, upgrade_cost(item)):
		return null
	item = ensure_instance(hero, item)
	item.stat_bonuses = item.stat_bonuses.duplicate()  # never touch a shared dictionary
	item.upgrade_level += 1
	for k in item.stat_bonuses.keys():
		var v := float(item.stat_bonuses[k])
		if v > 0.0:
			item.stat_bonuses[k] = v * UPGRADE_STAT_MULT if v < 1.0 else float(maxi(roundi(v * UPGRADE_STAT_MULT), int(v) + 1))
	if item is WeaponItemData:
		var w := item as WeaponItemData
		var base := (w.template as WeaponItemData).base_damage if w.template else w.base_damage
		w.base_damage += base * UPGRADE_DAMAGE
	if item.has_durability:
		item.max_durability = roundi(item.max_durability * 1.1)
		item.durability = item.max_durability
	_rename(item)
	_notify(hero)
	return item


static func enchant(hero: Hero, item: ItemData) -> ItemData:
	var essence := available_essence(hero)
	if not is_smithable(item) or not item.enchant_bonuses.is_empty() or essence == &"" or not pay(hero, enchant_cost(item, essence)):
		return null
	item = ensure_instance(hero, item)
	var pool: Array = ENCHANTS[essence]
	var bonus: Dictionary = pool[randi() % pool.size()]
	item.enchant_bonuses = bonus.duplicate()
	item.stat_bonuses = item.stat_bonuses.duplicate()
	for k in bonus:
		item.stat_bonuses[k] = float(item.stat_bonuses.get(k, 0.0)) + float(bonus[k])
	_notify(hero)
	return item


## Breaks an item from the backpack into materials.
static func smelt(hero: Hero, index: int) -> bool:
	var stack := hero.inventory.stack_at(index)
	if stack == null or not is_smithable(stack.item):
		return false
	var res := smelt_result(stack.item)
	hero.inventory.take_at(index, 1)
	hero.add_gold(int(res["gold"]))
	for id in res["mats"]:
		var it := ItemDatabase.get_item(id)
		if it:
			hero.inventory.add_item(it, int(res["mats"][id]))
	return true


static func repair(hero: Hero, item: ItemData) -> bool:
	var cost := repair_cost(item)
	if int(cost["gold"]) <= 0 or not pay(hero, cost):
		return false
	item.durability = item.max_durability
	_notify(hero)
	return true


static func _rename(item: ItemData) -> void:
	var name := item.display_name
	var plus := name.rfind(" +")
	if plus > 0 and name.substr(plus + 2).is_valid_int():
		name = name.left(plus)
	item.display_name = "%s +%d" % [name, item.upgrade_level]


static func _notify(hero: Hero) -> void:
	hero.equipment.changed.emit()
	hero.inventory.changed.emit()
