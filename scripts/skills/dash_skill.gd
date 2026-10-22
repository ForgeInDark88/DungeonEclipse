class_name DashSkill
extends SkillEffect
## Quick invulnerable dash forward. Optionally hurts enemies passed through.

@export var speed: float = 420.0
@export var duration: float = 0.18
@export var duration_per_level: float = 0.03
@export var damage_multiplier: float = 0.0


func execute(caster: Node, level: int) -> bool:
	var start: Vector2 = caster.global_position
	caster.dash(speed, duration + duration_per_level * (level - 1))
	Fx.sparks(caster.get_parent(), start + Vector2(0, -10), Color(0.8, 0.85, 1.0), 10, 60.0)
	if damage_multiplier > 0.0:
		var reach := speed * (duration + duration_per_level * (level - 1))
		for enemy in caster.get_tree().get_nodes_in_group("enemies"):
			var rel: Vector2 = enemy.global_position - start
			if absf(rel.y) < 20.0 and signf(rel.x) == caster.facing and absf(rel.x) <= reach \
					and LineOfSight.can_hit(caster, start + Vector2(0, -10), enemy):
				var d: Dictionary = caster.roll_damage(damage_multiplier)
				enemy.take_damage(d["amount"], d["crit"], start)
	return true


func describe(level: int) -> String:
	var text := "Рывок на %d пикс., неуязвимость во время рывка" % roundi(speed * (duration + duration_per_level * (level - 1)))
	if damage_multiplier > 0.0:
		text += ", урон %d%% по пути" % roundi(damage_multiplier * 100)
	return text
