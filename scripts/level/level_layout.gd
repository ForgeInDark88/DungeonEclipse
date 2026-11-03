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
## A road event's room (LevelGenerator.generate_event_room): the scenery of
## the event in the middle, the way in on the left, the exit on the right.
var is_event_room := false
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
## Town of the expedition loop: building foundations {"id", "cell"} and the
## residents standing in the street {"id", "cell"} (TownBuilder.build_hub).
var town_buildings: Array[Dictionary] = []
var town_people: Array[Dictionary] = []
## The open surface of a location (SurfaceGenerator): sky instead of the
## back wall, no exit seal.
var is_surface := false
## A camp of the road (CampBuilder): safe ground, the camp's spots.
var is_camp := false
var camp_kind: StringName = &"forest"
## Portal id -> cell of the portals between the layers of a location
## (LocationInstance portals; LocationBuilder fills them).
var portal_cells: Dictionary = {}
## Portal id -> look of a way down from the surface (cave, well, crypt...).
var portal_kinds: Dictionary = {}
## Surface (SurfaceGenerator): props {"tex": name in assets/sprites/surface,
## "cell", "z"}, ponds and ravines (Rect2i cells), points of interest
## {"type", "cell", "rect"}.
var surface_props: Array[Dictionary] = []
var water: Array[Rect2i] = []
var ravines: Array[Rect2i] = []
var pois: Array[Dictionary] = []
## Surface: things to gather {"kind": ResourceNode kind, "cell"}, barrels
## and crates {"look", "cell"}.
var resources: Array[Dictionary] = []
var breakables: Array[Dictionary] = []
## A location of several layers stacked into one level (LocationBuilder):
## [{layer: int, rect: Rect2i (cells), origin: Vector2i, layout: LevelLayout,
##   depth: int, biome: BiomeData, kind: LocationInstance.Kind}]. Empty for
## an ordinary level.
var bands: Array = []


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
