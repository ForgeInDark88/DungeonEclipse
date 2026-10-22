class_name DecorData
extends Resource
## Decoration placed in the level (bones, cobwebs, crystals, statues...).
## Pure visuals: no collision.

enum Placement { FLOOR, CEILING }

@export var texture: Texture2D
@export var placement: Placement = Placement.FLOOR
@export var weight: float = 1.0
## Optional glow (alpha 0 = no light).
@export var light_color: Color = Color(0, 0, 0, 0)
@export var light_scale: float = 0.3
## Not darkened by the dungeon (glowing things).
@export var unshaded: bool = false
## Gentle swinging (vines, chains, cobwebs).
@export var sway: bool = false
