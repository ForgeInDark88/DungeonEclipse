class_name SurfaceGenerator
extends RefCounted
## The open surface of a location (LocationInstance layer SURFACE): a wide
## stretch of land under the sky, generated from a seed like LevelGenerator
## builds a floor. Pure data: a LevelLayout with the ground, ledges, chests,
## monsters and the portals' cells (layout.portal_cells): "map" at the start
## on the left, "main" (the main way down) near the right end, the side
## entrances in between.
##
## Relief is stepped (cells, no slopes): the ground rises and falls by 1–2
## cells per step, what the hero and every monster (LevelNav jumps up to 3)
## walk and jump over without special code. See README «Поверхность».

const T = LevelLayout.Tile
const SCREEN_CELLS := 40
const HEIGHT := 44
## Lowest / highest ground row.
const GROUND_MIN := 18
const GROUND_MAX := HEIGHT - 6
const SAFE_START := 12

var rng := RandomNumberGenerator.new()
var layout: LevelLayout
## Ground row (the first solid cell) of every column.
var ground: PackedInt32Array = PackedInt32Array()
var _taken: Dictionary = {}  # Vector2i -> true


## `screens`: the width in screens (6–12). `sides`: side entrance count.
func generate(depth: int, seed_value: int, sides := 1, screens := -1) -> LevelLayout:
	rng.seed = seed_value
	if screens < 0:
		screens = rng.randi_range(6, 8)
	var w := screens * SCREEN_CELLS
	layout = LevelLayout.new(w, HEIGHT, T.EMPTY)
	layout.is_surface = true
	_taken.clear()
	_relief()
	_ledges()
	_place_portals(sides)
	_place_chests(depth)
	_place_enemies(depth)
	return layout


# ------------------------------------------------------------------ relief
func _relief() -> void:
	var w := layout.width
	ground.resize(w)
	var y := HEIGHT - 12
	var x := 0
	while x < w:
		var seg := rng.randi_range(6, 14)
		# Flat start and flat entrance ground: the portals need a floor.
		if x < SAFE_START or x > w - 18:
			seg = maxi(seg, 10)
		else:
			y = clampi(y + [-2, -1, -1, 0, 1, 1, 2][rng.randi() % 7], GROUND_MIN, GROUND_MAX)
		for i in seg:
			if x + i < w:
				ground[x + i] = y
		x += seg
	for cx in w:
		for cy in range(ground[cx], HEIGHT):
			layout.set_tile(cx, cy, T.BEDROCK if cy >= HEIGHT - 2 else T.BRICK)
	# The world's edges: walls on both sides and a ceiling high in the sky.
	for cy in HEIGHT:
		layout.set_tile(0, cy, T.BEDROCK)
		layout.set_tile(w - 1, cy, T.BEDROCK)
	for cx in w:
		layout.set_tile(cx, 0, T.BEDROCK)


## Floating ledges over the ground: a second path and a perch for chests.
func _ledges() -> void:
	var x := SAFE_START + 4
	while x < layout.width - 20:
		x += rng.randi_range(8, 18)
		if rng.randf() < 0.55:
			var len := rng.randi_range(4, 7)
			var gy := _min_ground(x, x + len)
			var ly := gy - rng.randi_range(3, 4)
			if ly < 3:
				continue
			for i in len:
				layout.set_tile(x + i, ly, T.PLATFORM)
			x += len


func _min_ground(x0: int, x1: int) -> int:
	var m := HEIGHT
	for x in range(maxi(0, x0), mini(layout.width, x1 + 1)):
		m = mini(m, ground[x])
	return m


## A standing cell on the ground of column x (the empty cell above it).
func ground_cell(x: int) -> Vector2i:
	return Vector2i(x, ground[clampi(x, 0, layout.width - 1)] - 1)


# ----------------------------------------------------------------- portals
func _place_portals(sides: int) -> void:
	var w := layout.width
	layout.start_cell = ground_cell(4)
	layout.portal_cells[&"map"] = ground_cell(2)
	layout.portal_cells[&"main"] = ground_cell(w - 8)
	layout.exit_cell = layout.portal_cells[&"main"]
	_reserve(layout.start_cell, 4)
	_reserve(layout.portal_cells[&"main"], 3)
	var span := float(w - 60) / float(maxi(1, sides))
	for k in sides:
		var x := 30 + roundi(span * k + rng.randf_range(span * 0.25, span * 0.75))
		var c := ground_cell(x)
		layout.portal_cells[StringName("side_%d" % (k + 1))] = c
		_reserve(c, 3)


func _reserve(c: Vector2i, r: int) -> void:
	for dx in range(-r, r + 1):
		_taken[Vector2i(c.x + dx, c.y)] = true


# -------------------------------------------------------------- the living
func _place_chests(depth: int) -> void:
	var count := rng.randi_range(3, 5)
	for i in count * 6:
		if layout.chests.size() >= count:
			break
		var c := _free_spot(SAFE_START, layout.width - 4)
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


func _place_enemies(depth: int) -> void:
	var count := clampi(roundi((5 + layout.width / 30 + depth / 3) * Net.monster_count_mult()), 4, 26)
	for i in count * 4:
		if layout.enemy_cells.size() >= count:
			break
		var c := _free_spot(SAFE_START + 6, layout.width - 4)
		if c.x < 0:
			continue
		layout.enemy_cells.append(c)
		_reserve(c, 1)


## A free standing cell on the ground or on a ledge between columns x0..x1.
func _free_spot(x0: int, x1: int) -> Vector2i:
	for attempt in 12:
		var x := rng.randi_range(x0, x1)
		var c := ground_cell(x)
		# A ledge above? Sometimes stand on it instead.
		if rng.randf() < 0.3:
			for y in range(c.y - 1, 2, -1):
				if layout.get_tile(x, y) == T.PLATFORM:
					c = Vector2i(x, y - 1)
					break
		if _taken.has(c) or layout.get_tile(c.x, c.y) != T.EMPTY or layout.get_tile(c.x, c.y - 1) != T.EMPTY:
			continue
		if not LevelLayout.is_ground(layout.get_tile(c.x, c.y + 1)):
			continue
		return c
	return Vector2i(-1, -1)
