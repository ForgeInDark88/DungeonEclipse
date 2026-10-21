class_name UsableItemData
extends ItemData
## Item that can be used from the inventory or the quick bar.
## Behaviour lives in `effects` (ItemEffect resources), so new items need no
## code changes in the core: combine existing effects or write a new
## ItemEffect script.

@export var effects: Array[ItemEffect] = []
## Removes one from the stack when at least one effect succeeded.
@export var consume_on_use: bool = true
@export var cooldown: float = 0.3
## Hero animation played on use: "use" (drink), "attack_quick" (throw),
## "attack_slash" (swing a tool), "interact" or "" for none.
@export var use_animation: StringName = &"use"


func _init() -> void:
	item_type = ItemType.USABLE


func subtitle() -> String:
	return "Используемое" if consume_on_use else "Инструмент"


## Returns true when the item was actually used.
func use(user: Node) -> bool:
	var used := false
	for effect in effects:
		if effect != null and effect.apply(user):
			used = true
	return used
