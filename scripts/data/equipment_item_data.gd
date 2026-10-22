class_name EquipmentItemData
extends ItemData
## Item that goes into an equipment slot. `slot_type` must match an
## EquipSlotDef.slot_type from data/equipment_layout.tres
## (weapon, helmet, chest, gloves, boots, ring, amulet, ...).

const SLOT_TYPE_NAMES := {
	&"weapon": "Оружие",
	&"helmet": "Шлем",
	&"chest": "Нагрудник",
	&"gloves": "Перчатки",
	&"boots": "Сапоги",
	&"ring": "Кольцо",
	&"amulet": "Амулет",
}

@export var slot_type: StringName = &"weapon"
## Set this item belongs to (ItemSetData.id in data/sets/), empty = none.
@export var set_id: StringName = &""
## Optional animated layer shown on the hero while equipped
## (same layout as the hero body sheet).
@export var visual_sheet: Texture2D
## Hero layer it fills: "armor" (over the class outfit), "boots", "gloves"
## or "head" (replaces the class headgear).
@export var visual_layer: StringName = &"armor"


func _init() -> void:
	item_type = ItemType.EQUIPMENT
	max_stack = 1


func subtitle() -> String:
	return SLOT_TYPE_NAMES.get(slot_type, String(slot_type))
