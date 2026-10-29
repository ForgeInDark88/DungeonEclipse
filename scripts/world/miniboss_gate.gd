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
## Which gate of the floor (DungeonLevel numbers them in build order).
var gate_id := 0
## Ambush room: no champion - the doors slam and WAVES of monsters pour in
## (spawned by the host at `ambush_cells`); when the last wave falls the
## doors open and a relic altar rises (on every machine: relics are personal).
var ambush := false
var ambush_cells: Array[Vector2i] = []
const WAVES := 3
var _wave := 0
var _alive: Array[Enemy] = []
var _wave_delay := 0.0

var _closed := false
## Seconds after the floor build before the seal may trigger: everyone is
## still transitioning floors and may report stale positions.
var _arm_time := 4.0
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


func _physics_process(delta: float) -> void:
	if _closed:
		if ambush:
			_ambush_step(delta)
		elif not is_instance_valid(champion) or champion.is_dead():
			_open()
		return
	# Grace period after the floor build: guests may still report positions
	# from the previous floor, and a stale point can land inside the room -
	# never slam the bars on a ghost.
	_arm_time -= delta
	if _arm_time > 0.0:
		if is_instance_valid(champion):
			champion.held = true
		return
	var intruder := false
	for n in get_tree().get_nodes_in_group("player"):
		var player := n as Player
		# Any hero counts - including a guest's puppet on the host machine.
		if player == null or player.dead:
			continue
		# Trigger only when the hero is well inside, never standing in an opening.
		var c := level.world_to_cell(player.global_position)
		var inner := Rect2i(room_cells.position + Vector2i(2, 2), room_cells.size - Vector2i(4, 2))  # bottom rows stay: the hero walks there
		if inner.has_point(c):
			intruder = true
			break
	if intruder:
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
	var at := _center()
	AudioManager.play_sfx(&"chest_locked", at)
	AudioManager.play_sfx(&"dig", at, -4.0)
	EventBus.screen_shake.emit(4.0)
	if ambush:
		EventBus.message.emit("Засада! Двери захлопнулись — отбейте %d волны" % WAVES)
		AudioManager.play_sfx(&"boss_roar", at, -6.0)
		_wave_delay = 1.0
	else:
		EventBus.message.emit("Двери захлопнулись! Страж этажа преграждает путь")
	_net_broadcast(true)


func _center() -> Vector2:
	if champion and is_instance_valid(champion):
		return champion.global_position
	return level.cell_bottom(room_cells.position + Vector2i(room_cells.size.x / 2, room_cells.size.y - 1))


## Host: the next wave when the room is clear, the doors when all are beaten.
func _ambush_step(delta: float) -> void:
	_alive = _alive.filter(func(e: Enemy) -> bool: return is_instance_valid(e) and not e.is_dead())
	if not _alive.is_empty():
		return
	if _wave >= WAVES:
		_open()
		return
	_wave_delay -= delta
	if _wave_delay > 0.0:
		return
	_wave += 1
	_wave_delay = 1.4
	var count := 3 + level.floor_number / 6 + (_wave - 1)
	_alive = level.spawn_ambush_wave(ambush_cells, count, _wave == WAVES)
	EventBus.message.emit("Волна %d из %d" % [_wave, WAVES])
	for c in ambush_cells.slice(0, mini(4, ambush_cells.size())):
		Fx.sparks(level.entities, level.cell_bottom(c) + Vector2(0, -10), Color(0.75, 0.3, 1.0), 10, 80.0)


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
	if ambush:
		EventBus.message.emit("Засада отбита! Алтарь реликвий ждёт")
		var altar := RelicAltar.new()
		level.add_entity(altar, _center())
	else:
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
		ns.broadcast_gate(closed, gate_id)
