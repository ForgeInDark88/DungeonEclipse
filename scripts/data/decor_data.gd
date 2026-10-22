class_name DecorData
extends Resource
## Decoration placed in the level (bones, cobwebs, crystals, statues...).
## Pure visuals: no collision.

## WALL: hangs on the back wall at eye level (shelves, frescoes, masks...).
## Textures wider than a cell (32 px) stand on / need two cells.
enum Placement { FLOOR, CEILING, WALL }

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
