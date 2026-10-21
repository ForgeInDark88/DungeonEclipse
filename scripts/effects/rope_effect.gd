class_name RopeEffect
extends ItemEffect
## Hangs a climbable rope from the hero position up to the ceiling.

@export var max_length: int = 10


func apply(user: Node) -> bool:
	var level: DungeonLevel = user.level
	if level == null:
		return false
	var cell := level.world_to_cell(user.global_position + Vector2(0, -4))
	return level.place_rope(cell, max_length) > 0


func describe() -> String:
	return "Верёвка вверх до %d клеток — по ней можно лазать" % max_length
