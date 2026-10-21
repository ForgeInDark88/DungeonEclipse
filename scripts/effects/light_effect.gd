class_name LightEffect
extends ItemEffect
## Temporarily widens the hero light (torch).

@export var light_scale: float = 2.2
@export var duration: float = 60.0


func apply(user: Node) -> bool:
	user.boost_light(light_scale, duration)
	return true


func describe() -> String:
	return "Освещает подземелье на %d сек." % roundi(duration)
