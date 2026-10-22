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
var _summons: Array[Node] = []
var _jump_from := Vector2.ZERO
var _jump_t := 0.0


func setup(p_data: EnemyData, p_floor: int) -> void:
	super(p_data, p_floor)
	boss = p_data as BossData


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


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player
	_contact_cd = maxf(0.0, _contact_cd - delta)
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
			if _act_time <= 0.0:
				EventBus.message.emit(boss.title)
				_enter(Act.IDLE, 0.5)
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
	if absf(velocity.x) > 1.0:
		sprite.flip_h = velocity.x < 0.0
	_contact_damage()
	_update_boss_animation()


func _enter(new_act: Act, time: float) -> void:
	act = new_act
	_act_time = time


func _check_phase() -> void:
	var ratio := float(hp) / max_hp
	while phase_index + 1 < boss.phases.size() and ratio <= boss.phases[phase_index + 1].hp_threshold:
		phase_index += 1
		var ph := current_phase()
		data_tint_override(ph.tint)
		if ph.message != "":
			EventBus.message.emit(ph.message)
		EventBus.screen_shake.emit(6.0)
		Fx.sparks(get_parent(), global_position + Vector2(0, -24), ph.tint, 30, 160.0)
		phase_changed.emit(phase_index)


func data_tint_override(tint: Color) -> void:
	sprite.modulate = tint


func _move_idle(delta: float, flyer: bool) -> void:
	if _player == null:
		return
	var spd := data.speed * current_phase().speed_mult
	if flyer:
		var target := _player.global_position + Vector2(signf(global_position.x - _player.global_position.x) * 70.0, -70.0)
		velocity = velocity.move_toward((target - global_position).limit_length(spd * 2.0), 300.0 * delta)
	else:
		var dx := _player.global_position.x - global_position.x
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
			_target_pos = Vector2(_player.global_position.x, global_position.y)
			Telegraph.circle(parent, _target_pos, _attack.radius, _attack.windup + 0.5)
		BossAttack.Kind.FIRE_RAIN:
			_rain_spots.clear()
			for i in _attack.count:
				var x := _player.global_position.x + randf_range(-120.0, 120.0)
				var ground := _ground_below(Vector2(x, _player.global_position.y - 20.0), lvl)
				_rain_spots.append(ground)
				Telegraph.circle(parent, ground, _attack.radius, _attack.windup + 0.6)
		BossAttack.Kind.TELEPORT:
			var tw := create_tween()
			tw.tween_property(sprite, "modulate:a", 0.2, _attack.windup)
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
			sprite.modulate.a = 1.0
			Fx.explosion(get_parent(), global_position + Vector2(0, -20), 30.0, Color(1.0, 0.5, 0.2))
			_fan(a, dmg)
			_end_attack()
		BossAttack.Kind.FIRE_RAIN:
			for spot in _rain_spots:
				_drop_fire(spot, a, dmg)
			_end_attack()


func _end_attack() -> void:
	_enter(Act.RECOVER, current_phase().attack_interval)


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
			p.y -= sin(t * PI) * 80.0
			velocity = (p - global_position) / maxf(delta, 0.001)
			if t >= 1.0:
				velocity = Vector2.ZERO
				_shockwave(a)
				_end_attack()


func _shockwave(a: BossAttack) -> void:
	EventBus.screen_shake.emit(8.0)
	Fx.dust(get_parent(), global_position, true)
	Fx.explosion(get_parent(), global_position + Vector2(0, -4), a.radius, Color(0.9, 0.8, 0.6))
	if _player and _player.global_position.distance_to(global_position) <= a.radius + 6.0:
		_player.take_damage(roundi(damage * a.damage_mult), global_position, a.damage_type)
		_apply_attack_effects(a, _player)


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
	lvl.add_entity(p, spot + Vector2(0, -150))


func _summon(a: BossAttack) -> void:
	_summons = _summons.filter(func(n: Node) -> bool: return is_instance_valid(n) and not n.is_dead())
	var lvl := _level()
	if a.summon == null or lvl == null:
		return
	for i in mini(a.count, a.max_summons - _summons.size()):
		var e: Enemy = (load("res://scenes/enemies/enemy.tscn") as PackedScene).instantiate()
		e.setup(a.summon, floor_number)
		var side := -1.0 if i % 2 == 0 else 1.0
		lvl.add_entity(e, global_position + Vector2(side * (30.0 + i * 12.0), -8.0))
		Fx.sparks(lvl.entities, e.global_position + Vector2(0, -8), Color(0.7, 0.4, 1.0), 12, 70.0)
		_summons.append(e)


func _apply_attack_effects(a: BossAttack, target: Node) -> void:
	if not is_instance_valid(target):
		return
	for e in a.hit_effects:
		if e:
			e.try_apply(self, target, damage)


func _contact_damage() -> void:
	if _player == null or _player.dead or _contact_cd > 0.0:
		return
	var reach := data.collision_size * 0.5 + Vector2(6, 10)
	var rel := _player.global_position - global_position
	if absf(rel.x) < reach.x and rel.y > -data.collision_size.y - 10.0 and rel.y < 10.0:
		var mult := boss.contact_damage_mult * (2.0 if act == Act.ACTING else 1.0)
		_player.take_damage(roundi(damage * mult), global_position)
		_contact_cd = 0.8


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
	EventBus.screen_shake.emit(10.0)
	Fx.explosion(get_parent(), global_position + Vector2(0, -20), 60.0, Color(1.0, 0.7, 0.3))
	var rewards: Array = []
	for id in boss.reward_items:
		var it := ItemDatabase.get_item(id)
		if it:
			rewards.append({"item": it, "count": 1})
	if not rewards.is_empty():
		EventBus.spawn_items.emit(global_position + Vector2(0, -16), rewards)
	EventBus.boss_defeated.emit(boss, global_position)
	super()
