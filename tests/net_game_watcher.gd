class_name NetGameWatcher
extends Node
## The persistent half of tests/net_game_sim.gd — survives scene changes.

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


func _finish(code_holds := 2.0) -> void:
	print("RESULT: ", "OK" if _fails == 0 else "%d FAILURES" % _fails)
	await get_tree().create_timer(code_holds).timeout
	get_tree().quit(1 if _fails > 0 else 0)


func _run_host() -> void:
	Net.my_info = {"name": "Хост", "race": &"human", "cls": &"warrior", "female": false}
	check(Net.host_game(), "host: port open")
	var race: RaceData = ItemDatabase.races[0]
	var cls: ClassData = ItemDatabase.classes[0]
	GameState.start_new_run(race, cls, 12345, false, &"normal")
	GameState.next_floor()  # descend to floor 1 so the guest joins a dungeon
	var t := Timer.new()
	t.autostart = true
	t.wait_time = 1.0
	t.timeout.connect(func() -> void:
		if _done or Net.players.size() < 2:
			return
		_done = true
		await get_tree().create_timer(3.0).timeout
		var scene := get_tree().current_scene
		var np: Node = scene.net_players if scene != null and "net_players" in scene else null
		check(np != null and np.get_child_count() >= 2, "host sees the guest puppet (%d)" % (np.get_child_count() if np else 0))
		_finish())
	add_child(t)
	get_tree().create_timer(20.0).timeout.connect(func() -> void:
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
		var scene := get_tree().current_scene
		print("PULSE: scene=%s floor=%d active=%s players=%d" % [scene.name if scene else "none", GameState.floor_number, GameState.run_active, Net.players.size()])
		if scene == null or not ("net_sync" in scene) or scene.net_sync == null:
			return
		if GameState.floor_number < 1:
			return
		_done = true
		await get_tree().create_timer(2.0).timeout
		scene = get_tree().current_scene
		check(GameState.run_active, "client: run active")
		check(GameState.floor_number >= 1, "client: inside the dungeon (floor %d)" % GameState.floor_number)
		var ns: Node = scene.net_sync if "net_sync" in scene else null
		var group_mobs := get_tree().get_nodes_in_group("enemies").size()
		var shells: int = ns.enemies.size() if ns != null else -1
		print("DBG: floor=%d run_seed=%d group_mobs=%d registered=%d net_game_group=%d" % [GameState.floor_number, GameState.run_seed, group_mobs, shells, get_tree().get_nodes_in_group("net_game").size()])
		check(ns != null and shells > 0, "client sees mobs (%d shells, %d in group)" % [shells, group_mobs])
		var np: Node = scene.net_players if "net_players" in scene else null
		check(np != null and np.get_child_count() >= 2, "client sees the host puppet (%d players)" % (np.get_child_count() if np else 0))
		_finish(0.5))
	add_child(t)
	get_tree().create_timer(1.0).timeout.connect(func() -> void:
		var ok := Net.join_game("127.0.0.1")
		print("DBG: join -> ", ok))
	get_tree().create_timer(18.0).timeout.connect(func() -> void:
		if not _done:
			check(false, "client: never entered the game")
			_finish(0.5))
