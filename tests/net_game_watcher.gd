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
	# The two machines run this phase at different moments: both walk back
	# and forth for a while and watch the range the other's puppet covers.
	var lo := theirs.global_position.x
	var hi := lo
	for i in 30:
		if i % 6 == 0:
			mine.global_position += Vector2(150 if (i / 6) % 2 == 0 else -150, 0)
		await get_tree().create_timer(0.15).timeout
		lo = minf(lo, theirs.global_position.x)
		hi = maxf(hi, theirs.global_position.x)
	var moved := hi - lo
	check(moved > 40.0, "the other hero's puppet moved (%.0f px)" % moved)
	# --- input phase: the guest fires a synthetic skill keypress; the host
	# must see the cast fx (broadcast_cast works from a client).
	if not is_host:
		print("DBG: skill_1 pressed, hero=", mine.hero != null,
				" skill=", mine.hero.skills.get_skill(0) if mine and mine.hero else null)
		Input.action_press("skill_1")
		await get_tree().create_timer(0.3).timeout
		Input.action_release("skill_1")
		await get_tree().create_timer(1.0).timeout
	# --- death phase: the guest dies; the host's puppet must show the death
	# state (dead flag), then the guest revives and both move on.
	if not is_host:
		mine.hero.stats.take_damage(99999)
		await get_tree().create_timer(1.5).timeout
		check(mine.dead, "client: hero died")
		# The host checks the corpse at ~2.5s: revive only after that.
		await get_tree().create_timer(2.0).timeout
		mine.revive()
		if g != null and g.net_sync:
			g.net_sync.broadcast_player_hp(Net.multiplayer.get_unique_id(),
					mine.hero.stats.hp, mine.hero.stats.max_hp(), false)
		await get_tree().create_timer(0.5).timeout
	else:
		# Poll: the guest's phase start is not synchronized with ours.
		var corpse: Player = null
		for i in 10:
			await get_tree().create_timer(1.0).timeout
			corpse = _their_puppet(1)
			if corpse != null and corpse.dead:
				break
		print("DBG host corpse dead=", corpse.dead if corpse else "null")
		check(corpse != null and corpse.dead, "host: guest puppet marked dead")
	# --- chest phase: the guest stands at a chest and sends the real
	# request_chest_open; both sides must see it open.
	var chest: Chest = null
	for c in get_tree().get_nodes_in_group("chests"):
		if not c.opened and not c.sealed and c.tier < 2:
			chest = c
			break
	if chest == null:
		print("SKIP: no chest on this floor")
	elif is_host:
		await get_tree().create_timer(7.0).timeout
		check(chest.opened, "host: guest's chest request opened the chest")
	else:
		# Stand right at the chest so the host's range check passes.
		mine.global_position = chest.global_position + Vector2(-20, 0)
		await get_tree().create_timer(0.8).timeout
		chest.interact(mine)
		await get_tree().create_timer(2.0).timeout
		check(chest.opened, "client: chest opened through the host")
	# --- loot phase: every pickup a guest sees must be a replica of a host
	# pickup (no phantom copies of its own).
	await get_tree().create_timer(1.5).timeout
	var own := 0
	var reps := 0
	for n in get_tree().get_nodes_in_group("pickups"):
		var pk := n as ItemPickup
		if pk == null or pk.is_queued_for_deletion():
			continue
		print("DBG pickup ", "host" if is_host else "guest", " id=", pk.net_id, " puppet=", pk.puppet, " item=", pk.item.id if pk.item else "?", " pos=", pk.global_position)
		if pk.puppet:
			reps += 1
		else:
			own += 1
	if not is_host:
		check(own == 0, "guest: no phantom (local) pickups (%d, replicas %d)" % [own, reps])
	# --- costume phase: the guest equips a sword; the host's puppet copy
	# must mirror the same gear through net_state.
	if is_host:
		await get_tree().create_timer(4.0).timeout
		var w: EquipmentItemData = theirs.hero.weapon() if theirs and theirs.hero else null
		check(w != null and String(w.id) == "bronze_sword",
				"host: guest's gear mirrored (%s)" % (String(w.id) if w else "none"))
	else:
		var sword: EquipmentItemData = ItemDatabase.get_item(&"bronze_sword")
		if sword == null:
			print("SKIP: no bronze_sword in the item database")
		else:
			mine.hero.equipment.equip(sword, &"weapon")
			await get_tree().create_timer(4.0).timeout
			var w: EquipmentItemData = mine.hero.weapon()
			check(w != null and String(w.id) == "bronze_sword", "guest: sword equipped")
	# --- enemy hp replication phase: the host wounds one mob, the client's
	# shell must show the damage through the enemy_state snapshots.
	if is_host:
		var wounded := false
		if ns != null and g.level != null:
			var origin2: Vector2 = g.level.start_position()
			var victim: Enemy = null
			var best := -1.0
			for id in ns.enemies:
				var e: Enemy = ns.enemies[id]
				# The farthest mob: wounding a nearby one aggro's it onto the
				# idle test heroes and can end the run mid-check.
				if is_instance_valid(e) and not e.is_dead() and e.hp > 20:
					var d: float = e.global_position.distance_to(origin2)
					if d > best:
						best = d
						victim = e
			if victim != null:
				victim.take_damage(10, false, victim.global_position + Vector2(0, -20), 0)
				wounded = true
		check(wounded, "host: wounded a mob for the hp sync check")
		await get_tree().create_timer(1.0).timeout
	else:
		await get_tree().create_timer(3.0).timeout
		var bled := false
		if ns != null:
			for id in ns.enemies:
				var e: Enemy = ns.enemies[id]
				if is_instance_valid(e) and e.hp < e.max_hp:
					bled = true
					break
		check(bled, "client: enemy hp replicated from host")
	# --- tile break replication phase: the guest asks, the host applies,
	# everyone converges on the same layout.
	var level: DungeonLevel = g.level
	if level != null:
		var origin := level.start_position()
		var sc := level.world_to_cell(origin)
		var cell := Vector2i(-1, -1)
		for r in range(1, 7):
			if cell.x >= 0:
				break
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if maxi(absi(dx), absi(dy)) != r:
						continue
					var c := sc + Vector2i(dx, dy)
					if level.layout.get_tile(c.x, c.y) == LevelLayout.Tile.BRICK:
						cell = c
						break
				if cell.x >= 0:
					break
			if cell.x >= 0:
				break
		if cell.x < 0:
			print("SKIP: no breakable brick near the start")
		else:
			var dist := origin.distance_to(level.cell_center(cell))
			check(dist < 200.0, "brick cell near the start (%.0f px)" % dist)
			if is_host:
				# The guest's request travels over the network; poll for it.
				for i in 10:
					if not is_instance_valid(level) \
							or level.layout.get_tile(cell.x, cell.y) == LevelLayout.Tile.EMPTY:
						break
					await get_tree().create_timer(1.0).timeout
				if not is_instance_valid(level):
					check(false, "host: level freed mid-test")
					_finish(0.5)
					return
				check(level.layout.get_tile(cell.x, cell.y) == LevelLayout.Tile.EMPTY,
						"host: guest's tile break applied")
			else:
				# Stand still near the cell: the host validates range.
				if mine != null:
					mine.global_position = origin
				await get_tree().create_timer(0.7).timeout
				if not is_instance_valid(level):
					check(false, "client: level freed mid-test")
					_finish(0.5)
					return
				level.break_tile(cell)  # a client only sends the request
				await get_tree().create_timer(2.0).timeout
				check(level.layout.get_tile(cell.x, cell.y) == LevelLayout.Tile.EMPTY,
						"client: tile break replicated back")
	# --- trap phase: the guest springs a rock trap; the host must see the
	# same rocks fall (shower / loose rock) at the guest's spot.
	var trap: Node = null
	if level != null:
		var traps := get_tree().get_nodes_in_group("traps")
		traps.sort_custom(func(a: Node, b: Node) -> bool: return a.net_seq < b.net_seq)
		for t in traps:
			if t.disarmed:
				continue
			if (t.data.kind == TrapData.Kind.PRESSURE_PLATE and t.linked == null) or t.data.kind == TrapData.Kind.FALLING_ROCK:
				trap = t
				break
	if trap == null:
		print("SKIP: no rock trap on this floor")
	elif is_host:
		var seen := false
		for i in 40:
			await get_tree().create_timer(0.1).timeout
			if not is_instance_valid(trap):
				break
			if trap.data.kind == TrapData.Kind.FALLING_ROCK:
				seen = trap._phase != ""
			else:
				seen = level.find_children("*", "RockProjectile", true, false).size() > 0 \
						or trap._cooldown > 0.0
			if seen:
				break
		check(seen, "host: guest's rock trap fell here too")
	else:
		if mine != null:
			mine.global_position = trap.global_position + Vector2(0, 30)
		await get_tree().create_timer(0.7).timeout
		if is_instance_valid(trap):
			trap.spring_shared(mine.global_position if mine else trap.global_position)
		await get_tree().create_timer(1.0).timeout
	# --- floor transition phase: the host descends; the guest must rebuild
	# the floor and receive the new floor's enemies via the world re-sync.
	if is_host:
		# Let the guest finish its floor 1 checks before pulling everyone down.
		await get_tree().create_timer(5.0).timeout
		GameState.next_floor()
	for i in 20:
		if GameState.floor_number == 2:
			break
		await get_tree().create_timer(1.0).timeout
	# The floor keeps building and the world snapshot keeps arriving: let it.
	await get_tree().create_timer(4.0).timeout
	check(GameState.floor_number == 2, "both on floor 2 (got %d)" % GameState.floor_number)
	var shells2: int = ns.enemies.size() if ns != null else -1
	check(shells2 > 0, "floor 2 mobs present (%d)" % shells2)
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
