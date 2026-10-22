class_name BossAttack
extends Resource
## One telegraphed boss attack. The boss shows a warning (red marker / glow)
## for `windup` seconds, then acts.

enum Kind { CHARGE, JUMP_SLAM, PROJECTILE_FAN, SUMMON, TELEPORT, FIRE_RAIN }

@export var kind: Kind = Kind.CHARGE
@export var windup: float = 0.8
## Multiplier of the boss damage.
@export var damage_mult: float = 1.0
## Projectiles / summons / fire drops.
@export var count: int = 5
@export var spread_degrees: float = 50.0
@export var projectile_texture: Texture2D
@export var projectile_speed: float = 160.0
## WeaponItemData.DamageType of projectiles / shockwaves.
@export var damage_type: int = 0
## Shockwave / fire drop radius.
@export var radius: float = 40.0
## CHARGE speed in px/s.
@export var speed: float = 260.0
@export var summon: EnemyData
@export var max_summons: int = 4
## Applied to the hero on hit.
@export var hit_effects: Array[HitEffect] = []
