class_name DungeonLevel
extends Node2D
## One dungeon floor in the world: tile layers built from a LevelLayout,
## plus every entity of the floor (chests, enemies, door, drops, projectiles).
## Freed as a whole when the hero goes down to the next floor.

const TILE := 16
# Loaded lazily (not preload): these scenes' scripts reference DungeonLevel,
# preloading them here would create a load cycle.
const CHEST_SCENE := "res://scenes/world/chest.tscn"
const ENEMY_SCENE := "res://scenes/enemies/enemy.tscn"
const DOOR_SCENE := "res://scenes/world/exit_door.tscn"
const TORCH_SCENE := "res://scenes/world/wall_torch.tscn"
const DRIP_SCENE := "res://scenes/world/water_drip.tscn"
const TRAP_SCENE := "res://scenes/traps/trap.tscn"
const MERCHANT_SCENE := "res://scenes/npc/merchant.tscn"
## No traps this close (in cells) to the start.
const SAFE_START_RADIUS := 8
const T = LevelLayout.Tile

@onready var back: TileMapLayer = $Back
@onready var tiles: TileMapLayer = $Tiles
@onready var glow: TileMapLayer = $Glow
@onready var entities: Node2D = $Entities

var layout: LevelLayout
var floor_number: int = 1
var biome: BiomeData
var rng := RandomNumberGenerator.new()
## Cells of glowing ore veins (break them for loot).
var ore_cells: Dictionary = {}


func build(p_layout: LevelLayout, p_floor: int, seed_value: int, p_biome: BiomeData = null) -> void:
	layout = p_layout
	floor_number = p_floor
	biome = p_biome
	rng.seed = seed_value
	var ts := TilesetBuilder.get_tileset(biome.tileset_texture if biome else null)
	back.tile_set = ts
	tiles.tile_set = ts
	glow.tile_set = ts
	if biome:
		back.modulate = biome.back_wall_modulate
	_place_ore()
	# Back wall with gaps: through them the parallax cave is visible.
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.08
	for y in layout.height:
		for x in layout.width:
			var cell := Vector2i(x, y)
			if noise.get_noise_2d(x, y) > -0.25 or _near_solid(cell):
				back.set_cell(cell, TilesetBuilder.SOURCE_ID, Vector2i(_variant(cell), AssetPaths.TILE_ROW_BACKWALL))
			_apply_tile(cell, layout.get_tile(x, y))
	_spawn_door()
	_spawn_specials()
	_spawn_chests()
	_spawn_enemies()
	_spawn_ambience()
	_spawn_decorations()
	_spawn_traps()


## Deterministic 0..3 variant per cell.
func _variant(cell: Vector2i) -> int:
	return absi(hash(cell * 7 + Vector2i(floor_number, 3))) % 4


func _near_solid(cell: Vector2i) -> bool:
	for d in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if LevelLayout.is_solid(layout.get_tile(cell.x + d.x, cell.y + d.y)):
			return true
	return false


func _place_ore() -> void:
	ore_cells.clear()
	var chance := biome.ore_chance if biome else 0.04
	for y in range(1, layout.height - 1):
		for x in range(1, layout.width - 1):
			if layout.get_tile(x, y) != T.BRICK:
				continue
			# Only visible bricks (touching an open cell) become ore.
			var exposed := false
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				if not LevelLayout.is_solid(layout.get_tile(x + d.x, y + d.y)):
					exposed = true
			if exposed and rng.randf() < chance:
				ore_cells[Vector2i(x, y)] = true


## Picks the atlas tile for a cell from its neighbours (autotiling): exposed
## top / bottom edges, platform ends, random variants, ore.
func _apply_tile(cell: Vector2i, kind: int) -> void:
	glow.erase_cell(cell)
	var v := _variant(cell)
	match kind:
		T.EMPTY:
			tiles.erase_cell(cell)
		T.BEDROCK:
			tiles.set_cell(cell, TilesetBuilder.SOURCE_ID, Vector2i(v, AssetPaths.TILE_ROW_BEDROCK))
		T.BRICK:
			var coords: Vector2i
			if ore_cells.has(cell):
				coords = AssetPaths.TILE_ORE
				glow.set_cell(cell, TilesetBuilder.SOURCE_ID, AssetPaths.TILE_ORE_GLOW)
			elif not LevelLayout.is_solid(layout.get_tile(cell.x, cell.y - 1)):
				coords = Vector2i(v, AssetPaths.TILE_ROW_BRICK_TOP)
			elif not LevelLayout.is_solid(layout.get_tile(cell.x, cell.y + 1)):
				coords = Vector2i(v, AssetPaths.TILE_ROW_BRICK_BOTTOM)
			else:
				# Mostly plain bricks, sometimes cracked.
				coords = Vector2i(2 if v == 3 else v % 2, AssetPaths.TILE_ROW_BRICK)
			tiles.set_cell(cell, TilesetBuilder.SOURCE_ID, coords)
		T.PLATFORM:
			var left := layout.get_tile(cell.x - 1, cell.y) == T.PLATFORM
			var right := layout.get_tile(cell.x + 1, cell.y) == T.PLATFORM
			var c := AssetPaths.TILE_PLATFORM_MID
			if not left:
				c = AssetPaths.TILE_PLATFORM_LEFT
			elif not right:
				c = AssetPaths.TILE_PLATFORM_RIGHT
			tiles.set_cell(cell, TilesetBuilder.SOURCE_ID, c)
		T.LADDER:
			tiles.set_cell(cell, TilesetBuilder.SOURCE_ID, AssetPaths.TILE_LADDER, 0)
		T.LADDER_TOP:
			tiles.set_cell(cell, TilesetBuilder.SOURCE_ID, AssetPaths.TILE_LADDER, TilesetBuilder.LADDER_TOP_ALT)


## Re-picks the tile of a cell and its neighbours (after digging).
func _refresh_around(cell: Vector2i) -> void:
	for d in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var c: Vector2i = cell + d
		if layout.in_bounds(c.x, c.y):
			_apply_tile(c, layout.get_tile(c.x, c.y))


# ------------------------------------------------------------- coordinates
func world_to_cell(p: Vector2) -> Vector2i:
	var local := to_local(p)
	return Vector2i(floori(local.x / TILE), floori(local.y / TILE))


## World position of the bottom-center of a cell (where feet stand).
func cell_bottom(cell: Vector2i) -> Vector2:
	return to_global(Vector2(cell.x * TILE + TILE / 2.0, (cell.y + 1) * TILE))


func cell_center(cell: Vector2i) -> Vector2:
	return to_global(Vector2(cell.x * TILE + TILE / 2.0, cell.y * TILE + TILE / 2.0))


func start_position() -> Vector2:
	return cell_bottom(layout.start_cell)


func bounds_px() -> Rect2:
	return Rect2(global_position, Vector2(layout.width * TILE, layout.height * TILE))


func kind_at(p: Vector2) -> int:
	var c := world_to_cell(p)
	return layout.get_tile(c.x, c.y)


func is_ladder_at(p: Vector2) -> bool:
	return LevelLayout.is_ladder(kind_at(p))


func is_ground_at(p: Vector2) -> bool:
	return LevelLayout.is_ground(kind_at(p))


func is_solid_at(p: Vector2) -> bool:
	return LevelLayout.is_solid(kind_at(p))


## Ladder column center x for a world position (to snap while climbing).
func ladder_center_x(p: Vector2) -> float:
	return cell_center(world_to_cell(p)).x


# ------------------------------------------------------------ modification
## Breaks a brick tile. Bedrock (outer border) is indestructible.
func break_tile(cell: Vector2i, effects := true) -> bool:
	if layout.get_tile(cell.x, cell.y) != T.BRICK:
		return false
	layout.set_tile(cell.x, cell.y, T.EMPTY)
	var was_ore := ore_cells.erase(cell)
	_refresh_around(cell)
	if was_ore:
		var ore := ItemDatabase.get_item(biome.ore_item if biome else &"iron_ore")
		if ore:
			EventBus.spawn_items.emit(cell_center(cell), [{"item": ore, "count": rng.randi_range(1, 2)}])
		Fx.sparks(entities, cell_center(cell), Color(1.0, 0.85, 0.4), 12, 90.0)
	if effects:
		AudioManager.play_sfx(&"dig", cell_center(cell))
		_debris(cell_center(cell))
		Fx.shards(entities, cell_center(cell), Color(0.6, 0.45, 0.36), 8)
		# Sometimes there is something inside the wall.
		if not was_ore and rng.randf() < 0.06:
			var ore := ItemDatabase.get_item(&"iron_ore") if rng.randf() < 0.6 else ItemDatabase.get_item(&"gold_coin")
			if ore:
				EventBus.spawn_items.emit(cell_center(cell), [{"item": ore, "count": 1}])
	return true


func explode(center: Vector2, radius: float) -> void:
	var c := world_to_cell(center)
	var r := ceili(radius / TILE)
	var broke := false
	for y in range(c.y - r, c.y + r + 1):
		for x in range(c.x - r, c.x + r + 1):
			if cell_center(Vector2i(x, y)).distance_to(center) <= radius:
				broke = break_tile(Vector2i(x, y), false) or broke
	if broke:
		_debris(center, 24)
		Fx.shards(entities, center, Color(0.6, 0.45, 0.36), 16)


## Hangs a rope (ladder tiles) from `cell` upward. Returns number of cells.
func place_rope(cell: Vector2i, max_length: int) -> int:
	var count := 0
	var y := cell.y
	# Also cover the cell at the feet so the rope can be grabbed from the ground.
	if layout.get_tile(cell.x, y + 1) == T.EMPTY:
		y += 1
	while count < max_length and layout.get_tile(cell.x, y) == T.EMPTY:
		layout.set_tile(cell.x, y, T.LADDER)
		_refresh_around(Vector2i(cell.x, y))
		count += 1
		y -= 1
	return count


func add_entity(node: Node2D, world_pos: Vector2) -> void:
	entities.add_child(node)
	node.global_position = world_pos


func _debris(pos: Vector2, amount: int = 10) -> void:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = amount
	p.lifetime = 0.6
	p.explosiveness = 1.0
	p.spread = 180.0
	p.direction = Vector2.UP
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 110.0
	p.gravity = Vector2(0, 400)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	p.color = Color(0.45, 0.33, 0.27)
	entities.add_child(p)
	p.global_position = pos
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)


# ----------------------------------------------------------------- spawning
func _spawn_door() -> void:
	var door := (load(DOOR_SCENE) as PackedScene).instantiate()
	add_entity(door, cell_bottom(layout.exit_cell))


## Merchant and random-event rooms reserved by the generator.
func _spawn_specials() -> void:
	for info in layout.specials:
		match info["type"]:
			&"merchant":
				var m: Merchant = (load(MERCHANT_SCENE) as PackedScene).instantiate()
				m.floor_number = floor_number
				add_entity(m, cell_bottom(info["cell"]))


func _spawn_chests() -> void:
	for info in layout.chests:
		var chest := (load(CHEST_SCENE) as PackedScene).instantiate()
		chest.tier = info["tier"]
		chest.floor_number = floor_number
		add_entity(chest, cell_bottom(info["cell"]))


## Decoration only: wall torches (one per room at most) and ceiling drips.
func _spawn_ambience() -> void:
	var rw := LevelGenerator.ROOM_W
	var rh := LevelGenerator.ROOM_H
	for ry in range(layout.height / rh):
		for rx in range(layout.width / rw):
			if rng.randf() < 0.75:
				var x := rx * rw + rng.randi_range(3, rw - 4)
				var y := (ry + 1) * rh - 4
				if layout.get_tile(x, y) == T.EMPTY and layout.get_tile(x, y + 1) == T.EMPTY:
					var torch: WallTorch = (load(TORCH_SCENE) as PackedScene).instantiate()
					if biome:
						torch.light_color = biome.torch_color
					add_entity(torch, cell_bottom(Vector2i(x, y)))
			if rng.randf() < 0.6:
				var x := rx * rw + rng.randi_range(2, rw - 3)
				var y := ry * rh + 1
				if layout.get_tile(x, y) == T.EMPTY and LevelLayout.is_solid(layout.get_tile(x, y - 1)):
					var drip: WaterDrip = (load(DRIP_SCENE) as PackedScene).instantiate()
					drip.level = self
					add_entity(drip, cell_center(Vector2i(x, y)) + Vector2(0, -6))


## Bones, cobwebs, crystals, statues... from BiomeData.decorations.
func _spawn_decorations() -> void:
	if biome == null or biome.decorations.is_empty():
		return
	var weights: Array[float] = []
	for d in biome.decorations:
		weights.append(d.weight)
	var rooms := (layout.width / LevelGenerator.ROOM_W) * (layout.height / LevelGenerator.ROOM_H)
	var count := roundi(rooms * biome.decor_per_room)
	var used := {}
	var tries := 0
	while count > 0 and tries < count * 20:
		tries += 1
		var data: DecorData = biome.decorations[LootTable._weighted_index(weights, rng)]
		var cell := Vector2i(rng.randi_range(1, layout.width - 2), rng.randi_range(1, layout.height - 2))
		if used.has(cell) or layout.get_tile(cell.x, cell.y) != T.EMPTY or cell == layout.exit_cell:
			continue
		var tall := data.texture.get_height() > TILE
		var pos: Vector2
		if data.placement == DecorData.Placement.FLOOR:
			if layout.get_tile(cell.x, cell.y + 1) != T.BRICK or (tall and layout.get_tile(cell.x, cell.y - 1) != T.EMPTY):
				continue
			pos = cell_bottom(cell)
		else:
			if not LevelLayout.is_solid(layout.get_tile(cell.x, cell.y - 1)):
				continue
			pos = cell_center(cell) - Vector2(0, TILE / 2.0)
		used[cell] = true
		var deco := Decoration.new()
		deco.data = data
		add_entity(deco, pos)
		count -= 1


## Traps from ItemDatabase.traps_for_floor(): more on deeper floors.
func _spawn_traps() -> void:
	var pool := ItemDatabase.traps_for_floor(floor_number, biome.id if biome else &"")
	if pool.is_empty():
		return
	var weights: Array[float] = []
	for t in pool:
		weights.append(t.weight)
	var rooms := (layout.width / LevelGenerator.ROOM_W) * (layout.height / LevelGenerator.ROOM_H)
	var count := mini(2 + floor_number, rooms + 2)
	var used := {}
	for c in layout.chests:
		used[c["cell"]] = true
	used[layout.exit_cell] = true
	for info in layout.specials:
		for dx in range(-3, 4):
			used[info["cell"] + Vector2i(dx, 0)] = true
	var walls: Array[Trap] = []
	var plates: Array[Trap] = []
	var tries := 0
	while count > 0 and tries < 400:
		tries += 1
		var data: TrapData = pool[LootTable._weighted_index(weights, rng)]
		var placed := _place_trap(data, used)
		if placed:
			count -= 1
			if data.kind == TrapData.Kind.ARROW_WALL:
				walls.append(placed)
			elif data.kind == TrapData.Kind.PRESSURE_PLATE:
				plates.append(placed)
	# Plates fire the nearest arrow wall in their row.
	for plate in plates:
		for w in walls:
			if absf(w.global_position.y - plate.global_position.y) < 2.0 and absf(w.global_position.x - plate.global_position.x) < TILE * 12:
				plate.linked = w


func _place_trap(data: TrapData, used: Dictionary) -> Trap:
	var cell := Vector2i(rng.randi_range(2, layout.width - 3), rng.randi_range(2, layout.height - 3))
	if used.has(cell) or layout.get_tile(cell.x, cell.y) != T.EMPTY:
		return null
	if Vector2(cell).distance_to(Vector2(layout.start_cell)) < SAFE_START_RADIUS:
		return null
	var below := layout.get_tile(cell.x, cell.y + 1)
	var trap: Trap = (load(TRAP_SCENE) as PackedScene).instantiate()
	trap.setup(data, floor_number)
	var pos: Vector2
	match data.kind:
		TrapData.Kind.SPIKES, TrapData.Kind.PRESSURE_PLATE, TrapData.Kind.ACID_POOL:
			if below != T.BRICK or LevelLayout.is_ladder(layout.get_tile(cell.x, cell.y - 1)):
				trap.free()
				return null
			pos = cell_bottom(cell)
		TrapData.Kind.FALLING_ROCK:
			if not LevelLayout.is_solid(layout.get_tile(cell.x, cell.y - 1)):
				trap.free()
				return null
			# Something to fall on within a few cells.
			var floor_found := false
			for dy in range(1, 7):
				if LevelLayout.is_ground(layout.get_tile(cell.x, cell.y + dy)):
					floor_found = true
					break
			if not floor_found:
				trap.free()
				return null
			pos = to_global(Vector2(cell.x * TILE + TILE / 2.0, cell.y * TILE))
		TrapData.Kind.ARROW_WALL:
			# Mounted in front of a wall, on the floor level of a corridor.
			if below != T.BRICK:
				trap.free()
				return null
			var left_wall := LevelLayout.is_solid(layout.get_tile(cell.x - 1, cell.y))
			var right_wall := LevelLayout.is_solid(layout.get_tile(cell.x + 1, cell.y))
			if left_wall == right_wall:
				trap.free()
				return null
			trap.facing = 1.0 if left_wall else -1.0
			pos = cell_bottom(cell)
	used[cell] = true
	add_entity(trap, pos)
	return trap


func _spawn_enemies() -> void:
	var pool := ItemDatabase.enemies_for_floor(floor_number, biome.id if biome else &"")
	if pool.is_empty():
		return
	var weights: Array[float] = []
	for e in pool:
		weights.append(e.spawn_weight)
	for cell in layout.enemy_cells:
		var data: EnemyData = pool[LootTable._weighted_index(weights, rng)]
		var enemy := (load(ENEMY_SCENE) as PackedScene).instantiate()
		enemy.setup(data, floor_number)
		var pos := cell_bottom(cell)
		if data.behavior == EnemyData.Behavior.FLYER:
			pos.y -= TILE * 2
		add_entity(enemy, pos)
