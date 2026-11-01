class_name LocationDefinition
extends Resource
## How a kind of map node becomes a location (data/locations/<id>.tres, the
## id is the node type): a surface on top, entrances down, a dungeon of a few
## floors below, the guardian's arena at the bottom of boss nodes. Add a
## file to give a node type layers; a type without one keeps the old single
## room (road events) or the camp screen.

## Node type (ExpeditionMap.TYPES key) this definition is for.
@export var id: StringName
## Shown on the map tooltip ("Лес и пещеры", "Логово стража"...).
@export var display_name: String = ""
## The open surface on top (false: the dungeon starts right at the map).
@export var has_surface: bool = true
## Dungeon floors under the surface (rolled from the location seed).
@export var floors_min: int = 2
@export var floors_max: int = 3
## Side entrances on the surface besides the main one.
@export var side_entrances_min: int = 1
@export var side_entrances_max: int = 2
## The last floor is the guardian's arena (boss / lair nodes): the way back
## to the map opens only after the guardian falls.
@export var boss_arena: bool = false
## The last floor of a dungeon without a guardian holds a reward room.
@export var reward_room: bool = true
## 1..5 skulls on the map tooltip.
@export_range(1, 5) var danger: int = 2
## What the map tooltip promises (shown as is, translated).
@export var rewards_hint: String = ""
@export_group("Respawn on the surface")
## Ordinary surface monsters come back this many seconds after they fell...
@export var respawn_time: float = 90.0
## ...but never closer than this to a hero (px).
@export var respawn_min_distance: float = 360.0
## At most this many returns per spot (0: never).
@export var respawn_max: int = 2
## Elites, guardians and dungeon monsters never come back (the dungeon is
## cleared for good while the location lasts).
@export var respawn_in_dungeon: bool = false
