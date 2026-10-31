class_name BuildingData
extends Resource
## A building of the town on its fixed foundation (TownBuilder places it at
## `slot`). Level 0 is ruins / an empty lot; 1..max_level are built and
## upgraded (Buildings.can_build / build). Add a .tres to data/buildings/
## (with a free slot) to add a building.

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var order: int = 0
## Cell x of the foundation's centre on the street.
@export var slot: int = 0
## Cells the foundation takes (ruins and the build area).
@export var width: int = 5
## Level the town starts with (the shop and the Sanctum stand from day one).
@export var start_level: int = 0
@export var max_level: int = 3
## Cost of each level, 1..max_level: {"gold": 60, "wood": 4, "stone": 2}.
@export var costs: Array[Dictionary] = []
## Who must live in town before level 1 can be built (&"" = nobody).
@export var requires_resident: StringName
## Region guardian beaten before level `boss_level` (&"" = none).
@export var requires_boss: StringName
## Level that needs `requires_boss` (0 = the last level).
@export var boss_level: int = 0
## From this level on a blueprint of the building is needed (0 = never).
@export var blueprint_level: int = 0
## What each level gives (shown in the building book), 1..max_level.
@export var level_texts: Array[String] = []
## What the building does when used: shop, smith, temple, tavern, alchemist,
## library, sanctum, warehouse, scout, quests, hall.
@export var action: StringName
## The built look; upgrades add banners, lights and smoke on top.
@export var texture: Texture2D
## Chimney spot on the texture (smoke from level 3), (0, 0) = none.
@export var chimney: Vector2 = Vector2.ZERO
## Prosperity per level.
@export var prosperity: int = 3
