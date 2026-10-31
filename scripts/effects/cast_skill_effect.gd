class_name CastSkillEffect
extends ItemEffect
## A scroll that casts a skill effect (fireball, frost nova...) once, at the
## given level, without mana.

@export var skill_effect: SkillEffect
@export var level: int = 2


func apply(user: Node) -> bool:
	return skill_effect != null and skill_effect.execute(user, level)


func describe() -> String:
	return tr("Заклинание: ") + (skill_effect.describe(level) if skill_effect else "")
