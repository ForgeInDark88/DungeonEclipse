class_name SkillEffect
extends Resource
## Base class for skill behaviour. `caster` is the Player, `level` is the
## skill level (1..max_level). Return true if the skill fired (mana and
## cooldown are spent only then).


func execute(_caster: Node, _level: int) -> bool:
	return false


## Tooltip line for the given level.
func describe(_level: int) -> String:
	return ""
