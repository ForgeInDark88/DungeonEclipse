class_name UnlockEffect
extends ItemEffect
## Unlocks the nearest locked chest within range. Keys are also spent
## automatically when interacting with a locked chest.

@export var range_px: float = 40.0
## < 1: a lockpick — it may break (and is spent either way).
@export_range(0.0, 1.0) var success_chance: float = 1.0


func apply(user: Node) -> bool:
	for chest in user.get_tree().get_nodes_in_group("chests"):
		if chest.locked and chest.global_position.distance_to(user.global_position) <= range_px:
			if randf() <= success_chance:
				chest.unlock()
			else:
				EventBus.message.emit(tr("Отмычка сломалась"))
				AudioManager.play_sfx(&"chest_locked", chest.global_position)
			return true
	EventBus.message.emit(tr("Рядом нет запертого сундука"))
	return false


func describe() -> String:
	if success_chance < 1.0:
		return tr("Вскрывает запертый сундук рядом (шанс %d%%)") % roundi(success_chance * 100.0)
	return tr("Открывает запертый сундук рядом")
