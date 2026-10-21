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
## First floor where it may spawn, and spawn weight.
@export var min_floor: int = 1
@export var spawn_weight: float = 1.0
## Biome ids where it appears (empty = everywhere).
@export var biomes: Array[StringName] = []
@export var tint: Color = Color.WHITE
@export_group("Sounds (ids from AssetPaths.SFX)")
@export var sound_hurt: StringName = &"enemy_hurt"
@export var sound_death: StringName = &"enemy_death"
@export var sound_attack: StringName = &""
