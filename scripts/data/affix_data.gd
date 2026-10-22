class_name AffixData
extends Resource
## Random weapon modifier («Острый», «… пламени»). Rolled by ItemFactory when
## a rare or epic weapon drops; its values are baked into that weapon copy.
## Add a .tres to data/affixes/ to get a new affix.

@export var id: StringName
## Prefix by gender {"m": "Острый", "f": "Острая", "n": "Острое"}.
## Empty = this affix is a suffix.
@export var prefix_forms: Dictionary = {}
## Suffix after the name, e.g. "пламени".
@export var suffix: String = ""
## Short line for the tooltip.
@export var description: String = ""
@export var min_rarity: ItemData.Rarity = ItemData.Rarity.RARE
@export var weight: float = 1.0
## Weapon types it can appear on (empty = all).
@export var allowed_types: Array[int] = []

@export_group("Effects")
@export var stat_bonuses: Dictionary = {}
## Relative changes, e.g. 0.2 = +20%.
@export var damage_mult: float = 0.0
@export var speed_mult: float = 0.0
@export var reach_add: float = 0.0
@export var knockback_add: float = 0.0
## -1 = keep the weapon's damage type.
@export var damage_type: int = -1
@export var hit_effects: Array[HitEffect] = []


func is_prefix() -> bool:
	return not prefix_forms.is_empty()


func fits(weapon: WeaponItemData) -> bool:
	return weapon.rarity >= min_rarity and (allowed_types.is_empty() or int(weapon.weapon_type) in allowed_types)


## Applies the affix to a weapon copy (values stay with that copy).
func apply_to(w: WeaponItemData) -> void:
	w.base_damage = snappedf(w.base_damage * (1.0 + damage_mult), 0.1)
	w.attack_speed = snappedf(w.attack_speed * (1.0 + speed_mult), 0.01)
	w.reach += reach_add
	w.knockback += knockback_add
	if damage_type >= 0:
		w.damage_type = damage_type
	var bonuses := w.stat_bonuses.duplicate()
	for k in stat_bonuses:
		bonuses[k] = float(bonuses.get(k, 0.0)) + float(stat_bonuses[k])
	w.stat_bonuses = bonuses
	var effects: Array[HitEffect] = w.on_hit_effects.duplicate()
	effects.append_array(hit_effects)
	w.on_hit_effects = effects
