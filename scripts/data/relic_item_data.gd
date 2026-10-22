class_name RelicItemData
extends ItemData
## A relic / talisman: works for the whole run just by lying in the backpack
## (no slot). `stat_bonuses` apply while carried (one copy of each relic
## counts); special powers below are handled by Hero / Player.

## Heals this much HP for every monster killed.
@export var heal_on_kill: int = 0
## On death: the hero comes back with `revive_percent` HP; the relic is spent.
@export var second_chance: bool = false
@export_range(0.0, 1.0) var revive_percent: float = 0.5


func _init() -> void:
	item_type = ItemType.RELIC
	max_stack = 1


func subtitle() -> String:
	return "Реликвия (действует из рюкзака)"
