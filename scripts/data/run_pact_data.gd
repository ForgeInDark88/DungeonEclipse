class_name RunPactData
extends Resource
## A blessing or a curse of the altar of fate, active until the end of the run
## (not a talent: lost on death). Add a .tres to data/pacts/.
## `stats` are flat hero bonuses (StatTypes keys, negative = penalty);
## `effects` are run multipliers read through GameState.run_effect():
##   enemy_hp, enemy_damage — ordinary monsters and elites (+0.2 = +20%),
##   xp, gold — rewards for kills.

enum Kind { BLESSING, CURSE }

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var kind: Kind = Kind.BLESSING
@export var stats: Dictionary = {}
@export var effects: Dictionary = {}
@export var weight: float = 1.0
@export var min_floor: int = 1


func is_curse() -> bool:
	return kind == Kind.CURSE
