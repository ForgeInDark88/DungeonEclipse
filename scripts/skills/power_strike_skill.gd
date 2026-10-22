class_name PowerStrikeSkill
extends SkillEffect
## Heavy pickaxe blow: big melee damage in front and breaks bricks there.

@export var damage_multiplier: float = 2.2
@export var damage_per_level: float = 0.4
@export var reach: float = 26.0


func execute(caster: Node, level: int) -> bool:
	var front: Vector2 = caster.global_position + Vector2(caster.facing * reach * 0.6, -10)
	var mult := damage_multiplier + damage_per_level * (level - 1)
	for enemy in caster.get_tree().get_nodes_in_group("enemies"):
		if enemy.global_position.distance_to(front) <= reach:
			var d: Dictionary = caster.roll_damage(mult)
			enemy.take_damage(d["amount"], d["crit"], caster.global_position)
	var lvl: DungeonLevel = caster.level
	if lvl:
		for dy in [-18, -6]:
			lvl.break_tile(lvl.world_to_cell(caster.global_position + Vector2(caster.facing * 14.0, dy)))
	Fx.sparks(caster.get_parent(), front, Color(0.9, 0.9, 1.0), 10, 80.0)
	EventBus.screen_shake.emit(3.0)
	return true


func describe(level: int) -> String:
	return "Мощный удар киркой: урон %d%%, ломает кирпич перед героем" % roundi((damage_multiplier + damage_per_level * (level - 1)) * 100)
