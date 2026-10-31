class_name Identify
extends RefCounted
## Unidentified / cursed items of the hero (scrolls and merchant services).

const IDENTIFY_PRICE := 15
const UNCURSE_PRICE := 60


static func _owned(hero: Hero) -> Array[ItemData]:
	var out: Array[ItemData] = []
	for item: EquipmentItemData in hero.equipment.items.values():
		if item:
			out.append(item)
	for st in hero.inventory.slots:
		if st != null:
			out.append(st.item)
	return out


static func unidentified_count(hero: Hero) -> int:
	return _owned(hero).filter(func(it: ItemData) -> bool: return it.unidentified).size()


static func cursed_count(hero: Hero) -> int:
	return _owned(hero).filter(func(it: ItemData) -> bool: return it.cursed and not it.unidentified).size()


## Identifies everything; returns the revealed names.
static func all(hero: Hero) -> Array[String]:
	var names: Array[String] = []
	for it in _owned(hero):
		if it.identify():
			names.append(it.display_name + (TranslationServer.translate(" (проклят)") if it.cursed else ""))
	if not names.is_empty():
		hero.inventory.changed.emit()
		hero.equipment.changed.emit()
	return names


static func lift_curses(hero: Hero) -> int:
	var n := 0
	for it in _owned(hero):
		if it.cursed and not it.unidentified:
			it.lift_curse()
			n += 1
	if n > 0:
		hero.equipment.changed.emit()
		hero.inventory.changed.emit()
	return n
