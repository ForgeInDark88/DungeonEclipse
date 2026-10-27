class_name DifficultyData
extends Resource
## Difficulty of a run, chosen when creating the hero.
## «normal»). Add a .tres to data/difficulties/.
## `effects` are run multipliers added to GameState.run_effect() (same keys as
## RunPactData.effects): enemy_hp, enemy_damage (monsters, elites and bosses),
## xp, gold (rewards for kills).

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
## Position in the selection row.
@export var order: int = 0
@export var color: Color = Color.WHITE
@export var effects: Dictionary = {}
## Multiplier of the chance that a monster is an elite.
@export var elite_chance_mult: float = 1.0
## Multiplier of the damage dealt by traps.
@export var trap_damage_mult: float = 1.0
## Multiplier of the Sanctum shards earned at the end of the run.
@export var shard_mult: float = 1.0
## Share of the floor's monsters that must die before the exit unseals.
@export_range(0.0, 1.0) var seal_share: float = 0.6
