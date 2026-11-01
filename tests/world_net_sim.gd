extends SceneTree
## One "machine" of the world session test (tests/world_net.sh starts a host
## and several clients). Env: ROLE host|client, PORT, NICK, PASS, EXPECT
## (ok | a WorldNet fail reason), TOKEN_FILE, PROTOCOL_LIE=1, GOLD_MARK,
## STAY (seconds online), CHECK_GOLD (gold the profile must bring back),
## DENY_PENDING=1 (host refuses new devices), SAVES (host saves dir).

var fails := 0
var pp: Node
var wn: Node
var net: Node
var flow: Node
var role := OS.get_environment("ROLE")
var nick := OS.get_environment("NICK")


func check(c: bool, what: String) -> void:
	print(("PASS: " if c else "FAIL: ") + "[%s] %s" % [nick if role == "client" else "host", what])
	if not c:
		fails += 1


func env_int(k: String, d: int) -> int:
	var v := OS.get_environment(k)
	return int(v) if v != "" else d


func _initialize() -> void:
	await process_frame
	pp = root.get_node("PlayerProfiles")
	wn = root.get_node("WorldNet")
	net = root.get_node("Net")
	flow = root.get_node("GameFlow")
	var sm = root.get_node("SaveManager")
	sm.remember_slot = false
	var tf := OS.get_environment("TOKEN_FILE")
	if tf != "":
		pp.identity_path = tf
	if role == "host":
		await _host()
	else:
		await _client()
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAILURES" % fails))
	quit(1 if fails > 0 else 0)


func _host() -> void:
	var sm = root.get_node("SaveManager")
	var idb = root.get_node("ItemDatabase")
	var gs = root.get_node("GameState")
	sm.saves_dir = OS.get_environment("SAVES") if OS.get_environment("SAVES") != "" else "user://test_net_saves/"
	if env_int("FRESH", 1) == 1:
		sm.delete_slot(1)
		sm.use_slot(1)
		var town := TownState.new()
		Buildings.init_town(town)
		town.world_seed = 777
		if OS.get_environment("WAREHOUSE") == "1":
			town.set_building_level(&"warehouse", 1)
		var hero := Hero.new(idb.races[0], idb.classes[0], idb.equipment_layout)
		hero.give_starting_kit()
		town.hero = RunCodec.save_hero(hero)
		gs.town = town
		sm.save_town(town, {"name": "Сетевой мир"})
	NetSettings.path = "user://test_net_settings_host_%d.cfg" % env_int("PORT", 7790)
	sm.last_name = "Хозяин"
	var err: String = wn.host_world(1, env_int("PORT", 7790), OS.get_environment("PASS"), env_int("SEATS", 3), false)
	check(err == "", "the world is hosted (%s)" % err)
	if OS.get_environment("SCENARIO") == "flow":
		await _host_flow()
		return
	if OS.get_environment("SCENARIO") == "verify":
		check(gs.town.players.has("alice") and pp.hero_of("Alice").gold == 123, "after a restart the host still has Alice's profile")
		await create_timer(float(env_int("STAY", 12))).timeout
		wn.close_session()
		return
	if OS.get_environment("SCENARIO") == "trade":
		await _host_trade()
		return
	if OS.get_environment("SCENARIO") == "coop":
		await _host_coop()
		return
	var kicked := false
	var t := 0.0
	var stay := float(env_int("STAY", 40))
	while t < stay:
		await create_timer(0.25).timeout
		t += 0.25
		if OS.get_environment("DENY_PENDING") == "1":
			for peer in pp.pending.keys():
				pp.deny(peer)
		# kick whoever is called Kickme
		for id in wn.roster.keys():
			if not kicked and wn.roster[id]["nick"] == "Kickme" and wn.roster[id]["status"] == "online":
				await create_timer(4.0).timeout
				wn.kick(id)
				kicked = true
	print("ROSTER: %s" % str(wn.roster.values().map(func(r): return "%s:%s" % [r["nick"], r["status"]])))
	var profiles: Dictionary = gs.town.players
	print("PROFILES: %s" % str(profiles.keys()))
	check(profiles.has("alice") and profiles.has("bob"), "profiles were made for Alice and Bob")
	check(not profiles.has("carl"), "no profile for a refused player")
	var alice: Hero = pp.hero_of("Alice")
	check(alice != null and alice.gold == 123, "Alice's last pushed hero is kept (gold %d)" % (alice.gold if alice else -1))
	check(wn.chat_log.any(func(l): return l[0] == "Alice" and l[1] == "hi from Alice"), "the host got Alice's chat")
	check(kicked, "the host kicked Kickme")
	flow.save_town()
	var back = sm.load_town()
	check(back != null and back.players.has("alice") and RunCodec.load_hero(back.players["alice"]["hero"]).gold == 123,
		"profiles survive the save (restart of the host)")
	wn.close_session()


## Host side of the flow scenario: once a guest is in, lead the party out
## of town, into a node, back to the map, home.
func _host_flow() -> void:
	var gs = root.get_node("GameState")
	var t := 0.0
	while wn.roster.size() < 2 and t < 20.0:
		await create_timer(0.25).timeout
		t += 0.25
	check(wn.roster.size() == 2, "a guest joined")
	await create_timer(2.0).timeout
	flow.open_map()
	await create_timer(2.0).timeout
	var id: int = gs.run.next_choices()[0]
	flow.enter_node(id)
	await create_timer(4.0).timeout
	flow.location_cleared()
	await create_timer(2.5).timeout
	flow.retreat()
	await create_timer(2.5).timeout
	flow.back_to_town()
	await create_timer(3.0).timeout
	check(flow.state == flow.State.TOWN, "the host is back in town")
	wn.close_session()


## Host side of the trade scenario: accept the guest's invite, offer 5 gold,
## confirm; then check what came over, and the guest's safe.
func _host_trade() -> void:
	var gs = root.get_node("GameState")
	var tr_ = wn.trade
	gs.hero.gold = 100
	var st := {"id": 0}
	tr_.invited.connect(func(id: int, _n: String) -> void: st["id"] = id)
	var t := 0.0
	while st["id"] == 0 and t < 25.0:
		await create_timer(0.25).timeout
		t += 0.25
	check(st["id"] != 0, "the host got the guest's trade invite")
	tr_.accept(st["id"])
	await create_timer(1.0).timeout
	tr_.set_offer([], 5)
	await create_timer(1.0).timeout
	tr_.confirm()
	t = 0.0
	while tr_.current != 0 and t < 10.0:
		await create_timer(0.25).timeout
		t += 0.25
	check(gs.hero.gold == 100 - 5 + 10, "the host paid 5 and got 10 gold (%d)" % gs.hero.gold)
	check(gs.hero.inventory.count_of(&"rope") >= 1, "the host got the guest's rope")
	await create_timer(6.0).timeout
	var safe: Array = gs.town.players.get("trader", {}).get("safe", [])
	check(safe.size() == 1, "the guest's personal safe is kept in its profile (%d)" % safe.size())
	wn.close_session()


## The state of the location on this machine: the level's tiles, chests,
## and the enemies (their net ids and kinds) - equal on every machine.
func state_hash() -> String:
	var game = current_scene
	if game == null or not ("level" in game) or game.level == null:
		return "no-level"
	var lvl = game.level
	var chests := []
	for c in root.get_tree().get_nodes_in_group("chests"):
		chests.append([int(c.global_position.x), int(c.global_position.y)])
	chests.sort()
	var foes := []
	var ns = root.get_tree().get_first_node_in_group("net_game")
	if ns:
		for id in ns.enemies:
			var e = ns.enemies[id]
			if is_instance_valid(e):
				foes.append("%d:%s" % [id, e.data.id])
	foes.sort()
	return ("%s|%s|%s" % [lvl.layout.tiles.hex_encode().sha256_text(), str(chests), str(foes)]).sha256_text().left(16) + " foes=%d" % foes.size()


func _make_invulnerable() -> void:
	var game = current_scene
	if game and "player" in game and game.player:
		game.player._invulnerable = 999.0


## Host side of the co-op run: two guests, three locations, hashes.
func _host_coop() -> void:
	var gs = root.get_node("GameState")
	var t := 0.0
	while wn.roster.size() < 3 and t < 30.0:
		await create_timer(0.25).timeout
		t += 0.25
	check(wn.roster.size() == 3, "two guests joined")
	await create_timer(1.5).timeout
	var log_text := str(wn.chat_log)
	check(log_text.contains("Ann") and log_text.contains("Ben"), "the session log tells who came")
	var epic_name := ""
	for id in root.get_node("ItemDatabase").items:
		var it = root.get_node("ItemDatabase").items[id]
		if it.rarity >= ItemData.Rarity.EPIC:
			epic_name = TranslationServer.translate(it.display_name)
			break
	var waited := 0.0
	while not log_text.contains(epic_name) and waited < 10.0:
		await create_timer(0.25).timeout
		waited += 0.25
		log_text = str(wn.chat_log)
	check(epic_name != "" and log_text.contains(epic_name), "the session log tells a guest's find")
	# the generator: one seed, one level
	var a := LevelGenerator.new().generate(7, 99)
	var b := LevelGenerator.new().generate(7, 99)
	check(a.tiles == b.tiles and str(a.chests) == str(b.chests), "the same seed builds the same level")
	await create_timer(2.0).timeout
	flow.open_map()
	await create_timer(2.5).timeout
	for k in 3:
		var id: int = gs.run.next_choices()[0]
		gs.run.map.nodes[id]["type"] = &"level"
		gs.run.map.nodes[id]["sub"] = &""
		flow.enter_node(id)
		await create_timer(9.0).timeout
		_make_invulnerable()
		print("HASH %d: %s" % [k, state_hash()])
		flow.location_cleared()
		await create_timer(3.0).timeout
	flow.retreat()
	await create_timer(2.5).timeout
	flow.back_to_town()
	await create_timer(3.0).timeout
	wn.close_session()


func _client() -> void:
	var expect := OS.get_environment("EXPECT")
	var st := {"done": false, "result": "", "kicked": false}
	wn.join_result.connect(func(okk: bool, reason: String) -> void:
		if reason == "pending":
			return
		if reason == "kicked":
			st["kicked"] = true
		if not st["done"]:
			st["done"] = true
			st["result"] = "ok" if okk else reason)
	wn.hero_needed.connect(func() -> void:
		pp.create_hero(&"human", &"rogue", false))
	if OS.get_environment("PROTOCOL_LIE") == "1":
		wn.protocol_override = 1
	await create_timer(0.2).timeout
	var ok: bool = wn.join_world("127.0.0.1", env_int("PORT", 7790), nick, OS.get_environment("PASS"))
	var t := 0.0
	while not st["done"] and t < 15.0:
		await create_timer(0.2).timeout
		t += 0.2
	check(ok or expect != "ok", "the join started")
	var result: String = st["result"]
	check(result == expect, "join result is '%s' (expected '%s')" % [result, expect])
	if result != "ok":
		return
	await create_timer(1.5).timeout
	var gs = root.get_node("GameState")
	if OS.get_environment("SCENARIO") == "trade":
		var idb = root.get_node("ItemDatabase")
		gs.hero.gold = 50
		gs.hero.inventory.add_item(idb.get_item(&"rope"), 1)
		var ri: int = -1
		for i in gs.hero.inventory.slots.size():
			var s = gs.hero.inventory.slots[i]
			if s and s.item.id == &"rope":
				ri = i
		await create_timer(1.0).timeout
		wn.trade.invite(1)
		var tt := 0.0
		while wn.trade.current == 0 and tt < 10.0:
			await create_timer(0.25).timeout
			tt += 0.25
		check(wn.trade.current != 0, "the trade window opened")
		wn.trade.set_offer([ri], 10)
		await create_timer(1.5).timeout
		wn.trade.confirm()
		tt = 0.0
		while wn.trade.current != 0 and tt < 10.0:
			await create_timer(0.25).timeout
			tt += 0.25
		check(gs.hero.gold == 50 - 10 + 5, "the guest paid 10 and got 5 gold (%d)" % gs.hero.gold)
		check(gs.hero.inventory.count_of(&"rope") == 0, "the rope went to the host")
		# the personal safe: put a bomb in it (the host keeps it in my profile)
		gs.hero.inventory.add_item(idb.get_item(&"bomb"), 1)
		for i in gs.hero.inventory.slots.size():
			var s2 = gs.hero.inventory.slots[i]
			if s2 and s2.item.id == &"bomb":
				wn.town_net.put(gs.hero.inventory.take_at(i))
				break
		await create_timer(3.0).timeout
		check(wn.town_net.safe_cache.size() == 1, "my safe holds the bomb")
		wn.close_session()
		return
	if OS.get_environment("SCENARIO") == "coop":
		if nick == "Ann":
			var wait := 0.0
			while not wn.roster.has(root.get_multiplayer().get_unique_id()) and wait < 10.0:
				await create_timer(0.2).timeout
				wait += 0.2
			for id in root.get_node("ItemDatabase").items:
				if root.get_node("ItemDatabase").items[id].rarity >= ItemData.Rarity.EPIC:
					wn.report(&"found", id)
					break
		var k := 0
		var tt := 0.0
		var printed := {}
		while tt < 60.0 and wn.session:
			await create_timer(0.25).timeout
			tt += 0.25
			_make_invulnerable()
			if flow.state == flow.State.LOCATION and current_scene and "level" in current_scene and current_scene.level:
				var key: int = gs.run.node_id if gs.run else -1
				if not printed.has(key):
					printed[key] = true
					var at := tt
					while tt < at + 7.0:
						await create_timer(0.25).timeout
						tt += 0.25
						_make_invulnerable()
					print("HASH %d: %s" % [k, state_hash()])
					k += 1
		check(k == 3, "the guest went through three locations (%d)" % k)
		return
	if OS.get_environment("SCENARIO") == "flow":
		var seen: Array = []
		flow.state_changed.connect(func(s: int) -> void: seen.append(s))
		var tt := 0.0
		while tt < 24.0:
			await create_timer(0.25).timeout
			tt += 0.25
		var S = flow.State
		print("STATES: %s" % str(seen))
		check(seen.slice(0, 5) == [S.EXPEDITION_MAP, S.LOCATION, S.EXPEDITION_MAP, S.RUN_RESULT, S.TOWN],
			"the guest followed the host: map, location, map, result, town")
		check(gs.run == null and gs.is_town(), "the guest is back in town with the party")
		wn.close_session()
		return
	check(gs.hero != null and gs.town != null, "the guest has its hero and the host's town")
	check(current_scene != null and current_scene.scene_file_path == gs.GAME and gs.is_town(), "the guest walks the host's town")
	var want := env_int("CHECK_GOLD", -1)
	if want >= 0:
		check(gs.hero.gold == want, "the profile brought the gear back (gold %d)" % gs.hero.gold)
		check(gs.hero.inventory.count_of(&"map_scroll") >= 4, "the backpack came back too (map scrolls %d)" % gs.hero.inventory.count_of(&"map_scroll"))
		check(gs.hero.equipment.items.values().any(func(i): return i != null), "the worn gear came back")
	var mark := env_int("GOLD_MARK", -1)
	if mark >= 0:
		gs.hero.gold = mark
		gs.hero.inventory.add_item(root.get_node("ItemDatabase").get_item(&"map_scroll"), 4)
		pp.push_now()
	wn.say("hi from %s" % nick)
	var stay := float(env_int("STAY", 3))
	t = 0.0
	var chat_ok := false
	while t < stay:
		await create_timer(0.25).timeout
		t += 0.25
		if wn.chat_log.any(func(l): return l[1] == "hi from %s" % nick):
			chat_ok = true
		if st["kicked"]:
			break
	if nick == "Kickme":
		check(st["kicked"], "Kickme was kicked by the host")
	check(chat_ok, "my chat line came back from the host")
	if not st["kicked"]:
		wn.close_session()
