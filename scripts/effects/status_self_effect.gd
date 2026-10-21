class_name StatusSelfEffect
extends ItemEffect
## Applies a status to the user (regeneration potion, shield elixir...).

@export var status: StringName = &"regen"
@export var duration: float = 10.0
@export var power: float = 3.0


func apply(user: Node) -> bool:
	user.status.apply(status, duration, power)
	return true


func describe() -> String:
	match status:
		&"regen":
			return "Регенерация: %d HP / 0.5 с на %d сек." % [roundi(power), roundi(duration)]
		&"shield":
			return "Щит на %d урона, %d сек." % [roundi(power), roundi(duration)]
	return "%s на %d сек." % [StatusEffects.display_name(status), roundi(duration)]
