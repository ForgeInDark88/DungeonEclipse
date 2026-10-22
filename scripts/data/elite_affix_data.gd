class_name EliteAffixData
extends Resource
## Elite monster modifier («Быстрый», «Огненный», «Регенерирующий»...).
## Elites appear more often on deeper floors (see DungeonLevel); add a .tres
## to data/elites/ for a new kind.

@export var id: StringName
## Prefix by gender {"m": "Быстрый", "f": "Быстрая", "n": "Быстрое"}.
@export var prefix_forms: Dictionary = {}
@export var hp_mult: float = 1.5
@export var damage_mult: float = 1.2
@export var speed_mult: float = 1.0
@export var attack_cooldown_mult: float = 1.0
@export var armor_add: int = 0
@export var resistances: Dictionary = {}
@export var immunities: Array[StringName] = []
## Applied to the hero on hit (fiery → burn).
@export var hit_effects: Array[HitEffect] = []
## Permanent status on spawn (regenerating → regen with this power).
@export var spawn_status: StringName = &""
@export var spawn_status_power: float = 0.0
## Heals this share of damage dealt to the hero.
@export var life_steal: float = 0.0
@export var tint: Color = Color(1.0, 0.85, 0.4)
@export var xp_mult: float = 2.5
@export var gold_mult: float = 3.0
## Eclipse shards dropped on death (Sanctum currency, MetaProgress.SHARD_ITEM).
@export var shard_drop: int = 1
@export var weight: float = 1.0
@export var min_floor: int = 1


func prefix(gender: String) -> String:
	return prefix_forms.get(gender, prefix_forms.get("m", ""))
