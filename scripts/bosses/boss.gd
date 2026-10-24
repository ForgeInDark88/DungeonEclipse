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
var _jump_from := Vector2.ZERO
var _jump_t := 0.0
var _jump_arc := 80.0
var _spike_spots: Array[Vector2] = []
var _beam_dir := Vector2.RIGHT
var _beam_line: Line2D = null
var _beam_core: Line2D = null
var _beam_time := 0.0
var _beam_tick := 0.0


func setup(p_data: EnemyData, p_floor: int, p_elite: EliteAffixData = null, p_champion := false) -> void:
	super(p_data, p_floor, p_elite, p_champion)
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
	if puppet:
		# Co-op shell: glide to the host's position, no boss brain here.
		global_position = global_position.lerp(_net_target, minf(1.0, delta * 12.0))
		return
	if _dead:
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player
	_contact_cd = maxf(0.0, _contact_cd - delta)
	_hop_cd = maxf(0.0, _hop_cd - delta)
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
			if _beam_tick <= 0.0 and _player:
				_beam_tick = 0.22
				var from := global_position + Vector2(0, -22)
				var to := from + _beam_dir * 260.0
				var ap := _player.global_position + Vector2(0, -10)
				var ab := to - from
				var tt := clampf((ap - from).dot(ab) / ab.length_squared(), 0.0, 1.0)
				var dist := (ap - (from + ab * tt)).length()
				if dist <= 15.0:
					_player.take_damage(roundi(damage * a.damage_mult * 0.45), global_position, a.damage_type)
					_apply_attack_effects(a, _player)
			if _beam_time <= 0.0:
				_fade_beam()
				_end_attack()


func _shockwave(a: BossAttack) -> void:
	EventBus.screen_shake.emit(8.0)
	Fx.dust(get_parent(), global_position, true)
	Fx.explosion(get_parent(), global_position + Vector2(0, -4), a.radius, Color(0.9, 0.8, 0.6))
	if _player and _player.global_position.distance_to(global_position) <= a.radius + 6.0 \
			and LineOfSight.can_hit(self, global_position + Vector2(0, -8), _player):
		_player.take_damage(roundi(damage * a.damage_mult), global_position, a.damage_type)
		_apply_attack_effects(a, _player)


## Crystals burst from the telegraphed spots; standing on one hurts.
func _erupt_spikes(a: BossAttack, dmg: int) -> void:
	var parent := get_parent()
	for spot in _spike_spots:
		var spike := Node2D.new()
		var poly := Polygon2D.new()
		poly.polygon = PackedVector2Array([Vector2(-5, 1), Vector2(0, -16), Vector2(5, 1)])
		poly.color = Color(0.62, 0.93, 1.0, 0.95)
		var side := Polygon2D.new()
		side.polygon = PackedVector2Array([Vector2(3, 1), Vector2(7, -10), Vector2(10, 1)])
		side.color = Color(0.42, 0.72, 0.9, 0.9)
		var light := PointLight2D.new()
		light.texture = AssetPaths.tex(AssetPaths.LIGHT)
		light.color = Color(0.55, 0.95, 1.0)
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
		if _player and _player.global_position.distance_to(spot) <= a.radius 				and LineOfSight.can_hit(self, spot, _player):
			_player.take_damage(dmg, spot, a.damage_type)
			_apply_attack_effects(a, _player)
		tw.tween_interval(0.8)
		tw.tween_property(spike, "scale:y", 0.0, 0.2)
		tw.tween_callback(spike.queue_free)
	EventBus.screen_shake.emit(5.0)
	Fx.sparks(parent, global_position + Vector2(0, -24), Color(0.6, 0.95, 1.0), 14, 120.0)
	AudioManager.play_sfx(&"dig", global_position)


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
		lvl.add_entity(e, global_position + Vector2(side * (30.0 + i * 12.0), -8.0))
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
	sprite.modulate.a = 1.0
	for p in spots:
		var e: Enemy = (load("res://scenes/enemies/enemy.tscn") as PackedScene).instantiate()
		e.setup(a.summon, floor_number)
		lvl.add_entity(e, p)
		e.modulate = sprite.modulate
		Fx.sparks(lvl.entities, p + Vector2(0, -20), Color(0.8, 0.5, 1.0), 12, 70.0)
		_summons.append(e)
		get_tree().create_timer(a.lifetime, false).timeout.connect(func() -> void:
			if is_instance_valid(e) and not e.is_dead():
				Fx.sparks(e.get_parent(), e.global_position + Vector2(0, -20), Color(0.8, 0.5, 1.0), 10, 60.0)
				e.queue_free())
	EventBus.screen_shake.emit(3.0)


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
	if absf(rel.x) < reach.x and rel.y > -data.collision_size.y - 10.0 and rel.y < 10.0 \
			and LineOfSight.can_hit(self, global_position + Vector2(0, -data.collision_size.y * 0.5), _player):
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
	# Bosses pay a skill point: the risk buys progress in the tree.
	if GameState.hero and GameState.run_active:
		GameState.hero.skills.add_points(1)
		EventBus.message.emit("%s повержен: +1 очко навыка" % boss.title)
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
