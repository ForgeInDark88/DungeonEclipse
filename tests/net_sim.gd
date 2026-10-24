extends Node
## LAN co-op smoke test: run one process as the host and one as the client.
##   NET_ROLE=host godot --headless --path . res://tests/net_sim.tscn
##   NET_ROLE=client godot --headless --path . res://tests/net_sim.tscn
## The client connects over 127.0.0.1; both sides check registration and
## the co-op difficulty scaling, then report PASS/FAIL and exit.

var _fails := 0
var _done := false


func check(cond: bool, what: String) -> void:
	if cond:
		print("PASS: ", what)
	else:
		_fails += 1
		print("FAIL: ", what)


func _ready() -> void:
	var role := OS.get_environment("NET_ROLE")
	if role == "host":
		_run_host()
	else:
		_run_client()


func _run_host() -> void:
	Net.my_info = {"name": "Хост", "race": &"human", "cls": &"warrior", "female": false}
	check(Net.host_game(), "host opened the game port")
	var t := Timer.new()
	t.autostart = true
	t.wait_time = 1.0
	t.timeout.connect(func() -> void:
		if _done:
			return
		if Net.players.size() >= 2:
			_done = true
			check(true, "client registered on the host")
			check(Net.players.size() == 2, "roster has 2 players")
			check(absf(Net.enemy_hp_mult() - 1.4) < 0.01, "enemy hp mult x1.4 for 2 players (got %.2f)" % Net.enemy_hp_mult())
			check(absf(Net.enemy_damage_mult() - 1.25) < 0.01, "enemy damage mult x1.25 for 2 players")
			# Both sides agree on the roster.
			check(Net.players[1]["name"] == "Хост", "host entry present")
			for id in Net.players:
				if id != 1:
					check(Net.players[id]["name"].begins_with("Гость"), "guest entry present")
			print("RESULT: ", "OK" if _fails == 0 else "%d FAILURES" % _fails)
			# Hold the door a moment so the client finishes its own checks.
			await get_tree().create_timer(2.0).timeout
			get_tree().quit(1 if _fails > 0 else 0))
	add_child(t)
	# Give up after 15 s.
	get_tree().create_timer(15.0).timeout.connect(func() -> void:
		if not _done:
			check(false, "client never connected")
			print("RESULT: FAILURES")
			get_tree().quit(1))


func _run_client() -> void:
	Net.my_info = {"name": "Гость-7", "race": &"elf", "cls": &"mage", "female": true}
	var joined := false
	multiplayer.connected_to_server.connect(func() -> void: print("DBG: connected_to_server"))
	multiplayer.connection_failed.connect(func() -> void: print("DBG: connection_failed"))
	multiplayer.server_disconnected.connect(func() -> void: print("DBG: server_disconnected"))
	var t := Timer.new()
	t.autostart = true
	t.wait_time = 0.5
	t.timeout.connect(func() -> void:
		if joined or _done:
			return
		if Net.players.size() >= 2:
			joined = true
			_done = true
			check(true, "client sees the full roster")
			check(absf(Net.enemy_hp_mult() - 1.4) < 0.01, "client agrees on hp mult")
			print("RESULT: ", "OK" if _fails == 0 else "%d FAILURES" % _fails)
			get_tree().quit(1 if _fails > 0 else 0))
	add_child(t)
	# A short delay so the host is listening first.
	get_tree().create_timer(0.8).timeout.connect(func() -> void:
		var ok := Net.join_game("127.0.0.1")
		print("DBG: join_game -> ", ok)
		if not ok:
			check(false, "join_game failed")
			print("RESULT: FAILURES")
			get_tree().quit(1))
	get_tree().create_timer(15.0).timeout.connect(func() -> void:
		if not _done:
			check(false, "never saw the roster")
			print("RESULT: FAILURES")
			get_tree().quit(1))
