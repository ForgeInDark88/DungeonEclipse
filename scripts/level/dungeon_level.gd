class_name DungeonLevel
extends Node2D
## One dungeon floor in the world: tile layers built from a LevelLayout,
## plus every entity of the floor (chests, enemies, door, drops, projectiles).
## Freed as a whole when the hero goes down to the next floor.

const TILE := 16
const CHEST_SCENE := preload("res://scenes/world/chest.tscn")
const ENEMY_SCENE := preload("res://scenes/enemies/enemy.tscn")
const DOOR_SCENE := preload("res://scenes/world/exit_door.tscn")
const T = LevelLayout.Tile

@onready var back: TileMapLayer = $Back
@onready var tiles: TileMapLayer = $Tiles
@onready var entities: Node2D = $Entities

var layout: LevelLayout
var floor_number: int = 1
var rng := RandomNumberGenerator.new()


func build(p_layout: LevelLayout, p_floor: int, seed_value: int) -> void:
	layout = p_layout
	floor_number = p_floor
	rng.seed = seed_value
	var ts := TilesetBuilder.get_tileset()
	back.tile_set = ts
	tiles.tile_set = ts
	for y in layout.height:
		for x in layout.width:
			var cell := Vector2i(x, y)
			back.set_cell(cell, TilesetBuilder.SOURCE_ID, AssetPaths.TILE_BACKWALL)
			_apply_tile(cell, layout.get_tile(x, y))
	_spawn_door()
	_spawn_chests()
	_spawn_enemies()


func _apply_tile(cell: Vector2i, kind: int) -> void:
	var t := TilesetBuilder.tile_for(kind)
	if t[0] == Vector2i(-1, -1):
		tiles.erase_cell(cell)
	else:
		tiles.set_cell(cell, TilesetBuilder.SOURCE_ID, t[0], t[1])


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
	_apply_tile(cell, T.EMPTY)
	if effects:
		_debris(cell_center(cell))
		# Sometimes there is something inside the wall.
		if rng.randf() < 0.08:
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


## Hangs a rope (ladder tiles) from `cell` upward. Returns number of cells.
func place_rope(cell: Vector2i, max_length: int) -> int:
	var count := 0
	var y := cell.y
	# Also cover the cell at the feet so the rope can be grabbed from the ground.
	if layout.get_tile(cell.x, y + 1) == T.EMPTY:
		y += 1
	while count < max_length and layout.get_tile(cell.x, y) == T.EMPTY:
		layout.set_tile(cell.x, y, T.LADDER)
		_apply_tile(Vector2i(cell.x, y), T.LADDER)
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
	var door := DOOR_SCENE.instantiate()
	add_entity(door, cell_bottom(layout.exit_cell))


func _spawn_chests() -> void:
	for info in layout.chests:
		var chest := CHEST_SCENE.instantiate()
		chest.tier = info["tier"]
		chest.floor_number = floor_number
		add_entity(chest, cell_bottom(info["cell"]))


func _spawn_enemies() -> void:
	var pool := ItemDatabase.enemies_for_floor(floor_number)
	if pool.is_empty():
		return
	var weights: Array[float] = []
	for e in pool:
		weights.append(e.spawn_weight)
	for cell in layout.enemy_cells:
		var data: EnemyData = pool[LootTable._weighted_index(weights, rng)]
		var enemy := ENEMY_SCENE.instantiate()
		enemy.setup(data, floor_number)
		var pos := cell_bottom(cell)
		if data.behavior == EnemyData.Behavior.FLYER:
			pos.y -= TILE * 2
		add_entity(enemy, pos)
