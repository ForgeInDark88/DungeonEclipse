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
	["quest_board", 62, -1, false],
	["house_b", 63, -2, false], ["smithy", 71, -2, false], ["crates", 76, -1, false], ["lamppost", 79, -1, true],
	["barracks", 85, -2, false], ["fence", 92, -1, false], ["fence", 94, -1, false], ["signpost", 96, -1, false],
	["tree", 99, -1, false], ["dungeon_gate", 105, -2, false], ["lamppost", 7, -1, true],
]


## The town of the expedition loop: buildings on their foundations
## (data/buildings, each at its `slot`), houses that fill up as people move
## in, lamps that multiply with prosperity, the people in the street, the
## expedition gate at the far end.
const HUB_WIDTH := 142
const HUB_GATE := 136
const HOUSES := [16, 28, 40, 53, 73, 85, 97, 108, 119]
const HOUSE_TEX := ["house_a", "house_b", "house_c"]
const LAMPS := [6, 26, 44, 60, 76, 95, 110, 128]
const TREES := [4, 37, 63, 87, 121]
## Where people without a building of their own stand.
const SQUARE := 62


static func build_hub(town: TownState) -> LevelLayout:
	var l := LevelLayout.new(HUB_WIDTH, HEIGHT, LevelLayout.Tile.EMPTY)
	l.is_town = true
	for y in range(GROUND, HEIGHT):
		for x in HUB_WIDTH:
			l.set_tile(x, y, LevelLayout.Tile.BEDROCK if y == HEIGHT - 1 else LevelLayout.Tile.BRICK)
	for y in HEIGHT:
		for x in [0, 1, HUB_WIDTH - 2, HUB_WIDTH - 1]:
			l.set_tile(x, y, LevelLayout.Tile.BEDROCK)
	l.start_cell = Vector2i(HUB_GATE - 6, GROUND - 1)  # home through the gate
	l.exit_cell = Vector2i(HUB_GATE, GROUND - 1)
	var row := GROUND - 1
	for x in TREES:
		l.town_props.append({"tex": "tree", "cell": Vector2i(x, row), "z": -3, "lamp": false})
	var p := town.prosperity if town else 0
	var lamps := mini(LAMPS.size(), 3 + p / 5)
	for i in lamps:
		l.town_props.append({"tex": "lamppost", "cell": Vector2i(LAMPS[i], row), "z": -1, "lamp": true})
	l.town_props.append({"tex": "well", "cell": Vector2i(SQUARE, row), "z": -2, "lamp": false})
	l.town_props.append({"tex": "dungeon_gate", "cell": Vector2i(HUB_GATE, row), "z": -2, "lamp": false})
	l.town_props.append({"tex": "signpost", "cell": Vector2i(HUB_GATE - 4, row), "z": -1, "lamp": false})
	# A house for every person who lives here (the rest are empty lots).
	var people := town.residents.size() if town else 0
	for i in HOUSES.size():
		if i < people:
			l.town_props.append({"tex": HOUSE_TEX[i % HOUSE_TEX.size()], "cell": Vector2i(HOUSES[i], row), "z": -2, "lamp": false})
		else:
			l.town_props.append({"tex": "fence", "cell": Vector2i(HOUSES[i], row), "z": -1, "lamp": false})
	for b in ItemDatabase.buildings:
		l.town_buildings.append({"id": b.id, "cell": Vector2i(b.slot, row)})
	# The people: at the door of their building once it stands, else on the square.
	var k := 0
	if town:
		for id in town.residents:
			var n: NpcData = ItemDatabase.npcs.get(id)
			if n == null:
				continue
			var b := ItemDatabase.building(n.home)
			var x := SQUARE - 4 + (k % 3) * 4
			if b and town.building_level(b.id) > 0:
				x = b.slot + b.width / 2 + 1
			else:
				k += 1
			l.town_people.append({"id": id, "cell": Vector2i(x, row)})
	# The old townsfolk of the hub: the merchant at the shop, the guild's
	# board, the chronicler (in the library once it stands), the dummy.
	l.specials.append({"type": &"merchant", "cell": Vector2i(_slot(&"shop") + 2, row)})
	l.specials.append({"type": &"quest", "cell": Vector2i(_slot(&"quests") + 2, row)})
	var lib := ItemDatabase.building(&"library")
	var chron_x := (_slot(&"library") - 3) if lib and town and town.building_level(&"library") > 0 else SQUARE + 4
	l.specials.append({"type": &"chronicler", "cell": Vector2i(chron_x, row)})
	if town and town.building_level(&"smithy") > 0:
		l.specials.append({"type": &"smith", "cell": Vector2i(_slot(&"smithy") - 3, row)})
	l.specials.append({"type": &"dummy", "cell": Vector2i(HUB_GATE - 9, row)})
	return l


static func _slot(id: StringName) -> int:
	var b := ItemDatabase.building(id)
	return b.slot if b else SQUARE


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
	l.specials.append({"type": &"quest", "cell": Vector2i(61, GROUND - 1)})
	l.specials.append({"type": &"smith", "cell": Vector2i(73, GROUND - 1)})
	l.specials.append({"type": &"dummy", "cell": Vector2i(90, GROUND - 1)})
	l.specials.append({"type": &"chronicler", "cell": Vector2i(14, GROUND - 1)})
	return l
