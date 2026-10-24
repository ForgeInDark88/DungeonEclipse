class_name MinibossGate
extends Node
## The floor guardian's room: when the hero steps deep enough inside, every
## doorway slams shut (bedrock seals) and reopens only when the champion dies.

var level: DungeonLevel
var champion: Enemy
## Interior cells of the room (Rect2i in cell coords).
var room_cells: Rect2i

var _closed := false
var _door_cells: Array[Vector2i] = []


func _ready() -> void:
	# The doorway ring: one cell outside the room interior — walls everywhere
	# except the carved openings, those are the cells to seal.
	var ring := Rect2i(room_cells.position - Vector2i.ONE, room_cells.size + Vector2i(2, 2))
	for y in range(ring.position.y, ring.end.y):
		for x in range(ring.position.x, ring.end.x):
			var on_ring := x == ring.position.x or x == ring.end.x - 1 or y == ring.position.y or y == ring.end.y - 1
			if on_ring and level.layout.get_tile(x, y) == LevelLayout.Tile.EMPTY:
				_door_cells.append(Vector2i(x, y))
	set_physics_process(true)


func _physics_process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null:
		return
	if _closed:
		if not is_instance_valid(champion) or champion.is_dead():
			_open()
		return
	# Trigger only when the hero is well inside, never standing in a doorway.
	var c := level.world_to_cell(player.global_position)
	var inner := Rect2i(room_cells.position + Vector2i(2, 2), room_cells.size - Vector2i(4, 4))
	if inner.has_point(c):
		_close()


func _close() -> void:
	_closed = true
	for cell in _door_cells:
		level.layout.set_tile(cell.x, cell.y, LevelLayout.Tile.BEDROCK)
		level._refresh_around(cell)
		level._mark_nav_dirty(cell)
	AudioManager.play_sfx(&"dig", champion.global_position if champion else Vector2.ZERO)
	EventBus.screen_shake.emit(4.0)
	EventBus.message.emit("Двери захлопнулись! Страж этажа преграждает путь")


func _open() -> void:
	_closed = false
	for cell in _door_cells:
		level.layout.set_tile(cell.x, cell.y, LevelLayout.Tile.EMPTY)
		level._refresh_around(cell)
		level._mark_nav_dirty(cell)
	AudioManager.play_sfx(&"dig", Vector2.ZERO)
	EventBus.message.emit("Страж пал — двери открылись")
	set_physics_process(false)
	queue_free()
