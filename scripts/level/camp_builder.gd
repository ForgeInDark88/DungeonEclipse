class_name CampBuilder
extends RefCounted
## A camp on the road (map node «Лагерь») as a small place to walk: two
## screens of flat, safe ground with the fire in the middle, tents, the
## trader's cart, the workbench, the anvil, the stash, the rumour board,
## the signpost home and the road on. What stands depends on the town
## (Buildings levels: the smithy brings an anvil, the alchemist a table,
## the temple a second fire, the warehouse the stash) — the camp's level,
## kept in TownState.flags["camp_level"]. A forest, ruins or cave camp by
## the region (layout.camp_kind), each with its biome.

const T = LevelLayout.Tile
const WIDTH := 80
const HEIGHT := 26
const GROUND := 20


## What the town gives its camps: [spot kind, building, level].
const UPGRADES := [
	[&"anvil", &"smithy", 1],
	[&"workbench", &"alchemist", 1],
	[&"fire2", &"temple", 2],
	[&"stash", &"warehouse", 1],
]


static func camp_level(town: TownState) -> int:
	var n := 0
	for u in UPGRADES:
		if town and town.building_level(u[1]) >= int(u[2]):
			n += 1
	return n


static func has(town: TownState, kind: StringName) -> bool:
	for u in UPGRADES:
		if u[0] == kind:
			return town != null and town.building_level(u[1]) >= int(u[2])
	return true


static func build(seed_value: int, kind: StringName, town: TownState, companions: Array) -> LevelLayout:
	var l := LevelLayout.new(WIDTH, HEIGHT, T.EMPTY)
	l.is_camp = true
	l.camp_kind = kind
	l.is_surface = kind != &"cave"
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for x in WIDTH:
		var g := GROUND + (1 if x < 6 or x > WIDTH - 7 else 0)
		for y in range(g, HEIGHT):
			l.set_tile(x, y, T.BEDROCK if y >= HEIGHT - 2 else T.BRICK)
	for y in HEIGHT:
		for x in [0, WIDTH - 1]:
			l.set_tile(x, y, T.BEDROCK)
	if kind == &"cave":
		# a cave camp: a low rock ceiling with a gap of light
		for x in WIDTH:
			for y in range(0, 6 + (2 if absi(x - WIDTH / 2) > 12 else 0)):
				l.set_tile(x, y, T.BRICK if y > 0 else T.BEDROCK)
	var row := GROUND - 1
	l.start_cell = Vector2i(8, row)
	l.exit_cell = Vector2i(-1, -1)
	var spot := func(k: StringName, x: int) -> void:
		l.specials.append({"type": &"camp_spot", "kind": k, "cell": Vector2i(x, row)})
	spot.call(&"home", 4)
	spot.call(&"board", 14)
	if has(town, &"stash"):
		spot.call(&"stash", 20)
	spot.call(&"workbench", 26)
	spot.call(&"fire", WIDTH / 2)
	if has(town, &"fire2"):
		spot.call(&"fire2", WIDTH / 2 + 8)
	if has(town, &"anvil"):
		spot.call(&"anvil", 52)
	spot.call(&"rare", 60)
	spot.call(&"road", WIDTH - 5)
	l.specials.append({"type": &"merchant", "cell": Vector2i(64, row)})
	# the look of the place
	var tent := "tent"
	for x in [WIDTH / 2 - 10, WIDTH / 2 + 14]:
		l.surface_props.append({"tex": tent, "cell": Vector2i(x, row), "z": -2})
	l.surface_props.append({"tex": "cart", "cell": Vector2i(67, row), "z": -2})
	if kind == &"ruins":
		for x in [10, 32, 70]:
			l.surface_props.append({"tex": ["ruin_wall", "ruin_column"][x % 2], "cell": Vector2i(x, row), "z": -3})
	elif kind != &"cave":
		for x in [2, 11, 30, 48, 74]:
			l.surface_props.append({"tex": ["tree_oak", "tree_pine"][rng.randi() % 2], "cell": Vector2i(x, row), "z": -3})
	# the companions: the people freed on this road wait by the tents
	var k := 0
	for id in companions:
		if k >= 3:
			break
		l.town_people.append({"id": id, "cell": Vector2i(WIDTH / 2 - 6 + k * 5, row)})
		k += 1
	return l
