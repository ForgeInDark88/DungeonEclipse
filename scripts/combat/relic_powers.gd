class_name RelicPowers
extends Node
## Relics that change how the hero fights (RelicItemData.power): chain
## lightning every few hits, a blood pact, a phantom double after a parry,
## a volcano on landing, an aura of thorns... The hero carries them in the
## backpack; this node (a child of the local Player) reacts to the fight:
##   on_hit / on_kill / on_defend / on_land / on_skill / on_hurt,
##   damage_mult() for every blow, hurt_mult() / dodge() for every hit taken,
##   _process for the timed ones (storm crown, aegis, momentum, war drum).
## Owner-local in co-op like weapon procs: extra damage to enemy shells goes
## through the host (Enemy.take_damage on a puppet forwards it).

var player: Player
var _p: Dictionary = {}  # power -> RelicItemData (one of each counts)
var _hits := 0
var _last_kill_pos := Vector2.INF
var _echo_ready := false  # echo bell: the blow after a skill is doubled
var _run_time := 0.0  # momentum boots: seconds of running
var _momentum := false
var _drum := 0  # war drum stacks
var _drum_t := 0.0
var _storm_t := 4.0
var _aegis_t := 0.0
var _trail_t := 0.0  # comet tail: burning trail after a defence
var _trail_tick := 0.0


func setup(p: Player) -> void:
	player = p
	p.hero.inventory.changed.connect(_refresh)
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.own_kill.connect(_on_own_kill)
	_refresh()


func _on_enemy_killed(_d: EnemyData, pos: Vector2) -> void:
	_last_kill_pos = pos


func _on_own_kill(_d: EnemyData) -> void:
	on_kill(_last_kill_pos)


func _refresh() -> void:
	_p.clear()
	for r in player.hero.relics():
		if r.power != &"":
			_p[r.power] = r
	player.hero.stats.heal_mult = 0.0 if has(&"blood_pact") else 1.0
	if not has(&"war_drum"):
		_drum = 0
		_apply_drum()


func has(power: StringName) -> bool:
	return _p.has(power)


func _a(power: StringName, fallback: float) -> float:
	var r: RelicItemData = _p.get(power)
	return r.power_a if r and r.power_a != 0.0 else fallback


func _b(power: StringName, fallback: float) -> float:
	var r: RelicItemData = _p.get(power)
	return r.power_b if r and r.power_b != 0.0 else fallback


# ------------------------------------------------------------ outgoing
## Multiplier of every blow the hero deals (attacks, shots, skills).
func damage_mult() -> float:
	var m := 1.0
	if has(&"blood_pact"):
		m *= _a(&"blood_pact", 1.6)
	if has(&"glass_heart"):
		m *= _a(&"glass_heart", 1.8)
	if has(&"berserk_totem"):
		var lost := 1.0 - float(player.hero.stats.hp) / maxf(1.0, player.hero.stats.max_hp())
		m *= 1.0 + lost * _a(&"berserk_totem", 0.9)
	if _echo_ready:
		_echo_ready = false
		m *= 2.0
		_pop(tr("Эхо!"), Color(0.7, 0.85, 1.0))
	if _momentum:
		_momentum = false
		_run_time = 0.0
		m *= _a(&"momentum_boots", 2.0)
		_pop(tr("Разгон!"), Color(1.0, 0.8, 0.4))
	if has(&"lucky_clover") and randf() < _a(&"lucky_clover", 0.1):
		m *= 3.0
		_pop(tr("Удача!"), Color(0.5, 1.0, 0.5))
	return m


## Every confirmed hit of the hero on an enemy (Hero.apply_passive_hits).
func on_hit(enemy: Enemy, dmg: int) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	_hits += 1
	var pos := enemy.global_position + Vector2(0, -10)
	if has(&"chain_lightning") and _hits % int(_a(&"chain_lightning", 4)) == 0:
		_chain(enemy, maxi(1, roundi(dmg * _b(&"chain_lightning", 0.5))), 3)
	if has(&"vampire_fang"):
		_heal(maxi(1, roundi(dmg * _a(&"vampire_fang", 0.08))), false)
	if has(&"executioner_mark") and not enemy.is_dead() and float(enemy.hp) / maxf(1.0, enemy.max_hp) <= _a(&"executioner_mark", 0.25):
		Fx.sparks(enemy.get_parent(), pos, Color(1.0, 0.25, 0.25), 10, 90.0)
		_pop(tr("Казнь!"), Color(1.0, 0.3, 0.3), enemy.global_position)
		enemy.take_damage(dmg, true, player.global_position, 0)
	if has(&"frost_core") and not enemy.is_dead():
		if _hits % 6 == 0:
			_status(enemy, &"stun", 1.0, 1.0)
			Fx.ice_burst(enemy.get_parent(), pos, 22.0, Color(0.6, 0.9, 1.0))
		elif randf() < _a(&"frost_core", 0.3):
			_status(enemy, &"slow", 2.0, 0.4)
	if has(&"gravity_well") and _hits % 5 == 0:
		for o in _enemies_near(enemy.global_position, 64.0):
			if o != enemy:
				o.apply_knockback(signf(enemy.global_position.x - o.global_position.x), 160.0)
			_status(o, &"stun", 0.4, 1.0)
		Fx.nova_ring(enemy.get_parent(), pos, 40.0, Color(0.6, 0.4, 1.0))


func on_kill(pos: Vector2) -> void:
	if pos == Vector2.INF:
		return
	if has(&"blood_pact"):
		_heal(maxi(1, roundi(player.hero.stats.max_hp() * _b(&"blood_pact", 0.03))), true)
	if has(&"corpse_bomb"):
		var dmg := maxi(1, roundi(player.hero.stats.damage() * _a(&"corpse_bomb", 0.9)))
		Fx.explosion(player.get_parent(), pos + Vector2(0, -6), 40.0, Color(0.55, 1.0, 0.35))
		for o in _enemies_near(pos, 44.0):
			o.take_damage(dmg, false, pos, 3)
	if has(&"leech_charm"):
		player.hero.stats.restore_mana(int(_a(&"leech_charm", 6)))
	if has(&"war_drum"):
		_drum = mini(_drum + 1, 5)
		_drum_t = 6.0
		_apply_drum()


func on_defend() -> void:
	if has(&"phantom_blade"):
		_phantom()
	if has(&"comet_tail"):
		_trail_t = 1.6


func on_land(fall_speed: float) -> void:
	if not has(&"volcano") or fall_speed < 280.0:
		return
	var at := player.global_position
	var r := 34.0 + minf(30.0, (fall_speed - 280.0) * 0.12)
	Fx.explosion(player.get_parent(), at + Vector2(0, -4), r, Color(1.0, 0.45, 0.15))
	EventBus.screen_shake.emit(3.0)
	var dmg := maxi(1, roundi(player.hero.stats.damage() * _a(&"volcano", 1.4)))
	for o in _enemies_near(at, r + 6.0):
		o.take_damage(dmg, false, at, 1)


func on_skill() -> void:
	if has(&"echo_bell"):
		_echo_ready = true


# ------------------------------------------------------------ incoming
## True: this hit misses the hero completely (mirror shard).
func dodge() -> bool:
	if has(&"mirror_shard") and randf() < _a(&"mirror_shard", 0.15):
		_pop(tr("Мимо!"), Color(0.8, 0.85, 1.0))
		Fx.sparks(player.get_parent(), player.global_position + Vector2(0, -14), Color(0.85, 0.9, 1.0), 8, 70.0)
		return true
	return false


func hurt_mult() -> float:
	var m := 1.0
	if has(&"glass_heart"):
		m *= _b(&"glass_heart", 1.5)
	if has(&"greed_idol"):
		m *= _b(&"greed_idol", 1.25)
	return m


func on_hurt(amount: int, from_pos: Vector2) -> void:
	if has(&"thorn_mail") and amount > 0:
		var at := player.global_position if from_pos == Vector2.INF else from_pos
		var dmg := maxi(1, roundi(amount * _a(&"thorn_mail", 1.5)))
		for o in _enemies_near(player.global_position, 48.0):
			if from_pos == Vector2.INF or o.global_position.distance_to(at) < 60.0:
				o.take_damage(dmg, false, player.global_position, 0)
				Fx.sparks(o.get_parent(), o.global_position + Vector2(0, -10), Color(0.7, 0.9, 0.4), 6, 60.0)


# ------------------------------------------------------------ timed
func _process(delta: float) -> void:
	if player == null or player.dead or _p.is_empty():
		return
	if has(&"momentum_boots"):
		if player.is_on_floor() and absf(player.velocity.x) > 60.0:
			_run_time += delta
			if _run_time >= 1.5 and not _momentum:
				_momentum = true
				Fx.sparks(player.get_parent(), player.global_position + Vector2(0, -6), Color(1.0, 0.8, 0.4), 6, 50.0)
		elif not _momentum:
			_run_time = 0.0
	if _drum > 0:
		_drum_t -= delta
		if _drum_t <= 0.0:
			_drum = 0
			_apply_drum()
	if has(&"storm_crown"):
		_storm_t -= delta
		if _storm_t <= 0.0:
			_storm_t = _a(&"storm_crown", 7.0)
			var near := _enemies_near(player.global_position, 170.0)
			if not near.is_empty():
				var t: Enemy = near[randi() % near.size()]
				_bolt(player.global_position + Vector2(randf_range(-20, 20), -120), t.global_position + Vector2(0, -8))
				t.take_damage(maxi(1, roundi(player.hero.stats.damage() * _b(&"storm_crown", 2.0))), false, t.global_position, 4)
	if has(&"holy_aegis"):
		_aegis_t -= delta
		if _aegis_t <= 0.0:
			_aegis_t = _a(&"holy_aegis", 12.0)
			if not player.status.has(&"shield"):
				player.status.apply(&"shield", 30.0, roundi(player.hero.stats.max_hp() * _b(&"holy_aegis", 0.15)))
				_pop(tr("Эгида"), Color(1.0, 0.95, 0.6))
	if _trail_t > 0.0:
		_trail_t -= delta
		_trail_tick -= delta
		if _trail_tick <= 0.0:
			_trail_tick = 0.15
			var at := player.global_position
			Fx.sparks(player.get_parent(), at + Vector2(0, -3), Color(1.0, 0.5, 0.15), 5, 30.0)
			var dmg := maxi(1, roundi(player.hero.stats.damage() * _a(&"comet_tail", 0.35)))
			for o in _enemies_near(at, 22.0):
				o.take_damage(dmg, false, at, 1)


# ------------------------------------------------------------ helpers
func _enemies_near(at: Vector2, radius: float) -> Array[Enemy]:
	var out: Array[Enemy] = []
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e and not e.is_dead() and e.global_position.distance_to(at) <= radius \
				and LineOfSight.clear(player, at + Vector2(0, -8), e.global_position + Vector2(0, -8)):
			out.append(e)
	return out


func _chain(first: Enemy, dmg: int, jumps: int) -> void:
	var from := first.global_position + Vector2(0, -10)
	var hit := {first: true}
	var cur := first
	for k in jumps:
		var best: Enemy = null
		var best_d := 90.0
		for o in _enemies_near(cur.global_position, 90.0):
			if not hit.has(o):
				var d := o.global_position.distance_to(cur.global_position)
				if d < best_d:
					best_d = d
					best = o
		if best == null:
			break
		hit[best] = true
		var to := best.global_position + Vector2(0, -10)
		_bolt(from, to)
		best.take_damage(dmg, false, from, 4)
		from = to
		cur = best
	AudioManager.play_sfx(&"cast_bolt", first.global_position, -6.0)


func _bolt(a: Vector2, b: Vector2) -> void:
	var line := Line2D.new()
	line.width = 2.0
	line.default_color = Color(0.7, 0.85, 1.0)
	var pts := PackedVector2Array([a])
	for k in range(1, 6):
		pts.append(a.lerp(b, k / 6.0) + Vector2(randf_range(-5, 5), randf_range(-5, 5)))
	pts.append(b)
	line.points = pts
	line.z_index = 22
	Fx._beam(line)
	player.get_parent().add_child(line)
	var tw := line.create_tween()
	tw.tween_property(line, "modulate:a", 0.0, 0.25)
	tw.tween_callback(line.queue_free)
	Fx.sparks(player.get_parent(), b, Color(0.7, 0.85, 1.0), 6, 70.0)


## The phantom: a translucent double strikes around the hero three times.
func _phantom() -> void:
	var parent := player.get_parent()
	var base := player.global_position
	var facing := player.facing
	var dmg := maxi(1, roundi(player.hero.stats.damage() * _a(&"phantom_blade", 0.7)))
	for k in 3:
		player.get_tree().create_timer(0.25 + k * 0.45, false).timeout.connect(func() -> void:
			if not is_instance_valid(player):
				return
			Fx.afterimage(player.visual, parent)
			var at := base + Vector2(facing * 14.0, -12)
			SlashTrail.spawn(parent, at, Vector2(facing, 0), 26.0, false, Color(0.75, 0.6, 1.0))
			for o in _enemies_near(base + Vector2(facing * 16.0, 0), 36.0):
				o.take_damage(dmg, false, base, 4))


func _apply_drum() -> void:
	player.hero.attack_speed_mult = 1.0 + 0.08 * _drum
	if _drum > 0:
		_pop(tr("Барабан ×%d") % _drum, Color(1.0, 0.6, 0.3))


func _status(e: Enemy, id: StringName, dur: float, power: float) -> void:
	if e.puppet:
		var ns := get_tree().get_first_node_in_group("net_game") as NetSync
		if ns:
			ns.request_enemy_status.rpc_id(1, e.net_id, id, dur)
	else:
		e.status.apply(id, dur, power)


func _heal(amount: int, bypass_pact: bool) -> void:
	var st := player.hero.stats
	if bypass_pact:
		var keep := st.heal_mult
		st.heal_mult = 1.0
		st.heal(amount)
		st.heal_mult = keep
	else:
		st.heal(amount)


func _pop(text: String, color: Color, at := Vector2.INF) -> void:
	var p := player.global_position if at == Vector2.INF else at
	EventBus.floating_text.emit(p + Vector2(0, -30), text, color)
