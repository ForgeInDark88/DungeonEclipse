class_name BuffItemEffect
extends ItemEffect
## Temporary stat bonuses (potions of speed, strength, protection...).

@export var key: String = "potion"
@export var bonuses: Dictionary = {"speed": 30}
@export var duration: float = 30.0
@export var tint: Color = Color(1.0, 1.0, 1.0)


func apply(user: Node) -> bool:
	user.apply_buff("item_" + key, bonuses, duration, tint)
	Fx.sparks(user.get_parent(), user.global_position + Vector2(0, -10), tint, 10, 50.0)
	return true


func describe() -> String:
	var parts: Array[String] = []
	for k in bonuses:
		parts.append("%s %s" % [StatTypes.label(k), StatTypes.format_value(k, float(bonuses[k]), true)])
	return "%s на %d сек." % [", ".join(parts), roundi(duration)]
