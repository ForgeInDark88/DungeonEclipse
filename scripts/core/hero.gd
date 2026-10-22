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


func _init(p_race: RaceData, p_class: ClassData, layout: EquipmentLayout) -> void:
	race = p_race
	class_data = p_class
	equipment = Equipment.new(layout)
	equipment.changed.connect(_on_equipment_changed)
	stats.setup(race, class_data, level)
	skills.setup(class_data.skills)


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
	if not equipment.can_equip_in(item, slot_id):
		return false
	inventory.take_at(index)
	var previous := equipment.equip(item, slot_id)
	if previous != null:
		inventory.put_at(index, ItemStack.new(previous, 1))
	return true


## Moves a worn item back to the backpack (optionally to a given slot).
func unequip_to_inventory(slot_id: StringName, index: int = -1) -> bool:
	var item := equipment.get_item(slot_id)
	if item == null:
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
		EventBus.message.emit("Рюкзак полон")
		return false
	equipment.unequip(slot_id)
	inventory.add_item(item, 1)
	return true


## Moves an equipped item between two compatible slots (ring 1 <-> ring 2).
func move_equipment(from_slot: StringName, to_slot: StringName) -> void:
	var a := equipment.get_item(from_slot)
	if a == null or from_slot == to_slot or not equipment.can_equip_in(a, to_slot):
		return
	var b := equipment.get_item(to_slot)
	equipment.items[to_slot] = a
	equipment.items[from_slot] = b
	equipment.changed.emit()


func weapon() -> WeaponItemData:
	return equipment.get_item(&"weapon") as WeaponItemData


## Seconds between attacks with the current weapon (class penalty included).
func attack_interval() -> float:
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
		EventBus.message.emit("%s ломается! Нужен ремонт." % item.display_name)
		equipment.changed.emit()
	elif item.durability == item.max_durability / 5:
		EventBus.message.emit("%s почти сломан(а)" % item.display_name)


func _on_equipment_changed() -> void:
	var w := weapon()
	stats.weapon_base = w.effective_damage() if w else 0.0
	stats.weapon_penalty = 1.0 if class_data.allows_weapon(w) else ClassData.WRONG_WEAPON_DAMAGE
	stats.set_modifier("equipment", equipment.total_bonuses())
