class_name HealEffect
extends ItemEffect

@export var amount: int = 30
## Fraction of max HP added on top of `amount`.
@export_range(0.0, 1.0) var percent: float = 0.0


func apply(user: Node) -> bool:
	var stats: Stats = user.hero.stats
	if stats.hp >= stats.max_hp():
		return false
	var value := amount + roundi(stats.max_hp() * percent)
	stats.heal(value)
	EventBus.floating_text.emit(user.global_position + Vector2(0, -20), "+%d" % value, Color(0.4, 1.0, 0.4))
	return true


func describe() -> String:
	if percent > 0.0:
		return "Лечит %d + %d%% здоровья" % [amount, roundi(percent * 100)]
	return "Лечит %d здоровья" % amount
