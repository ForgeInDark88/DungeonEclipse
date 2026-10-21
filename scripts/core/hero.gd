class_name Hero
extends RefCounted
## Everything that belongs to the hero for the whole run (survives floor
## changes): race, class, stats, experience, inventory, equipment, quick bar,
## skills. The Player node is only the in-world body of this object.

signal xp_changed(xp: int, xp_to_next: int)
signal leveled_up(level: int)

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
		if item:
			inventory.add_item(item, int(class_data.starting_items[id]))
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


func _on_equipment_changed() -> void:
	stats.set_modifier("equipment", equipment.total_bonuses())
