class_name UnlockEffect
extends ItemEffect
## Unlocks the nearest locked chest within range. Keys are also spent
## automatically when interacting with a locked chest.

@export var range_px: float = 40.0


func apply(user: Node) -> bool:
	for chest in user.get_tree().get_nodes_in_group("chests"):
		if chest.locked and chest.global_position.distance_to(user.global_position) <= range_px:
			chest.unlock()
			return true
	EventBus.message.emit("Рядом нет запертого сундука")
	return false


func describe() -> String:
	return "Открывает запертый сундук рядом"
