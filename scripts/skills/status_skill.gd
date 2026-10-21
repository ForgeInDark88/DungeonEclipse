class_name StatusSkill
extends SkillEffect
## Applies a status to the caster (magic shield, regeneration...).

@export var status: StringName = &"shield"
@export var duration: float = 8.0
@export var duration_per_level: float = 1.0
## Shield: damage absorbed; regen: HP per tick.
@export var power: float = 25.0
@export var power_per_level: float = 15.0


func execute(caster: Node, level: int) -> bool:
	caster.status.apply(status, duration + duration_per_level * (level - 1), power + power_per_level * (level - 1))
	Fx.sparks(caster.get_parent(), caster.global_position + Vector2(0, -10), StatusEffects.color_of(status), 12, 50.0)
	return true


func describe(level: int) -> String:
	var p := roundi(power + power_per_level * (level - 1))
	var d := duration + duration_per_level * (level - 1)
	match status:
		&"shield":
			return "Щит поглощает %d урона, %d сек." % [p, roundi(d)]
		&"regen":
			return "Регенерация %d HP каждые 0.5 с, %d сек." % [p, roundi(d)]
	return "%s на %d сек." % [StatusEffects.display_name(status), roundi(d)]
