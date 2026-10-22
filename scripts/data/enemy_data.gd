class_name EnemyData
extends Resource
## A monster type. One generic enemy scene reads all of this.

enum Behavior { WALKER, FLYER, RANGED }

@export var id: StringName
@export var display_name: String = ""
@export var texture: Texture2D
## Animated sheet (idle, walk/fly, windup, attack, hurt, death) + its layout.
## If empty, the static `texture` is used.
@export var sheet: Texture2D
@export var sheet_layout: SpriteSheetLayout
@export var behavior: Behavior = Behavior.WALKER
@export var collision_size: Vector2 = Vector2(12, 12)
@export var max_hp: int = 20
@export var damage: int = 5
@export var armor: int = 0
@export var speed: float = 40.0
@export var chase_speed: float = 70.0
@export var aggro_range: float = 120.0
@export var attack_range: float = 16.0
@export var attack_cooldown: float = 1.0
## WALKER: hops while chasing (slimes).
@export var jumps: bool = false
## RANGED: projectile texture and speed.
@export var projectile_texture: Texture2D
@export var projectile_speed: float = 140.0
@export var xp_reward: int = 10
@export var loot_table: LootTable
@export_range(0.0, 1.0) var loot_chance: float = 0.35
## Gold dropped on death (scaled by floor).
@export var gold_min: int = 1
@export var gold_max: int = 4
## First floor where it may spawn, and spawn weight.
@export var min_floor: int = 1
@export var spawn_weight: float = 1.0
## Biome ids where it appears (empty = everywhere).
@export var biomes: Array[StringName] = []
@export var tint: Color = Color.WHITE
## Russian gender of the name (m/f/n) for elite prefixes.
@export var gender: String = "m"

@export_group("Special abilities")
## Flies through walls (ghosts): no world collision, no line-of-sight checks.
@export var phases_through_walls: bool = false
## Waits on the ceiling and drops on the hero passing below (spiders).
@export var ceiling_ambush: bool = false
## Melee hits damage everything in this radius (golem slam). 0 = normal hit.
@export var aoe_radius: float = 0.0
## Summoners: raise these instead of shooting every other attack.
@export var summon: EnemyData
@export var max_summons: int = 3
@export_group("Statuses and elements")
## Resistances by stat key: {"res_fire": 0.5, "res_poison": 1.0}.
@export var resistances: Dictionary = {}
## Statuses that never apply (e.g. golems are immune to poison).
@export var status_immunities: Array[StringName] = []
## Applied to the hero when this monster hits (melee or projectile).
@export var on_hit_effects: Array[HitEffect] = []
@export_group("Sounds (ids from AssetPaths.SFX)")
@export var sound_hurt: StringName = &"enemy_hurt"
@export var sound_death: StringName = &"enemy_death"
@export var sound_attack: StringName = &""
