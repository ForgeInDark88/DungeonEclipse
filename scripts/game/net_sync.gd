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
## Host → clients: an enemy exists at this spot.
@rpc("authority", "call_remote", "reliable")
func spawn_enemy(net_id: int, enemy_id: String, pos: Vector2, elite_id: StringName,
		champion: bool, floor_number: int, hp_mult: float, dmg_mult: float) -> void:
	if enemies.has(net_id):
		return
	var data := ItemDatabase.enemy_by_id(enemy_id)
	if data == null:
		return
	var e := (load("res://scenes/enemies/enemy.tscn") as PackedScene).instantiate()
	e.setup(data, floor_number, null, champion)
	e.puppet = true
	e.max_hp = roundi(e.max_hp * hp_mult)
	e.hp = e.max_hp
	e.damage = roundi(e.damage * dmg_mult)
	enemies[net_id] = e
	e.net_id = net_id
	get_parent().add_entity(e, pos)


## Host → clients: periodic snapshot of enemy positions and hp.
@rpc("authority", "call_remote", "unreliable")
func enemy_state(states: Array) -> void:
	for st: Array in states:
		var e: Enemy = enemies.get(int(st[0]))
		if e == null or not is_instance_valid(e):
			continue
		e.net_apply_state(st[1], st[2], int(st[3]), bool(st[4]))


func _broadcast_enemy_state() -> void:
	var states := []
	for id in enemies:
		var e: Enemy = enemies[id]
		if is_instance_valid(e):
			states.append([id, e.global_position.x, e.global_position.y, e.hp, e.dead])
	if not states.is_empty():
		enemy_state.rpc(states)


# --------------------------------------------------------------- combat
## Client → host: my attack hurt this enemy.
@rpc("any_peer", "call_remote", "reliable")
func net_hit(net_id: int, amount: int, crit: bool, from_x: float, damage_type: int) -> void:
	if not Net.is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	var e: Enemy = enemies.get(net_id)
	if e == null or not is_instance_valid(e) or e.dead:
		return
	_last_hitter[net_id] = sender
	var pos := Vector2(from_x, e.global_position.y)
	e.take_damage(amount, crit, pos, damage_type)


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
func request_hit(e: Enemy, amount: int, crit: bool, damage_type: int) -> void:
	net_hit.rpc_id(1, e.net_id, amount, crit, e.global_position.x, damage_type)


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


## Client → host: I touched a pickup.
@rpc("any_peer", "call_remote", "reliable")
func take_item(net_id: int) -> void:
	if not Net.is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	var pickup: ItemPickup = items.get(net_id)
	if pickup == null or not is_instance_valid(pickup):
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


## Host → the hit player's machine: an enemy hurt you.
@rpc("any_peer", "call_remote", "reliable")
func player_damage(amount: int, from_pos: Vector2, damage_type: int) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	if local_player:
		local_player.net_take_damage(amount, from_pos, damage_type)


## Host → all: a peer's hero state changed level (respawn, xp from host).
@rpc("any_peer", "call_remote", "reliable")
func player_hp(peer_id: int, hp: int, max_hp: int, dead: bool) -> void:
	get_tree().call_group("net_game", "on_player_hp", peer_id, hp, max_hp, dead)


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


# ---------------------------------------------------- chests and shops
## Anyone opened a chest → the others see it open (loot belongs to the opener).
func broadcast_chest(seq: int) -> void:
	chest_opened_remote.rpc(seq)


@rpc("authority", "call_remote", "reliable")
func chest_opened_remote(seq: int) -> void:
	for c in get_tree().get_nodes_in_group("chests"):
		if c.net_seq == seq and not c.opened:
			c.opened = true
			c.sprite.play(&"opening")
			c.sprite.animation_finished.connect(func() -> void: c.sprite.play(&"open"), CONNECT_ONE_SHOT)


## Someone bought a unique good → it vanishes from every copy of the stock.
func broadcast_purchase(merchant_seq: int, slot: int) -> void:
	purchase_remote.rpc(merchant_seq, slot)


@rpc("authority", "call_remote", "reliable")
func purchase_remote(merchant_seq: int, slot: int) -> void:
	for m in get_tree().get_nodes_in_group("merchants"):
		if m.net_seq == merchant_seq and slot < m.stock.size():
			m.stock.remove_at(slot)


# ------------------------------------------------- host-only world moves
## A client asked to descend / return to town; the host decides.
@rpc("any_peer", "call_remote", "reliable")
func request_floor(action: StringName) -> void:
	if not Net.is_host:
		return
	match action:
		&"next":
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
