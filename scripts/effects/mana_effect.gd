class_name ManaEffect
extends ItemEffect

@export var amount: int = 25


func apply(user: Node) -> bool:
	var stats: Stats = user.hero.stats
	if stats.mana >= stats.max_mana():
		return false
	stats.restore_mana(amount)
	EventBus.floating_text.emit(user.global_position + Vector2(0, -20), "+%d" % amount, Color(0.4, 0.6, 1.0))
	return true


func describe() -> String:
	return "Восстанавливает %d маны" % amount
