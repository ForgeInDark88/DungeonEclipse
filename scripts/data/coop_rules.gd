class_name CoopRules
extends Resource
## How the party changes the dungeon (data/coop/rules.tres). Every extra
## player (2–4) adds these shares.

## Health and damage of ordinary monsters and elites.
@export var hp_per_extra: float = 0.8
@export var damage_per_extra: float = 0.5
## Guardians (bosses) get this much health per extra player on top.
@export var boss_hp_per_extra: float = 0.4
## More monsters in a location.
@export var monsters_per_extra: float = 0.25
## Clear rewards for the town (resources) per extra player.
@export var reward_per_extra: float = 0.3
## Friendly fire of bombs when the world allows it (share of the damage).
@export var friendly_bomb_mult: float = 0.5
