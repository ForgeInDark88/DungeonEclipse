class_name BuffSkill
extends SkillEffect
## Temporary stat bonuses (shield, haste, ...). Bonuses grow per level.

@export var key: String = "buff"
@export var bonuses: Dictionary = {"armor": 10}
@export var bonuses_per_level: Dictionary = {"armor": 5}
@export var duration: float = 6.0
@export var duration_per_level: float = 1.0
@export var tint: Color = Color(0.6, 1.0, 0.6)
## Heals this fraction of max HP on cast.
@export var heal_percent: float = 0.0


func _bonuses_for(level: int) -> Dictionary:
	var result := {}
	for k in bonuses:
		result[k] = float(bonuses[k]) + float(bonuses_per_level.get(k, 0)) * (level - 1)
	return result


func execute(caster: Node, level: int) -> bool:
	caster.apply_buff("buff_" + key, _bonuses_for(level), duration + duration_per_level * (level - 1), tint)
	if heal_percent > 0.0:
		caster.hero.stats.heal(roundi(caster.hero.stats.max_hp() * heal_percent))
	Fx.sparks(caster.get_parent(), caster.global_position + Vector2(0, -10), tint, 12, 50.0)
	return true


func describe(level: int) -> String:
	var parts: Array[String] = []
	var b := _bonuses_for(level)
	for k in b:
		parts.append("%s %s" % [StatTypes.label(k), StatTypes.format_value(k, b[k], true)])
	var text := "%s на %d сек." % [", ".join(parts), roundi(duration + duration_per_level * (level - 1))]
	if heal_percent > 0.0:
		text += ", лечит %d%%" % roundi(heal_percent * 100)
	return text
