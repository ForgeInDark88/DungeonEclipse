class_name TownBuilder
extends RefCounted
## The town before the dungeon (floor 0): a street on solid ground between
## the city walls, buildings and props along it, the merchant at the shop,
## the blacksmith at the smithy and the dungeon gate at the far end.
## Pure data like LevelGenerator: DungeonLevel spawns everything.

const WIDTH := 112
const HEIGHT := 24
## Row of the street surface (first solid row).
const GROUND := 19

## Props along the street: [texture name in AssetPaths.TOWN_DIR, cell x, z_index, lamp light].
const PROPS := [
	["chapel", 9, -2, false], ["tree", 15, -1, false], ["house_a", 20, -2, false], ["lamppost", 24, -1, true],
	["shop", 30, -2, false], ["flowers", 35, -1, false], ["bench", 38, -1, false],
	["tavern", 45, -2, false], ["lamppost", 50, -1, true], ["well", 54, -1, false], ["tree", 58, -1, false],
	["house_b", 63, -2, false], ["smithy", 71, -2, false], ["crates", 76, -1, false], ["lamppost", 79, -1, true],
	["house_c", 85, -2, false], ["fence", 90, -1, false], ["fence", 92, -1, false], ["signpost", 96, -1, false],
	["tree", 99, -1, false], ["dungeon_gate", 105, -2, false], ["lamppost", 7, -1, true],
]


static func build() -> LevelLayout:
	var l := LevelLayout.new(WIDTH, HEIGHT, LevelLayout.Tile.EMPTY)
	l.is_town = true
	for y in range(GROUND, HEIGHT):
		for x in WIDTH:
			l.set_tile(x, y, LevelLayout.Tile.BEDROCK if y == HEIGHT - 1 else LevelLayout.Tile.BRICK)
	# city walls at both ends
	for y in HEIGHT:
		for x in [0, 1, WIDTH - 2, WIDTH - 1]:
			l.set_tile(x, y, LevelLayout.Tile.BEDROCK)
	l.start_cell = Vector2i(4, GROUND - 1)
	l.exit_cell = Vector2i(105, GROUND - 1)
	for p in PROPS:
		l.town_props.append({"tex": p[0], "cell": Vector2i(p[1], GROUND - 1), "z": p[2], "lamp": p[3]})
	l.specials.append({"type": &"merchant", "cell": Vector2i(33, GROUND - 1)})
	l.specials.append({"type": &"smith", "cell": Vector2i(73, GROUND - 1)})
	return l
