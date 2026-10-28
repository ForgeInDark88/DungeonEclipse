class_name BossAttack
extends Resource
## One telegraphed boss attack. The boss shows a warning (red marker / glow)
## for `windup` seconds, then acts.

## ILLUSIONS: the boss vanishes and reappears among `count` copies of itself
## (`summon`, usually a no_rewards fake) around the hero; copies fade after
## `lifetime` seconds.
## Signature moves (one per boss, see Boss._start_attack):
##   RAISE_DEAD  - bone spikes burst at the heroes' feet, skeletons (`summon`) rise there;
##   FIRE_WALL   - a wall of fire sweeps the arena floor (`count` 2 = from both sides);
##   MIRROR_SWAP - the boss and its target swap places, then a fan of bolts;
##   QUAKE       - stalactites (`projectile_texture`) fall on marked spots and on the heroes;
##   TOLL        - `count` ground waves roll out both ways: jump over or be stunned;
##   ASH_SWEEP   - a blade sweep `radius` wide that leaves smouldering ash (`lifetime` s);
##   DARKNESS    - the light dies for `lifetime` s, the boss fires fans out of the dark.
enum Kind { CHARGE, JUMP_SLAM, PROJECTILE_FAN, SUMMON, TELEPORT, FIRE_RAIN, ILLUSIONS, SPIKES, BEAM,
	RAISE_DEAD, FIRE_WALL, MIRROR_SWAP, QUAKE, TOLL, ASH_SWEEP, DARKNESS }

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
## ILLUSIONS: seconds before the copies fade.
@export var lifetime: float = 10.0
## Applied to the hero on hit.
@export var hit_effects: Array[HitEffect] = []
