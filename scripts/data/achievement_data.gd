class_name AchievementData
extends Resource
## An achievement: unlocked when a Codex counter reaches `target`.
## Counters (Codex.COUNTERS): kills, elites, bosses, floor, chests, epic_items,
## gold, traps, events, purchases, deaths, bestiary, items_known, runs.
## Drop a .tres into data/achievements to add one.

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D
@export var order: int = 0
@export var counter: StringName = &"kills"
@export var target: int = 1
## Eclipse shards paid into the Sanctum when unlocked.
@export var reward_shards: int = 1
## Hidden achievements show "???" until unlocked.
@export var hidden: bool = false
