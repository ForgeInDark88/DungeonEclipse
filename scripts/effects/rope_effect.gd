class_name RopeEffect
extends ItemEffect
## Hangs a climbable rope from the hero position up to the ceiling.

@export var max_length: int = 10


func apply(user: Node) -> bool:
	var level: DungeonLevel = user.level
	if level == null:
		return false
	var cell := level.world_to_cell(user.global_position + Vector2(0, -4))
	if Net.active and not Net.is_host:
		# Ropes change tiles: the host places the real one and broadcasts the
		# cells; the guest still climbs because the tiles arrive quickly.
		# Untyped NetSync on purpose (cyclic class dependency otherwise).
		var ns = user.get_tree().get_first_node_in_group("net_game")
		if ns:
			ns.request_rope.rpc_id(1, cell, max_length)
		return true
	return level.place_rope(cell, max_length) > 0


func describe() -> String:
	return tr("Верёвка вверх до %d клеток — по ней можно лазать") % max_length
