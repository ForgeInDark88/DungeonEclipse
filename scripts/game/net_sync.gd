class_name NetSync
extends Node
## World-level replication for LAN co-op (added by game.gd when Net.active).
## The host simulates enemies and loot; clients own their hero and send
## hits/pickups here. Everything is keyed by small net ids.
## Lives in the group "net_game" so menu-less events can reach it.

const STATE_RATE := 0.08  # enemy state broadcast period (s)

var next_net_id := 1
var enemies := {}          # net_id -> Enemy node (real on host, shell on client)
var items := {}            # net_id -> ItemPickup node
var _last_hitter := {}     # net_id -> peer id (kill credit)
var _hit_budget := {}      # peer id -> hits sent this second (anti-spam)
var _hit_second := 0
var _state_timer := 0.0


func _ready() -> void:
	add_to_group("net_game")


func _process(delta: float) -> void:
	if not Net.active or not Net.is_host:
		return
	_state_timer -= delta
	if _state_timer <= 0.0:
		_state_timer = STATE_RATE
		_broadcast_enemy_state()


# --------------------------------------------------------------- registry
## Called by DungeonLevel for every spawned enemy (deterministic ids).
func register_enemy_node(e: Enemy) -> void:
	enemies[e.net_id] = e


func clear_floor() -> void:
	enemies.clear()
	items.clear()
	_last_hitter.clear()
	_hit_budget.clear()


func register_enemy(e: Enemy) -> int:
	var id := next_net_id
	next_net_id += 1
	enemies[id] = e
	e.net_id = id
	return id


func unregister_enemy(net_id: int) -> void:
	enemies.erase(net_id)
	_last_hitter.erase(net_id)


# ----------------------------------------------------------- enemy spawn
## Host → clients: an enemy exists at this spot (spawned only on the host).
@rpc("authority", "call_remote", "reliable")
func spawn_enemy(net_id: int, enemy_id: String, pos: Vector2, elite_id: StringName,
		champion: bool, held: bool, hp: int) -> void:
	_spawn_shell(net_id, enemy_id, pos, elite_id, champion, held, hp)


## Builds the client-side shell. setup() applies floor scaling, the party
## multipliers and altar curses — no extra multiplication here.
func _spawn_shell(net_id: int, enemy_id: String, pos: Vector2, elite_id: StringName,
		champion: bool, held: bool, hp: int) -> void:
	if enemies.has(net_id):
		return
	var data := ItemDatabase.enemy_by_id(enemy_id)
	if data == null:
		return
	var elite: EliteAffixData = null
	for aff in ItemDatabase.elites:
		if aff.id == elite_id:
			elite = aff
			break
	var e := (load("res://scenes/enemies/enemy.tscn") as PackedScene).instantiate()
	e.setup(data, GameState.floor_number, elite, champion)
	e.puppet = true
	e.held = held
	if hp > 0 and hp < e.max_hp:
		e.hp = hp
	enemies[net_id] = e
	e.net_id = net_id
	var game := get_tree().current_scene
	if game == null or not ("level" in game) or game.level == null:
		e.free()
		enemies.erase(net_id)
		return
	game.level.add_entity(e, pos)


## Host → clients: periodic snapshot of enemy positions, hp and AI state.
@rpc("authority", "call_remote", "unreliable")
func enemy_state(states: Array) -> void:
	for st: Array in states:
		var e: Enemy = enemies.get(int(st[0]))
		if e == null or not is_instance_valid(e):
			continue
		e.net_apply_state(st[1], st[2], int(st[3]), bool(st[4]), int(st[5]),
				float(st[6]))


func _broadcast_enemy_state() -> void:
	var states := []
	for id in enemies:
		var e: Enemy = enemies[id]
		if is_instance_valid(e):
			var ai_state: int = e.state
			# Boss has its own Act machine; expose its windup/acting as the
			# common Enemy ATTACK state understood by every shell.
			if e is Boss:
				var b := e as Boss
				if b.act == Boss.Act.WINDUP or b.act == Boss.Act.ACTING:
					ai_state = Enemy.State.ATTACK
			states.append([id, e.global_position.x, e.global_position.y, e.hp,
					e.is_dead(), ai_state, e._attack_anim_left])
	if not states.is_empty():
		enemy_state.rpc(states)


# --------------------------------------------------------------- combat
## Host → clients: a damage number over an enemy (the host rolls damage).
@rpc("authority", "call_remote", "unreliable")
func damage_number(pos: Vector2, amount: int, crit: bool) -> void:
	EventBus.damage_dealt.emit(pos, amount, crit, false)


## Host → clients: an enemy's floating text (immunity, DoT ticks, heals).
@rpc("authority", "call_remote", "unreliable")
func enemy_float_text(pos: Vector2, text: String, color: Color) -> void:
	EventBus.floating_text.emit(pos, text, color)


## Host → clients: an enemy flinched — shells replay the hurt reaction.
@rpc("authority", "call_remote", "unreliable")
func enemy_hurt(net_id: int) -> void:
	var e: Enemy = enemies.get(net_id)
	if e == null or not is_instance_valid(e) or e.is_dead():
		return
	e.net_hurt()


## Client → host: my attack hurt this enemy.
@rpc("any_peer", "call_remote", "reliable")
func net_hit(net_id: int, amount: int, crit: bool, from_x: float, from_y: float,
		damage_type: int) -> void:
	if not Net.is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	var e: Enemy = enemies.get(net_id)
	if e == null or not is_instance_valid(e) or e.is_dead():
		return
	if amount <= 0 or not _sender_near(sender, e.global_position, 420.0):
		return
	if not _hit_rate_ok(sender):
		return
	_last_hitter[net_id] = sender
	e.take_damage(amount, crit, Vector2(from_x, from_y), damage_type)


## Host → clients: an enemy died; shells play the death and free themselves.
@rpc("authority", "call_remote", "reliable")
func enemy_died(net_id: int, xp: int, gold: int, killer: int) -> void:
	var e: Enemy = enemies.get(net_id)
	if e and is_instance_valid(e):
		e.net_die()
	enemies.erase(net_id)
	_last_hitter.erase(net_id)
	# Every player counts the kill locally (quests, codex, combo).
	if e:
		EventBus.enemy_killed.emit(e.data, e.global_position)
		var b := e as Boss
		if b and b.boss:
			EventBus.boss_defeated.emit(b.boss, e.global_position)
			# The +1 skill point the host's boss death grants locally.
			GameState.hero.skills.add_points(1)
			EventBus.message.emit("%s повержен: +1 очко навыка" % b.boss.title)
	if killer == multiplayer.get_unique_id() and (xp > 0 or gold > 0):
		GameState.hero.gain_kill_reward(xp, gold)


## Client shells call this instead of applying damage locally.
func request_hit(e: Enemy, amount: int, crit: bool, damage_type: int,
		from_pos := Vector2.INF) -> void:
	var pos := from_pos if from_pos != Vector2.INF else e.global_position
	net_hit.rpc_id(1, e.net_id, amount, crit, pos.x, pos.y, damage_type)


# Host side: an enemy actually died → tell everyone, credit the killer.
func broadcast_death(e: Enemy, xp: int, gold: int) -> void:
	var killer := int(_last_hitter.get(e.net_id, 1))
	enemy_died.rpc(e.net_id, xp, gold, killer)
	# The host's own kill event (clients got theirs through the rpc).
	enemies.erase(e.net_id)
	_last_hitter.erase(e.net_id)
	EventBus.enemy_killed.emit(e.data, e.global_position)
	if killer == 1:
		GameState.hero.gain_kill_reward(xp, gold)


# ------------------------------------------------------------- pickups
## Host → clients: a dropped item appeared.
@rpc("authority", "call_remote", "reliable")
func spawn_item(net_id: int, item_dict: Dictionary, count: int, pos: Vector2) -> void:
	if items.has(net_id):
		return
	var it := RunCodec.item_from_dict(item_dict)
	if it == null:
		return
	var pickup: ItemPickup = (load("res://scenes/world/item_pickup.tscn") as PackedScene).instantiate()
	pickup.name = "Pickup_%d" % net_id
	pickup.puppet = true
	pickup.net_id = net_id
	pickup.setup(it, count, Vector2.ZERO)
	items[net_id] = pickup
	get_parent().add_child(pickup)
	pickup.global_position = pos


## Host: its own player collected this pickup — remove replicas everywhere.
func forget_item(net_id: int) -> void:
	if not Net.is_host or net_id <= 0 or not items.has(net_id):
		return
	items.erase(net_id)
	item_taken.rpc(net_id)


## Client → host: I touched a pickup.
@rpc("any_peer", "call_remote", "reliable")
func take_item(net_id: int) -> void:
	if not Net.is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	var pickup: ItemPickup = items.get(net_id)
	if pickup == null or not is_instance_valid(pickup):
		return
	if not _sender_near(sender, pickup.global_position, 140.0):
		return
	items.erase(net_id)
	item_granted.rpc_id(sender, RunCodec.item_to_dict(pickup.item), pickup.count)
	item_taken.rpc(net_id)
	pickup.queue_free()


## Host → all: the pickup is gone.
@rpc("authority", "call_remote", "reliable")
func item_taken(net_id: int) -> void:
	var pickup: ItemPickup = items.get(net_id)
	if pickup and is_instance_valid(pickup):
		pickup.queue_free()
	items.erase(net_id)


## Host → taker: here is what you picked up (the world copy is already gone).
@rpc("authority", "call_remote", "reliable")
func item_granted(item_dict: Dictionary, count: int) -> void:
	var it := RunCodec.item_from_dict(item_dict)
	var hero := GameState.hero
	if it == null or hero == null:
		return
	if it.currency_value > 0:
		hero.add_gold(it.currency_value * count)
		EventBus.floating_text.emit(_my_pos() + Vector2(0, -16), "+%d з." % (it.currency_value * count), Color(1.0, 0.85, 0.3))
	else:
		var left := hero.inventory.add_item(it, count)
		if left < count:
			EventBus.item_collected.emit(it, _my_pos())
			EventBus.floating_text.emit(_my_pos() + Vector2(0, -16), "+%d %s" % [count - left, it.display_name], it.rarity_color())


func _my_pos() -> Vector2:
	var p := get_tree().get_first_node_in_group("player") as Node2D
	return p.global_position if p else Vector2.ZERO


## Host side: a pickup appeared → everyone sees it.
func broadcast_item(pickup: ItemPickup) -> void:
	var id := next_net_id
	next_net_id += 1
	pickup.net_id = id
	items[id] = pickup
	spawn_item.rpc(id, RunCodec.item_to_dict(pickup.item), pickup.count, pickup.global_position)


# ---------------------------------------------------------- players
var local_player: Player  # set by game.gd on every machine


## Host → the affected player's machine: a status landed on your hero.
@rpc("any_peer", "call_remote", "reliable")
func player_status(target_peer: int, id: StringName, duration: float, power: float) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	if local_player and Net.multiplayer.get_unique_id() == target_peer:
		local_player.status.apply(id, duration, power)


## Host → the healed player's machine: life steal from a host-judged hit.
@rpc("any_peer", "call_remote", "reliable")
func player_heal(target_peer: int, amount: int) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	if local_player and Net.multiplayer.get_unique_id() == target_peer:
		local_player.heal_status(amount)


## Client → host: my melee/projectile attack reached this enemy. The claim
## carries what the owner rolled; the host re-validates and applies.
@rpc("any_peer", "call_remote", "reliable")
func request_player_hit(net_id: int, amount: int, crit: bool, damage_type: int,
		from: Vector2, knockback: float) -> void:
	if not Net.is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	var e: Enemy = enemies.get(net_id)
	if e == null or not is_instance_valid(e) or e.is_dead():
		return
	if amount <= 0 or not _sender_near(sender, e.global_position, 420.0):
		return
	if not _hit_rate_ok(sender):
		return
	_last_hitter[net_id] = sender
	var pos := Vector2(from.x, from.y)
	e.take_damage(amount, crit, pos, damage_type)
	# The owner still needs the real dealt amount for weapon procs and life
	# steal; armor/resistances already reduced it on the host.
	if is_instance_valid(e) and not e.is_dead():
		hit_confirmed.rpc_id(sender, net_id, amount)
		if knockback > 0.0:
			e.apply_knockback(signf(e.global_position.x - pos.x), knockback)


## Host → the attacker's machine: your hit landed, here is what it dealt.
@rpc("any_peer", "call_remote", "reliable")
func hit_confirmed(net_id: int, dealt: int) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	var e: Enemy = enemies.get(net_id)
	if local_player and e != null and is_instance_valid(e):
		local_player.net_confirm_hit(e, dealt)


func _hit_rate_ok(peer_id: int) -> bool:
	var second := Time.get_ticks_msec() / 1000
	if second != _hit_second:
		_hit_second = second
		_hit_budget.clear()
	var sent := int(_hit_budget.get(peer_id, 0)) + 1
	_hit_budget[peer_id] = sent
	return sent <= 60


## Host → the hit player's machine: an enemy hurt you.
@rpc("any_peer", "call_remote", "reliable")
func player_damage(amount: int, from_pos: Vector2, damage_type: int) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	if local_player:
		local_player.net_take_damage(amount, from_pos, damage_type)


## Host → all: a peer's hero state changed (death/respawn), reliable.
@rpc("authority", "call_remote", "reliable")
func player_hp(peer_id: int, hp: int, max_hp: int, dead: bool) -> void:
	var game := get_tree().current_scene
	if game == null or not ("net_players" in game):
		return
	var p := game.net_players.get_node_or_null("Player_%d" % peer_id) as Player
	if p == null:
		return
	var was_dead := p.dead
	p.dead = dead
	if p.hero:
		p.hero.stats.hp = hp
	if dead and not was_dead:
		p.animator.die()
	elif not dead and was_dead:
		p.revive()


func broadcast_player_hp(peer_id: int, hp: int, max_hp: int, dead: bool) -> void:
	player_hp.rpc(peer_id, hp, max_hp, dead)


## Client → host: my game scene is up, spawn my puppet and tell the others.
@rpc("any_peer", "call_remote", "reliable")
func net_hello() -> void:
	if not Net.is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	var game := get_tree().current_scene
	if game and game.has_method("_spawn_net_puppet"):
		game._spawn_net_puppet.call_deferred(sender)
	if game and game.has_method("spawn_ally"):
		for pid in Net.players:
			if pid != 1 and pid != sender:
				game.spawn_ally.rpc_id(sender, pid, Net.players[pid])
	# The floor is already built on the joiner: push everything that happened.
	send_world_state(sender)


## Host → late joiner: everything that already happened on this floor.
@rpc("authority", "call_remote", "reliable")
func world_state(floor_num: int, tiles: Array, chests: Array, stock: Array,
		puzzles: Array, enemy_list: Array) -> void:
	if floor_num != GameState.floor_number:
		return  # a snapshot of a floor we already left
	var game := get_tree().current_scene
	if game == null or not ("level" in game) or game.level == null:
		return
	var level: DungeonLevel = game.level
	for t in tiles:
		level.apply_remote_tile(Vector2i(int(t[0]), int(t[1])), int(t[2]))
	for seq: int in chests:
		for c in get_tree().get_nodes_in_group("chests"):
			if c.net_seq == seq and not c.opened:
				c.opened = true
				c.locked = false
				c.sprite.play(&"open")
	for entry in stock:
		for m in get_tree().get_nodes_in_group("merchants"):
			if m.net_seq == int(entry[0]):
				m.apply_stock_ids(entry[1])
	for entry in puzzles:
		for p in get_tree().get_nodes_in_group("puzzles"):
			if p.net_seq == int(entry[0]):
				p.net_apply(int(entry[1]), bool(entry[2]))
				break
	for d in enemy_list:
		_spawn_shell(int(d[0]), String(d[1]), Vector2(d[2], d[3]), d[4],
				bool(d[5]), bool(d[6]), int(d[7]))


## Host: collect everything a late joiner missed and push it over.
func send_world_state(peer_id: int) -> void:
	if not Net.is_host:
		return
	var game := get_tree().current_scene
	var level: DungeonLevel = game.level if game != null and "level" in game else null
	var tiles := []
	if level != null and level.layout != null:
		for cell in level.changed_cells:
			tiles.append([cell.x, cell.y, level.layout.get_tile(cell.x, cell.y)])
	var chests := []
	for c in get_tree().get_nodes_in_group("chests"):
		if c.opened:
			chests.append(c.net_seq)
	var stock := []
	for m in get_tree().get_nodes_in_group("merchants"):
		var ids := []
		for it: ItemData in m.stock:
			ids.append(String(it.id))
		stock.append([m.net_seq, ids])
	var puzzles := []
	for p in get_tree().get_nodes_in_group("puzzles"):
		puzzles.append([p.net_seq, p.progress, p.solved])
	var list := []
	for id in enemies:
		var e: Enemy = enemies[id]
		if is_instance_valid(e) and not e.is_dead():
			list.append([id, String(e.data.id), e.global_position.x, e.global_position.y,
					e.elite.id if e.elite else StringName(), e.champion, e.held, e.hp])
	world_state.rpc_id(peer_id, GameState.floor_number, tiles, chests, stock, puzzles, list)


# ---------------------------------------------------- chests and shops
## Client → host: request a chest open. The opener handles their own key locally.
@rpc("any_peer", "call_remote", "reliable")
func request_chest_open(seq: int, has_key: bool) -> void:
	if not Net.is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	var chest := _find_seq_node("chests", seq) as Chest
	if chest == null or chest.opened or chest.sealed or not _sender_near(sender, chest.global_position, 72.0):
		return
	var consume_key := chest.locked
	if consume_key and not has_key:
		return
	if consume_key:
		chest.unlock()
	chest.open(sender, consume_key)


func broadcast_chest(seq: int, opener_peer: int = 1, consume_key: bool = false) -> void:
	chest_opened_remote.rpc(seq, opener_peer, consume_key)


@rpc("authority", "call_remote", "reliable")
func chest_opened_remote(seq: int, opener_peer: int, consume_key: bool) -> void:
	for c in get_tree().get_nodes_in_group("chests"):
		if c.net_seq != seq or c.opened:
			continue
		c.opened = true
		c.locked = false
		c.sprite.play(&"opening")
		c.sprite.animation_finished.connect(func() -> void: c.sprite.play(&"open"), CONNECT_ONE_SHOT)
		if consume_key and opener_peer == multiplayer.get_unique_id():
			GameState.hero.inventory.remove_by_id(&"key", 1)


## Client → host: buy an offer; host checks that the offer still exists.
@rpc("any_peer", "call_remote", "reliable")
func request_purchase(merchant_seq: int, offer_key: String) -> void:
	if not Net.is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	var merchant := _find_seq_node("merchants", merchant_seq) as Merchant
	if merchant == null or not _sender_near(sender, merchant.global_position, 80.0):
		return
	var slot := merchant.find_offer(offer_key)
	if slot < 0:
		return
	var item: ItemData = merchant.stock[slot]
	var item_dict := RunCodec.item_to_dict(item)
	var remove_offer := not item.is_stackable()
	if remove_offer:
		merchant.stock.remove_at(slot)
	purchase_remote.rpc(merchant_seq, offer_key, sender, item_dict, remove_offer)


func broadcast_purchase(merchant: Merchant, offer_key: String, item: ItemData, remove_offer: bool) -> void:
	purchase_remote.rpc(merchant.net_seq, offer_key, 1, RunCodec.item_to_dict(item), remove_offer)


@rpc("authority", "call_remote", "reliable")
func purchase_remote(merchant_seq: int, offer_key: String, buyer_peer: int,
		item_dict: Dictionary, remove_offer: bool) -> void:
	var merchant := _find_seq_node("merchants", merchant_seq) as Merchant
	if merchant == null:
		return
	var slot := merchant.find_offer(offer_key)
	if slot < 0:
		return
	if buyer_peer == multiplayer.get_unique_id():
		var shop := get_tree().get_first_node_in_group("active_shop_book") as ShopBook
		if shop:
			shop.complete_network_purchase(item_dict)
	if remove_offer:
		merchant.stock.remove_at(slot)
		get_tree().call_group("active_shop_book", "refresh_network_stock")


## Client → host: I sold a unique item to the merchant; it joins the stock.
@rpc("any_peer", "call_remote", "reliable")
func request_sell(merchant_seq: int, item_dict: Dictionary) -> void:
	if not Net.is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	var merchant := _find_seq_node("merchants", merchant_seq) as Merchant
	if merchant == null or merchant.stock.size() >= Merchant.STOCK_CAP:
		return
	if not _sender_near(sender, merchant.global_position, 80.0):
		return
	var item := RunCodec.item_from_dict(item_dict)
	if item == null or item.is_stackable():
		return
	merchant.stock.append(item)
	stock_added.rpc(merchant_seq, item_dict)


## Host → all: the merchant bought a unique item, it is now in the stock.
@rpc("authority", "call_remote", "reliable")
func stock_added(merchant_seq: int, item_dict: Dictionary) -> void:
	var merchant := _find_seq_node("merchants", merchant_seq) as Merchant
	if merchant == null or merchant.stock.size() >= Merchant.STOCK_CAP:
		return
	var item := RunCodec.item_from_dict(item_dict)
	if item == null or item.is_stackable():
		return
	merchant.stock.append(item)
	get_tree().call_group("active_shop_book", "refresh_network_stock")


# ---------------------------------------------------- puzzles and gates
## Client → host: I pulled a puzzle lever; the host judges the rune order.
@rpc("any_peer", "call_remote", "reliable")
func request_puzzle_pull(puzzle_seq: int, lever_index: int) -> void:
	if not Net.is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	var puzzle: Node = null
	for p in get_tree().get_nodes_in_group("puzzles"):
		if p.net_seq == puzzle_seq:
			puzzle = p
			break
	if puzzle == null or puzzle.solved or lever_index < 0 or lever_index >= puzzle.levers.size():
		return
	var lever: Node = puzzle.levers[lever_index]
	if lever.down or not _sender_near(sender, lever.global_position, 96.0):
		return
	var game := get_tree().current_scene
	var puller: Player = null
	if game != null and "net_players" in game:
		puller = game.net_players.get_node_or_null("Player_%d" % sender)
	if puller == null or puller.dead:
		return
	puzzle.pull(lever, puller)


## Host → all: the puzzle's progress and solved state.
@rpc("authority", "call_remote", "reliable")
func puzzle_state(puzzle_seq: int, progress: int, solved: bool) -> void:
	for p in get_tree().get_nodes_in_group("puzzles"):
		if p.net_seq == puzzle_seq:
			p.net_apply(progress, solved)
			return


## Host: the champion's room sealed or opened → replicate the barrier.
func broadcast_gate(closed: bool) -> void:
	gate_state.rpc(closed)


@rpc("authority", "call_remote", "reliable")
func gate_state(closed: bool) -> void:
	get_tree().call_group("miniboss_gates", "net_close" if closed else "net_open")


# ------------------------------------------------------------- world events
## Client → host: I successfully disarmed this trap (rolled with my own
## hero); the host marks it spent and tells everyone.
@rpc("any_peer", "call_remote", "reliable")
func request_trap_disarm(seq: int) -> void:
	if not Net.is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	for t in get_tree().get_nodes_in_group("traps"):
		if t.net_seq == seq and not t.disarmed:
			if _sender_near(sender, t.global_position, 96.0):
				t._apply_disarmed()
				t._net_disarm_broadcast()
			return


## Client → host: my failed attempt triggered the trap on my machine.
@rpc("any_peer", "call_remote", "reliable")
func request_trap_spring(seq: int) -> void:
	if not Net.is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	for t in get_tree().get_nodes_in_group("traps"):
		if t.net_seq == seq and not t.disarmed:
			if _sender_near(sender, t.global_position, 96.0):
				t.trigger()
			return


## Host → all: the trap is spent everywhere.
@rpc("authority", "call_remote", "reliable")
func trap_disarmed_net(seq: int) -> void:
	for t in get_tree().get_nodes_in_group("traps"):
		if t.net_seq == seq and not t.disarmed:
			t._apply_disarmed()
			return


## Client → host: I dropped an item; spawn the shared pickup at my puppet.
@rpc("any_peer", "call_remote", "reliable")
func request_drop(item_dict: Dictionary, count: int) -> void:
	if not Net.is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	var item := RunCodec.item_from_dict(item_dict)
	if item == null or count <= 0 or count > 99:
		return
	var game := get_tree().current_scene
	var p: Player = game.net_players.get_node_or_null("Player_%d" % sender) if game != null and "net_players" in game else null
	if p == null:
		return
	EventBus.spawn_items.emit(p.global_position + Vector2(p.facing * 10.0, -12.0),
			[{"item": item, "count": count}])


## Client → host: I used a one-shot event.
@rpc("any_peer", "call_remote", "reliable")
func request_event_use(seq: int) -> void:
	if not Net.is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	var event: EventObject = null
	for e in get_tree().get_nodes_in_group("events"):
		if e.net_seq == seq:
			event = e
			break
	if event == null or event.used or not _sender_near(sender, event.global_position, 96.0):
		return
	var game := get_tree().current_scene
	var p: Player = game.net_players.get_node_or_null("Player_%d" % sender) if game != null and "net_players" in game else null
	if p == null or p.dead:
		return
	# Execute on the host's mirror of the sender; rewards (gold/xp/status)
	# are then forwarded by the regular hero/player sync channels.
	event._activate(p)
	event.finish()


@rpc("authority", "call_remote", "reliable")
func event_used(seq: int) -> void:
	for e in get_tree().get_nodes_in_group("events"):
		if e.net_seq == seq and not e.used:
			e.finish()
			return


## Client → host: my fate altar choice (offer index). Run-wide, so the host
## applies it to GameState and broadcasts to everyone.
@rpc("any_peer", "call_remote", "reliable")
func request_pact(seq: int, offer_index: int) -> void:
	if not Net.is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	for e in get_tree().get_nodes_in_group("events"):
		if e.net_seq == seq and e.has_method("_take"):
			if e.used or offer_index < 0 or offer_index >= e._offers.size():
				return
			if not _sender_near(sender, e.global_position, 96.0):
				return
			e._take(e._offers[offer_index],
					e.get_tree().current_scene.net_players.get_node_or_null("Player_%d" % sender))
			return


## Host → all: the fate altar choice was made; apply the same pact locally.
@rpc("authority", "call_remote", "reliable")
func pact_taken(seq: int, offer_index: int) -> void:
	for e in get_tree().get_nodes_in_group("events"):
		if e.net_seq == seq and e.has_method("_take") and offer_index < e._offers.size():
			e._take_net(e._offers[offer_index])
			return


## Host: spawn the real bomb (damage, tile breaks) and mirror a visual copy
## to every client. Used by the host's own throws and validated requests.
func spawn_net_bomb(pos: Vector2, dir: float, damage: int, radius: float, fuse_time: float,
		damage_type: int, status_id: StringName, status_duration: float, status_power: float,
		breaks_tiles: bool, color: Color) -> void:
	var game := get_tree().current_scene
	var level: DungeonLevel = game.level if game != null and "level" in game else null
	if level == null:
		return
	var bomb: Node2D = (load("res://scenes/world/bomb.tscn") as PackedScene).instantiate()
	bomb.damage = damage
	bomb.radius = radius
	bomb.fuse_time = fuse_time
	bomb.velocity = Vector2(160.0 * dir, -170.0)
	bomb.damage_type = damage_type
	bomb.status = status_id
	bomb.status_duration = status_duration
	bomb.status_power = status_power
	bomb.breaks_tiles = breaks_tiles
	bomb.color = color
	level.add_entity(bomb, pos)
	bomb_spawned.rpc(pos, dir, fuse_time, damage_type, status_id, status_duration,
			status_power, breaks_tiles, color)


## Client → host: I threw a bomb; validate, spawn, mirror to everyone.
@rpc("any_peer", "call_remote", "reliable")
func request_bomb(pos: Vector2, dir: float, damage: int, radius: float, fuse_time: float,
		damage_type: int, status_id: StringName, status_duration: float, status_power: float,
		breaks_tiles: bool, color: Color) -> void:
	if not Net.is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not _sender_near(sender, pos, 160.0) or damage <= 0 or damage > 200 or radius > 128.0:
		return
	spawn_net_bomb(pos, dir, damage, radius, fuse_time, damage_type, status_id,
			status_duration, status_power, breaks_tiles, color)


## Host → clients: a visual-only bomb copy (no damage, no tile changes —
## the host's real bomb does the work when it explodes).
@rpc("authority", "call_remote", "reliable")
func bomb_spawned(pos: Vector2, dir: float, fuse_time: float, damage_type: int,
		status_id: StringName, status_duration: float, status_power: float,
		breaks_tiles: bool, color: Color) -> void:
	var game := get_tree().current_scene
	var level: DungeonLevel = game.level if game != null and "level" in game else null
	if level == null:
		return
	var bomb: Node2D = (load("res://scenes/world/bomb.tscn") as PackedScene).instantiate()
	bomb.visual_only = true
	bomb.fuse_time = fuse_time
	bomb.radius = 36.0
	bomb.velocity = Vector2(160.0 * dir, -170.0)
	bomb.damage_type = damage_type
	bomb.status = status_id
	bomb.status_duration = status_duration
	bomb.status_power = status_power
	bomb.breaks_tiles = false
	bomb.color = color
	level.add_entity(bomb, pos)


## Client → host: I threw a rope; the host places the real ladder tiles.
@rpc("any_peer", "call_remote", "reliable")
func request_rope(cell: Vector2i, max_length: int) -> void:
	if not Net.is_host or max_length <= 0 or max_length > 64:
		return
	var sender := multiplayer.get_remote_sender_id()
	var game := get_tree().current_scene
	var level: DungeonLevel = game.level if game != null and "level" in game else null
	if level == null or not _sender_near(sender, level.cell_center(cell), 120.0):
		return
	level.place_rope(cell, max_length)


## Host → all: ladder tiles of a rope placed on the host.
@rpc("authority", "call_remote", "reliable")
func ropes_placed(cells: Array) -> void:
	var game := get_tree().current_scene
	var level: DungeonLevel = game.level if game != null and "level" in game else null
	if level == null:
		return
	for c in cells:
		level.apply_remote_tile(Vector2i(c.x, c.y), LevelLayout.Tile.LADDER)


## Host → clients: an enemy projectile flies (visual copy, no damage —
## hits on guests arrive through player_damage).
@rpc("authority", "call_remote", "unreliable")
func enemy_projectile(texture_path: String, pos: Vector2, dir: Vector2, speed: float,
		lifetime: float) -> void:
	var game := get_tree().current_scene
	var level: DungeonLevel = game.level if game != null and "level" in game else null
	if level == null:
		return
	var proj: Projectile = (load("res://scenes/world/projectile.tscn") as PackedScene).instantiate()
	proj.setup(load(texture_path) as Texture2D, dir, speed, 0, "net_visual")
	proj.lifetime = lifetime
	level.add_entity(proj, pos)


## Any peer → others: a visual projectile copy (no damage — the owner's own
## projectile deals damage through request_player_hit on hit).
@rpc("any_peer", "call_remote", "unreliable")
func projectile_fx(texture_path: String, pos: Vector2, dir: Vector2, speed: float,
		lifetime: float, color: Color) -> void:
	if multiplayer.get_remote_sender_id() == multiplayer.get_unique_id():
		return
	var game := get_tree().current_scene
	var level: DungeonLevel = game.level if game != null and "level" in game else null
	if level == null:
		return
	var proj: Projectile = (load("res://scenes/world/projectile.tscn") as PackedScene).instantiate()
	proj.setup(load(texture_path) as Texture2D, dir, speed, 0, "net_visual")
	proj.lifetime = lifetime
	proj.blast_color = color
	level.add_entity(proj, pos)


## Any peer → others: an area blast's visual (damage travels per-enemy).
@rpc("any_peer", "call_remote", "reliable")
func blast_fx(center: Vector2, radius: float, vfx: StringName, color: Color) -> void:
	var game := get_tree().current_scene
	if game == null or not ("level" in game) or game.level == null:
		return
	var parent: Node = game.level.entities
	match vfx:
		&"slash":
			Fx.arc_slash(parent, center, radius, color, 1.0)
		&"blades":
			Fx.blade_fan(parent, center, radius, color)
		&"ring":
			Fx.nova_ring(parent, center, radius, color)
		&"ice":
			Fx.ice_burst(parent, center, radius, color)
		&"light":
			Fx.light_pillars(parent, center, radius, color)
		&"sun":
			Fx.sun_flash(parent, center, radius, color)
		&"quake":
			Fx.rock_burst(parent, center, radius, color)
		_:
			Fx.explosion(parent, center, radius, color)


func _find_seq_node(group_name: StringName, seq: int) -> Node:
	for node in get_tree().get_nodes_in_group(group_name):
		if node.net_seq == seq:
			return node
	return null


func _sender_near(peer_id: int, pos: Vector2, max_distance: float) -> bool:
	var game := get_tree().current_scene
	if game == null or not ("net_players" in game):
		return false
	var player := game.net_players.get_node_or_null("Player_%d" % peer_id) as Player
	return player != null and is_instance_valid(player) and player.global_position.distance_to(pos) <= max_distance

# ------------------------------------------------------------- casts
## Any player attack → the others see the swing animation and slash trail.
func broadcast_attack(caster_peer: int, anim: StringName, aim: Vector2, reach: float,
		thrust: bool, color: Color) -> void:
	attack_fx.rpc(caster_peer, anim, aim, reach, thrust, color)


@rpc("any_peer", "call_remote", "unreliable")
func attack_fx(caster_peer: int, anim: StringName, aim: Vector2, reach: float,
		thrust: bool, color: Color) -> void:
	if caster_peer == multiplayer.get_unique_id():
		return
	var scene := get_tree().current_scene
	if scene == null or not ("net_players" in scene):
		return
	var puppet: Player = scene.net_players.get_node_or_null("Player_%d" % caster_peer)
	if puppet == null or puppet.hero == null or puppet.dead:
		return
	# A puppet that died earlier may still have the DEATH state in its
	# animator (an unreliable packet was lost): stand it up before swinging.
	if puppet.animator.state == puppet.animator.State.DEATH:
		puppet.animator.revive()
	if anim != &"":
		puppet.animator.play_action(anim, 0.35)
	puppet.face_aim_to(aim)
	# The weapon trail the attacker saw on their machine (melee only).
	if reach > 0.0 and scene.level:
		var origin: Vector2 = puppet.global_position + Vector2(0, -12)
		SlashTrail.spawn(scene.level.entities, origin + aim.normalized() * 4.0,
				aim.normalized(), reach, thrust, color)


## Any player cast → everyone sees the animation, sound and the visuals.
func broadcast_cast(caster_peer: int, skill_id: StringName, aim: Vector2) -> void:
	cast_fx.rpc(caster_peer, skill_id, aim)


@rpc("any_peer", "call_remote", "unreliable")
func cast_fx(caster_peer: int, skill_id: StringName, aim: Vector2) -> void:
	# The caster already saw their own cast.
	if caster_peer == multiplayer.get_unique_id():
		return
	var scene := get_tree().current_scene
	if scene == null or not ("net_players" in scene):
		return
	var puppet: Player = scene.net_players.get_node_or_null("Player_%d" % caster_peer)
	if puppet == null or puppet.hero == null:
		return
	var skill := load("res://data/skills/%s.tres" % skill_id) as SkillData
	if skill == null:
		return
	if skill.cast_animation != &"":
		puppet.animator.play_action(skill.cast_animation, 0.4)
	var snd := skill.cast_sound if skill.cast_sound != &"" else &"skill_cast"
	AudioManager.play_sfx(snd, puppet.global_position, -4.0)
	_net_skill_visual(puppet, skill, aim)


## A silent copy of the skill's show: blasts replay their silhouette,
## projectiles fly without dealing damage.
func _net_skill_visual(puppet: Player, skill: SkillData, aim: Vector2) -> void:
	var fx_parent := puppet.get_parent()
	var origin := puppet.global_position + Vector2(0, -11)
	var effect: SkillEffect = skill.effect
	if effect == null:
		Fx.sparks(fx_parent, origin, Color(0.8, 0.7, 1.0), 10, 60.0)
		return
	if effect is AreaBlastSkill:
		var blast: AreaBlastSkill = effect as AreaBlastSkill
		var radius: float = blast.radius
		var center := origin + aim.normalized() * radius * 0.6
		match String(blast.vfx):
			"meteor":
				Fx.meteor_fall(fx_parent, center, radius, blast.color)
				Fx.meteor_impact(fx_parent, center, radius, blast.color)
			"ice":
				Fx.ice_burst(fx_parent, center, radius, blast.color)
			"light":
				Fx.light_pillars(fx_parent, center, radius, blast.color)
			"sun":
				Fx.sun_flash(fx_parent, center, radius, blast.color)
			"quake", "rock":
				Fx.rock_burst(fx_parent, center, radius, blast.color)
			"ring", "nova":
				Fx.nova_ring(fx_parent, center, radius, blast.color)
			"slash":
				Fx.arc_slash(fx_parent, center, radius, blast.color, 1.0)
			"blades":
				Fx.blade_fan(fx_parent, center, radius, blast.color)
			_:
				Fx.explosion(fx_parent, center, radius, blast.color)
	elif effect is ProjectileSkill:
		var ps := effect as ProjectileSkill
		var dir := (aim - origin).normalized() if aim != origin else Vector2.RIGHT
		var proj: Node2D = (load("res://scenes/world/projectile.tscn") as PackedScene).instantiate()
		proj.setup(ps.texture, dir, ps.speed, 0, &"net_visual")
		fx_parent.add_child(proj)
		proj.global_position = origin
	else:
		Fx.sparks(fx_parent, origin, Color(0.8, 0.7, 1.0), 10, 60.0)


# ----------------------------------------------------- tile mutations
@rpc("any_peer", "call_remote", "reliable")
func request_tile_break(cell: Vector2i) -> void:
	if not Net.is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	var game := get_tree().current_scene
	var level := game.level as DungeonLevel if game != null and "level" in game else null
	if level == null or cell.x < 0 or cell.y < 0 or cell.x >= level.layout.width or cell.y >= level.layout.height:
		return
	if not _sender_near(sender, level.cell_center(cell), 220.0):
		return
	level.break_tile(cell)


@rpc("any_peer", "call_remote", "reliable")
func request_tile_explosion(center: Vector2, radius: float) -> void:
	if not Net.is_host or radius <= 0.0 or radius > 256.0:
		return
	var sender := multiplayer.get_remote_sender_id()
	var game := get_tree().current_scene
	var level := game.level as DungeonLevel if game != null and "level" in game else null
	if level == null or not _sender_near(sender, center, radius + 96.0):
		return
	level.explode(center, radius)


@rpc("authority", "call_remote", "reliable")
func tile_broken(cell: Vector2i) -> void:
	var game := get_tree().current_scene
	if game != null and "level" in game and game.level:
		game.level.apply_remote_tile(cell, LevelLayout.Tile.EMPTY)


@rpc("any_peer", "call_remote", "reliable")
func request_floor(action: StringName) -> void:
	if not Net.is_host:
		return
	# Only a living hero may move the party.
	var game := get_tree().current_scene
	if game != null and "net_players" in game:
		var p := game.net_players.get_node_or_null("Player_%d" % multiplayer.get_remote_sender_id()) as Player
		if p == null or p.dead:
			return
	match action:
		&"next":
			# A guest's town gate: while a return floor is pending, "next"
			# means resume the descent (the guest does not know the state).
			if GameState.town_return_floor > 0:
				GameState.resume_from_town()
			else:
				GameState.next_floor()
		&"town":
			GameState.return_to_town()
		&"resume":
			GameState.resume_from_town()


# A late joiner needs the current floor + world (spawned by game.gd).
@rpc("authority", "call_remote", "reliable")
func world_snapshot(floor_number: int, seed_value: int, difficulty_id: StringName) -> void:
	GameState.begin_network_run(seed_value, difficulty_id, floor_number)


# ----------------------------------------------------------------- leave
func on_peer_left(peer_id: int) -> void:
	var p := get_tree().get_first_node_in_group("net_players") as Node
	if p == null:
		return
	for child in p.get_children():
		if child.name == "Player_%d" % peer_id:
			child.queue_free()
