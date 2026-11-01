extends Node
## Headless monster-AI simulation:
##   godot --headless --fixed-fps 60 --path . res://tests/ai_sim.tscn -- --levels=50 --seconds=25
## Generates N floors (floors 1..12, fixed seeds), drops an invulnerable hero
## that "roams" (jumps to a random standing spot every few seconds, so monsters
## patrol, notice, chase, search and return), simulates SIM seconds per floor
## and prints, per floor and in total: anti-stuck activations (new path /
## maneuver / teleport), monsters that wanted to move but stood still > 10 s,
## time monsters spent on trap cells and monsters lost outside the level.
## Exit code 1 when any monster was stuck > 10 s or stood in a trap.
##
## `--surface`: the open land of locations instead (SurfaceGenerator, every
## surface biome in turn, depth 1..24): stepped hills, cliffs with ladders,
## ravines, ponds. Also counts how long monsters that were not chasing
## anybody spent down in a ravine or a pond (they should not fall in for
## no reason).

const LEVEL_SCENE := preload("res://scenes/levels/dungeon_level.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const STUCK_LIMIT := 10.0
const ROAM_EVERY := 4.0

var levels := 50
var seconds := 25.0
var surface := false
var totals := {"levels": 0, "enemies": 0, "stuck": 0, "worst_still": 0.0, "danger_time": 0.0,
	"lost": 0, "chases": 0, "searches": 0, "returns": 0, "pit_time": 0.0}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--levels="):
			levels = int(a.get_slice("=", 1))
		elif a == "--verbose":
			AIDebug.verbose = true
		elif a == "--surface":
			surface = true
		elif a.begins_with("--seconds="):
			seconds = float(a.get_slice("=", 1))
	AIDebug.reset()
	MetaProgress.apply_upgrades = false
	var started := Time.get_ticks_msec()
	print("AI simulation: %d %s × %.0f s" % [levels, "surfaces" if surface else "floors", seconds])
	for i in levels:
		if surface:
			await _run_level(1 + i % 24, 2000 + i * 7919, i)
			continue
		var floor_number := 1 + i % 12
		if floor_number % GameState.BOSS_EVERY == 0:
			floor_number += 1  # arenas have their own boss logic
		await _run_level(floor_number, 1000 + i * 7919, i)
	var c := AIDebug.counters
	print("----------------------------------------------------------")
	print("Floors: %d, monsters: %d" % [totals["levels"], totals["enemies"]])
	print("Anti-stuck: new path %d, maneuver %d, teleport %d" % [AIDebug.count("repath"), AIDebug.count("maneuver"), AIDebug.count("teleport")])
	print("Nav rebuilds: %d" % AIDebug.count("nav"))
	print("States seen: chase %d, search %d, return %d" % [totals["chases"], totals["searches"], totals["returns"]])
	print("Monsters stuck > %ds: %d (worst %.1f s)" % [STUCK_LIMIT, totals["stuck"], totals["worst_still"]])
	print("Time on trap cells: %.1f s, lost outside the level: %d" % [totals["danger_time"], totals["lost"]])
	if surface:
		print("Idle time down in ravines / ponds: %.1f s" % totals["pit_time"])
	print("Real time: %.1f s" % ((Time.get_ticks_msec() - started) / 1000.0))
	var ok: bool = totals["stuck"] == 0 and totals["danger_time"] < 0.5 and totals["lost"] == 0 \
			and totals["pit_time"] < 1.0
	print("RESULT: ", "OK" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)


func _run_level(floor_number: int, seed_value: int, index: int) -> void:
	seed(seed_value)
	GameState.floor_number = floor_number
	var layout: LevelLayout
	var biome: BiomeData
	if surface:
		var ids: Array = ItemDatabase.surface_biomes.keys()
		ids.sort()
		biome = ItemDatabase.surface_biomes[ids[index % ids.size()]]
		layout = SurfaceGenerator.new().generate(floor_number, seed_value, 2, 6, biome)
	else:
		layout = LevelGenerator.new().generate(floor_number, seed_value)
		biome = ItemDatabase.biome_for_floor(floor_number)
	var level: DungeonLevel = LEVEL_SCENE.instantiate()
	add_child(level)
	level.build(layout, floor_number, seed_value, biome)
	var hero := Hero.new(ItemDatabase.races[0], ItemDatabase.classes[0], ItemDatabase.equipment_layout)
	GameState.hero = hero
	var player: Player = PLAYER_SCENE.instantiate()
	add_child(player)
	player.setup(hero, null)
	player.set_level(level)
	player.global_position = level.start_position()
	var stand_cells: Array[Vector2i] = []
	for y in layout.height:
		for x in layout.width:
			if level.nav.standable(x, y) and not level.nav.is_dangerous(Vector2i(x, y)):
				stand_cells.append(Vector2i(x, y))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var enemies: Array[Enemy] = []
	for n in level.entities.get_children():
		if n is Enemy:
			enemies.append(n)
	var seen_states := {}
	var pit_time := 0.0
	var frames := int(seconds * Engine.physics_ticks_per_second)
	var roam := 0.0
	for f in frames:
		player._invulnerable = 999.0
		hero.stats.hp = hero.stats.max_hp()
		roam -= 1.0 / Engine.physics_ticks_per_second
		if roam <= 0.0 and not stand_cells.is_empty():
			roam = ROAM_EVERY
			# Mostly near the monsters' area: a random spot, half the time close to the last one.
			player.global_position = level.cell_bottom(stand_cells[rng.randi() % stand_cells.size()])
			player.velocity = Vector2.ZERO
		await get_tree().physics_frame
		if f % 15 == 0:
			for e in enemies:
				if is_instance_valid(e):
					seen_states[e.get_instance_id() * 10 + e.state] = true
					if surface and e.state in [Enemy.State.PATROL, Enemy.State.RETURN] and e.data.behavior != EnemyData.Behavior.FLYER:
						var ec := level.world_to_cell(e.global_position + Vector2(0, -4))
						for pit in layout.ravines + layout.water:
							if Rect2i(pit.position + Vector2i(0, 1), pit.size).has_point(ec) and not _home_in(e, level, pit):
								pit_time += 15.0 / Engine.physics_ticks_per_second
	var stuck := 0
	var worst := 0.0
	var danger := 0.0
	var lost := 0
	var bounds := level.bounds_px().grow(32)
	for e in enemies:
		if not is_instance_valid(e):
			continue
		worst = maxf(worst, e.max_still_time)
		if e.max_still_time > STUCK_LIMIT:
			stuck += 1
			print("   stuck: %s at %s state %s (%.1f s)" % [e.data.id, level.world_to_cell(e.global_position), e.state_name(), e.max_still_time])
		danger += e.danger_time
		if not bounds.has_point(e.global_position):
			lost += 1
	for k in seen_states:
		match k % 10:
			Enemy.State.CHASE:
				totals["chases"] += 1
			Enemy.State.SEARCH:
				totals["searches"] += 1
			Enemy.State.RETURN:
				totals["returns"] += 1
	totals["levels"] += 1
	totals["enemies"] += enemies.size()
	totals["stuck"] += stuck
	totals["worst_still"] = maxf(totals["worst_still"], worst)
	totals["danger_time"] += danger
	totals["lost"] += lost
	totals["pit_time"] += pit_time
	print("#%02d %s %2d seed %6d: %2d monsters, stuck>10s %d, worst still %.1f s, trap time %.1f s, lost %d, pit %.1f s | repath %d maneuver %d teleport %d" % [
		index, String(biome.id) if surface else "floor", floor_number, seed_value, enemies.size(), stuck, worst, danger, lost, pit_time,
		AIDebug.count("repath"), AIDebug.count("maneuver"), AIDebug.count("teleport")])
	player.queue_free()
	level.queue_free()
	await get_tree().physics_frame


## A monster that lives down there (spawned in the ravine) is at home.
func _home_in(e: Enemy, level: DungeonLevel, pit: Rect2i) -> bool:
	return Rect2i(pit.position, pit.size + Vector2i(0, 2)).has_point(level.world_to_cell(e._home + Vector2(0, -4)))
