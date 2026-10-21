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
## Optional wear: every copy that drops is an instance that loses durability
## (weapons when hitting, armor when hit). Broken items give no bonuses.
## Shop price in gold (0 = automatic from type and rarity). Sells for 40%.
@export var price: int = 0
## > 0: picking it up adds this much gold per piece instead of an item.
@export var currency_value: int = 0
@export var has_durability := false
@export var max_durability: int = 100

# --- Runtime instance data ------------------------------------------------
# The .tres file is a TEMPLATE and never changes. Items that need their own
# values (affixes, durability) are runtime copies made by make_instance() /
# ItemFactory: `template` points back to the .tres, the rest is per copy.
var template: ItemData
var durability: int = -1
var affixes: Array[AffixData] = []


func is_instance() -> bool:
	return template != null


func is_broken() -> bool:
	return has_durability and is_instance() and durability == 0


## Runtime copy of this template with its own durability (affixes are added
## by ItemFactory).
func make_instance() -> ItemData:
	var inst := duplicate(true) as ItemData
	inst.template = self if template == null else template
	if has_durability:
		inst.durability = max_durability
	return inst


const AUTO_PRICES := {ItemType.EQUIPMENT: [30, 120, 400], ItemType.USABLE: [15, 50, 120], ItemType.MATERIAL: [4, 20, 60]}
const SELL_FACTOR := 0.4


## Buy price; affixes and wear change it for instances.
func buy_price() -> int:
	var p := price if price > 0 else int(AUTO_PRICES[item_type][rarity])
	if self is WeaponItemData and price <= 0:
		p = roundi(p * 1.2)
	p = roundi(p * (1.0 + 0.25 * affixes.size()))
	if has_durability and is_instance() and max_durability > 0:
		p = roundi(p * (0.4 + 0.6 * float(durability) / max_durability))
	return maxi(1, p)


func sell_price() -> int:
	return maxi(1, roundi(buy_price() * SELL_FACTOR))


## Bonuses that currently apply (none while broken).
func active_bonuses() -> Dictionary:
	return {} if is_broken() else stat_bonuses


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
