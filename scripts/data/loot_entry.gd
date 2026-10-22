class_name LootEntry
extends Resource
## One possible drop of a LootTable. The item's rarity and item_level decide
## when it can appear (see LootTable); these fields narrow it further.

@export var item: ItemData
## Relative chance among entries of the same rarity.
@export var weight: float = 1.0
@export var min_count: int = 1
@export var max_count: int = 1
## Floors where the entry may drop (max_floor 0 = no upper limit).
@export var min_floor: int = 1
@export var max_floor: int = 0


func allowed_on(floor_number: int) -> bool:
	return floor_number >= min_floor and (max_floor <= 0 or floor_number <= max_floor)
