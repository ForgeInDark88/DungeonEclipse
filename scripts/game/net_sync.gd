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
var minions := {}         # uid -> Minion: other players' servants (visual copies)
## Host: a hero asked to move the party (exit / gate / stairs) and waits there
## for the others; the move happens by itself once everyone living is near.
const GATHER_RADIUS := 220.0
var _pending_action := &""
var _pending_peer := 0
var _pending_pos := Vector2.ZERO
var _pending_left := 0.0
var _gather_timer := 0.0
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
	if _pending_action != &"":
		_gather_timer -= delta
		_pending_left -= delta
		if _gather_timer <= 0.0:
			_gather_timer = 0.3
			_check_gathering()


# --------------------------------------------------------------- registry
## Called by DungeonLevel for every spawned enemy (deterministic ids).
func register_enemy_node(e: Enemy) -> void:
	enemies[e.net_id] = e


func clear_floor() -> void:
	enemies.clear()
	items.clear()
	_last_hitter.clear()
	_hit_budget.clear()
	minions.clear()  # the copies lived among the old level's entities
	_pending_action = &""


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
		champion: bool, held: bool, hp: int, role_id: StringName) -> void:
	_spawn_shell(net_id, enemy_id, pos, elite_id, champion, held, hp, role_id)


## Builds the client-side shell. setup() applies floor scaling, the party
## multipliers and altar curses — no extra multiplication here.
func _spawn_shell(net_id: int, enemy_id: String, pos: Vector2, elite_id: StringName,
		champion: bool, held: bool, hp: int, role_id: StringName = &"") -> void:
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
	var role := ItemDatabase.squad_role(role_id) if role_id != &"" else null
	if role:
		e.assign_role(role)
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
				float(st[6]), int(st[7]) if st.size() > 7 else -1)


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
					e.is_dead(), ai_state, e._attack_anim_left, e.max_hp])
	if not states.is_empty():
		enemy_state.rpc(states)


# --------------------------------------------------------------- combat
## Host → clients: a boss ability visual (no damage - the host judged it).
@rpc("authority", "call_remote", "reliable")
func boss_fx(kind: StringName, from: Vector2, dir_or_radius: Vector2,
		color: Color, extra: Array) -> void:
	var game := get_tree().current_scene
	if game == null or not ("level" in game) or game.level == null:
		return
	var parent: Node = game.level.entities
	match kind:
		&"shockwave":
			var r: float = extra[0] if extra.size() > 0 else 60.0
			EventBus.screen_shake.emit(8.0)
			Fx.dust(parent, from, true)
			Fx.explosion(parent, from + Vector2(0, -4), r, Color(0.9, 0.8, 0.6))
		&"beam":
			var to := from + dir_or_radius * 260.0
			var mat := CanvasItemMaterial.new()
			mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
			var line := Line2D.new()
			line.width = 14.0
			line.default_color = color
			line.points = PackedVector2Array([from, to])
			line.z_index = 25
			line.material = mat
			var core := Line2D.new()
			core.width = 5.0
			core.default_color = Color.WHITE
			core.points = line.points
			core.z_index = 26
			core.material = mat
			parent.add_child(line)
			parent.add_child(core)
			var light := PointLight2D.new()
			light.texture = AssetPaths.tex(AssetPaths.LIGHT)
			light.color = color
			light.energy = 2.2
			light.texture_scale = 1.4
			parent.add_child(light)
			light.global_position = from + dir_or_radius * 130.0
			var tw := light.create_tween()
			tw.tween_property(light, "energy", 0.0, 0.6)
			tw.tween_callback(light.queue_free)
			Fx.sparks(parent, from, Color(0.7, 1.0, 1.0), 10, 90.0)
			EventBus.screen_shake.emit(3.0)
			var tw2 := line.create_tween()
			tw2.tween_interval(0.8)
			tw2.tween_property(line, "width", 0.0, 0.22)
			tw2.tween_callback(line.queue_free)
			var tw3 := core.create_tween()
			tw3.tween_interval(0.8)
			tw3.tween_property(core, "width", 0.0, 0.22)
			tw3.tween_callback(core.queue_free)
		&"hazard":
			BossHazard.spawn(parent, int(extra[0]) as BossHazard.Style, from, Vector2(extra[1], extra[2]),
					float(extra[3]), dir_or_radius, 0, 0, false)
		&"intro":
			var b := get_tree().get_first_node_in_group("bosses")
			if b:
				EventBus.boss_intro.emit(b)
				AudioManager.play_sfx(&"boss_gong", from)
		&"banner":
			EventBus.boss_banner.emit(String(extra[0]), String(extra[1]), color)
			if String(extra[1]) != "" and not String(extra[1]).begins_with("«"):
				AudioManager.play_sfx(&"boss_roar", from)
		&"aura":
			var b := get_tree().get_first_node_in_group("bosses") as Boss
			if b:
				b.set_aura(int(extra[0]), color)
				b.data_tint_override(color if int(extra[0]) < 3 else Color(1.0, 0.55, 0.5))
		&"darkness":
			Boss.darken(parent, float(extra[0]) if extra.size() > 0 else 4.0)
		&"swap":
			for p in [from, dir_or_radius]:
				Fx.sparks(parent, p + Vector2(0, -14), color, 18, 90.0)
		&"spikes":
			for spot_v in extra:
				var spot: Vector2 = spot_v
				var spike := Node2D.new()
				var poly := Polygon2D.new()
				poly.polygon = PackedVector2Array([Vector2(-5, 1), Vector2(0, -16), Vector2(5, 1)])
				poly.color = Color(color.r, color.g, color.b, 0.95)
				var side := Polygon2D.new()
				side.polygon = PackedVector2Array([Vector2(3, 1), Vector2(7, -10), Vector2(10, 1)])
				side.color = color.darkened(0.3)
				var light := PointLight2D.new()
				light.texture = AssetPaths.tex(AssetPaths.LIGHT)
				light.color = color
				light.energy = 1.4
				light.texture_scale = 0.35
				light.position = Vector2(0, -8)
				spike.add_child(poly)
				spike.add_child(side)
				spike.add_child(light)
				spike.z_index = 12
				parent.add_child(spike)
				spike.global_position = spot
				spike.scale = Vector2(1.0, 0.05)
				var tw := spike.create_tween()
				tw.tween_property(spike, "scale:y", 1.0, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				tw.tween_interval(0.8)
				tw.tween_property(spike, "scale:y", 0.0, 0.2)
				tw.tween_callback(spike.queue_free)
			EventBus.screen_shake.emit(5.0)
			Fx.sparks(parent, from + Vector2(0, -24), Color(0.6, 0.95, 1.0), 14, 120.0)


## Any peer → all: shared combat game feel (screen shake from hits).
@rpc("any_peer", "call_remote", "unreliable")
func net_shake(strength: float) -> void:
	EventBus.screen_shake.emit(strength)


## Host → clients: a damage number over an enemy (the host rolls damage).
## attacker_peer lets each machine react (portrait snarl) only to ITS hero.
@rpc("authority", "call_remote", "unreliable")
func damage_number(pos: Vector2, amount: int, crit: bool, attacker_peer: int) -> void:
	if attacker_peer == multiplayer.get_unique_id():
		EventBus.damage_dealt.emit(pos, amount, crit, false)
	else:
		# Others' hits: the number without the personal reactions.
		EventBus.damage_dealt_others.emit(pos, amount, crit)


## Host → clients: an enemy's floating text (immunity, DoT ticks, heals).
@rpc("authority", "call_remote", "unreliable")
func enemy_float_text(pos: Vector2, text: String, color: Color) -> void:
	EventBus.floating_text.emit(pos, text, color)


## Host → clients: an enemy flinched — shells replay the hurt reaction.
@rpc("authority", "call_remote", "unreliable")
func enemy_hurt(net_id: int, crit: bool = false) -> void:
	var e: Enemy = enemies.get(net_id)
	if e == null or not is_instance_valid(e) or e.is_dead():
		return
	e.net_hurt(crit)


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
			if b.boss.final:
				GameState.run_stats["victory"] = true
			EventBus.boss_defeated.emit(b.boss, e.global_position)
			# The +1 skill point the host's boss death grants locally.
			GameState.hero.skills.add_points(1)
			EventBus.message.emit("%s повержен: +1 очко навыка" % b.boss.title)
	if killer == multiplayer.get_unique_id() and e:
		EventBus.own_kill.emit(e.data)
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
		EventBus.own_kill.emit(e.data)
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


## A peer reports its hero state (death/respawn). any_peer: the DYING
## client sends this — authority mode would reject client broadcasts.
@rpc("any_peer", "call_remote", "reliable")
func player_hp(peer_id: int, hp: int, max_hp: int, dead: bool) -> void:
	# Only the hero's owner may report about it.
	if multiplayer.get_remote_sender_id() != peer_id:
		return
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
				bool(d[5]), bool(d[6]), int(d[7]), StringName(d[8]) if d.size() > 8 else &"")


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
					e.elite.id if e.elite else StringName(), e.champion, e.held, e.hp,
					e.role.id if e.role else StringName()])
	world_state.rpc_id(peer_id, GameState.floor_number, tiles, chests, stock, puzzles, list)
	if level != null:
		seal_state.rpc_id(peer_id, level.seal_kills)


## Client → host: a status on a real enemy (a guest's parry stuns it).
@rpc("any_peer", "call_remote", "reliable")
func request_enemy_status(net_id: int, id: StringName, duration: float) -> void:
	if not Net.is_host or id != &"stun":
		return
	var e: Enemy = enemies.get(net_id)
	if e and is_instance_valid(e) and not e.is_dead():
		e.status.apply(id, clampf(duration, 0.0, 2.0))


## Host → clients: kills counted toward the floor's exit seal.
@rpc("authority", "call_remote", "reliable")
func seal_state(kills: int) -> void:
	var game := get_tree().current_scene
	var level: DungeonLevel = game.level if game != null and "level" in game else null
	if level != null:
		level.set_seal_kills(kills)


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
		if consume_key and opener_peer == multiplayer.get_unique_id():
			GameState.hero.inventory.remove_by_id(&"key", 1)
		if c.mimic:
			c.queue_free()  # the monster arrives as an enemy descriptor
			continue
		c.opened = true
		c.locked = false
		c.sprite.play(&"opening")
		c.sprite.animation_finished.connect(func() -> void: c.sprite.play(&"open"), CONNECT_ONE_SHOT)


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
	# Booked for the sender: everyone sees it used, the sender applies the
	# effect to its real hero (the mirror here would only fake it) and asks
	# back for the shared parts (loot, ambush) through request_event_world.
	event.net_grantee = sender
	event.net_world_calls = 0
	event.finish()
	event_grant.rpc_id(sender, seq)


## Host → the guest who used the event: apply it to your hero.
@rpc("authority", "call_remote", "reliable")
func event_grant(seq: int) -> void:
	for e in get_tree().get_nodes_in_group("events"):
		if e.net_seq == seq:
			if not e.used:
				e.finish()
			if local_player and not local_player.dead:
				e.net_granted(local_player)
			return


## Guest → host: the world part of an event granted to me (loot roll,
## ambush). Only the grantee, only a few times per event.
@rpc("any_peer", "call_remote", "reliable")
func request_event_world(seq: int, kind: StringName, table_name: StringName, number: int, chance: float) -> void:
	if not Net.is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	for e in get_tree().get_nodes_in_group("events"):
		if e.net_seq != seq:
			continue
		if not e.used or e.net_grantee != sender or e.net_world_calls >= 4:
			return
		e.net_world_calls += 1
		match kind:
			&"loot":
				e._reward_item(table_name, clampi(number, 1, GameState.floor_number + 3))
			&"ambush":
				e._ambush(clampi(number, 1, 8), clampf(chance, 0.0, 1.0))
		return


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


## True when every LIVING hero stands near `pos` — the party may move on.
## The fallen don't count: they revive on the next floor anyway.
func party_at(pos: Vector2, radius: float) -> bool:
	var game := get_tree().current_scene
	if game == null or not ("net_players" in game):
		return true
	for p: Player in _party(game):
		if p.dead:
			continue
		if p.global_position.distance_to(pos) > radius:
			return false
	return true


## Living heroes near `pos` / all living heroes (the door prompt shows it).
func party_count_at(pos: Vector2, radius: float = GATHER_RADIUS) -> Vector2i:
	var game := get_tree().current_scene
	if game == null or not ("net_players" in game):
		return Vector2i(1, 1)
	var near := 0
	var total := 0
	for p: Player in _party(game):
		if p.dead:
			continue
		total += 1
		if p.global_position.distance_to(pos) <= radius:
			near += 1
	return Vector2i(near, total)


## The heroes in the co-op container (their sparks and trails live there too).
func _party(game: Node) -> Array[Player]:
	var list: Array[Player] = []
	for n in game.net_players.get_children():
		if n is Player:
			list.append(n)
	return list


func _hero_node(peer_id: int) -> Player:
	var game := get_tree().current_scene
	if game == null or not ("net_players" in game):
		return null
	return game.net_players.get_node_or_null("Player_%d" % peer_id) as Player


func _peer_name(peer_id: int) -> String:
	return String(Net.players.get(peer_id, {}).get("name", "Игрок"))


## Client → host: move the party (`next`, `town`, `resume`).
@rpc("any_peer", "call_remote", "reliable")
func request_floor(action: StringName) -> void:
	if not Net.is_host:
		return
	host_party_move(multiplayer.get_remote_sender_id(), action)


## Host: a living hero at an exit asks to move on. Everyone gathered: go now;
## otherwise the hero waits at the exit, everyone is told who is missing, and
## the move happens by itself when the party gathers (or is called off when
## the waiting hero walks away).
func host_party_move(peer_id: int, action: StringName) -> void:
	var p := _hero_node(peer_id)
	if p == null or p.dead:
		return
	if action == &"next" and GameState.town_return_floor <= 0 and not GameState.is_town():
		var game := get_tree().current_scene
		var lvl: DungeonLevel = game.level if game != null and "level" in game else null
		if lvl != null and lvl.is_sealed():
			return  # the exit seal holds until enough monsters fall
	if party_at(p.global_position, GATHER_RADIUS):
		_pending_action = &""
		_do_party_move(action)
		return
	var fresh := _pending_action != action or _pending_peer != peer_id
	_pending_action = action
	_pending_peer = peer_id
	_pending_pos = p.global_position
	_pending_left = 90.0
	if fresh:
		_announce("%s ждёт у выхода. Подойдите: %s" % [_peer_name(peer_id), ", ".join(_missing_names())])


func _missing_names() -> Array[String]:
	var names: Array[String] = []
	var game := get_tree().current_scene
	if game == null or not ("net_players" in game):
		return names
	for p: Player in _party(game):
		if not p.dead and p.global_position.distance_to(_pending_pos) > GATHER_RADIUS:
			names.append(_peer_name(int(String(p.name).get_slice("_", 1))))
	return names


func _check_gathering() -> void:
	var p := _hero_node(_pending_peer)
	if p == null or p.dead or p.global_position.distance_to(_pending_pos) > 160.0 or _pending_left <= 0.0:
		_pending_action = &""
		_announce("Спуск отменён: %s отошёл от выхода." % _peer_name(_pending_peer) if p != null and not p.dead and _pending_left > 0.0 else "Спуск отменён.")
		return
	if party_at(_pending_pos, GATHER_RADIUS):
		var action := _pending_action
		_pending_action = &""
		_do_party_move(action)


func _do_party_move(action: StringName) -> void:
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


## A party-wide message (host → everyone, itself included).
func _announce(text: String) -> void:
	EventBus.message.emit(text)
	party_message.rpc(text)


@rpc("authority", "call_remote", "reliable")
func party_message(text: String) -> void:
	EventBus.message.emit(text)


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


# ------------------------------------------------------------- servants
## The necromancer's machine runs its servants; everyone else gets a copy.
@rpc("any_peer", "call_remote", "reliable")
func minion_spawn(uid: int, kind: int, pos: Vector2) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if minions.has(uid) or uid / 100000 != sender:
		return
	var scene := get_tree().current_scene
	if scene == null or not ("net_players" in scene):
		return
	var owner_p := scene.net_players.get_node_or_null("Player_%d" % sender) as Player
	if owner_p == null or scene.level == null:
		return
	minions[uid] = Minion.spawn_remote(owner_p, uid, kind as Minion.Kind, pos, scene.level.entities)


@rpc("any_peer", "call_remote", "unreliable")
func minion_state(uid: int, pos: Vector2, flip: bool) -> void:
	var m: Minion = _minion(uid)
	if m:
		m.net_state(pos, flip)


@rpc("any_peer", "call_remote", "unreliable")
func minion_attack(uid: int, at: Vector2) -> void:
	var m: Minion = _minion(uid)
	if m:
		m.net_attack(at)


@rpc("any_peer", "call_remote", "reliable")
func minion_gone(uid: int) -> void:
	var m: Minion = _minion(uid)
	minions.erase(uid)
	if m:
		m._crumble()


func _minion(uid: int) -> Minion:
	if uid / 100000 != multiplayer.get_remote_sender_id():
		return null
	var m: Minion = minions.get(uid)
	if m == null or not is_instance_valid(m) or m.is_queued_for_deletion():
		minions.erase(uid)
		return null
	return m


## Host → one guest: a boss moved your hero (the Illusionist's swap).
@rpc("authority", "call_remote", "reliable")
func player_teleport(pos: Vector2) -> void:
	if local_player and not local_player.dead:
		local_player.global_position = pos
		local_player.velocity = Vector2.ZERO


## Host → one guest: a boss's roar shoves your hero away.
@rpc("authority", "call_remote", "reliable")
func player_push(impulse: Vector2) -> void:
	if local_player and not local_player.dead:
		local_player.push(impulse)
