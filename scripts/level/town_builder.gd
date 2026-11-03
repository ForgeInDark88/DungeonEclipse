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


## The town of the expedition loop (stage 18): a wide town of districts
## (data/districts) left to right — the outskirts with the training ground,
## the temple hill on a terrace, the houses, the market, the craftsmen, the
## square at the expedition gate. Buildings stand on their foundations
## (BuildingData.slot) in their district; a district still closed is fenced
## off by a palisade with scaffolding behind it. Lamps, banners and houses
## multiply as the town grows; the people keep a schedule (TownNpc).
const HUB_WIDTH := 256
const HUB_HEIGHT := 30
## Street surface row of the hub (a terrace district is `raise` rows higher).
const HUB_GROUND := 25
const HUB_GATE := 248
## At most this many townsfolk walk the street at once.
const MAX_PEOPLE := 12
## Banner poles on the square and the market (one per 6 prosperity).
const BANNERS := [210, 233, 130, 160, 178, 245]
const HOUSE_TEX := ["house_a", "house_b", "house_c"]
## The roof cache of the houses' district: a ladder, a ledge, a chest once.
const ROOF_LADDER := 109
const ROOF_LEDGE := Vector2i(109, 116)
const ROOF_ROW := HUB_GROUND - 8
## Where people without a building of their own stand.
const SQUARE := 220


## Street surface row at column x (terraces raise it; stairs at their ends).
static func ground_at(x: int) -> int:
	var d := TownDistricts.of_x(x)
	if d == null or d.raise <= 0:
		return HUB_GROUND
	var into := mini(x - d.x_from, d.x_to - 1 - x)
	return HUB_GROUND - mini(d.raise, into + 1)


static func build_hub(town: TownState) -> LevelLayout:
	var l := LevelLayout.new(HUB_WIDTH, HUB_HEIGHT, LevelLayout.Tile.EMPTY)
	l.is_town = true
	for x in HUB_WIDTH:
		var g := ground_at(x)
		for y in range(g, HUB_HEIGHT):
			l.set_tile(x, y, LevelLayout.Tile.BEDROCK if y == HUB_HEIGHT - 1 else LevelLayout.Tile.BRICK)
	for y in HUB_HEIGHT:
		for x in [0, 1, HUB_WIDTH - 2, HUB_WIDTH - 1]:
			l.set_tile(x, y, LevelLayout.Tile.BEDROCK)
	l.start_cell = Vector2i(HUB_GATE - 6, HUB_GROUND - 1)  # home through the gate
	l.exit_cell = Vector2i(HUB_GATE, HUB_GROUND - 1)
	var p := town.prosperity if town else 0
	var open := {}
	for d in TownDistricts.all():
		open[d.id] = TownDistricts.is_open(d, town)
	# the walls of the town at both ends
	_prop(l, "wall_tower", 5, -3)
	_prop(l, "wall_tower", 251, -3)
	_prop(l, "dungeon_gate", HUB_GATE, -2)
	_prop(l, "signpost", HUB_GATE - 4, -1)
	# districts: their props, their houses, a palisade if closed
	var houses: Array[int] = []
	for d in TownDistricts.all():
		if not open[d.id]:
			_close(l, d, open)
			continue
		for pr in d.props:
			_prop(l, String(pr["tex"]), int(pr["x"]), int(pr["z"]), bool(pr.get("lamp", false)))
		houses.append_array(d.houses)
		# a carriage stop once the town has a coachman (prosperity 6)
		if p >= 6:
			l.specials.append({"type": &"carriage", "cell": _cell(d.x_from + 3 + d.raise), "district": d.id})
	# banners of a growing town
	for i in mini(BANNERS.size(), p / 6):
		var bx: int = BANNERS[i]
		var bd := TownDistricts.of_x(bx)
		if bd and open[bd.id]:
			_prop(l, "banner_pole", bx, -2)
	# a house for every person who lives here (the rest: empty lots)
	var people := town.residents.size() if town else 0
	for i in houses.size():
		if i < people:
			_prop(l, HOUSE_TEX[i % HOUSE_TEX.size()], houses[i], -2)
		else:
			_prop(l, "fence", houses[i], -1)
	for b in ItemDatabase.buildings:
		l.town_buildings.append({"id": b.id, "cell": _cell(b.slot)})
	# the outskirts: the training ground (dummies, a target, the ring)
	if open.get(&"outskirts", false):
		for x in [18, 26, 29]:
			l.specials.append({"type": &"dummy", "cell": _cell(x)})
	else:
		l.specials.append({"type": &"dummy", "cell": _cell(HUB_GATE - 12)})
	# the square: the memorial to the fallen
	l.specials.append({"type": &"memorial", "cell": _cell(223)})
	# the houses' roofs: a ladder up to a ledge with a cache (once per town)
	if open.get(&"residential", false):
		for y in range(ROOF_ROW + 1, HUB_GROUND):
			l.set_tile(ROOF_LADDER, y, LevelLayout.Tile.LADDER)
		l.set_tile(ROOF_LADDER, ROOF_ROW, LevelLayout.Tile.LADDER_TOP)
		for x in range(ROOF_LEDGE.x + 1, ROOF_LEDGE.y + 1):
			l.set_tile(x, ROOF_ROW, LevelLayout.Tile.PLATFORM)
		if not (town and town.flags.get("roof_cache", false)):
			l.specials.append({"type": &"roof_cache", "cell": Vector2i(ROOF_LEDGE.y - 1, ROOF_ROW - 1)})
	# the people: at most MAX_PEOPLE, each with a day of places
	var k := 0
	if town:
		var hi := 0
		for id in town.residents:
			if l.town_people.size() >= MAX_PEOPLE:
				break
			var n: NpcData = ItemDatabase.npcs.get(id)
			if n == null:
				continue
			var b := ItemDatabase.building(n.home)
			var work := SQUARE - 4 + (k % 3) * 4
			if b and town.building_level(b.id) > 0:
				work = b.slot + b.width / 2 + 1
			else:
				k += 1
			var home: int = houses[hi % houses.size()] + 2 if not houses.is_empty() else work
			hi += 1
			var sched := {
				"morning": _reach(work, _gathering(&"market", open, work), open),
				"day": work,
				"evening": _reach(work, _gathering(&"tavern", open, work), open),
				"night": _reach(work, home, open),
			}
			l.town_people.append({"id": id, "cell": _cell(work), "schedule": sched})
	# the old townsfolk of the hub: the merchant at the shop, the guild's
	# board, the chronicler (in the library once it stands), the smith
	l.specials.append({"type": &"merchant", "cell": _cell(_slot(&"shop") + 2)})
	l.specials.append({"type": &"quest", "cell": _cell(_slot(&"quests") + 2)})
	var lib := ItemDatabase.building(&"library")
	var chron_x := (_slot(&"library") - 3) if lib and town and town.building_level(&"library") > 0 and open.get(&"residential", false) else SQUARE + 4
	l.specials.append({"type": &"chronicler", "cell": _cell(chron_x)})
	if town and town.building_level(&"smithy") > 0 and open.get(&"crafts", false):
		l.specials.append({"type": &"smith", "cell": _cell(_slot(&"smithy") - 3)})
	return l


## A standing cell on the street at column x (terraces included).
static func _cell(x: int) -> Vector2i:
	return Vector2i(x, ground_at(x) - 1)


static func _prop(l: LevelLayout, tex: String, x: int, z: int, lamp := false) -> void:
	l.town_props.append({"tex": tex, "cell": _cell(x), "z": z, "lamp": lamp})


## A closed district: a palisade (and a wall the hero cannot pass) at the
## side facing an open neighbour, scaffolding behind it.
static func _close(l: LevelLayout, d: DistrictData, open: Dictionary) -> void:
	var left := TownDistricts.of_x(d.x_from - 1)
	var right := TownDistricts.of_x(d.x_to)
	for side in [[left, d.x_from], [right, d.x_to - 1]]:
		var nb: DistrictData = side[0]
		var x: int = side[1]
		if nb == null or not open.get(nb.id, false):
			continue
		var g := ground_at(x)
		for y in range(g - 6, g):
			l.set_tile(x, y, LevelLayout.Tile.BEDROCK)
		l.town_props.append({"tex": "district_gate", "cell": Vector2i(x, g - 1), "z": 1, "lamp": false})
		l.specials.append({"type": &"district_notice", "cell": Vector2i(x + (2 if nb == right else -2), ground_at(x + (2 if nb == right else -2)) - 1), "district": d.id})
	for x in range(d.x_from + 6, d.x_to - 4, 14):
		l.town_props.append({"tex": "scaffold", "cell": _cell(x), "z": -3, "lamp": false})


## `to` unless a closed district lies on the way from `from` (then stay).
static func _reach(from: int, to: int, open: Dictionary) -> int:
	for d in TownDistricts.all():
		if not open.get(d.id, false) and d.x_to > mini(from, to) and d.x_from < maxi(from, to):
			return from
	return to


## Where the people gather at an hour: the market / the tavern if its
## district is open (else where they work).
static func _gathering(kind: StringName, open: Dictionary, fallback: int) -> int:
	for d in TownDistricts.all():
		if d.gathering == kind and open.get(d.id, false):
			if kind == &"tavern":
				var t := ItemDatabase.building(&"tavern")
				if t and GameState.town and GameState.town.building_level(&"tavern") > 0:
					return t.slot + 2
			return (d.x_from + d.x_to) / 2
	return fallback


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
