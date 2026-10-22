class_name RepairEffect
extends ItemEffect
## Restores durability of every equipped item (whetstone / repair kit).

@export_range(0.0, 1.0) var fraction: float = 1.0


func apply(user: Node) -> bool:
	var hero: Hero = user.hero
	var repaired := false
	for item: EquipmentItemData in hero.equipment.items.values():
		if item and item.has_durability and item.is_instance() and item.durability < item.max_durability:
			item.durability = mini(item.max_durability, item.durability + ceili(item.max_durability * fraction))
			repaired = true
	if not repaired:
		EventBus.message.emit("Снаряжению не нужен ремонт")
		return false
	hero.equipment.changed.emit()
	EventBus.message.emit("Снаряжение отремонтировано")
	return true


func describe() -> String:
	return "Чинит надетое снаряжение на %d%% прочности" % roundi(fraction * 100.0)
