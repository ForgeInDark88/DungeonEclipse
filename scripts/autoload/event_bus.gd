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
## A hit landed: shows the damage number and drives game feel
## (hit-stop, shake, red screen flash when `on_player`).
signal damage_dealt(world_pos: Vector2, amount: int, crit: bool, on_player: bool)
## An item went from the world into the backpack (HUD flies its icon).
signal item_collected(item: ItemData, world_pos: Vector2)
signal trap_disarmed(trap: TrapData)
## A merchant wants to open its shop UI.
signal shop_requested(merchant: Node, player: Node)
signal boss_spawned(boss: Node)
signal boss_hp_changed(hp: int, max_hp: int)
signal boss_defeated(boss: BossData, world_pos: Vector2)
## Statistics hooks (Codex: achievements, bestiary, item encyclopedia).
signal elite_killed(enemy_data: EnemyData)
signal gold_earned(amount: int)
signal event_completed(event: Node)
signal item_bought(item: ItemData)
signal achievement_unlocked(achievement: AchievementData)
