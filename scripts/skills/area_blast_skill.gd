class_name AreaBlastSkill
extends SkillEffect
## Damages every enemy around the caster (optionally breaks bricks, slows).

@export var radius: float = 48.0
@export var radius_per_level: float = 6.0
@export var damage_multiplier: float = 1.6
@export var damage_per_level: float = 0.35
@export var knockback: float = 160.0
@export var breaks_tiles: bool = false
## Freezes enemies for this long (seconds), 0 = no freeze.
@export var stun_time: float = 0.0
@export var color: Color = Color(1.0, 0.5, 0.2)


func execute(caster: Node, level: int) -> bool:
	var center: Vector2 = caster.global_position + Vector2(0, -10)
	var r := radius + radius_per_level * (level - 1)
	var mult := damage_multiplier + damage_per_level * (level - 1)
	for enemy in caster.get_tree().get_nodes_in_group("enemies"):
		if enemy.global_position.distance_to(center) <= r:
			var d: Dictionary = caster.roll_damage(mult)
			enemy.take_damage(d["amount"], d["crit"], center)
			if enemy.hp > 0:
				var dir: Vector2 = (enemy.global_position - center).normalized()
				enemy.velocity = dir * knockback + Vector2(0, -60)
				if stun_time > 0.0:
					enemy.stun(stun_time)
	if breaks_tiles and caster.level:
		caster.level.explode(center, r * 0.6)
	Fx.explosion(caster.get_parent(), center, r, color)
	EventBus.screen_shake.emit(4.0)
	return true


func describe(level: int) -> String:
	var text := "Удар по области (радиус %d), урон %d%%" % [roundi(radius + radius_per_level * (level - 1)), roundi((damage_multiplier + damage_per_level * (level - 1)) * 100)]
	if stun_time > 0.0:
		text += ", замедляет на %.1f сек." % stun_time
	if breaks_tiles:
		text += ", ломает кирпич"
	return text
