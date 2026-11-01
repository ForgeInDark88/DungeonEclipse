class_name SurfaceGenerator
extends RefCounted
## The open surface of a location (LocationInstance layer SURFACE): a wide
## stretch of land under the sky, generated from a seed like LevelGenerator
## builds a floor. Pure data: a LevelLayout with
## - relief: stepped hills (±1–3 cells), cliffs with a ladder in their face,
##   ravines under a plank bridge (a ladder out of them), shallow ponds,
##   trees with a climbable trunk up to a crown ledge;
## - portals (layout.portal_cells): "map" on the left at the start, "main"
##   (the main way down) near the right end, the side entrances between
##   them (layout.portal_kinds: cave, well, crypt, ruin stairs, sinkhole);
## - 3–6 points of interest (layout.pois): a bandits' camp, a shrine, a
##   ruined tower, a trader's cart, a graveyard, a well, a hunters' camp;
## - props (layout.town_props-style entries in layout.surface_props), water
##   (layout.water), chests and monsters.
##
## Relief is stepped (cells, no slopes): see README «Поверхность».
## Every point of interest, entrance and the map exit stand on ground the
## hero (and LevelNav: jumps up to 3 cells) can walk to — tests/location_test.

const T = LevelLayout.Tile
const SCREEN_CELLS := 40
const HEIGHT := 48
## Lowest / highest ground row.
const GROUND_MIN := 18
const GROUND_MAX := HEIGHT - 6
const SAFE_START := 12
const POI_TYPES := [&"bandit_camp", &"shrine", &"tower", &"cart", &"graveyard", &"well", &"hunters", &"stranger"]
const SIDE_KINDS := [&"cave", &"well", &"crypt", &"ruin_stairs", &"sinkhole"]

var rng := RandomNumberGenerator.new()
var layout: LevelLayout
var biome: SurfaceBiomeData
## Ground row (the first solid cell) of every column.
var ground: PackedInt32Array = PackedInt32Array()
var _taken: Dictionary = {}  # Vector2i -> true
## Columns where nothing else may be built (cliffs, ravines, ponds, POIs).
var _busy_cols: Dictionary = {}


## `screens`: the width in screens (6–12, -1: rolled). `sides`: side
## entrances. `p_biome`: what grows here (null: plain forest rules).
## The node's type (a rescue node keeps its prisoner in the bandits' camp).
var node_type: StringName = &""


func generate(depth: int, seed_value: int, sides := 1, screens := -1, p_biome: SurfaceBiomeData = null) -> LevelLayout:
	rng.seed = seed_value
	biome = p_biome if p_biome else SurfaceBiomeData.new()
	if screens < 0:
		screens = rng.randi_range(6, 9)
	var w := screens * SCREEN_CELLS
	layout = LevelLayout.new(w, HEIGHT, T.EMPTY)
	layout.is_surface = true
	_taken.clear()
	_busy_cols.clear()
	_relief()
	_fill_ground()
	_cliffs(screens)
	_ravines(screens)
	_ponds(screens)
	_place_portals(sides)
	_place_pois(depth)
	_trees(screens)
	_ledges()
	_props()
	_resources(screens)
	_place_chests(depth)
	_place_enemies(depth)
	_edges()
	return layout


# ------------------------------------------------------------------ relief
func _relief() -> void:
	var w := layout.width
	ground.resize(w)
	var y := HEIGHT - 14
	var x := 0
	# at most 2 cells per step: a hop for the hero, a jump for every monster
	var steps: Array = [[-1, 0, 1], [-1, -1, 0, 1, 1], [-2, -1, -1, 0, 1, 1, 2], [-2, -2, -1, 0, 1, 2, 2]][clampi(biome.roughness, 1, 3)]
	while x < w:
		var seg := rng.randi_range(6, 14)
		# Flat start and flat entrance ground: the portals need a floor.
		if x < SAFE_START or x > w - 18:
			seg = maxi(seg, 10)
		else:
			y = clampi(y + steps[rng.randi() % steps.size()], GROUND_MIN, GROUND_MAX)
		for i in seg:
			if x + i < w:
				ground[x + i] = y
		x += seg


## After a stretch was levelled: the land on both sides comes to it in steps
## of at most 2 cells (stops at a cliff, which has its ladder).
func _smooth_around(x0: int, x1: int) -> void:
	for dir in [-1, 1]:
		var cx: int = x0 - 1 if dir < 0 else x1 + 1
		while cx > 0 and cx < layout.width - 1 and not _busy_cols.has(cx):
			var prev: int = ground[cx - dir]
			if absi(ground[cx] - prev) <= 2:
				break
			ground[cx] = prev + (2 if ground[cx] > prev else -2)
			_fill_ground(cx, cx)
			cx += dir


func _fill_ground(x0 := 0, x1 := -1) -> void:
	if x1 < 0:
		x1 = layout.width - 1
	for cx in range(maxi(0, x0), mini(layout.width, x1 + 1)):
		for cy in HEIGHT:
			layout.set_tile(cx, cy, T.EMPTY if cy < ground[cx] else (T.BEDROCK if cy >= HEIGHT - 2 else T.BRICK))


## The world's edges: walls on both sides and a ceiling high in the sky.
func _edges() -> void:
	var w := layout.width
	for cy in HEIGHT:
		layout.set_tile(0, cy, T.BEDROCK)
		layout.set_tile(w - 1, cy, T.BEDROCK)
	for cx in w:
		layout.set_tile(cx, 0, T.BEDROCK)


func _free_cols(x0: int, x1: int) -> bool:
	if x0 < SAFE_START + 4 or x1 > layout.width - 20:
		return false
	for x in range(x0 - 2, x1 + 3):
		if _busy_cols.has(x):
			return false
	return true


func _mark_cols(x0: int, x1: int) -> void:
	for x in range(x0, x1 + 1):
		_busy_cols[x] = true


## A cliff: the land rises 4–7 cells at once; a ladder in the face.
func _cliffs(screens: int) -> void:
	for s in screens:
		if rng.randf() >= biome.cliff_chance:
			continue
		var x := s * SCREEN_CELLS + rng.randi_range(6, SCREEN_CELLS - 10)
		if not _free_cols(x, x + 1):
			continue
		var rise := rng.randi_range(4, 7)
		var up := rng.randf() < 0.5 or ground[x] + rise > GROUND_MAX
		var from := ground[x]
		var to := clampi(from - rise if up else from + rise, GROUND_MIN, GROUND_MAX)
		if absi(to - from) < 4:
			continue
		# everything right of the cliff moves with it
		var delta := to - from
		for cx in range(x, layout.width - 18):
			ground[cx] = clampi(ground[cx] + delta, GROUND_MIN, GROUND_MAX)
		for cx in range(layout.width - 18, layout.width):
			ground[cx] = ground[layout.width - 19]
		_fill_ground(x, layout.width - 1)
		# the ladder: in the high side's edge column, down to the low ground
		var lx := x if delta < 0 else x - 1
		var top := mini(ground[x - 1], ground[x])
		var bottom := maxi(ground[x - 1], ground[x])
		layout.set_tile(lx, top, T.LADDER_TOP)
		for cy in range(top + 1, bottom):
			layout.set_tile(lx, cy, T.LADDER)
		_mark_cols(x - 2, x + 2)


## A ravine: a gap 4–7 wide, 5–8 deep, a plank bridge over it, a ladder out.
func _ravines(screens: int) -> void:
	for s in screens:
		if rng.randf() >= biome.ravine_chance:
			continue
		var wdt := rng.randi_range(4, 7)
		var x := s * SCREEN_CELLS + rng.randi_range(6, SCREEN_CELLS - wdt - 6)
		if not _free_cols(x - 1, x + wdt):
			continue
		var gy := ground[x - 1]
		# level the banks
		for cx in range(x - 2, x + wdt + 2):
			ground[cx] = gy
		var depth := rng.randi_range(5, 8)
		_fill_ground(x - 2, x + wdt + 2)
		_smooth_around(x - 2, x + wdt + 1)
		for cx in range(x, x + wdt):
			for cy in range(gy, mini(gy + depth, HEIGHT - 3)):
				layout.set_tile(cx, cy, T.EMPTY)
			ground[cx] = mini(gy + depth, HEIGHT - 3)
		for cx in range(x, x + wdt):
			layout.set_tile(cx, gy, T.PLATFORM)
		# the bridge is at the banks' ground row: walk across; a ladder out of the bottom
		layout.set_tile(x, gy, T.LADDER_TOP)
		for cy in range(gy + 1, ground[x]):
			layout.set_tile(x, cy, T.LADDER)
		layout.ravines.append(Rect2i(x, gy, wdt, ground[x] - gy))
		_mark_cols(x - 2, x + wdt + 1)
		# a hidden cave in the far bank: a cracked wall, a chest behind it
		var wall := x + wdt
		var bottom := ground[x + 1] - 1
		var room := true
		for cx in range(wall + 2, wall + 7):
			# nothing else in those columns (wall + 1 is the ravine's own margin), and solid earth over the cave
			if _busy_cols.has(cx) or cx >= layout.width - 20 or ground[cx] > bottom - 3:
				room = false
		if rng.randf() < 0.45 and room:
			for cx in range(wall + 1, wall + 6):
				for cy in range(bottom - 1, bottom + 1):
					layout.set_tile(cx, cy, T.EMPTY)
			var cells: Array[Vector2i] = [Vector2i(wall, bottom - 1), Vector2i(wall, bottom)]
			for cc in cells:
				layout.set_tile(cc.x, cc.y, T.BRICK)
			layout.secret_walls.append(cells)
			layout.chests.append({"cell": Vector2i(wall + 4, bottom), "tier": 2, "secret": true})
			_mark_cols(wall, wall + 6)


## A shallow pond: a dip 2 cells deep under the water's surface.
func _ponds(screens: int) -> void:
	for s in screens:
		if rng.randf() >= biome.pond_chance:
			continue
		var wdt := rng.randi_range(6, 10)
		var x := s * SCREEN_CELLS + rng.randi_range(6, SCREEN_CELLS - wdt - 6)
		if not _free_cols(x - 1, x + wdt):
			continue
		var gy := ground[x - 1]
		for cx in range(x - 2, x + wdt + 2):
			ground[cx] = gy
		_fill_ground(x - 2, x + wdt + 2)
		_smooth_around(x - 2, x + wdt + 1)
		for cx in range(x, x + wdt):
			var d := 1 if cx == x or cx == x + wdt - 1 else 2
			for cy in range(gy, gy + d):
				layout.set_tile(cx, cy, T.EMPTY)
			ground[cx] = gy + d
		layout.water.append(Rect2i(x, gy, wdt, 2))
		_mark_cols(x - 1, x + wdt)


## A standing cell on the ground of column x (the empty cell above it).
func ground_cell(x: int) -> Vector2i:
	return Vector2i(x, ground[clampi(x, 0, layout.width - 1)] - 1)


func _flat(x: int, r: int) -> bool:
	for dx in range(-r, r + 1):
		var cx := clampi(x + dx, 0, layout.width - 1)
		if ground[cx] != ground[x] or _busy_cols.has(cx):
			return false
	return true


## The nearest column to x with flat free ground r cells to each side.
func _flat_near(x: int, r: int) -> int:
	for d in 40:
		for cx in [x + d, x - d]:
			if cx > SAFE_START + r and cx < layout.width - 10 - r and _flat(cx, r):
				return cx
	return -1


# ----------------------------------------------------------------- portals
func _place_portals(sides: int) -> void:
	var w := layout.width
	layout.start_cell = ground_cell(4)
	layout.portal_cells[&"map"] = ground_cell(2)
	layout.portal_cells[&"main"] = ground_cell(w - 8)
	layout.portal_kinds[&"main"] = &"cave"
	layout.exit_cell = layout.portal_cells[&"main"]
	_reserve(layout.start_cell, 4)
	_reserve(layout.portal_cells[&"main"], 3)
	var span := float(w - 60) / float(maxi(1, sides))
	for k in sides:
		var x := 30 + roundi(span * k + rng.randf_range(span * 0.25, span * 0.75))
		var fx := _flat_near(x, 2)
		if fx < 0:
			fx = x
		var c := ground_cell(fx)
		var pid := StringName("side_%d" % (k + 1))
		layout.portal_cells[pid] = c
		layout.portal_kinds[pid] = SIDE_KINDS[rng.randi() % SIDE_KINDS.size()]
		_reserve(c, 3)
		_mark_cols(fx - 2, fx + 2)


func _reserve(c: Vector2i, r: int) -> void:
	for dx in range(-r, r + 1):
		_taken[Vector2i(c.x + dx, c.y)] = true


# -------------------------------------------------------- points of interest
func _place_pois(depth: int) -> void:
	var count := rng.randi_range(3, 6)
	var kinds: Array = POI_TYPES.duplicate()
	_shuffle(kinds)
	if node_type == &"rescue":
		kinds.erase(&"bandit_camp")
		kinds.push_front(&"bandit_camp")  # the prisoner waits in the bandits' camp
	var w := layout.width
	var span := float(w - 50) / float(count)
	for k in count:
		var kind: StringName = kinds[k % kinds.size()]
		var x := 24 + roundi(span * k + rng.randf_range(span * 0.2, span * 0.8))
		var r := 5 if kind in [&"bandit_camp", &"graveyard", &"hunters"] else 3
		var fx := _flat_near(x, r)
		if fx < 0:
			continue
		var c := ground_cell(fx)
		layout.pois.append({"type": kind, "cell": c, "rect": Rect2i(fx - r, c.y - 6, r * 2 + 1, 7)})
		_build_poi(kind, fx, r, depth)
		_mark_cols(fx - r, fx + r)


func _prop(tex: StringName, c: Vector2i, z := -1) -> void:
	layout.surface_props.append({"tex": tex, "cell": c, "z": z})


func _build_poi(kind: StringName, x: int, r: int, depth: int) -> void:
	var c := ground_cell(x)
	match kind:
		&"bandit_camp":
			_prop(&"tent", Vector2i(x - 3, c.y))
			_prop(&"tent", Vector2i(x + 3, c.y))
			_prop(&"campfire", c, 0)
			layout.chests.append({"cell": Vector2i(x + r - 1, c.y), "tier": 2 if depth >= 6 else 1})
			layout.specials.append({"type": &"elite_pack", "cell": Vector2i(x - 1, c.y)})
			if node_type == &"rescue":
				# the cage by the fire; its guards are the camp's bandits
				layout.specials.append({"type": &"rescue", "cell": Vector2i(x + 1, c.y),
						"cells": [Vector2i(x - 4, c.y), Vector2i(x + 3, c.y), Vector2i(x - 2, c.y)]})
			else:
				for dx in [-4, 2, 4]:
					var e := Vector2i(x + dx, c.y)
					if not e in layout.enemy_cells:
						layout.enemy_cells.append(e)
			layout.breakables.append({"look": &"barrel", "cell": Vector2i(x - r, c.y)})
			layout.breakables.append({"look": &"crate", "cell": Vector2i(x + r - 2, c.y)})
			_reserve(c, r)
		&"hunters":
			_prop(&"tent", Vector2i(x - 2, c.y))
			_prop(&"campfire", Vector2i(x + 1, c.y), 0)
			layout.specials.append({"type": &"camp_fire", "cell": Vector2i(x + 3, c.y)})
			_reserve(c, r)
		&"shrine":
			_prop(&"ruin_column", Vector2i(x - 2, c.y))
			_prop(&"ruin_column", Vector2i(x + 2, c.y))
			layout.specials.append({"type": &"event", "cell": c, "room": Rect2i(x - 8, c.y - 6, 17, 7), "roll": rng.randi()})
			_reserve(c, r)
		&"tower":
			# A ruined tower: a ladder inside up to two floors, a chest on top.
			_prop(&"tower_ruin", c, -2)
			for cy in range(c.y - 9, c.y + 1):
				layout.set_tile(x, cy, T.LADDER)
			layout.set_tile(x, c.y - 10, T.LADDER_TOP)
			for dx in range(-2, 3):
				if dx != 0:
					layout.set_tile(x + dx, c.y - 10, T.PLATFORM)
					layout.set_tile(x + dx, c.y - 5, T.PLATFORM)
			layout.chests.append({"cell": Vector2i(x + 2, c.y - 11), "tier": 1 if depth < 8 else 2})
			_reserve(c, r)
		&"cart":
			_prop(&"cart", Vector2i(x - 2, c.y))
			layout.specials.append({"type": &"merchant", "cell": Vector2i(x + 1, c.y)})
			layout.breakables.append({"look": &"crate", "cell": Vector2i(x + 3, c.y)})
			_reserve(c, r)
		&"stranger":
			# a wanderer with an errand (the quest board's giver)
			_prop(&"campfire", Vector2i(x - 2, c.y), 0)
			layout.specials.append({"type": &"quest", "cell": Vector2i(x + 1, c.y)})
			_reserve(c, r)
		&"graveyard":
			for dx in [-4, -2, 0, 2, 4]:
				_prop(&"gravestone", Vector2i(x + dx, c.y))
			layout.chests.append({"cell": Vector2i(x + r, c.y), "tier": 1})
			layout.enemy_cells.append(Vector2i(x - 1, c.y))
			_reserve(c, r)
		&"well":
			_prop(&"well", c)
			layout.chests.append({"cell": Vector2i(x + 2, c.y), "tier": 0})
			_reserve(c, r)
	# a note of the chronicle lies at the first shrine, tower or graveyard
	if layout.lore_cell.x < 0 and kind in [&"shrine", &"tower", &"graveyard"]:
		layout.lore_cell = Vector2i(x - 1, c.y) if kind != &"tower" else Vector2i(x - 2, c.y - 11)


# --------------------------------------------------------- trees and props
## Trees: props; some have a trunk to climb (a ladder) and a crown ledge.
func _trees(screens: int) -> void:
	if biome.trees.is_empty():
		return
	var count := roundi(biome.tree_density * screens)
	for i in count:
		var x := rng.randi_range(SAFE_START, layout.width - 12)
		var c := ground_cell(x)
		if _busy_cols.has(x) or layout.get_tile(c.x, c.y) != T.EMPTY:
			continue
		var tex: StringName = biome.trees[rng.randi() % biome.trees.size()]
		_prop(tex, c, -2)
		if rng.randf() < 0.35 and _flat(x, 2) and c.y > 8:
			# climbable: trunk up 4 cells, a crown ledge of 5
			for cy in range(c.y - 3, c.y + 1):
				layout.set_tile(x, cy, T.LADDER)
			layout.set_tile(x, c.y - 4, T.LADDER_TOP)
			for dx in [-2, -1, 1, 2]:
				if layout.get_tile(x + dx, c.y - 4) == T.EMPTY:
					layout.set_tile(x + dx, c.y - 4, T.PLATFORM)
			_mark_cols(x - 2, x + 2)


## Floating ledges (rocky outcrops) over open ground.
func _ledges() -> void:
	var x := SAFE_START + 4
	while x < layout.width - 20:
		x += rng.randi_range(10, 20)
		if rng.randf() < 0.4:
			var len := rng.randi_range(4, 7)
			if not _free_cols(x, x + len):
				continue
			var gy := _min_ground(x, x + len)
			var ly := gy - 3
			if ly < 3:
				continue
			for i in len:
				layout.set_tile(x + i, ly, T.PLATFORM)
			x += len


func _props() -> void:
	for x in range(SAFE_START, layout.width - 10):
		if _busy_cols.has(x):
			continue
		var c := ground_cell(x)
		if layout.get_tile(c.x, c.y) != T.EMPTY:
			continue
		var r := rng.randf()
		if r < 0.035 and not biome.rocks.is_empty():
			_prop(biome.rocks[rng.randi() % biome.rocks.size()], c, -1)
		elif r < 0.09 and not biome.small.is_empty():
			_prop(biome.small[rng.randi() % biome.small.size()], c, 1)


## Trees to chop, boulders and ore veins, herbs and berry bushes, crosses
## over buried treasure, crates by the road.
func _resources(screens: int) -> void:
	for p in layout.surface_props:
		var tex := String(p["tex"])
		if tex.begins_with("tree") and tex != "tree_dead" and rng.randf() < 0.5:
			layout.resources.append({"kind": &"tree", "cell": p["cell"]})
		elif tex == "rock_big" or tex == "rock_red":
			layout.resources.append({"kind": &"boulder", "cell": p["cell"]})
	var add := func(kind: StringName, count: int) -> void:
		for i in count:
			var x := rng.randi_range(SAFE_START + 4, layout.width - 12)
			if _busy_cols.has(x):
				continue
			var c := ground_cell(x)
			if _taken.has(c) or layout.get_tile(c.x, c.y) != T.EMPTY:
				continue
			layout.resources.append({"kind": kind, "cell": c})
			_reserve(c, 1)
	add.call(&"vein", rng.randi_range(1, 2) + screens / 5)
	add.call(&"herb", rng.randi_range(2, 4))
	add.call(&"berries", rng.randi_range(1, 3))
	add.call(&"dig", rng.randi_range(0, 2))
	for i in rng.randi_range(1, 3):
		var x := rng.randi_range(SAFE_START + 4, layout.width - 12)
		var c := ground_cell(x)
		if not _busy_cols.has(x) and not _taken.has(c) and layout.get_tile(c.x, c.y) == T.EMPTY:
			layout.breakables.append({"look": [&"barrel", &"crate"][rng.randi() % 2], "cell": c})
			_reserve(c, 1)


func _min_ground(x0: int, x1: int) -> int:
	var m := HEIGHT
	for x in range(maxi(0, x0), mini(layout.width, x1 + 1)):
		m = mini(m, ground[x])
	return m


# -------------------------------------------------------------- the living
func _place_chests(depth: int) -> void:
	var count := rng.randi_range(2, 4)
	var placed := 0
	for i in count * 6:
		if placed >= count:
			break
		var c := _free_spot(SAFE_START, layout.width - 4, false)
		if c.x < 0:
			continue
		var tier := 0
		var r := rng.randf()
		if r < 0.04 + 0.01 * depth:
			tier = 2
		elif r < 0.22:
			tier = 1
		layout.chests.append({"cell": c, "tier": tier})
		_reserve(c, 2)
		placed += 1


func _place_enemies(depth: int) -> void:
	var count := clampi(roundi((5 + layout.width / 30 + depth / 3) * Net.monster_count_mult()), 4, 28)
	for i in count * 4:
		if layout.enemy_cells.size() >= count:
			break
		var c := _free_spot(SAFE_START + 6, layout.width - 4)
		if c.x < 0:
			continue
		layout.enemy_cells.append(c)
		_reserve(c, 1)


## A free standing cell on the ground or on a ledge between columns x0..x1.
func _free_spot(x0: int, x1: int, ledges := true) -> Vector2i:
	for attempt in 12:
		var x := rng.randi_range(x0, x1)
		var c := ground_cell(x)
		# A ledge above? Sometimes stand on it instead.
		if rng.randf() < 0.3 and ledges:
			for y in range(c.y - 1, 2, -1):
				if layout.get_tile(x, y) == T.PLATFORM:
					c = Vector2i(x, y - 1)
					break
		if _taken.has(c) or layout.get_tile(c.x, c.y) != T.EMPTY or layout.get_tile(c.x, c.y - 1) != T.EMPTY:
			continue
		if not LevelLayout.is_ground(layout.get_tile(c.x, c.y + 1)):
			continue
		if layout.water.any(func(wr: Rect2i) -> bool: return wr.grow(1).has_point(c)):
			continue
		return c
	return Vector2i(-1, -1)


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = t
