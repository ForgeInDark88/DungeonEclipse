class_name DetectEffect
extends ItemEffect
## Reveals the whole floor on the map and makes traps glow for a while.

@export var duration: float = 30.0


func apply(user: Node) -> bool:
	var level: DungeonLevel = user.level
	if level == null:
		return false
	level.reveal_all()
	for n in level.entities.get_children():
		if n is Trap:
			var tw := n.create_tween()
			tw.tween_property(n, "modulate", Color(1.6, 0.5, 0.5), 0.3)
			tw.tween_interval(duration)
			tw.tween_property(n, "modulate", Color.WHITE, 1.0)
	EventBus.message.emit("Этаж и все ловушки обнаружены")
	return true


func describe() -> String:
	return "Открывает карту этажа и подсвечивает ловушки на %d сек." % roundi(duration)
