class_name SkillData
extends Resource
## A class skill. Behaviour is in `effect` (a SkillEffect resource).
## Active skills go to the HUD and are cast; passive ones (effect = PassiveSkill)
## work all the time. Skill tree: `required_level`, `requires`, `tree_row`.
## Skills with required_level <= 1 and no `requires` are known from the start.

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D
@export var mana_cost: int = 10
@export var cooldown: float = 3.0
@export_range(1, 5) var max_level: int = 4
@export var effect: SkillEffect
## Hero animation played when cast ("" = none, e.g. dashes use the dash pose).
@export var cast_animation: StringName = &"attack_cast"
@export_group("Skill tree")
## Hero level needed to learn the skill (1 skill point).
@export var required_level: int = 1
## Skills that must be learned first.
@export var requires: Array[SkillData] = []
## Tier in the tree (0 = top). Columns are laid out automatically in the order
## of ClassData.skills, so one skill can be shared by several classes.
@export var tree_row: int = 0
@export_group("Weapon synergy")
## WeaponItemData.WeaponType values that empower the skill.
@export var synergy_weapons: Array[int] = []
## Extra power with a matching weapon: damage, buff size and passive bonuses ×(1 + this).
@export var synergy_power: float = 0.3


func is_passive() -> bool:
	return effect is PassiveSkill


func is_starting() -> bool:
	return required_level <= 1 and requires.is_empty()


func has_synergy(w: WeaponItemData) -> bool:
	return w != null and int(w.weapon_type) in synergy_weapons


## Power multiplier of the skill with weapon `w`.
func power_with(w: WeaponItemData) -> float:
	return 1.0 + synergy_power if has_synergy(w) else 1.0


func synergy_text() -> String:
	if synergy_weapons.is_empty():
		return ""
	var names: Array[String] = []
	for t in synergy_weapons:
		names.append(String(WeaponItemData.WEAPON_TYPE_NAMES[t]).to_lower())
	return "Синергия (%s): +%d%% силы" % [", ".join(names), roundi(synergy_power * 100.0)]
