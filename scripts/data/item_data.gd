class_name ItemData
extends Resource
## Base item resource. Specialized types: EquipmentItemData, UsableItemData.
## Plain ItemData with type MATERIAL is a resource / misc item.

enum ItemType { EQUIPMENT, USABLE, MATERIAL }
enum Rarity { COMMON, RARE, EPIC }

const RARITY_NAMES := ["Обычный", "Редкий", "Эпический"]
const RARITY_COLORS := [Color(0.85, 0.82, 0.75), Color(0.35, 0.6, 1.0), Color(0.75, 0.4, 1.0)]
const TYPE_NAMES := ["Снаряжение", "Используемое", "Ресурс"]

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D
@export var item_type: ItemType = ItemType.MATERIAL
@export var rarity: Rarity = Rarity.COMMON
@export_range(1, 999) var max_stack: int = 1
## Bonuses keyed by StatTypes names (only applied while equipped).
@export var stat_bonuses: Dictionary = {}


func is_stackable() -> bool:
	return max_stack > 1


func rarity_color() -> Color:
	return RARITY_COLORS[rarity]


func rarity_name() -> String:
	return RARITY_NAMES[rarity]


func type_name() -> String:
	return TYPE_NAMES[item_type]


## Text shown under the item name in tooltips (overridden by subclasses).
func subtitle() -> String:
	return type_name()
