extends Node
## Scripted monster-AI scenarios on small hand-made levels:
##   godot --headless --fixed-fps 60 --path . res://tests/ai_behaviour_test.tscn
## Each scenario builds a LevelLayout in code, places a hero and a monster and
## checks one behaviour (navigation, sight, memory, hearing, no hits through walls).

const LEVEL_SCENE := preload("res://scenes/levels/dungeon_level.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const ENEMY_SCENE := preload("res://scenes/enemies/enemy.tscn")
const T = LevelLayout.Tile

var failures: Array[String] = []
var level: DungeonLevel
var player: Player


func check(cond: bool, msg: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + msg)
	if not cond:
		failures.append(msg)


func _ready() -> void:
	MetaProgress.apply_upgrades = false
	await _scenario("jump over spikes", _spikes)
	await _scenario("jump up a ledge", _ledge)
	await _scenario("climb a ladder", _ladder)
	await _scenario("walls block sight", _sight)
	await _scenario("memory, search, return", _memory)
	await _scenario("hearing", _hearing)
	await _scenario("graph rebuilt after digging", _digging)
	await _scenario("flyer goes around a wall", _flyer)
	await _scenario("ranged keeps distance", _ranged)
	await _scenario("no slam through a wall", _wall_slam)
	await _scenario("deep floors: calling allies", _coordination)
	await _scenario("anti-stuck: repath, maneuver, teleport", _anti_stuck)
	print("FAILURES: ", failures.size())
	for f in failures:
		print("  - ", f)
	get_tree().quit(1 if failures.size() > 0 else 0)


func _scenario(title: String, body: Callable) -> void:
	print("== ", title)
	seed(1234)
	await body.call()
	if is_instance_valid(player):
		player.queue_free()
	if is_instance_valid(level):
		level.queue_free()
	await get_tree().physics_frame


## Room 30×12: bedrock border, floor bricks in row 10 (feet stand in row 9).
func _room() -> LevelLayout:
	var l := LevelLayout.new(30, 12, T.EMPTY)
	for x in l.width:
		l.set_tile(x, 0, T.BEDROCK)
		l.set_tile(x, l.height - 1, T.BEDROCK)
		l.set_tile(x, 10, T.BRICK)
	for y in l.height:
		l.set_tile(0, y, T.BEDROCK)
		l.set_tile(l.width - 1, y, T.BEDROCK)
	l.start_cell = Vector2i(2, 9)
	l.exit_cell = Vector2i(27, 9)
	return l


func _build(l: LevelLayout, hero_cell: Vector2i) -> void:
	level = LEVEL_SCENE.instantiate()
	add_child(level)
	l.is_arena = true  # no random content: we place everything ourselves
	level.build(l, 1, 1, null)
	for n in level.entities.get_children():
		n.queue_free()  # arena door / boss
	var hero := Hero.new(ItemDatabase.races[0], ItemDatabase.classes[0], ItemDatabase.equipment_layout)
	GameState.hero = hero
	player = PLAYER_SCENE.instantiate()
	add_child(player)
	player.setup(hero, null)
	player.set_level(level)
	player.global_position = level.cell_bottom(hero_cell)
	await get_tree().physics_frame


func _enemy(id: StringName, cell: Vector2i, floor_number: int = 1) -> Enemy:
	var data: EnemyData = null
	for e in ItemDatabase.enemies:
		if e.id == id:
			data = e
	var e: Enemy = ENEMY_SCENE.instantiate()
	e.setup(data, floor_number)
	level.add_entity(e, level.cell_bottom(cell) + (Vector2(0, -8) if data.behavior == EnemyData.Behavior.FLYER else Vector2.ZERO))
	return e


func _run(seconds: float, until: Callable = Callable()) -> void:
	for i in int(seconds * 60):
		if is_instance_valid(player):
			player._invulnerable = 999.0
			player.hero.stats.hp = player.hero.stats.max_hp()
		await get_tree().physics_frame
		if until.is_valid() and until.call():
			return


# --------------------------------------------------------------- scenarios
func _spikes() -> void:
	var l := _room()
	await _build(l, Vector2i(20, 9))
	level.nav.set_danger(Vector2i(10, 9), LevelNav.Danger.FORBIDDEN, 50.0)
	level.nav._apply_dangers()
	var path := level.nav.ground_path(Vector2i(3, 9), Vector2i(20, 9), 2)
	var cells := path.map(func(p: Dictionary) -> Vector2i: return p["cell"])
	var kinds := path.map(func(p: Dictionary) -> int: return p["kind"])
	check(not cells.has(Vector2i(10, 9)) and kinds.has(LevelNav.Edge.JUMP), "path jumps over the spike cell")
	var e := _enemy(&"skeleton", Vector2i(3, 9))
	e.hear(player.global_position)
	await _run(8.0, func() -> bool: return level.world_to_cell(e.global_position).x >= 16)
	check(level.world_to_cell(e.global_position).x >= 16, "skeleton crossed the spikes (cell %s)" % level.world_to_cell(e.global_position))
	check(e.danger_time == 0.0, "never stood on the spikes")


func _ledge() -> void:
	var l := _room()
	for x in range(15, 29):
		for y in range(8, 10):
			l.set_tile(x, y, T.BRICK)  # step 2 cells up
	await _build(l, Vector2i(22, 7))
	var e := _enemy(&"skeleton", Vector2i(4, 9))
	e.hear(player.global_position)
	await _run(14.0, func() -> bool: return level.world_to_cell(e.global_position + Vector2(0, -2)).x >= 17 and e.is_on_floor())
	var c := level.world_to_cell(e.global_position + Vector2(0, -2))
	check(c.x >= 17 and c.y == 7, "skeleton jumped up the ledge (cell %s)" % c)


func _ladder() -> void:
	var l := _room()
	for x in range(13, 29):
		l.set_tile(x, 5, T.BRICK)  # upper floor, 5 rows up: only the ladder leads there
	l.set_tile(12, 5, T.LADDER_TOP)
	for y in range(6, 10):
		l.set_tile(12, y, T.LADDER)
	await _build(l, Vector2i(20, 4))
	var e := _enemy(&"skeleton", Vector2i(4, 9))
	e.hear(player.global_position)
	await _run(12.0, func() -> bool: return level.world_to_cell(e.global_position + Vector2(0, -2)).y <= 4)
	var c := level.world_to_cell(e.global_position + Vector2(0, -2))
	check(c.y <= 4, "skeleton climbed the ladder (cell %s)" % c)


func _sight() -> void:
	var l := _room()
	for y in range(1, 10):
		l.set_tile(12, y, T.BRICK)
	await _build(l, Vector2i(16, 9))
	var e := _enemy(&"skeleton", Vector2i(9, 9))
	e.sprite.flip_h = false
	await _run(0.5)
	check(not e._can_see_player(), "no sight through the brick wall")
	level.break_tile(Vector2i(12, 9), false)
	level.break_tile(Vector2i(12, 8), false)
	await _run(0.5)
	check(e._can_see_player(), "sees the hero once the wall is dug through")


func _memory() -> void:
	var l := _room()
	await _build(l, Vector2i(12, 9))
	var e := _enemy(&"skeleton", Vector2i(6, 9))
	await _run(2.0, func() -> bool: return e.state == Enemy.State.CHASE)
	check(e.state == Enemy.State.CHASE, "notices and chases (%s)" % e.state_name())
	# The hero vanishes behind a wall far away: the monster goes to the last spot.
	for y in range(1, 10):
		l.set_tile(20, y, T.BRICK)
	level._refresh_around(Vector2i(20, 5))
	level.nav.rebuild()
	player.global_position = level.cell_bottom(Vector2i(26, 9))
	await _run(8.0, func() -> bool: return e.state == Enemy.State.SEARCH)
	check(e.state == Enemy.State.SEARCH, "searches the last seen spot (%s)" % e.state_name())
	await _run(10.0, func() -> bool: return e.state == Enemy.State.PATROL)
	check(e.state == Enemy.State.PATROL, "returns home and patrols again (%s)" % e.state_name())


func _hearing() -> void:
	var l := _room()
	for y in range(1, 10):
		l.set_tile(15, y, T.BRICK)
		l.set_tile(22, y, T.BRICK)
	await _build(l, Vector2i(18, 9))
	var e := _enemy(&"skeleton", Vector2i(8, 9))
	await _run(0.3)
	EventBus.noise.emit(level.cell_bottom(Vector2i(14, 9)), 200.0)
	await _run(0.1)
	check(e.state == Enemy.State.SEARCH, "a loud noise makes it search (%s)" % e.state_name())
	var far := _enemy(&"skeleton", Vector2i(26, 9))
	EventBus.noise.emit(level.cell_bottom(Vector2i(3, 9)), 60.0)
	await _run(0.1)
	check(far.state == Enemy.State.PATROL, "too far to hear (%s)" % far.state_name())


func _digging() -> void:
	var l := _room()
	await _build(l, Vector2i(25, 9))
	var v := level.nav.version
	level.break_tile(Vector2i(10, 10), false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(level.nav.version > v, "nav rebuilt after a brick broke")
	check(not level.nav.standable(10, 9), "the hole is no longer standable")


func _flyer() -> void:
	var l := _room()
	for y in range(1, 8):
		l.set_tile(13, y, T.BRICK)  # wall with a gap at the bottom (rows 8-9)
	await _build(l, Vector2i(22, 9))
	var e := _enemy(&"bat", Vector2i(6, 5))
	e.hear(player.global_position)
	await _run(10.0, func() -> bool: return level.world_to_cell(e.global_position).x >= 16)
	check(level.world_to_cell(e.global_position).x >= 16, "bat flew under the wall (cell %s)" % level.world_to_cell(e.global_position))
	check(e.max_still_time < 2.0, "bat did not hang at the wall (%.1f s)" % e.max_still_time)


func _ranged() -> void:
	var l := _room()
	await _build(l, Vector2i(14, 9))
	var e := _enemy(&"cultist", Vector2i(12, 9))
	e.hear(player.global_position)
	await _run(0.2)
	var d0 := e.global_position.distance_to(player.global_position)
	await _run(2.5)
	var d1 := e.global_position.distance_to(player.global_position)
	check(d1 > d0 + 16.0, "cultist backs off from the hero (%.0f → %.0f px)" % [d0, d1])


func _wall_slam() -> void:
	var l := _room()
	for y in range(1, 10):
		l.set_tile(12, y, T.BRICK)
	await _build(l, Vector2i(13, 9))
	var e := _enemy(&"golem", Vector2i(11, 9))
	await _run(0.2)
	var hp := player.hero.stats.hp
	e._begin_attack()
	for i in 60:
		player._invulnerable = 0.0
		await get_tree().physics_frame
	check(player.hero.stats.hp == hp, "golem slam does not pass through the wall")


func _coordination() -> void:
	var l := _room()
	await _build(l, Vector2i(14, 9))
	var a := _enemy(&"skeleton", Vector2i(10, 9), 10)
	var b := _enemy(&"skeleton", Vector2i(3, 9), 10)
	b.sprite.flip_h = true  # looks away: it can only learn from the call
	a.sprite.flip_h = false
	await _run(1.0, func() -> bool: return a.state != Enemy.State.PATROL)
	check(a.state in [Enemy.State.ALERT, Enemy.State.CHASE], "first skeleton notices the hero (%s)" % a.state_name())
	check(b.state in [Enemy.State.SEARCH, Enemy.State.CHASE, Enemy.State.ALERT], "the ally was called (%s)" % b.state_name())
	var low := _enemy(&"skeleton", Vector2i(3, 9), 1)
	check(low.coordination() == 0.0 and a.coordination() == 1.0, "coordination grows with the floor")


func _anti_stuck() -> void:
	var l := _room()
	await _build(l, Vector2i(24, 9))
	# A crate the navigation does not know about blocks the corridor.
	var crate := StaticBody2D.new()
	crate.collision_layer = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(16, 48)
	shape.shape = rect
	crate.add_child(shape)
	level.add_entity(crate, level.cell_center(Vector2i(12, 8)))
	var e := _enemy(&"golem", Vector2i(9, 9))
	AIDebug.reset()
	e.hear(player.global_position)
	await _run(8.0, func() -> bool: return AIDebug.count("teleport") > 0)
	check(AIDebug.count("repath") > 0 and AIDebug.count("maneuver") > 0, "repath and maneuver tried first")
	check(AIDebug.count("teleport") > 0, "then teleported to a safe node")
	check(e.global_position.is_finite() and level.nav.standable(level.world_to_cell(e.global_position + Vector2(0, -2)).x, level.world_to_cell(e.global_position + Vector2(0, -2)).y, 2), "landed on a standable cell")
