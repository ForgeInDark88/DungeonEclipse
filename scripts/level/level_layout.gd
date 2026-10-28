class_name LevelLayout
extends RefCounted
## Result of LevelGenerator: a tile grid plus spawn points. Pure data.

enum Tile { EMPTY, BEDROCK, BRICK, PLATFORM, LADDER, LADDER_TOP }

var width: int
var height: int
var tiles := PackedByteArray()
var start_cell := Vector2i.ZERO
var exit_cell := Vector2i.ZERO
## Array of {cell: Vector2i, tier: int} (0 wood, 1 iron, 2 gold/locked)
var chests: Array[Dictionary] = []
var enemy_cells: Array[Vector2i] = []
## Special rooms: Array of {"type": StringName, "cell": Vector2i} (merchant, events...).
var specials: Array[Dictionary] = []
## Boss arena floors: one big room, the boss spawns at boss_cell and the exit
## door appears only after the boss is defeated.
## Where the floor's note lies (Vector2i(-1, -1) = none).
var lore_cell := Vector2i(-1, -1)
var is_arena := false
## Boss arenas: lasting hazards {"style": BossHazard.Style, "x0", "x1" (cells),
## "row" (the cell row they lie on), "h" (px), "damage" (true/false)}.
var arena_hazards: Array[Dictionary] = []
var boss_cell := Vector2i.ZERO
## The town before the dungeon (TownBuilder): no back wall, props instead of rooms.
var is_town := false
## Cracked walls into secret rooms: Array of Array[Vector2i] (one wall each).
## A melee hit on any cell of a wall breaks the whole passage.
var secret_walls: Array = []
## Array of {"tex": String, "cell": Vector2i, "z": int, "lamp": bool}.
var town_props: Array[Dictionary] = []


func _init(w: int, h: int, fill: int = Tile.BRICK) -> void:
	width = w
	height = h
	tiles.resize(w * h)
	tiles.fill(fill)


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


func get_tile(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return Tile.BEDROCK
	return tiles[y * width + x]


func set_tile(x: int, y: int, t: int) -> void:
	if in_bounds(x, y):
		tiles[y * width + x] = t


static func is_solid(t: int) -> bool:
	return t == Tile.BEDROCK or t == Tile.BRICK


## Something you can stand on.
static func is_ground(t: int) -> bool:
	return is_solid(t) or t == Tile.PLATFORM or t == Tile.LADDER_TOP


static func is_ladder(t: int) -> bool:
	return t == Tile.LADDER or t == Tile.LADDER_TOP
