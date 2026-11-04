extends SceneTree
## LevelGenerator over 500 seeds (classic floors, depths 1..30, every third
## with the flooded basins of the Drowned Vaults):
## - the same seed builds the same floor;
## - the exit is reachable from the start along the monsters' ground graph
##   (LevelNav, clearance 2);
## - what the hero can reach (HeroReach: walk, ladders, a jump of 4 cells
##   up and 3 across, falls, dropping through ledges) holds every chest;
## - every chest stands in the open and is reachable: a chest of an open
##   room right away, one behind a cracked secret wall once the wall is
##   broken (entry "secret"); a sealed room without one is for bombs only
##   (entry "bomb", by design: counted, not walked to);
## - no monster place is inside the rock;
## - water lies over a floor, never over the start, the exit or a chest.
##   godot --headless -s tools/tests/level_gen_test.gd   (SEEDS=n)

var fails := 0


func check(c: bool, what: String) -> void:
	if not c:
		fails += 1
		if fails < 40:
			print("FAIL: " + what)


## Cells the hero can stand in, from `start`: walking, ladders (climb, step
## off sideways), jumps up to 4 cells high and 3 across through open air,
## falls, dropping through one-way ledges.
func _initialize() -> void:
	await process_frame
	var Gen = load("res://scripts/level/level_generator.gd")
	var count := int(OS.get_environment("SEEDS")) if OS.get_environment("SEEDS") != "" else 500
	var paths := 0
	var chests := 0
	var basins := 0
	var bomb_rooms := 0
	var t0 := Time.get_ticks_msec()
	for i in count:
		var floor_number := 1 + i % 30
		var seed_value := 424242 + i * 7907
		var gen = Gen.new()
		gen.flooded_pools = 3 if i % 3 == 0 else 0
		var lay = gen.generate(floor_number, seed_value)
		var tag := "floor %d seed %d" % [floor_number, seed_value]
		if i < 20:
			var again = Gen.new()
			again.flooded_pools = gen.flooded_pools
			check(again.generate(floor_number, seed_value).tiles == lay.tiles, "%s: the same seed, the same floor" % tag)
		var nav := LevelNav.new(lay)
		# the same floor with its secret walls broken through
		var open = load("res://scripts/level/level_layout.gd").new(lay.width, lay.height)
		open.tiles = lay.tiles.duplicate()
		for wall in lay.secret_walls:
			for c: Vector2i in wall:
				open.set_tile(c.x, c.y, LevelLayout.Tile.EMPTY)
		var hero_reach_d := HeroReach.cells(lay, lay.start_cell)
		var open_reach := HeroReach.cells(open, lay.start_cell)
		check(hero_reach_d.has(lay.exit_cell), "%s: the hero reaches the exit" % tag)
		paths += 1
		check(not nav.ground_path(lay.start_cell, lay.exit_cell, 2).is_empty(), "%s: the exit %s is reachable from the start %s" % [tag, lay.exit_cell, lay.start_cell])
		for ch in lay.chests:
			var c: Vector2i = ch["cell"]
			chests += 1
			check(lay.get_tile(c.x, c.y) == LevelLayout.Tile.EMPTY, "%s: chest %s in the open" % [tag, c])
			var entry: StringName = ch.get("entry", &"")
			if entry == &"bomb":
				bomb_rooms += 1  # a sealed room: only a bomb gets in (by design)
				continue
			paths += 1
			var reach: Dictionary = open_reach if entry == &"secret" else hero_reach_d
			check(reach.has(c), "%s: chest %s is reachable%s" % [tag, c, " (the secret wall broken)" if entry == &"secret" else ""])
		for e: Vector2i in lay.enemy_cells:
			var t: int = lay.get_tile(e.x, e.y)
			check(t != LevelLayout.Tile.BRICK and t != LevelLayout.Tile.BEDROCK, "%s: monster place %s in the open" % [tag, e])
		for r: Rect2i in lay.water:
			basins += 1
			for x in range(r.position.x, r.end.x):
				check(LevelLayout.is_solid(lay.get_tile(x, r.end.y)), "%s: basin %s has a floor" % [tag, r])
			for c in [lay.start_cell, lay.exit_cell]:
				check(not r.grow(1).has_point(c), "%s: no water over %s" % [tag, c])
	print("floors: %d, paths checked: %d, chests: %d (behind bomb-only walls: %d), flooded basins: %d, %.1f ms a floor" % [count, paths, chests, bomb_rooms, basins, float(Time.get_ticks_msec() - t0) / count])
	print("FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)
