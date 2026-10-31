class_name Hero
extends RefCounted
## Everything that belongs to the hero for the whole run (survives floor
## changes): race, class, stats, experience, inventory, equipment, quick bar,
## skills. The Player node is only the in-world body of this object.

signal xp_changed(xp: int, xp_to_next: int)
signal leveled_up(level: int)
signal gold_changed(gold: int)

const INVENTORY_SIZE := 30

var race: RaceData
var class_data: ClassData
var stats := Stats.new()
var inventory := Inventory.new(INVENTORY_SIZE)
var equipment: Equipment
var quick_bar := QuickBar.new()
var skills := SkillSet.new()
var level: int = 1
var xp: int = 0
var gold: int = 0


## A heroine: female body layer and portrait (no effect on stats).
var female := false


## Body sheet for the hero's sex (falls back to RaceData.body_sheet).
func body_sheet() -> Texture2D:
	if female and race.body_sheet_female:
		return race.body_sheet_female
	return race.body_sheet


func _init(p_race: RaceData, p_class: ClassData, layout: EquipmentLayout) -> void:
	race = p_race
	class_data = p_class
	equipment = Equipment.new(layout)
	equipment.changed.connect(_on_equipment_changed)
	stats.setup(race, class_data, level)
	skills.changed.connect(_refresh_passives)
	inventory.changed.connect(_refresh_relics)
	EventBus.enemy_killed.connect(func(_d: EnemyData, _p: Vector2) -> void: _on_enemy_killed_heal())
	skills.setup(class_data.skills, class_data.tree_layout, class_data.branch_names)


## Fills inventory / equipment / quick bar from ClassData.starting_* fields.
func give_starting_kit() -> void:
	for id: StringName in class_data.starting_items:
		var item := ItemDatabase.get_item(id)
		if item == null:
			continue
		if item.is_stackable():
			inventory.add_item(item, int(class_data.starting_items[id]))
		else:
			for i in int(class_data.starting_items[id]):
				inventory.add_item(ItemFactory.create(item))
	for id in class_data.starting_equipment:
		var idx := inventory.find_index(id)
		if idx >= 0:
			equip_from_inventory(idx)
	var q := 0
	for id in class_data.starting_quick_bar:
		var item := ItemDatabase.get_item(id)
		if item and q < QuickBar.SIZE:
			quick_bar.assign(q, item)
			q += 1
	stats.hp = stats.max_hp()
	stats.mana = stats.max_mana()
	stats.recalculate()


## Net co-op: xp and gold from a kill credited to this hero by the host.
func gain_kill_reward(xp_amount: int, gold_amount: int) -> void:
	if xp_amount > 0:
		add_xp(xp_amount)
	if gold_amount > 0:
		add_gold(gold_amount)


## Co-op: back from the dead on a new floor.
func revive() -> void:
	stats.heal(stats.max_hp())  # heal/restore emit the signals the HUD listens to
	stats.restore_mana(stats.max_mana())


func add_gold(amount: int) -> void:
	gold = maxi(0, gold + amount)
	if amount > 0:
		GameState.run_stats["gold"] = int(GameState.run_stats.get("gold", 0)) + amount
		EventBus.gold_earned.emit(amount)
	gold_changed.emit(gold)


func spend_gold(amount: int) -> bool:
	if gold < amount:
		return false
	gold -= amount
	gold_changed.emit(gold)
	return true


func xp_to_next() -> int:
	return 30 + (level - 1) * 25 + (level - 1) * (level - 1) * 5


func add_xp(amount: int) -> void:
	xp += amount
	while xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		stats.set_level(level)
		skills.add_points(1)
		leveled_up.emit(level)
	xp_changed.emit(xp, xp_to_next())


## Equips the item at an inventory slot (swapping with the worn one).
func equip_from_inventory(index: int, slot_id: StringName = StringName()) -> bool:
	var stack := inventory.stack_at(index)
	if stack == null or not (stack.item is EquipmentItemData):
		return false
	var item := stack.item as EquipmentItemData
	if slot_id == StringName():
		slot_id = equipment.slot_for(item)
	if not equipment.can_equip_in(item, slot_id) or equipment.is_locked(slot_id):
		return false
	inventory.take_at(index)
	var previous := equipment.equip(item, slot_id)
	if previous != null:
		inventory.put_at(index, ItemStack.new(previous, 1))
	return true


## Moves a worn item back to the backpack (optionally to a given slot).
func unequip_to_inventory(slot_id: StringName, index: int = -1) -> bool:
	var item := equipment.get_item(slot_id)
	if item == null or equipment.is_locked(slot_id):
		return false
	if index >= 0:
		var target := inventory.stack_at(index)
		if target != null:
			# Swap if the backpack item fits this slot, otherwise refuse.
			if equipment.can_equip_in(target.item, slot_id):
				inventory.take_at(index)
				equipment.equip(target.item as EquipmentItemData, slot_id)
				inventory.put_at(index, ItemStack.new(item, 1))
				return true
			return false
		equipment.unequip(slot_id)
		inventory.put_at(index, ItemStack.new(item, 1))
		return true
	if inventory.free_space_for(item) <= 0:
		EventBus.message.emit(tr("Рюкзак полон"))
		return false
	equipment.unequip(slot_id)
	inventory.add_item(item, 1)
	return true


## Moves an equipped item between two compatible slots (ring 1 <-> ring 2).
func move_equipment(from_slot: StringName, to_slot: StringName) -> void:
	var a := equipment.get_item(from_slot)
	if a == null or from_slot == to_slot or not equipment.can_equip_in(a, to_slot):
		return
	if equipment.is_locked(from_slot) or equipment.is_locked(to_slot):
		return
	var b := equipment.get_item(to_slot)
	equipment.items[to_slot] = a
	equipment.items[from_slot] = b
	equipment.changed.emit()


func weapon() -> WeaponItemData:
	return equipment.get_item(&"weapon") as WeaponItemData


## Seconds between attacks with the current weapon (class penalty included).
## Relics (the war drum): attacks this much faster.
var attack_speed_mult := 1.0


func attack_interval() -> float:
	return _base_attack_interval() / maxf(0.1, attack_speed_mult)


func _base_attack_interval() -> float:
	var w := weapon()
	if w == null:
		return class_data.attack_cooldown
	var interval := w.cooldown()
	if not class_data.allows_weapon(w):
		interval /= ClassData.WRONG_WEAPON_SPEED
	return interval


## Wears the weapon by `amount` (called on each hit).
func wear_weapon(amount: int = 1) -> void:
	_wear(weapon(), amount)


## Wears a random worn armor piece (called when the hero is hit).
func wear_armor(amount: int = 1) -> void:
	var pieces: Array[EquipmentItemData] = []
	for item: EquipmentItemData in equipment.items.values():
		if item and not (item is WeaponItemData) and item.has_durability and item.is_instance() and item.durability > 0:
			pieces.append(item)
	if not pieces.is_empty():
		_wear(pieces.pick_random(), amount)


func _wear(item: EquipmentItemData, amount: int) -> void:
	if item == null or not item.has_durability or not item.is_instance() or item.durability <= 0:
		return
	item.durability = maxi(0, item.durability - amount)
	if item.durability == 0:
		EventBus.message.emit(tr("%s ломается! Нужен ремонт.") % item.display_name)
		equipment.changed.emit()
	elif item.durability == item.max_durability / 5:
		EventBus.message.emit(tr("%s почти сломан(а)") % item.display_name)


func _on_equipment_changed() -> void:
	var w := weapon()
	stats.weapon_base = w.effective_damage() if w else 0.0
	stats.weapon_penalty = 1.0 if class_data.allows_weapon(w) else ClassData.WRONG_WEAPON_DAMAGE
	stats.set_modifier("equipment", equipment.total_bonuses())
	stats.set_modifier("sets", set_bonuses())
	_refresh_passives()


## Stat bonuses of learned passive skills (stronger with a synergy weapon).
func _refresh_passives() -> void:
	var total := {}
	var w := weapon()
	for s in skills.passives():
		var b: Dictionary = (s.effect as PassiveSkill).bonuses_for(skills.rank(s), s.power_with(w))
		for k in b:
			total[k] = float(total.get(k, 0.0)) + float(b[k])
	if total.is_empty() and not stats.has_modifier("passives"):
		return
	stats.set_modifier("passives", total)


## Rolls the on-hit effects of passive skills (called by the Player on weapon hits).
func apply_passive_hits(attacker: Node, target: Node, damage: int) -> void:
	var w := weapon()
	for s in skills.passives():
		var p := s.effect as PassiveSkill
		if p.hit_effect and randf() < p.chance_for(skills.rank(s), s.power_with(w)):
			p.hit_effect.on_hit(attacker, target, damage)
	# Relic powers react to every confirmed hit (melee, shots, the host's ok).
	var pl := attacker as Player
	if pl and pl.relic_powers and target is Enemy:
		pl.relic_powers.on_hit(target, damage)


# ------------------------------------------------------------------- sets
## Parts of each set worn: set id -> count.
func worn_sets() -> Dictionary:
	var worn := {}
	for item: EquipmentItemData in equipment.items.values():
		if item and item.set_id != &"":
			worn[item.set_id] = int(worn.get(item.set_id, 0)) + 1
	return worn


func set_bonuses() -> Dictionary:
	var total := {}
	var worn := worn_sets()
	for id in worn:
		var data: ItemSetData = ItemDatabase.sets.get(id)
		if data == null:
			continue
		var b := data.bonuses_for(worn[id])
		for k in b:
			total[k] = float(total.get(k, 0.0)) + float(b[k])
	return total


# ----------------------------------------------------------------- relics
## Relics in the backpack, one per id.
func relics() -> Array[RelicItemData]:
	var out: Array[RelicItemData] = []
	var seen := {}
	for stack in inventory.slots:
		if stack and stack.item is RelicItemData and not seen.has(stack.item.id):
			seen[stack.item.id] = true
			out.append(stack.item)
	return out


func _refresh_relics() -> void:
	var total := {}
	for r in relics():
		for k in r.stat_bonuses:
			total[k] = float(total.get(k, 0.0)) + float(r.stat_bonuses[k])
	stats.set_modifier("relics", total)


func _on_enemy_killed_heal() -> void:
	var heal := 0
	for r in relics():
		heal += r.heal_on_kill
	if heal > 0 and stats.hp > 0:
		stats.heal(heal)


## A "second chance" relic saves the hero once: returns true if it did.
func try_second_chance() -> bool:
	for r in relics():
		if r.second_chance:
			inventory.remove_by_id(r.id, 1)
			stats.hp = maxi(1, roundi(stats.max_hp() * r.revive_percent))
			stats.hp_changed.emit(stats.hp, stats.max_hp())
			EventBus.message.emit(tr("%s сгорает — вы снова на ногах!") % r.display_name)
			return true
	return false
