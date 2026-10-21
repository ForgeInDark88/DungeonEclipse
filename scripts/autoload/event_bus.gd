extends Node
## Global signals between systems that should not know each other.

## Text floating up in the world (damage numbers, heals, pickups).
signal floating_text(world_pos: Vector2, text: String, color: Color)
## Short message shown in the HUD log line.
signal message(text: String)
signal enemy_killed(enemy_data: EnemyData, world_pos: Vector2)
signal player_died
signal floor_changed(floor_number: int)
## Request to spawn items in the world (chest loot, enemy drops, dropped items).
signal spawn_items(world_pos: Vector2, stacks: Array)
signal inventory_toggled(open: bool)
signal chest_opened(chest: Node)
signal screen_shake(strength: float)
