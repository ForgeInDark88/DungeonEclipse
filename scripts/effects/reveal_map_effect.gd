class_name RevealMapEffect
extends ItemEffect
## Reveals the whole floor on the minimap (map scroll).


func apply(user: Node) -> bool:
	if user.level == null:
		return false
	user.level.reveal_all()
	EventBus.message.emit(tr("Карта этажа раскрыта (M)"))
	return true


func describe() -> String:
	return tr("Раскрывает всю карту этажа")
