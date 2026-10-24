class_name MinibossGate
extends Node
## The floor guardian's room: while the hero is outside, the champion waits
## motionless inside. When the hero steps deep enough into the room, every
## opening slams shut - doorways AND ladders - behind falling portcullises
## (bedrock under them for physics), and they reopen when the champion dies.

const BARS := preload("res://assets/sprites/props/gate_bars.png")
const T := LevelLayout.Tile

var level: DungeonLevel
var champion: Enemy
## Interior cells of the room (Rect2i in cell coords).
var room_cells: Rect2i
## Guest copy: no local trigger, closes/opens on the host's broadcasts.
var networked := false

var _closed := false
## Every opening cell in the room ring: cell -> original tile (EMPTY or a
## ladder - ladders seal shut too, and restore afterwards).
var _seals: Dictionary = {}
var _bars: Array[Sprite2D] = []


func _ready() -> void:
	add_to_group("miniboss_gates")
	var ring := Rect2i(room_cells.position - Vector2i.ONE, room_cells.size + Vector2i(2, 2))
	var t := level.layout
	for y in range(ring.position.y, ring.end.y):
		for x in range(ring.position.x, ring.end.x):
			var on_ring := x == ring.position.x or x == ring.end.x - 1 or y == ring.position.y or y == ring.end.y - 1
			if not on_ring:
				continue
			var tile: int = t.get_tile(x, y)
			if tile == T.EMPTY or LevelLayout.is_ladder(tile):
				_seals[Vector2i(x, y)] = tile
	set_physics_process(not networked)


func _physics_process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null:
		return
	if _closed:
		if not is_instance_valid(champion) or champion.is_dead():
			_open()
		return
	# The guardian stands guard - asleep on its post - until the doors slam.
	if is_instance_valid(champion):
		champion.held = true
	# Trigger only when the hero is well inside, never standing in an opening.
	var c := level.world_to_cell(player.global_position)
	var inner := Rect2i(room_cells.position + Vector2i(2, 2), room_cells.size - Vector2i(4, 2))  # bottom rows stay: the hero walks there
	if inner.has_point(c):
		_close()


func _close() -> void:
	_closed = true
	if is_instance_valid(champion):
		champion.held = false
	for cell: Vector2i in _seals:
		# apply_remote_tile records the change: late joiners get the seals.
		level.apply_remote_tile(cell, T.BEDROCK)
		var bars := Sprite2D.new()
		bars.texture = BARS
		bars.centered = false
		bars.z_index = 14
		level.entities.add_child(bars)
		var base := level.cell_bottom(cell) - Vector2(DungeonLevel.TILE / 2.0, DungeonLevel.TILE)
		bars.global_position = base + Vector2(0, -26.0)
		bars.modulate = Color(1, 1, 1, 0.0)
		var tw := bars.create_tween()
		tw.tween_property(bars, "position:y", base.y, 0.13).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(bars, "modulate:a", 1.0, 0.1)
		_bars.append(bars)
	AudioManager.play_sfx(&"chest_locked", champion.global_position if champion else Vector2.ZERO)
	AudioManager.play_sfx(&"dig", champion.global_position if champion else Vector2.ZERO, -4.0)
	EventBus.screen_shake.emit(4.0)
	EventBus.message.emit("Двери захлопнулись! Страж этажа преграждает путь")
	_net_broadcast(true)


func _open() -> void:
	_closed = false
	for cell: Vector2i in _seals:
		level.apply_remote_tile(cell, _seals[cell])
	for bars in _bars:
		if is_instance_valid(bars):
			var tw := bars.create_tween()
			tw.tween_property(bars, "modulate:a", 0.0, 0.25)
			tw.tween_callback(bars.queue_free)
	_bars.clear()
	AudioManager.play_sfx(&"ui_book_open", Vector2.ZERO, -4.0)
	EventBus.message.emit("Страж пал — двери открылись")
	set_physics_process(false)
	_net_broadcast(false)
	queue_free()


## The host decides; guest copies receive this through the NetSync broadcasts.
func net_close() -> void:
	if not _closed:
		_close()


func net_open() -> void:
	if _closed:
		_open()


func _net_broadcast(closed: bool) -> void:
	if not Net.active or not Net.is_host:
		return
	var ns := get_tree().get_first_node_in_group("net_game") as NetSync
	if ns:
		ns.broadcast_gate(closed)
