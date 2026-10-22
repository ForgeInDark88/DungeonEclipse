class_name TrapData
extends Resource
## A trap type. The behaviour comes from `kind` (code in scripts/traps/trap.gd);
## everything else is data, so variants (poison spikes, fire arrows...) are
## just new .tres files in data/traps/.

enum Kind { SPIKES, FALLING_ROCK, ARROW_WALL, ACID_POOL, PRESSURE_PLATE }

@export var id: StringName
@export var display_name: String = ""
@export var kind: Kind = Kind.SPIKES
@export var damage: int = 10
## +X damage fraction per floor below the first (0.2 = +20% per floor).
@export var damage_per_floor: float = 0.2
## WeaponItemData.DamageType of the hit.
@export var damage_type: int = 0
## Statuses etc. applied on hit (StatusHitEffect...).
@export var hit_effects: Array[HitEffect] = []
## Seconds between activations (spikes cycle, arrow interval, rock respawn).
@export var cooldown: float = 2.0
## Detection distance in pixels (rocks, arrow walls).
@export var trigger_range: float = 64.0
@export var projectile_texture: Texture2D
@export var projectile_speed: float = 220.0
@export_range(0.0, 1.0) var disarm_difficulty: float = 0.4
@export var can_disarm: bool = true
@export var xp_for_disarm: int = 6

@export_group("Look")
@export var sheet: Texture2D
@export var sheet_layout: SpriteSheetLayout
@export var texture: Texture2D
@export var tint: Color = Color.WHITE

@export_group("Spawning")
@export var min_floor: int = 1
@export var weight: float = 1.0
## Biome ids (empty = everywhere).
@export var biomes: Array[StringName] = []


func damage_for_floor(floor_number: int) -> int:
	return roundi(damage * (1.0 + damage_per_floor * maxi(0, floor_number - 1)))
