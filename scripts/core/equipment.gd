class_name Equipment
extends RefCounted
## Equipped items by slot id. Slots come from an EquipmentLayout resource,
## so adding a slot is a data change. Emits `changed` after every change and
## exposes the summed bonuses for Stats.

signal changed

var layout: EquipmentLayout
## slot id -> EquipmentItemData (or null)
var items: Dictionary = {}


func _init(p_layout: EquipmentLayout = null) -> void:
	layout = p_layout
	if layout:
		for def in layout.slots:
			items[def.id] = null


func slot_defs() -> Array[EquipSlotDef]:
	return layout.slots if layout else ([] as Array[EquipSlotDef])


func get_def(slot_id: StringName) -> EquipSlotDef:
	for def in slot_defs():
		if def.id == slot_id:
			return def
	return null


func get_item(slot_id: StringName) -> EquipmentItemData:
	return items.get(slot_id)


func can_equip_in(item: ItemData, slot_id: StringName) -> bool:
	var def := get_def(slot_id)
	return def != null and item is EquipmentItemData and (item as EquipmentItemData).slot_type == def.slot_type


## Best slot for an item: first empty slot of the matching type, else the first
## matching one (swap). Empty StringName if none.
func slot_for(item: EquipmentItemData) -> StringName:
	var fallback := StringName()
	for def in slot_defs():
		if def.slot_type == item.slot_type:
			if items[def.id] == null:
				return def.id
			if fallback == StringName():
				fallback = def.id
	return fallback


## Equips into a slot and returns the previously equipped item (or null).
func equip(item: EquipmentItemData, slot_id: StringName) -> EquipmentItemData:
	if not can_equip_in(item, slot_id):
		return item
	var previous: EquipmentItemData = items[slot_id]
	items[slot_id] = item
	changed.emit()
	return previous


func unequip(slot_id: StringName) -> EquipmentItemData:
	var previous: EquipmentItemData = items.get(slot_id)
	if previous != null:
		items[slot_id] = null
		changed.emit()
	return previous


## The item currently worn in the slot this item would go to (for tooltips).
func compare_target(item: EquipmentItemData) -> EquipmentItemData:
	var slot := slot_for(item)
	if slot == StringName():
		return null
	return items[slot]


func total_bonuses() -> Dictionary:
	var total := {}
	for item: EquipmentItemData in items.values():
		if item == null:
			continue
		for k in item.stat_bonuses:
			total[k] = float(total.get(k, 0.0)) + float(item.stat_bonuses[k])
	return total
