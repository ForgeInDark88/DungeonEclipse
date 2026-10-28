class_name BossData
extends EnemyData
## A boss: an enemy with phases of telegraphed attacks. Arenas appear every
## GameState.BOSS_EVERY floors; bosses from data/bosses/ take turns by `order`.

@export var title: String = ""
@export var order: int = 0
## The Eclipse itself: not in the rotation, waits on ItemDatabase.final_floor()
## after all the guardians; its death is the end of the run (victory screen).
@export var final: bool = false
@export var phases: Array[BossPhase] = []
@export var music: StringName = &"boss"
## Contact damage multiplier while touching the hero.
@export var contact_damage_mult: float = 0.5
## Reward: item ids dropped on death (besides the epic chest).
@export var reward_items: Array[StringName] = [&"guardian_seal"]
## Own light so the boss reads well in any biome (alpha 0 = none).
@export var glow_color: Color = Color(1.0, 0.8, 0.6, 1.0)
@export var glow_scale: float = 1.0
## Presentation: said when the heroes first come close (the intro card) and
## when the boss falls (the last words).
@export var intro_line: String = ""
@export var defeat_line: String = ""
## The arena built for this boss (LevelGenerator.generate_arena):
## ossuary, pyre, mirrors, crystal, flooded, ashen, eclipse; "" = plain hall.
@export var arena_style: StringName = &""
## The biome the arena is dressed in (tiles, light, music between fights).
@export var arena_biome: StringName = &""
