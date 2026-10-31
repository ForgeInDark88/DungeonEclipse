class_name TeleportEffect
extends ItemEffect
## Moves the hero to a random safe standing spot of the floor, away from
## monsters (or next to the exit door with `to_exit`).

@export var to_exit: bool = false
@export var min_distance_cells: int = 12


func apply(user: Node) -> bool:
	var level: DungeonLevel = user.level
	if level == null or level.nav == null:
		return false
	var target := Vector2i(-1, -1)
	if to_exit:
		target = level.nav.safe_cell_near(level.layout.exit_cell + Vector2i(-2, 0), 1)
	else:
		var here := level.world_to_cell(user.global_position)
		var cells: Array[Vector2i] = []
		for y in level.layout.height:
			for x in level.layout.width:
				var c := Vector2i(x, y)
				if level.nav.standable(x, y, 2) and not level.nav.is_dangerous(c) and Vector2(c).distance_to(Vector2(here)) >= min_distance_cells:
					cells.append(c)
		var enemies := user.get_tree().get_nodes_in_group("enemies")
		cells.shuffle()
		for c in cells:
			var pos := level.cell_bottom(c)
			if enemies.all(func(e: Node) -> bool: return e.global_position.distance_to(pos) > 96.0):
				target = c
				break
	if target.x < 0:
		EventBus.message.emit(tr("Свиток не нашёл безопасного места"))
		return false
	Fx.sparks(user.get_parent(), user.global_position + Vector2(0, -10), Color(0.7, 0.5, 1.0), 16, 80.0)
	user.global_position = level.cell_bottom(target)
	user.velocity = Vector2.ZERO
	Fx.sparks(user.get_parent(), user.global_position + Vector2(0, -10), Color(0.7, 0.5, 1.0), 16, 80.0)
	AudioManager.play_sfx(&"portal", user.global_position)
	return true


func describe() -> String:
	return tr("Переносит к выходу с этажа") if to_exit else tr("Переносит в случайное безопасное место этажа")
