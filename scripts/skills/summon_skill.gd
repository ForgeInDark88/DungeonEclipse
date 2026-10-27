class_name SummonSkill
extends SkillEffect
## Necromancer: raises undead servants (Minion) next to the caster. Higher
## levels raise more at once and let more stay; the oldest crumble first
## when the limit is reached.

@export var kind: Minion.Kind = Minion.Kind.WARRIOR
@export var count: int = 1
## One extra minion per this many levels (0 = never).
@export var extra_every_levels: int = 2
@export var max_alive: int = 2
@export var max_alive_per_level: int = 1
@export var damage_multiplier: float = 0.6
@export var damage_per_level: float = 0.1
@export var lifetime: float = 20.0
@export var lifetime_per_level: float = 3.0


func execute(caster: Node, level: int) -> bool:
	var player := caster as Player
	if player == null:
		return false
	var n := count + (level - 1) / extra_every_levels if extra_every_levels > 0 else count
	var cap := max_alive + max_alive_per_level * (level - 1)
	var mine: Array[Minion] = []
	for m in caster.get_tree().get_nodes_in_group("minions"):
		if m is Minion and m.owner_player == player and m.kind == kind and not m.is_queued_for_deletion():
			mine.append(m)
	# Over the limit: the oldest servants return to dust.
	while mine.size() + n > cap and not mine.is_empty():
		mine.pop_front()._crumble()
	var mult := damage_multiplier + damage_per_level * (level - 1)
	var life := lifetime + lifetime_per_level * (level - 1)
	for i in n:
		var slot := mine.size() + i
		var pos: Vector2 = player.global_position + Vector2(player.facing * (14.0 + i * 12.0), 0)
		Minion.spawn(player, kind, mult, life, slot, pos)
	AudioManager.play_sfx(&"skill_cast", player.global_position)
	return true


func describe(level: int) -> String:
	var n := count + (level - 1) / extra_every_levels if extra_every_levels > 0 else count
	var names := ["скелета-воина", "скелета-лучника", "костяного голема"]
	return "Поднимает %d %s на %d с (урон %d%%, не больше %d)" % [n, names[kind],
		roundi(lifetime + lifetime_per_level * (level - 1)),
		roundi((damage_multiplier + damage_per_level * (level - 1)) * 100), max_alive + max_alive_per_level * (level - 1)]
