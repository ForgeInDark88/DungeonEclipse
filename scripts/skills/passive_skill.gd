class_name PassiveSkill
extends SkillEffect
## Always-on skill: stat bonuses (Stats modifier "passives") and an optional
## effect on the hero's weapon hits. Not placed in the HUD, never cast.

@export var bonuses: Dictionary = {}
@export var bonuses_per_level: Dictionary = {}
## Applied on weapon hits with `hit_chance` (+ per level).
@export var hit_effect: HitEffect
@export_range(0.0, 1.0) var hit_chance: float = 0.1
@export var hit_chance_per_level: float = 0.05


func execute(_caster: Node, _level: int) -> bool:
	return false


func bonuses_for(level: int, power := 1.0) -> Dictionary:
	var result := {}
	if level <= 0:
		return result
	for k in bonuses:
		result[k] = (float(bonuses[k]) + float(bonuses_per_level.get(k, 0)) * (level - 1)) * power
	for k in bonuses_per_level:
		if not result.has(k):
			result[k] = float(bonuses_per_level[k]) * level * power
	return result


func chance_for(level: int, power := 1.0) -> float:
	return clampf((hit_chance + hit_chance_per_level * (level - 1)) * power, 0.0, 1.0)


func describe(level: int) -> String:
	var parts: Array[String] = []
	var b := bonuses_for(maxi(level, 1))
	for k in b:
		parts.append("%s %s" % [StatTypes.label(k), StatTypes.format_value(k, b[k], true)])
	if hit_effect:
		parts.append(tr("при ударе %d%%: %s") % [roundi(chance_for(maxi(level, 1)) * 100.0), hit_effect.describe()])
	return tr("Пассивно: ") + ", ".join(parts)
