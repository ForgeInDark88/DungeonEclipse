class_name WeaponItemData
extends EquipmentItemData
## A weapon: it is drawn in the hero's hand and defines how the hero attacks
## (damage, speed, reach, pattern, damage type, projectile, on-hit effects).

enum WeaponType { SWORD, AXE, SPEAR, DAGGER, BOW, STAFF, MACE }
## ARC = swing in front, THRUST = narrow long poke, SHOOT = projectile,
## THROW = thrown projectile that falls with gravity.
enum Pattern { ARC, THRUST, SHOOT, THROW }
enum DamageType { PHYSICAL, FIRE, ICE, POISON, MAGIC }

const WEAPON_TYPE_NAMES := ["Меч", "Топор", "Копьё", "Кинжал", "Лук", "Посох", "Булава"]
const DAMAGE_TYPE_NAMES := ["Физический", "Огонь", "Лёд", "Яд", "Магия"]
const DAMAGE_TYPE_COLORS := [Color(0.95, 0.95, 1.0), Color(1.0, 0.5, 0.15), Color(0.5, 0.8, 1.0), Color(0.45, 0.9, 0.3), Color(0.8, 0.45, 1.0)]
## Default hero animation per weapon type.
const TYPE_ANIMATIONS := [&"attack_slash", &"attack_heavy", &"attack_thrust", &"attack_quick", &"attack_shoot", &"attack_cast", &"attack_heavy"]
const TYPE_PATTERNS := [Pattern.ARC, Pattern.ARC, Pattern.THRUST, Pattern.THRUST, Pattern.SHOOT, Pattern.SHOOT, Pattern.ARC]

@export var weapon_type: WeaponType = WeaponType.SWORD
## Damage before attribute scaling (see Stats.damage()).
@export var base_damage: float = 6.0
## Attacks per second.
@export var attack_speed: float = 2.0
## Hit distance in pixels (melee) or projectile range factor.
@export var reach: float = 24.0
@export var knockback: float = 120.0
@export var attack_pattern: Pattern = Pattern.ARC
@export var two_handed: bool = false
@export var damage_type: DamageType = DamageType.PHYSICAL
## Hero animation; empty = default for the weapon type.
@export var attack_animation: StringName = &""
@export_group("Projectile")
@export var projectile_texture: Texture2D
@export var projectile_speed: float = 260.0
@export var projectile_pierce: int = 0
@export var projectile_blast_radius: float = 0.0
@export_group("On hit")
## Status / life steal effects applied to each target hit.
@export var on_hit_effects: Array[HitEffect] = []
@export_group("Look")
## Sprite in the hand (empty = icon). Drawn pointing at `held_angle`
## (degrees, -45 = up-right like item icons) with the grip at `grip_pixel`.
@export var held_texture: Texture2D
@export var held_angle: float = -45.0
@export var grip_pixel: Vector2 = Vector2(3, 12)
## Russian grammatical gender of the name for affix prefixes: m, f, n.
@export var gender: String = "m"


func _init() -> void:
	super()
	slot_type = &"weapon"
	has_durability = true
	max_durability = 150


func subtitle() -> String:
	var t: String = WEAPON_TYPE_NAMES[weapon_type]
	return t + (" (двуручное)" if two_handed else "")


func animation() -> StringName:
	return attack_animation if attack_animation != &"" else TYPE_ANIMATIONS[weapon_type]


func cooldown() -> float:
	return 1.0 / maxf(0.1, attack_speed)


## Weapon damage after breakage (broken weapons hit for half).
func effective_damage() -> float:
	return base_damage * (0.5 if is_broken() else 1.0)


func damage_color() -> Color:
	return DAMAGE_TYPE_COLORS[damage_type]


func is_ranged() -> bool:
	return attack_pattern == Pattern.SHOOT or attack_pattern == Pattern.THROW
