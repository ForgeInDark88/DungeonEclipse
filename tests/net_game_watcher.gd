extends Node
## The persistent half of tests/net_game_sim.gd - survives scene changes.
## Phase 1: guest joins mid-run, both sides see puppets and mob shells.
## Phase 2: each side teleports its own hero; the other side's puppet must
## move accordingly (live position replication both ways).

var is_host := false
var _fails := 0
var _done := false


func check(cond: bool, what: String) -> void:
	if cond:
		print("PASS: ", what)
	else:
		_fails += 1
		print("FAIL: ", what)


func _ready() -> void:
	if is_host:
		_run_host()
	else:
		_run_client()


func _finish(hold := 2.0) -> void:
	print("RESULT: ", "OK" if _fails == 0 else "%d FAILURES" % _fails)
	await get_tree().create_timer(hold).timeout
	get_tree().quit(1 if _fails > 0 else 0)


func _game() -> Node:
	var scene := get_tree().current_scene
	if scene != null and "net_players" in scene:
		return scene
	return null


func _my_player() -> Player:
	for n in get_tree().get_nodes_in_group("player"):
		var pl := n as Player
		if pl != null and not pl.puppet:
			return pl
	return null


func _their_puppet(my_id: int) -> Player:
	var g := _game()
	if g == null or g.net_players == null:
		return null
	for n in g.net_players.get_children():
		var pl := n as Player
		if pl != null and pl.peer_id != my_id:
			return pl
	return null


## Shared: once the game scene is up, run checks and the movement phase.
func _watch_game() -> void:
	var my_id := Net.multiplayer.get_unique_id()
	await get_tree().create_timer(2.0).timeout
	var g := _game()
	check(GameState.run_active, "run active")
	var ns: Node = g.net_sync if g != null else null
	var shells: int = ns.enemies.size() if ns != null else -1
	check(shells > 0, "mob shells registered (%d)" % shells)
	var mine := _my_player()
	var theirs := _their_puppet(my_id)
	check(mine != null, "own player exists")
	check(theirs != null, "the other hero's puppet exists")
	if mine == null or theirs == null:
		_finish(0.5)
		return
	# --- live movement phase
	var start := theirs.global_position
	mine.global_position += Vector2(150, 0)
	await get_tree().create_timer(2.5).timeout
	var moved := absf(theirs.global_position.x - start.x)
	check(moved > 40.0, "the other hero's puppet moved (%.0f px)" % moved)
	_finish()


func _run_host() -> void:
	Net.my_info = {"name": "Хост", "race": &"human", "cls": &"warrior", "female": false}
	check(Net.host_game(), "host: port open")
	var race: RaceData = ItemDatabase.races[0]
	var cls: ClassData = ItemDatabase.classes[0]
	GameState.start_new_run(race, cls, 12345, false, &"normal")
	GameState.next_floor()
	var t := Timer.new()
	t.autostart = true
	t.wait_time = 1.0
	t.timeout.connect(func() -> void:
		if _done or Net.players.size() < 2:
			return
		_done = true
		_watch_game())
	add_child(t)
	get_tree().create_timer(25.0).timeout.connect(func() -> void:
		if not _done:
			check(false, "host: guest never joined")
			_finish(0.5))


func _run_client() -> void:
	Net.my_info = {"name": "Гость", "race": &"elf", "cls": &"mage", "female": true}
	var t := Timer.new()
	t.autostart = true
	t.wait_time = 1.0
	t.timeout.connect(func() -> void:
		if _done:
			return
		var g := _game()
		if g == null or g.net_sync == null or GameState.floor_number < 1:
			return
		_done = true
		_watch_game())
	add_child(t)
	get_tree().create_timer(1.0).timeout.connect(func() -> void:
		var ok := Net.join_game("127.0.0.1")
		print("DBG: join -> ", ok))
	get_tree().create_timer(25.0).timeout.connect(func() -> void:
		if not _done:
			check(false, "client: never entered the game")
			_finish(0.5))
