class_name Boss
extends Enemy
## Boss AI on top of Enemy (HP, damage, statuses, animations, death):
## phases by HP threshold, each with a pool of telegraphed BossAttacks.

signal phase_changed(index: int)

enum Act { INTRO, IDLE, WINDUP, ACTING, RECOVER }

var boss: BossData
var phase_index := 0
var act: Act = Act.INTRO
var _act_time := 1.2
var _attack: BossAttack
var _last_attack: BossAttack
var _target_pos := Vector2.ZERO
var _contact_cd := 0.0
var _hop_cd := 0.0
## Enrage: below ENRAGE_THRESHOLD the boss attacks faster, moves and
## hits harder - "finish it or die" in both directions.
var _enraged := false
var _jump_from := Vector2.ZERO
var _jump_t := 0.0
var _jump_arc := 80.0
var _spike_spots: Array[Vector2] = []
var _beam_dir := Vector2.RIGHT
var _beam_line: Line2D = null
var _beam_core: Line2D = null
var _beam_time := 0.0
var _beam_tick := 0.0
## Presentation: the intro waits for the heroes to come close; phase changes
## make the boss untouchable for a moment (the roar).
const INTRO_RANGE := 230.0
const INTRO_TIME := 2.6
const PHASE_LOCK := 2.5
var _intro_started := false
var _phase_lock := 0.0
var _aura: CPUParticles2D
var _shield: Sprite2D


## Enrage below this HP fraction: faster, hits harder, contact hurts.
const ENRAGE_THRESHOLD := 0.25

func setup(p_data: EnemyData, p_floor: int, p_elite: EliteAffixData = null, p_champion := false) -> void:
	super(p_data, p_floor, p_elite, p_champion)
	boss = p_data as BossData
	# Bosses hit 1.5x harder than the floor curve: they must be feared.
	damage = roundi(damage * 1.5)


func _ready() -> void:
	super()
	add_to_group("bosses")
	scale = Vector2.ONE
	hp_bar.visible = false  # the HUD shows a big bar instead
	if boss.glow_color.a > 0.0:
		var glow := PointLight2D.new()
		glow.texture = AssetPaths.tex(AssetPaths.LIGHT)
		glow.color = boss.glow_color
		glow.texture_scale = boss.glow_scale
		glow.energy = 1.3
		glow.position = Vector2(0, -data.collision_size.y * 0.6)
		add_child(glow)
	EventBus.boss_spawned.emit(self)


func current_phase() -> BossPhase:
	return boss.phases[phase_index] if phase_index < boss.phases.size() else null


## Co-op: the closest standing hero gets the boss's attention.
## Every living hero on this machine (the local one and guests' puppets).
func _alive_heroes() -> Array[Player]:
	var out: Array[Player] = []
	for n in get_tree().get_nodes_in_group("player"):
		var p := n as Player
		if p != null and not p.dead:
			out.append(p)
	return out


## Co-op: boss ability visuals exist only on the host - echo them to guests.
func _net_boss_fx(kind: StringName, from: Vector2, dir: Vector2, color: Color, extra: Array) -> void:
	if not Net.active or not Net.is_host:
		return
	var ns = get_tree().get_first_node_in_group("net_game")
	if ns:
		ns.boss_fx.rpc(kind, from, dir, color, extra)


func _nearest_alive_player() -> Player:
	var best: Player = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group("player"):
		var pl := n as Player
		if pl == null or pl.dead:
			continue
		var d := global_position.distance_to(pl.global_position)
		if d < best_d:
			best_d = d
			best = pl
	return best


## The big HUD bar follows the real numbers whatever changed them: hits,
## poison and fire ticks, heals, the host's snapshots on a co-op shell.
var _shown_hp := Vector2i(-1, -1)


func _process(_delta: float) -> void:
	var now := Vector2i(maxi(hp, 0), max_hp)
	if now != _shown_hp:
		_shown_hp = now
		EventBus.boss_hp_changed.emit(now.x, now.y)


func _physics_process(delta: float) -> void:
	if puppet:
		# Boss shells have no local phase machine; mirror the host's Enemy
		# state/timers so windup and attack animations are visible to guests.
		var before := global_position
		var since := Time.get_ticks_msec() / 1000.0 - _net_last
		var target := _net_target
		if since > 0.12 and _net_vel.length() > 1.0:
			target += _net_vel * minf(since, 0.4)
		global_position = global_position.lerp(target, minf(1.0, delta * 12.0))
		_attack_anim_left = maxf(0.0, _attack_anim_left - delta)
		var dx: float = (global_position.x - before.x) / maxf(delta, 0.0001)
		if state == State.HURT:
			_play(&"hurt")
		elif state == State.ATTACK:
			_play(&"windup")
		elif _attack_anim_left > 0.0:
			_play(&"attack")
		elif data.behavior == EnemyData.Behavior.FLYER or absf(dx) > 12.0:
			if absf(dx) > 12.0:
				sprite.flip_h = dx < 0.0
			_play(_move_anim())
		else:
			_play(&"idle")
		return
	if _dead:
		return
	# The boss switches to the closest living hero (guests included).
	_retarget -= delta
	if _retarget <= 0.0:
		_retarget = 0.7
		var best := _nearest_alive_player()
		if best != null and best != _player and (_player == null or not is_instance_valid(_player)
				or _player.dead or global_position.distance_to(best.global_position)
				< global_position.distance_to(_player.global_position) * 0.75):
			_player = best
	if _player == null or not is_instance_valid(_player) or _player.dead:
		_player = _nearest_alive_player()
	_contact_cd = maxf(0.0, _contact_cd - delta)
	_hop_cd = maxf(0.0, _hop_cd - delta)
	_phase_lock = maxf(0.0, _phase_lock - delta)
	# Boss._physics_process fully replaces Enemy's, so the one-shot "attack"
	# animation timer must be decayed here as well — otherwise it stays > 0
	# forever after the first skill and the sprite freezes on its last frame.
	_attack_anim_left = maxf(0.0, _attack_anim_left - delta)
	_check_phase()
	var flyer := data.behavior == EnemyData.Behavior.FLYER
	if not flyer:
		velocity.y = minf(velocity.y + GRAVITY * delta, 500.0)
	if status.is_stunned():
		velocity.x = move_toward(velocity.x, 0.0, 800.0 * delta)
		move_and_slide()
		_play(&"hurt")
		return
	_act_time -= delta
	match act:
		Act.INTRO:
			velocity.x = 0.0
			if not _intro_started:
				_act_time = INTRO_TIME
				if hp < max_hp or (_player and global_position.distance_to(_player.global_position) < INTRO_RANGE):
					_start_intro()
			elif _act_time <= 0.0:
				_enter(Act.IDLE, 0.4)
		Act.IDLE, Act.RECOVER:
			_move_idle(delta, flyer)
			if _act_time <= 0.0 and _player and not _player.dead:
				_choose_attack()
		Act.WINDUP:
			velocity.x = move_toward(velocity.x, 0.0, 800.0 * delta)
			if flyer:
				velocity.y = move_toward(velocity.y, 0.0, 800.0 * delta)
			if _act_time <= 0.0:
				_set_flash(0.0)
				_start_attack()
		Act.ACTING:
			_update_attack_act(delta)
	move_and_slide()
	_clamp_to_arena()
	if absf(velocity.x) > 1.0:
		sprite.flip_h = velocity.x < 0.0
	_contact_damage()
	_update_boss_animation()


## The boss never leaves its arena: flyers chasing a hero over the edge,
## teleports, illusions and swaps are all kept inside the walls.
func _clamp_to_arena() -> void:
	var lvl := _level()
	if lvl == null:
		return
	var b := lvl.bounds_px().grow(-float(DungeonLevel.TILE))
	var half := data.collision_size.x * 0.5 + 2.0
	var p := global_position
	var lo := Vector2(b.position.x + half, b.position.y + data.collision_size.y + 2.0)
	var hi := Vector2(b.end.x - half, b.end.y)
	var c := p.clamp(lo, hi)
	if c != p:
		global_position = c
		if c.x != p.x:
			velocity.x = 0.0
		if c.y != p.y:
			velocity.y = 0.0


func _enter(new_act: Act, time: float) -> void:
	act = new_act
	_act_time = time


func _check_phase() -> void:
	var ratio := float(hp) / max_hp
	while phase_index + 1 < boss.phases.size() and ratio <= boss.phases[phase_index + 1].hp_threshold:
		phase_index += 1
		var ph := current_phase()
		data_tint_override(ph.tint)
		_phase_roar(ph.message, ph.tint)
		phase_changed.emit(phase_index)
	# Enrage: the last stand - faster cadence, heavier contact, red haze.
	if not _enraged and ratio <= ENRAGE_THRESHOLD and ratio > 0.0:
		_enraged = true
		_banner(display_name(), "в ярости!", Color(1.0, 0.3, 0.2))
		EventBus.screen_shake.emit(8.0)
		Fx.sparks(get_parent(), global_position + Vector2(0, -24), Color(1.0, 0.25, 0.15), 40, 180.0)
		data_tint_override(Color(1.0, 0.55, 0.5))
		set_aura(3, Color(1.0, 0.3, 0.15))
		_net_boss_fx(&"aura", global_position, Vector2.ZERO, Color(1.0, 0.3, 0.15), [3])


func data_tint_override(tint: Color) -> void:
	sprite.modulate = tint


func _move_idle(delta: float, flyer: bool) -> void:
	if _player == null:
		return
	var spd := data.speed * current_phase().speed_mult * (1.5 if _enraged else 1.0)
	if flyer:
		var target := _player.global_position + Vector2(signf(global_position.x - _player.global_position.x) * 70.0, -70.0)
		velocity = velocity.move_toward((target - global_position).limit_length(spd * 2.0), 300.0 * delta)
	else:
		var dx := _player.global_position.x - global_position.x
		var dy := _player.global_position.y - global_position.y
		if dy < -48.0 and absf(dx) < 160.0 and is_on_floor() and _hop_cd <= 0.0:
			# The hero camps on the arena boards: hop up after them, or the
			# walker would just pace under the platform out of reach.
			velocity.y = -370.0
			velocity.x = signf(dx) * clampf(absf(dx) * 1.2, 60.0, 160.0)
			_hop_cd = 1.5
		else:
			velocity.x = signf(dx) * spd if absf(dx) > 30.0 else 0.0


func _choose_attack() -> void:
	var ph := current_phase()
	if ph == null or ph.attacks.is_empty():
		_enter(Act.RECOVER, 1.0)
		return
	var options := ph.attacks.filter(func(a: BossAttack) -> bool: return a != _last_attack) if ph.attacks.size() > 1 else ph.attacks
	_attack = options.pick_random()
	_last_attack = _attack
	sprite.flip_h = _player.global_position.x < global_position.x
	_set_flash(0.4, Color(1.0, 0.2, 0.1))
	var lvl := _level()
	var parent := get_parent()
	match _attack.kind:
		BossAttack.Kind.CHARGE:
			var dir := signf(_player.global_position.x - global_position.x)
			Telegraph.line(parent, global_position + Vector2(0, -4), dir * 200.0, _attack.windup)
			_target_pos = Vector2(dir, 0)
		BossAttack.Kind.JUMP_SLAM:
			# Aim at the surface under the hero — high arena boards included,
			# so camping on a platform still gets slammed.
			var ground := _ground_below(_player.global_position + Vector2(0, -20.0), _level())
			_target_pos = Vector2(_player.global_position.x, ground.y)
			Telegraph.circle(parent, _target_pos, _attack.radius, _attack.windup + 0.5)
		BossAttack.Kind.FIRE_RAIN:
			_rain_spots.clear()
			for i in _attack.count:
				var x := _player.global_position.x + randf_range(-120.0, 120.0)
				var ground := _ground_below(Vector2(x, _player.global_position.y - 20.0), lvl)
				_rain_spots.append(ground)
				Telegraph.circle(parent, ground, _attack.radius, _attack.windup + 0.6)
		BossAttack.Kind.SPIKES:
			# Waves of crystal: a line chasing the hero plus a ring around them.
			var lvl3 := _level()
			_spike_spots.clear()
			if lvl3:
				var aim := (_player.global_position - global_position).normalized()
				for i in 5:
					_spike_spots.append(_ground_below(global_position + aim * (26.0 + i * 32.0), lvl3))
				for i in 6:
					var sa := TAU * i / 6.0
					_spike_spots.append(_ground_below(_player.global_position + Vector2.from_angle(sa) * 44.0, lvl3))
				for spot in _spike_spots:
					Telegraph.circle(parent, spot, _attack.radius * 0.7, _attack.windup + 0.5)
		BossAttack.Kind.BEAM:
			# A grinding beam through the hero's position: dots along the path.
			_beam_dir = (_player.global_position - global_position + Vector2(0, -18)).normalized()
			for i in 7:
				Telegraph.circle(parent, global_position + Vector2(0, -22) + _beam_dir * (30.0 + i * 34.0), 12.0, _attack.windup)
		BossAttack.Kind.TELEPORT, BossAttack.Kind.ILLUSIONS:
			var tw := create_tween()
			tw.tween_property(sprite, "modulate:a", 0.2, _attack.windup)
		BossAttack.Kind.RAISE_DEAD:
			_spike_spots.clear()
			for p in _alive_heroes():
				_spike_spots.append(_ground_below(p.global_position + Vector2(0, -20), lvl))
			while _spike_spots.size() < _attack.count:
				var x := _player.global_position.x + randf_range(-110.0, 110.0)
				_spike_spots.append(_ground_below(Vector2(x, _player.global_position.y - 20.0), lvl))
			for spot in _spike_spots:
				var t := Telegraph.circle(parent, spot, _attack.radius, _attack.windup + 0.3)
				t.color = Color(0.9, 0.85, 0.6)
		BossAttack.Kind.FIRE_WALL:
			var b := lvl.bounds_px() if lvl else Rect2(global_position - Vector2(300, 200), Vector2(600, 400))
			var ground := _ground_below(global_position + Vector2(0, -20), lvl)
			# The wall rolls out from the boss's side of the arena toward the heroes.
			var from_left := global_position.x < _player.global_position.x
			_target_pos = Vector2(b.position.x + 24.0 if from_left else b.end.x - 24.0, ground.y)
			Telegraph.line(parent, _target_pos + Vector2(0, -2), (b.size.x - 48.0) * (1.0 if from_left else -1.0), _attack.windup + 0.3)
			if _attack.count >= 2:
				Telegraph.line(parent, Vector2(b.end.x - 24.0 if from_left else b.position.x + 24.0, ground.y - 2.0),
						(b.size.x - 48.0) * (-1.0 if from_left else 1.0), _attack.windup + 0.3)
		BossAttack.Kind.MIRROR_SWAP:
			_target_pos = _player.global_position
			var t := Telegraph.circle(parent, _player.global_position + Vector2(0, -10), 18.0, _attack.windup)
			t.color = Color(0.8, 0.5, 1.0)
			var t2 := Telegraph.circle(parent, global_position + Vector2(0, -20), 18.0, _attack.windup)
			t2.color = Color(0.8, 0.5, 1.0)
		BossAttack.Kind.QUAKE:
			_rain_spots.clear()
			var b := lvl.bounds_px() if lvl else Rect2(global_position - Vector2(300, 200), Vector2(600, 400))
			for p in _alive_heroes():
				_rain_spots.append(_ground_below(p.global_position + Vector2(0, -20), lvl))
			while _rain_spots.size() < _attack.count:
				var x := randf_range(b.position.x + 30.0, b.end.x - 30.0)
				_rain_spots.append(_ground_below(Vector2(x, global_position.y - 40.0), lvl))
			for spot in _rain_spots:
				Telegraph.circle(parent, spot, _attack.radius, _attack.windup + 0.6)
			EventBus.screen_shake.emit(3.0)
			AudioManager.play_sfx(&"cast_quake", global_position)
		BossAttack.Kind.TOLL:
			var t := Telegraph.circle(parent, _ground_below(global_position + Vector2(0, -20), lvl), 46.0, _attack.windup)
			t.color = Color(0.55, 1.0, 0.85)
		BossAttack.Kind.ASH_SWEEP:
			var ground := _ground_below(global_position + Vector2(0, -20), lvl)
			Telegraph.line(parent, ground + Vector2(0, -2), _attack.radius, _attack.windup)
			Telegraph.line(parent, ground + Vector2(0, -2), -_attack.radius, _attack.windup)
		BossAttack.Kind.DARKNESS:
			var tw := create_tween()
			tw.tween_property(sprite, "modulate:a", 0.5, _attack.windup)
	_enter(Act.WINDUP, _attack.windup)


var _rain_spots: Array[Vector2] = []


func _ground_below(from: Vector2, lvl: DungeonLevel) -> Vector2:
	if lvl == null:
		return from
	for i in 20:
		var p := from + Vector2(0, i * 16)
		if lvl.is_ground_at(p + Vector2(0, 2)):
			return Vector2(p.x, floorf((p.y + 2) / 16.0) * 16.0)
	return from


func _start_attack() -> void:
	var a := _attack
	var dmg := roundi(damage * a.damage_mult)
	match a.kind:
		BossAttack.Kind.CHARGE:
			velocity.x = _target_pos.x * a.speed * current_phase().speed_mult
			_enter(Act.ACTING, 1.4)
		BossAttack.Kind.JUMP_SLAM:
			_jump_from = global_position
			_jump_t = 0.0
			# Higher targets (boards) need a higher arc than the flat-floor hop.
			_jump_arc = maxf(80.0, _jump_from.y - _target_pos.y + 48.0)
			_enter(Act.ACTING, 0.6)
		BossAttack.Kind.PROJECTILE_FAN:
			_fan(a, dmg)
			_attack_anim_left = 0.3
			_end_attack()
		BossAttack.Kind.SUMMON:
			_summon(a)
			_end_attack()
		BossAttack.Kind.TELEPORT:
			var side := -1.0 if randf() < 0.5 else 1.0
			global_position = _player.global_position + Vector2(side * 60.0, -60.0)
			_clamp_to_arena()
			sprite.modulate.a = 1.0
			Fx.explosion(get_parent(), global_position + Vector2(0, -20), 30.0, Color(1.0, 0.5, 0.2))
			_fan(a, dmg)
			_end_attack()
		BossAttack.Kind.FIRE_RAIN:
			for spot in _rain_spots:
				_drop_fire(spot, a, dmg)
			_end_attack()
		BossAttack.Kind.ILLUSIONS:
			_illusions(a)
			_fan(a, dmg)
			_end_attack()
		BossAttack.Kind.SPIKES:
			_erupt_spikes(a, dmg)
			_attack_anim_left = 0.4
			_end_attack()
		BossAttack.Kind.BEAM:
			_fire_beam()
			_beam_time = 0.55
			_beam_tick = 0.0
			_enter(Act.ACTING, 0.62)
		BossAttack.Kind.RAISE_DEAD:
			_erupt_spikes(a, dmg, Color(0.92, 0.88, 0.72))
			_summon_at(a, _spike_spots)
			_attack_anim_left = 0.4
			_end_attack()
		BossAttack.Kind.FIRE_WALL:
			_fire_walls(a, dmg)
			_attack_anim_left = 0.4
			_end_attack()
		BossAttack.Kind.MIRROR_SWAP:
			_mirror_swap(a, dmg)
			_end_attack()
		BossAttack.Kind.QUAKE:
			for spot in _rain_spots:
				_drop_fire(spot, a, dmg)
			EventBus.screen_shake.emit(7.0)
			_net_shake(7.0)
			_attack_anim_left = 0.4
			_end_attack()
		BossAttack.Kind.TOLL:
			_toll(a, dmg)
			_attack_anim_left = 0.4
			_end_attack()
		BossAttack.Kind.ASH_SWEEP:
			_ash_sweep(a, dmg)
			_attack_anim_left = 0.4
			_end_attack()
		BossAttack.Kind.DARKNESS:
			sprite.modulate.a = 1.0
			darken(get_parent(), a.lifetime)
			_net_boss_fx(&"darkness", global_position, Vector2.ZERO, Color.BLACK, [a.lifetime])
			_beam_time = a.lifetime  # reused as the darkness timer
			_beam_tick = 0.4
			_enter(Act.ACTING, a.lifetime)


func _end_attack() -> void:
	_enter(Act.RECOVER, current_phase().attack_interval * (0.6 if _enraged else 1.0))


func _update_attack_act(delta: float) -> void:
	var a := _attack
	match a.kind:
		BossAttack.Kind.CHARGE:
			_attack_anim_left = 0.1
			if is_on_wall() or _act_time <= 0.0:
				velocity.x = 0.0
				if is_on_wall():
					EventBus.screen_shake.emit(4.0)
					Fx.dust(get_parent(), global_position, true)
				_end_attack()
		BossAttack.Kind.JUMP_SLAM:
			_jump_t += delta / 0.6
			var t := clampf(_jump_t, 0.0, 1.0)
			var p := _jump_from.lerp(_target_pos, t)
			p.y -= sin(t * PI) * _jump_arc
			velocity = (p - global_position) / maxf(delta, 0.001)
			if t >= 1.0:
				velocity = Vector2.ZERO
				_shockwave(a)
				_end_attack()
		BossAttack.Kind.BEAM:
			_beam_time -= delta
			_beam_tick -= delta
			if _beam_line:
				_beam_line.width = 14.0 + sin(_beam_time * 40.0) * 3.0
				if _beam_core:
					_beam_core.width = _beam_line.width * 0.35
			if _beam_tick <= 0.0:
				_beam_tick = 0.22
				var from := global_position + Vector2(0, -22)
				var to := from + _beam_dir * 260.0
				var ab := to - from
				for p in _alive_heroes():
					var ap := p.global_position + Vector2(0, -10)
					var tt := clampf((ap - from).dot(ab) / ab.length_squared(), 0.0, 1.0)
					var dist := (ap - (from + ab * tt)).length()
					if dist <= 15.0:
						p.take_damage(roundi(damage * a.damage_mult * 0.45), global_position, a.damage_type)
						_apply_attack_effects(a, p)
				for n in get_tree().get_nodes_in_group("minions"):
					var mn := n as Minion
					if mn == null:
						continue
					var mp := mn.global_position + Vector2(0, -10)
					var mt := clampf((mp - from).dot(ab) / ab.length_squared(), 0.0, 1.0)
					if (mp - (from + ab * mt)).length() <= 15.0:
						mn.take_damage(roundi(damage * a.damage_mult * 0.45), global_position)
			if _beam_time <= 0.0:
				_fade_beam()
				_end_attack()
		BossAttack.Kind.DARKNESS:
			# Out of the dark: a fan every second, then back to the fight.
			_beam_time -= delta
			_beam_tick -= delta
			_move_idle(delta, data.behavior == EnemyData.Behavior.FLYER)
			if _beam_tick <= 0.0 and _player:
				_beam_tick = 1.0
				_fan(a, roundi(damage * a.damage_mult))
				_attack_anim_left = 0.3
			if _beam_time <= 0.0:
				_end_attack()


func _shockwave(a: BossAttack) -> void:
	EventBus.screen_shake.emit(8.0)
	Fx.dust(get_parent(), global_position, true)
	Fx.explosion(get_parent(), global_position + Vector2(0, -4), a.radius, Color(0.9, 0.8, 0.6))
	_net_boss_fx(&"shockwave", global_position, Vector2.ZERO, Color.WHITE, [a.radius])
	Minion.hurt_in_radius(get_tree(), global_position, a.radius + 6.0, roundi(damage * a.damage_mult))
	for p in _alive_heroes():
		if p.global_position.distance_to(global_position) <= a.radius + 6.0 \
				and LineOfSight.can_hit(self, global_position + Vector2(0, -8), p):
			p.take_damage(roundi(damage * a.damage_mult), global_position, a.damage_type)
			_apply_attack_effects(a, p)


## Crystals burst from the telegraphed spots; standing on one hurts.
func _erupt_spikes(a: BossAttack, dmg: int, tint := Color(0.62, 0.93, 1.0)) -> void:
	var parent := get_parent()
	for spot in _spike_spots:
		var spike := Node2D.new()
		var poly := Polygon2D.new()
		poly.polygon = PackedVector2Array([Vector2(-5, 1), Vector2(0, -16), Vector2(5, 1)])
		poly.color = Color(tint.r, tint.g, tint.b, 0.95)
		var side := Polygon2D.new()
		side.polygon = PackedVector2Array([Vector2(3, 1), Vector2(7, -10), Vector2(10, 1)])
		side.color = tint.darkened(0.3)
		var light := PointLight2D.new()
		light.texture = AssetPaths.tex(AssetPaths.LIGHT)
		light.color = tint
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
		for p in _alive_heroes():
			if p.global_position.distance_to(spot) <= a.radius \
					and LineOfSight.can_hit(self, spot, p):
				p.take_damage(dmg, spot, a.damage_type)
				_apply_attack_effects(a, p)
		Minion.hurt_in_radius(get_tree(), spot, a.radius, dmg)
		tw.tween_interval(0.8)
		tw.tween_property(spike, "scale:y", 0.0, 0.2)
		tw.tween_callback(spike.queue_free)
	EventBus.screen_shake.emit(5.0)
	Fx.sparks(parent, global_position + Vector2(0, -24), Color(0.6, 0.95, 1.0), 14, 120.0)
	AudioManager.play_sfx(&"dig", global_position)
	_net_boss_fx(&"spikes", global_position, Vector2.ZERO, tint, _spike_spots.duplicate())


## A grinding crystal beam along the telegraphed line.
func _fire_beam() -> void:
	var parent := get_parent()
	var from := global_position + Vector2(0, -22)
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_beam_line = Line2D.new()
	_beam_line.width = 14.0
	_beam_line.default_color = Color(0.55, 0.95, 1.0)
	_beam_line.points = PackedVector2Array([from, from + _beam_dir * 260.0])
	_beam_line.z_index = 25
	_beam_line.material = mat
	_beam_core = Line2D.new()
	_beam_core.width = 5.0
	_beam_core.default_color = Color.WHITE
	_beam_core.points = _beam_line.points
	_beam_core.z_index = 26
	_beam_core.material = mat
	parent.add_child(_beam_line)
	parent.add_child(_beam_core)
	var light := PointLight2D.new()
	light.texture = AssetPaths.tex(AssetPaths.LIGHT)
	light.color = Color(0.55, 0.95, 1.0)
	light.energy = 2.2
	light.texture_scale = 1.4
	parent.add_child(light)
	light.global_position = from + _beam_dir * 130.0
	var tw := light.create_tween()
	tw.tween_property(light, "energy", 0.0, 0.6)
	tw.tween_callback(light.queue_free)
	Fx.sparks(parent, from, Color(0.7, 1.0, 1.0), 10, 90.0)
	AudioManager.play_sfx(&"enemy_shoot", global_position)
	EventBus.screen_shake.emit(3.0)
	_net_boss_fx(&"beam", from, _beam_dir, Color(0.55, 0.95, 1.0), [])


func _fade_beam() -> void:
	for line: Line2D in [_beam_line, _beam_core]:
		if line:
			var tw := line.create_tween()
			tw.tween_property(line, "width", 0.0, 0.22)
			tw.tween_callback(line.queue_free)
	_beam_line = null
	_beam_core = null


func _fan(a: BossAttack, dmg: int) -> void:
	var lvl := _level()
	if lvl == null or _player == null:
		return
	var from := global_position + Vector2(0, -data.collision_size.y * 0.6)
	var base := (_player.global_position + Vector2(0, -10) - from).angle()
	for i in a.count:
		var ang := base + deg_to_rad(lerpf(-a.spread_degrees, a.spread_degrees, float(i) / maxf(1.0, a.count - 1)) if a.count > 1 else 0.0)
		var p: Projectile = PROJECTILE_SCENE.instantiate()
		p.setup(a.projectile_texture, Vector2.from_angle(ang), a.projectile_speed, dmg, "player")
		p.damage_type = a.damage_type
		p.blast_color = Color(1.0, 0.5, 0.2)
		p.lifetime = 3.0
		p.on_hit = func(target: Node, _d: int) -> void: _apply_attack_effects(a, target)
		lvl.add_entity(p, from)
	AudioManager.play_sfx(&"enemy_shoot", global_position)


func _drop_fire(spot: Vector2, a: BossAttack, dmg: int) -> void:
	var lvl := _level()
	if lvl == null:
		return
	var p: Projectile = PROJECTILE_SCENE.instantiate()
	p.setup(a.projectile_texture, Vector2.DOWN, a.projectile_speed * 1.5, dmg, "player")
	p.damage_type = a.damage_type
	p.blast_radius = a.radius * 0.6
	p.blast_color = Color(1.0, 0.45, 0.15)
	p.lifetime = 2.0
	p.on_hit = func(target: Node, _d: int) -> void: _apply_attack_effects(a, target)
	# Falls from below the ceiling, never from inside the bricks.
	lvl.add_entity(p, LineOfSight.safe_point(self, spot + Vector2(0, -8), spot + Vector2(0, -150)))


func _summon(a: BossAttack) -> void:
	_summons.assign(_summons.filter(func(n) -> bool: return is_instance_valid(n) and not n.is_dead()))
	var lvl := _level()
	if a.summon == null or lvl == null:
		return
	for i in mini(a.count, a.max_summons - _summons.size()):
		var e: Enemy = (load("res://scenes/enemies/enemy.tscn") as PackedScene).instantiate()
		e.setup(a.summon, floor_number)
		var side := -1.0 if i % 2 == 0 else 1.0
		lvl._net_tag(e)  # co-op: guests must see (and can hit) the summons
		lvl.add_entity(e, global_position + Vector2(side * (30.0 + i * 12.0), -8.0))
		lvl._net_broadcast_enemy(e, null, false)
		Fx.sparks(lvl.entities, e.global_position + Vector2(0, -8), Color(0.7, 0.4, 1.0), 12, 70.0)
		_summons.append(e)


## The boss and its copies appear on a ring around the hero; nobody can tell
## which one is real (the copies die from one hit and give nothing).
func _illusions(a: BossAttack) -> void:
	_summons.assign(_summons.filter(func(n) -> bool: return is_instance_valid(n) and not n.is_dead()))
	var lvl := _level()
	if lvl == null or _player == null:
		sprite.modulate.a = 1.0
		return
	var n := mini(a.count, a.max_summons - _summons.size()) if a.summon else 0
	var center := _player.global_position + Vector2(0, -20)
	var spots: Array[Vector2] = []
	var turn := randf() * TAU
	for i in n + 1:
		var ang := turn + TAU * i / (n + 1)
		var p := center + Vector2(cos(ang) * 110.0, -40.0 - absf(sin(ang)) * 40.0)
		spots.append(LineOfSight.safe_point(self, center, p))
	spots.shuffle()
	var parent := get_parent()
	Fx.sparks(parent, global_position + Vector2(0, -20), Color(0.8, 0.5, 1.0), 20, 90.0)
	global_position = spots.pop_back()
	_clamp_to_arena()
	sprite.modulate.a = 1.0
	for p in spots:
		var e: Enemy = (load("res://scenes/enemies/enemy.tscn") as PackedScene).instantiate()
		e.setup(a.summon, floor_number)
		lvl._net_tag(e)
		lvl.add_entity(e, p)
		lvl._net_broadcast_enemy(e, null, false)
		e.modulate = sprite.modulate
		Fx.sparks(lvl.entities, p + Vector2(0, -20), Color(0.8, 0.5, 1.0), 12, 70.0)
		_summons.append(e)
		get_tree().create_timer(a.lifetime, false).timeout.connect(func() -> void:
			if is_instance_valid(e) and not e.is_dead():
				Fx.sparks(e.get_parent(), e.global_position + Vector2(0, -20), Color(0.8, 0.5, 1.0), 10, 60.0)
				e.queue_free())
	EventBus.screen_shake.emit(3.0)


# ------------------------------------------------------- presentation
func _start_intro() -> void:
	if _intro_started:
		return
	_intro_started = true
	act = Act.INTRO
	_act_time = INTRO_TIME
	EventBus.boss_intro.emit(self)
	_net_boss_fx(&"intro", global_position, Vector2.ZERO, boss.glow_color, [])
	AudioManager.play_sfx(&"boss_gong", global_position)
	_attack_anim_left = 0.6


## A new phase: the boss roars, shoves everyone back, can't be hurt for a
## moment, and the banner tells what changed.
## A phase is never skipped: until the next one starts, hits stop at its
## threshold (the roar and the shield always play).
func min_hp() -> int:
	if _dead or phase_index + 1 >= boss.phases.size():
		return 0
	return maxi(1, floori(max_hp * boss.phases[phase_index + 1].hp_threshold))


func _phase_roar(message: String, tint: Color) -> void:
	_phase_lock = PHASE_LOCK
	show_shield(PHASE_LOCK, tint)
	_net_boss_fx(&"shield", global_position, Vector2.ZERO, tint, [PHASE_LOCK])
	_enter(Act.RECOVER, PHASE_LOCK)
	_fade_beam()
	_banner(boss.display_name, message if message != "" else "Новая фаза!", tint)
	AudioManager.play_sfx(&"boss_roar", global_position)
	EventBus.screen_shake.emit(9.0)
	_net_shake(9.0)
	Fx.sparks(get_parent(), global_position + Vector2(0, -24), tint, 40, 180.0)
	Fx.explosion(get_parent(), global_position + Vector2(0, -data.collision_size.y * 0.5), 70.0, tint)
	_net_boss_fx(&"shockwave", global_position, Vector2.ZERO, tint, [70.0])
	for p in _alive_heroes():
		var rel := p.global_position - global_position
		if rel.length() < 140.0:
			var impulse := Vector2(signf(rel.x if absf(rel.x) > 1.0 else 1.0) * 260.0, -150.0)
			if p.puppet:
				var ns = get_tree().get_first_node_in_group("net_game")
				if ns:
					ns.player_push.rpc_id(p.peer_id, impulse)
			else:
				p.push(impulse)
	set_aura(phase_index, tint)
	_net_boss_fx(&"aura", global_position, Vector2.ZERO, tint, [phase_index])


## A glowing sphere around the boss while it cannot be hurt.
func show_shield(duration: float, tint: Color) -> void:
	if _shield == null:
		_shield = Sprite2D.new()
		_shield.texture = AssetPaths.tex(AssetPaths.SPRITES_DIR + "fx/shield_bubble.png")
		var m := CanvasItemMaterial.new()
		m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_shield.material = m
		_shield.z_index = 3
		add_child(_shield)
	var size := maxf(data.collision_size.x * 1.8, data.collision_size.y * 1.3)
	var base := Vector2.ONE * size / 30.0
	_shield.position = Vector2(0, -data.collision_size.y * 0.5)
	_shield.modulate = Color(tint.r, tint.g, tint.b, 0.0).lerp(Color(0.7, 0.85, 1.0, 0.0), 0.5)
	_shield.visible = true
	_shield.scale = base * 0.4
	var tw := _shield.create_tween()
	tw.tween_property(_shield, "scale", base, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_shield, "modulate:a", 0.85, 0.25)
	var pulses := maxi(1, int((duration - 0.6) / 0.5))
	for i in pulses:
		tw.tween_property(_shield, "modulate:a", 0.55, 0.25)
		tw.tween_property(_shield, "modulate:a", 0.85, 0.25)
	tw.tween_property(_shield, "modulate:a", 0.0, 0.3)
	tw.parallel().tween_property(_shield, "scale", base * 1.3, 0.3)
	tw.tween_callback(func() -> void: _shield.visible = false)


## A blow glances off the shield (or the intro): a quick bright ripple.
func _shield_flash() -> void:
	if _shield and _shield.visible:
		_shield.modulate.a = 1.0
	else:
		Fx.sparks(get_parent(), global_position + Vector2(0, -data.collision_size.y * 0.5), Color(0.75, 0.85, 1.0), 4, 40.0)


func _banner(title: String, text: String, color: Color) -> void:
	EventBus.boss_banner.emit(title, text, color)
	_net_boss_fx(&"banner", global_position, Vector2.ZERO, color, [title, text])


## Phase aura: embers rising around the boss, denser with every phase.
func set_aura(level: int, color: Color) -> void:
	if level <= 0:
		return
	if _aura == null:
		_aura = CPUParticles2D.new()
		_aura.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		_aura.direction = Vector2.UP
		_aura.spread = 25.0
		_aura.gravity = Vector2(0, -40)
		_aura.initial_velocity_min = 10.0
		_aura.initial_velocity_max = 35.0
		_aura.lifetime = 1.0
		_aura.scale_amount_min = 1.0
		_aura.scale_amount_max = 2.5
		var m := CanvasItemMaterial.new()
		m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		_aura.material = m
		_aura.z_index = 2
		add_child(_aura)
	_aura.emission_sphere_radius = maxf(data.collision_size.x, data.collision_size.y) * 0.55
	_aura.position = Vector2(0, -data.collision_size.y * 0.5)
	_aura.amount = 10 + level * 10
	_aura.color = color.lightened(0.2)
	_aura.emitting = true


# ------------------------------------------------------- signature moves
## A hazard on this machine (it hurts on the host) plus its copy for guests.
func _hazard(style: BossHazard.Style, pos: Vector2, size: Vector2, life: float, vel: Vector2,
		dmg: int, dtype: int) -> BossHazard:
	var h := BossHazard.spawn(get_parent(), style, pos, size, life, vel, dmg, dtype)
	_net_boss_fx(&"hazard", pos, vel, Color.WHITE, [int(style), size.x, size.y, life])
	return h


func _net_shake(strength: float) -> void:
	if Net.active and Net.is_host:
		var ns = get_tree().get_first_node_in_group("net_game")
		if ns:
			ns.net_shake.rpc(strength)


## Bone King: the dead rise where the spikes burst.
func _summon_at(a: BossAttack, spots: Array[Vector2]) -> void:
	_summons.assign(_summons.filter(func(n) -> bool: return is_instance_valid(n) and not n.is_dead()))
	var lvl := _level()
	if a.summon == null or lvl == null:
		return
	var free := a.max_summons - _summons.size()
	for spot in spots:
		if free <= 0:
			break
		free -= 1
		var e: Enemy = (load("res://scenes/enemies/enemy.tscn") as PackedScene).instantiate()
		e.setup(a.summon, floor_number)
		lvl._net_tag(e)
		lvl.add_entity(e, spot + Vector2(0, -2))
		lvl._net_broadcast_enemy(e, null, false)
		Fx.dust(lvl.entities, spot, true)
		_summons.append(e)


## Flame Witch: walls of fire roll across the arena floor; only the boards
## (or a well-timed jump over a low lick of flame) are safe.
func _fire_walls(a: BossAttack, dmg: int) -> void:
	var lvl := _level()
	var b := lvl.bounds_px() if lvl else Rect2(global_position - Vector2(300, 200), Vector2(600, 400))
	var dir := 1.0 if _target_pos.x < b.get_center().x else -1.0
	var life := (b.size.x - 48.0) / maxf(40.0, a.speed)
	_hazard(BossHazard.Style.FIRE, _target_pos, Vector2(16, 30), life, Vector2(dir * a.speed, 0), dmg, a.damage_type)
	if a.count >= 2:
		var other := Vector2(b.end.x - 24.0 if dir > 0.0 else b.position.x + 24.0, _target_pos.y)
		_hazard(BossHazard.Style.FIRE, other, Vector2(16, 30), life, Vector2(-dir * a.speed, 0), dmg, a.damage_type)
	AudioManager.play_sfx(&"cast_fire_wave", global_position)
	EventBus.screen_shake.emit(4.0)


## Illusionist: "which of us is where?" - the boss and its target swap.
func _mirror_swap(a: BossAttack, dmg: int) -> void:
	if _player == null or _player.dead:
		return
	var hero_pos := _player.global_position
	var boss_pos := global_position
	var land := _ground_below(boss_pos + Vector2(0, -20), _level())
	if _player.puppet:
		var ns = get_tree().get_first_node_in_group("net_game")
		if ns:
			ns.player_teleport.rpc_id(_player.peer_id, land)
		_player.net_place(land)
	else:
		_player.global_position = land
		_player.velocity = Vector2.ZERO
	global_position = hero_pos + Vector2(0, -24)
	_clamp_to_arena()
	sprite.modulate.a = 1.0
	for p in [hero_pos, land]:
		Fx.sparks(get_parent(), p + Vector2(0, -14), Color(0.85, 0.55, 1.0), 18, 90.0)
	_net_boss_fx(&"swap", hero_pos, land, Color(0.85, 0.55, 1.0), [])
	AudioManager.play_sfx(&"cast_void", global_position)
	_fan(a, dmg)
	_attack_anim_left = 0.3


## Drowned Bell: rolling rings of sound along the floor, both ways.
func _toll(a: BossAttack, dmg: int) -> void:
	var ground := _ground_below(global_position + Vector2(0, -20), _level())
	var b := _level().bounds_px() if _level() else Rect2(global_position - Vector2(300, 200), Vector2(600, 400))
	var life := b.size.x / maxf(40.0, a.speed) * 0.6
	for i in maxi(1, a.count):
		var me: WeakRef = weakref(self)
		get_tree().create_timer(i * 0.7, false).timeout.connect(func() -> void:
			if me.get_ref() == null or _dead or not is_inside_tree():
				return
			for dir in [-1.0, 1.0]:
				_hazard(BossHazard.Style.WAVE, ground + Vector2(dir * 14.0, 0), Vector2(10, 14), life,
						Vector2(dir * a.speed, 0), dmg, a.damage_type)
			EventBus.screen_shake.emit(5.0)
			_net_shake(5.0)
			AudioManager.play_sfx(&"boss_toll", global_position)
			Fx.explosion(get_parent(), global_position + Vector2(0, -data.collision_size.y * 0.6), 30.0, Color(0.55, 1.0, 0.85)))


## Ashen King: one huge sweep of the molten blade; the ground smoulders after.
func _ash_sweep(a: BossAttack, dmg: int) -> void:
	var ground := _ground_below(global_position + Vector2(0, -20), _level())
	for p in _alive_heroes():
		var rel := p.global_position - global_position
		if absf(rel.x) <= a.radius and rel.y > -48.0 and rel.y < 16.0 \
				and LineOfSight.can_hit(self, global_position + Vector2(0, -16), p):
			p.take_damage(dmg, global_position, a.damage_type)
			_apply_attack_effects(a, p)
	Minion.hurt_in_radius(get_tree(), global_position, a.radius, dmg)
	for dir in [-1.0, 1.0]:
		SlashTrail.spawn(get_parent(), global_position + Vector2(0, -18), Vector2(dir, 0), a.radius, false, Color(1.0, 0.5, 0.15))
	var n := maxi(2, a.count)
	for i in n:
		var x := lerpf(-a.radius, a.radius, (i + 0.5) / n)
		var spot := _ground_below(Vector2(ground.x + x, ground.y - 20.0), _level())
		_hazard(BossHazard.Style.ASH, spot, Vector2(a.radius * 2.0 / n - 4.0, 12), a.lifetime, Vector2.ZERO,
				roundi(dmg * 0.35), a.damage_type)
	EventBus.screen_shake.emit(6.0)
	_net_shake(6.0)
	AudioManager.play_sfx(&"cast_swing_heavy", global_position)


## Eclipse: the light dies on every machine for `duration` seconds.
static func darken(parent: Node, duration: float) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var cm := CanvasModulate.new()
	cm.color = Color.WHITE
	parent.add_child(cm)
	var tw := cm.create_tween()
	tw.tween_property(cm, "color", Color(0.16, 0.12, 0.22), 0.5)
	tw.tween_interval(maxf(0.1, duration - 1.0))
	tw.tween_property(cm, "color", Color.WHITE, 0.5)
	tw.tween_callback(cm.queue_free)


func _apply_attack_effects(a: BossAttack, target: Node) -> void:
	if not is_instance_valid(target):
		return
	for e in a.hit_effects:
		if e:
			e.try_apply(self, target, damage)


func _contact_damage() -> void:
	if _contact_cd > 0.0:
		return
	var body_reach := maxf(data.collision_size.x, data.collision_size.y) * 0.6
	for n in get_tree().get_nodes_in_group("minions"):
		var mn := n as Minion
		if mn and not mn.is_queued_for_deletion() and mn.global_position.distance_to(global_position + Vector2(0, -data.collision_size.y * 0.4)) <= body_reach:
			mn.take_damage(roundi(damage * boss.contact_damage_mult))
			_contact_cd = 0.5
	var reach := data.collision_size * 0.5 + Vector2(6, 10)
	for p in _alive_heroes():
		var rel := p.global_position - global_position
		if absf(rel.x) < reach.x and rel.y > -data.collision_size.y - 10.0 and rel.y < 10.0 \
				and LineOfSight.can_hit(self, global_position + Vector2(0, -data.collision_size.y * 0.5), p):
			var mult := boss.contact_damage_mult * (2.0 if act == Act.ACTING else 1.0)
			mult = maxf(mult, 1.0 if _enraged else mult)  # enraged contact hits at full power
			p.take_damage(roundi(damage * mult), global_position)
			_contact_cd = 0.8
			return


func _update_boss_animation() -> void:
	if act == Act.WINDUP:
		_play(&"windup")
	elif act == Act.ACTING or _attack_anim_left > 0.0:
		_play(&"attack")
	elif data.behavior == EnemyData.Behavior.FLYER or absf(velocity.x) > 5.0:
		_play(_move_anim())
	else:
		_play(&"idle")


func take_damage(amount: int, crit: bool = false, from_pos: Vector2 = Vector2.INF, damage_type: int = 0) -> void:
	if not puppet and (_phase_lock > 0.0 or act == Act.INTRO):
		# Before the fight (the intro) and while a new phase rises the boss
		# cannot be hurt; a blow from afar only starts the show.
		if act == Act.INTRO and not _intro_started:
			_start_intro()
		if randf() < 0.35:
			var spot := global_position + Vector2(0, -data.collision_size.y - 6)
			EventBus.floating_text.emit(spot, "Неуязвим", Color(0.8, 0.85, 1.0))
			if Net.active and Net.is_host:
				var ns = get_tree().get_first_node_in_group("net_game")
				if ns:
					ns.enemy_float_text.rpc(spot, "Неуязвим", Color(0.8, 0.85, 1.0))
		_shield_flash()
		return
	# Bosses are not knocked around or interrupted by hits.
	var v := velocity
	var prev_state := state
	super(amount, crit, from_pos, damage_type)
	if not _dead:
		velocity = v
		state = prev_state
	EventBus.boss_hp_changed.emit(hp, max_hp)


func apply_knockback(_dir: float, _force: float) -> void:
	pass


func stun(duration: float) -> void:
	status.apply(&"stun", duration * 0.3)  # bosses shrug off most of it


func _die() -> void:
	for s in _summons:
		if is_instance_valid(s) and not s.is_dead():
			s.take_damage(99999)
	GameState.run_stats["bosses"] = int(GameState.run_stats.get("bosses", 0)) + 1
	if boss.final:
		GameState.run_stats["victory"] = true
	# Bosses pay a skill point: the risk buys progress in the tree.
	if GameState.hero and GameState.run_active:
		GameState.hero.skills.add_points(1)
		EventBus.message.emit("%s повержен: +1 очко навыка" % boss.title)
	EventBus.screen_shake.emit(10.0)
	Fx.explosion(get_parent(), global_position + Vector2(0, -20), 60.0, Color(1.0, 0.7, 0.3))
	if boss.defeat_line != "":
		_banner(boss.display_name, "«%s»" % boss.defeat_line, boss.glow_color)
	# A chain of bursts across the body: the fall, not a pop.
	# (Driven by a tween on the level: the boss itself is gone by then.)
	var parent := get_parent()
	var pos := global_position
	var h := data.collision_size.y
	var col := boss.glow_color
	var tw := parent.create_tween()
	for i in 4:
		tw.tween_interval(0.15 if i == 0 else 0.22)
		tw.tween_callback(Fx.explosion.bind(parent, pos + Vector2(randf_range(-16, 16), -randf_range(0.2, 0.9) * h), 26.0 + i * 6.0, col))
		tw.tween_callback(EventBus.screen_shake.emit.bind(4.0))
	var rewards: Array = []
	for id in boss.reward_items:
		var it := ItemDatabase.get_item(id)
		if it:
			rewards.append({"item": it, "count": 1})
	if not rewards.is_empty():
		EventBus.spawn_items.emit(global_position + Vector2(0, -16), rewards)
	EventBus.boss_defeated.emit(boss, global_position)
	super()
