class_name DigEffect
extends ItemEffect
## Breaks brick tiles next to the hero (pickaxe): in front by default,
## below with S/Down held, above with W/Up held.

@export var reach_tiles: int = 1
## Bricks broken per use (better pickaxes cut a short tunnel).
@export var bricks_per_use: int = 1


func apply(user: Node) -> bool:
	var level: DungeonLevel = user.level
	if level == null:
		return false
	var step := Vector2i(int(user.facing), 0)
	var start := level.world_to_cell(user.global_position + Vector2(0, -8))
	if Input.is_action_pressed("move_down"):
		step = Vector2i.DOWN
		start = level.world_to_cell(user.global_position + Vector2(0, -2))
	elif Input.is_action_pressed("move_up"):
		step = Vector2i.UP
		start = level.world_to_cell(user.global_position + Vector2(0, -18))
	var broken := 0
	for i in range(1, reach_tiles + 1):
		if level.break_tile(start + step * i):
			broken += 1
			if broken >= bricks_per_use:
				break
	return broken > 0


func describe() -> String:
	var what := tr("кирпич рядом") if bricks_per_use <= 1 else tr("до %d кирпичей подряд") % bricks_per_use
	return tr("Разбивает %s (с S/↓ — под ногами, с W/↑ — над головой)") % what
