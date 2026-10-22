class_name Enemy
extends CharacterBody2D
## Generic monster driven by an EnemyData resource.
## States: PATROL -> CHASE (player in sight) -> ATTACK (wind-up, then hit/shoot).
## Behaviours: WALKER (ground, turns at walls/ledges, optional hops),
## FLYER (ignores gravity, swoops at the player), RANGED (keeps distance, shoots).
## Stats scale with the floor number.
## Animations (from EnemyData.sheet): idle, walk|fly, windup, attack, hurt,
## death; hit flash through the flash shader.

enum State { PATROL, CHASE, ATTACK, HURT }

const GRAVITY := 900.0
const PROJECTILE_SCENE := preload("res://scenes/world/projectile.tscn")
const HP_SCALE_PER_FLOOR := 0.3
const DMG_SCALE_PER_FLOOR := 0.18

var data: EnemyData
var floor_number: int = 1
var max_hp: int = 10
var hp: int = 10
var damage: int = 1
var state: State = State.PATROL
var dir: float = 1.0

var _attack_timer := 0.0
var _windup := 0.0
var _hurt_timer := 0.0
var _hop_timer := 0.0
var _think_timer := 0.0
var _float_t := 0.0
var _home := Vector2.ZERO
var _player: Player
var _dead := false
## Remaining time of the one-shot "attack" animation after a hit/shot.
var _attack_anim_left := 0.0
var _flash_tween: Tween
## Elite modifier (null for normal monsters).
var elite: EliteAffixData
var _speed_mult := 1.0
var _cooldown_mult := 1.0
var _summons: Array[Node] = []
var _summon_next := true
var _ambushing := false
var _name_label: Label

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var shape: CollisionShape2D = $CollisionShape2D
@onready var hp_bar: ProgressBar = $HpBar
@onready var status: StatusEffects = $StatusEffects


func setup(p_data: EnemyData, p_floor: int, p_elite: EliteAffixData = null) -> void:
	data = p_data
	floor_number = p_floor
	elite = p_elite
	var f := float(p_floor - 1)
	max_hp = roundi(data.max_hp * (1.0 + HP_SCALE_PER_FLOOR * f))
	damage = roundi(data.damage * (1.0 + DMG_SCALE_PER_FLOOR * f))
	if elite:
		max_hp = roundi(max_hp * elite.hp_mult)
		damage = roundi(damage * elite.damage_mult)
		_speed_mult = elite.speed_mult
		_cooldown_mult = elite.attack_cooldown_mult
	hp = max_hp


func display_name() -> String:
	if elite:
		var base := data.display_name
		return "%s %s" % [elite.prefix(data.gender), base.left(1).to_lower() + base.substr(1)]
	return data.display_name


func _ready() -> void:
	add_to_group("enemies")
	_setup_sprite()
	status.immunities = data.status_immunities
	var sv := StatusVisual.new()
	add_child(sv)
	sv.setup(status, sprite, data.collision_size.y)
	var rect := RectangleShape2D.new()
	rect.size = data.collision_size
	shape.shape = rect
	shape.position = Vector2(0, -data.collision_size.y / 2.0)
	hp_bar.position = Vector2(-8, -data.collision_size.y - 6)
	hp_bar.visible = false
	dir = -1.0 if randf() < 0.5 else 1.0
	_home = global_position
	_float_t = randf() * TAU
	if data.behavior == EnemyData.Behavior.FLYER:
		motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	if data.phases_through_walls:
		collision_mask = 0
		sprite.self_modulate.a = 0.85
	if elite:
		_setup_elite()
	if data.ceiling_ambush:
		_ambushing = true
		call_deferred("_hang_from_ceiling")


func _setup_elite() -> void:
	add_to_group("elites")
	scale = Vector2(1.2, 1.2)
	var imm: Array[StringName] = status.immunities.duplicate()
	imm.append_array(elite.immunities)
	status.immunities = imm
	if elite.spawn_status != &"":
		status.apply(elite.spawn_status, 9999.0, elite.spawn_status_power + floor_number * 0.5)
	var glow := PointLight2D.new()
	glow.texture = AssetPaths.tex(AssetPaths.LIGHT)
	glow.color = elite.tint
	glow.texture_scale = 0.35
	glow.energy = 0.9
	glow.position = Vector2(0, -data.collision_size.y / 2.0)
	add_child(glow)
	sprite.modulate = data.tint * elite.tint.lightened(0.3)
	_name_label = Label.new()
	_name_label.text = display_name()
	_name_label.add_theme_font_size_override("font_size", 6)
	_name_label.add_theme_color_override("font_color", elite.tint)
	_name_label.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.02))
	_name_label.add_theme_constant_override("outline_size", 3)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.size = Vector2(80, 10)
	_name_label.position = Vector2(-40, -data.collision_size.y - 16)
	_name_label.scale = Vector2.ONE / 1.2
	var m := CanvasItemMaterial.new()
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_name_label.material = m
	add_child(_name_label)


## Spiders: stick to the ceiling above the spawn point, upside down.
func _hang_from_ceiling() -> void:
	var q := PhysicsRayQueryParameters2D.create(global_position + Vector2(0, -4), global_position + Vector2(0, -200), 1)
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		_ambushing = false
		return
	global_position = hit["position"] + Vector2(0, data.collision_size.y + 1)
	sprite.flip_v = true


func _update_ambush() -> bool:
	if not _ambushing:
		return false
	velocity = Vector2.ZERO
	_play(&"idle")
	if _player and not _player.dead:
		var rel := _player.global_position - global_position
		if absf(rel.x) < 26.0 and rel.y > 0.0 and rel.y < 220.0:
			_ambushing = false
			sprite.flip_v = false
			velocity = Vector2(0, 60)
			_set_flash(0.5, Color(1.0, 0.3, 0.2))
			get_tree().create_timer(0.2).timeout.connect(func() -> void: _set_flash(0.0))
	return true



func _physics_process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player
	if _update_ambush():
		return
	if status.is_stunned():
		# Stunned: no thinking, no attacks, just physics.
		if data.behavior != EnemyData.Behavior.FLYER:
			velocity.y = minf(velocity.y + GRAVITY * delta, 420.0)
		velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
		if data.behavior == EnemyData.Behavior.FLYER:
			velocity.y = move_toward(velocity.y, 0.0, 600.0 * delta)
		if state == State.ATTACK:
			state = State.CHASE
			_set_flash(0.0)
		move_and_slide()
		_play(&"hurt")
		return
	_attack_timer = maxf(0.0, _attack_timer - delta)
	_think_timer -= delta
	if _think_timer <= 0.0:
		_think_timer = 0.2
		_think()

	match data.behavior:
		EnemyData.Behavior.FLYER:
			_fly(delta)
		_:
			_walk(delta)
	var slow := status.speed_multiplier() * _speed_mult
	if slow != 1.0:
		velocity.x *= slow
		if data.behavior == EnemyData.Behavior.FLYER:
			velocity.y *= slow
	move_and_slide()
	if absf(velocity.x) > 1.0:
		sprite.flip_h = velocity.x < 0.0
	_attack_anim_left = maxf(0.0, _attack_anim_left - delta)
	_update_animation()


# --------------------------------------------------------------- animation
func _setup_sprite() -> void:
	sprite.material = AssetPaths.flash_material()
	sprite.modulate = data.tint
	if data.sheet and data.sheet_layout:
		data.sheet_layout.apply_to(sprite, data.sheet)
	else:
		# Static fallback: one frame for every animation name.
		var frames := SpriteFrames.new()
		for anim in [&"default", &"idle", _move_anim(), &"windup", &"attack", &"hurt", &"death"]:
			if not frames.has_animation(anim):
				frames.add_animation(anim)
			frames.add_frame(anim, data.texture)
			frames.set_animation_loop(anim, anim in [&"idle", _move_anim()])
		sprite.sprite_frames = frames
		sprite.centered = false
		var tsize := data.texture.get_size() if data.texture else Vector2(16, 16)
		sprite.offset = Vector2(-tsize.x / 2.0, -tsize.y)
	sprite.play(&"idle")


func _move_anim() -> StringName:
	return &"fly" if data.behavior == EnemyData.Behavior.FLYER else &"walk"


func _play(anim: StringName) -> void:
	if sprite.animation != anim and sprite.sprite_frames.has_animation(anim):
		sprite.play(anim)


func _update_animation() -> void:
	if state == State.HURT:
		_play(&"hurt")
	elif state == State.ATTACK:
		_play(&"windup")
	elif _attack_anim_left > 0.0:
		_play(&"attack")
	elif data.behavior == EnemyData.Behavior.FLYER or absf(velocity.x) > 5.0:
		_play(_move_anim())
	else:
		_play(&"idle")


func _set_flash(amount: float, color := Color.WHITE) -> void:
	var m := sprite.material as ShaderMaterial
	m.set_shader_parameter("flash_color", color)
	m.set_shader_parameter("flash", amount)


func _player_visible() -> bool:
	if _player == null or _player.dead:
		return false
	var to_player := _player.global_position - global_position
	if to_player.length() > data.aggro_range:
		return false
	if data.behavior == EnemyData.Behavior.WALKER and absf(to_player.y) > 56.0:
		return false
	if data.phases_through_walls:
		return true
	# Line of sight against the world layer.
	var query := PhysicsRayQueryParameters2D.create(global_position + Vector2(0, -6), _player.global_position + Vector2(0, -10), 1)
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _think() -> void:
	if state == State.HURT or state == State.ATTACK:
		return
	state = State.CHASE if _player_visible() else State.PATROL


func _distance_to_player() -> float:
	return global_position.distance_to(_player.global_position) if _player else INF


# ------------------------------------------------------------------ walking
func _walk(delta: float) -> void:
	velocity.y = minf(velocity.y + GRAVITY * delta, 420.0)
	match state:
		State.HURT:
			_hurt_timer -= delta
			velocity.x = move_toward(velocity.x, 0.0, 400.0 * delta)
			if _hurt_timer <= 0.0:
				state = State.CHASE
		State.PATROL:
			velocity.x = dir * data.speed
			if is_on_floor() and (is_on_wall() or _ledge_ahead()):
				dir = -dir
		State.CHASE:
			var dx := _player.global_position.x - global_position.x
			var dist := _distance_to_player()
			if data.behavior == EnemyData.Behavior.RANGED:
				# Keep some distance and shoot.
				dir = signf(dx) if dx != 0.0 else dir
				var desired := 0.0
				if dist < data.attack_range * 0.5:
					desired = -dir * data.speed
				elif dist > data.attack_range * 0.9:
					desired = dir * data.speed
				if _ledge_ahead() and signf(desired) == dir:
					desired = 0.0
				velocity.x = desired
				if dist <= data.attack_range and _attack_timer <= 0.0:
					_begin_attack()
			else:
				dir = signf(dx) if absf(dx) > 2.0 else dir
				velocity.x = dir * data.chase_speed
				if data.jumps:
					_hop_timer -= delta
					if is_on_floor() and _hop_timer <= 0.0:
						velocity.y = -220.0
						_hop_timer = randf_range(0.6, 1.2)
				elif is_on_floor() and is_on_wall():
					velocity.y = -260.0  # try to hop over small obstacles
				if dist <= data.attack_range + 6.0 and _attack_timer <= 0.0:
					_begin_attack()
		State.ATTACK:
			velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
			_update_attack(delta)


func _ledge_ahead() -> bool:
	var level := _level()
	if level == null:
		return false
	var probe := global_position + Vector2(dir * (data.collision_size.x / 2.0 + 3.0), 4.0)
	return not level.is_ground_at(probe)


func _level() -> DungeonLevel:
	var p := get_parent()
	return p.get_parent() as DungeonLevel if p else null


# ------------------------------------------------------------------- flying
func _fly(delta: float) -> void:
	_float_t += delta
	match state:
		State.HURT:
			_hurt_timer -= delta
			velocity = velocity.move_toward(Vector2.ZERO, 300.0 * delta)
			if _hurt_timer <= 0.0:
				state = State.CHASE
		State.PATROL:
			var target := _home + Vector2(sin(_float_t * 0.7) * 40.0, sin(_float_t * 2.0) * 8.0)
			velocity = (target - global_position).limit_length(data.speed)
		State.CHASE:
			var target := _player.global_position + Vector2(0, -12)
			velocity = velocity.move_toward((target - global_position).normalized() * data.chase_speed, 300.0 * delta)
			velocity.y += sin(_float_t * 6.0) * 20.0
			if _distance_to_player() <= data.attack_range + 8.0 and _attack_timer <= 0.0:
				_begin_attack()
		State.ATTACK:
			velocity = velocity.move_toward(Vector2.ZERO, 200.0 * delta)
			_update_attack(delta)


# ------------------------------------------------------------------- attack
func _begin_attack() -> void:
	state = State.ATTACK
	_windup = 0.35 if data.behavior != EnemyData.Behavior.FLYER else 0.15
	# Telegraph: red glow during the wind-up.
	_set_flash(0.35, Color(1.0, 0.2, 0.1))


func _update_attack(delta: float) -> void:
	_windup -= delta
	if _windup > 0.0:
		return
	_set_flash(0.0)
	_attack_timer = data.attack_cooldown * _cooldown_mult
	state = State.CHASE
	_attack_anim_left = 0.25
	if _player == null or _player.dead:
		return
	if data.behavior == EnemyData.Behavior.RANGED:
		if data.summon and _summon_next and _alive_summons() < data.max_summons:
			_raise_summons()
		else:
			_shoot()
		_summon_next = not _summon_next
		return
	if data.behavior == EnemyData.Behavior.FLYER:
		velocity = (_player.global_position + Vector2(0, -10) - global_position).normalized() * data.chase_speed * 2.2
	elif data.behavior == EnemyData.Behavior.WALKER:
		velocity.x = dir * data.chase_speed * 1.8  # lunge
	if data.aoe_radius > 0.0:
		# Ground slam: hurts everything around, telegraphed by the wind-up.
		EventBus.screen_shake.emit(4.0)
		Fx.dust(get_parent(), global_position, true)
		Fx.explosion(get_parent(), global_position + Vector2(0, -4), data.aoe_radius, Color(0.8, 0.75, 0.65))
		if _player.global_position.distance_to(global_position) <= data.aoe_radius:
			_player.take_damage(damage, global_position)
			_apply_hit_effects(_player, damage)
	elif _distance_to_player() <= data.attack_range + 14.0:
		_player.take_damage(damage, global_position)
		_apply_hit_effects(_player, damage)


func _apply_hit_effects(target: Node, dmg: int) -> void:
	if not is_instance_valid(target) or target.dead:
		return
	for e in data.on_hit_effects:
		if e:
			e.try_apply(self, target, dmg)
	if elite:
		for e in elite.hit_effects:
			if e:
				e.try_apply(self, target, dmg)
		if elite.life_steal > 0.0 and hp > 0:
			var heal := maxi(1, roundi(dmg * elite.life_steal))
			hp = mini(max_hp, hp + heal)
			hp_bar.value = hp
			EventBus.floating_text.emit(global_position + Vector2(0, -data.collision_size.y - 6), "+%d" % heal, Color(0.9, 0.2, 0.3))


func _alive_summons() -> int:
	_summons = _summons.filter(func(n: Node) -> bool: return is_instance_valid(n) and not n.is_dead())
	return _summons.size()


func _raise_summons() -> void:
	var level := _level()
	if level == null:
		return
	for i in mini(2, data.max_summons - _alive_summons()):
		var e: Enemy = (load("res://scenes/enemies/enemy.tscn") as PackedScene).instantiate()
		e.setup(data.summon, floor_number)
		level.add_entity(e, global_position + Vector2((i * 2 - 1) * 16.0, -4.0))
		Fx.sparks(level.entities, e.global_position + Vector2(0, -8), Color(0.5, 1.0, 0.6), 12, 70.0)
		_summons.append(e)
	AudioManager.play_sfx(&"skill_cast", global_position)


## Elite / regen: statuses can heal monsters too.
func heal_status(amount: int) -> void:
	if _dead or hp >= max_hp:
		return
	hp = mini(max_hp, hp + amount)
	hp_bar.value = hp


func _shoot() -> void:
	var level := _level()
	if level == null:
		return
	var p: Projectile = PROJECTILE_SCENE.instantiate()
	var from := global_position + Vector2(0, -12)
	var dir_v := (_player.global_position + Vector2(0, -10) - from).normalized()
	p.setup(data.projectile_texture, dir_v, data.projectile_speed, damage, "player")
	p.blast_color = Color(0.8, 0.3, 1.0)
	p.on_hit = func(target: Node, dmg: int) -> void: _apply_hit_effects(target, dmg)
	AudioManager.play_sfx(data.sound_attack if data.sound_attack != &"" else &"enemy_shoot", global_position)
	level.add_entity(p, from)


# ------------------------------------------------------------------ damage
## Resistance 0..1 against a WeaponItemData.DamageType.
func resistance(damage_type: int) -> float:
	if damage_type <= 0 or damage_type >= StatTypes.DAMAGE_TYPE_RES.size():
		return 0.0
	var key: String = StatTypes.DAMAGE_TYPE_RES[damage_type]
	var r := float(data.resistances.get(key, 0.0))
	if elite:
		r += float(elite.resistances.get(key, 0.0))
	# Negative values are weaknesses (extra damage).
	return clampf(r, -1.0, 1.0)


func status_resistance(id: StringName) -> float:
	return resistance(StatusEffects.damage_type_of(id))


func take_damage(amount: int, crit: bool = false, from_pos: Vector2 = Vector2.INF, damage_type: int = 0) -> void:
	if hp <= 0:
		return
	# Physical damage is reduced by armor, elemental by resistances.
	var armor := data.armor + (elite.armor_add if elite else 0)
	var dealt := maxi(1, amount - armor) if damage_type == 0 else roundi(amount * (1.0 - resistance(damage_type)))
	if status.has(&"curse"):
		dealt = roundi(dealt * StatusEffects.CURSE_DAMAGE_MULT)
	if dealt <= 0:
		EventBus.floating_text.emit(global_position + Vector2(0, -data.collision_size.y - 4), "Иммунитет", Color(0.7, 0.7, 0.7))
		return
	hp -= dealt
	hp_bar.visible = true
	hp_bar.max_value = max_hp
	hp_bar.value = hp
	var top := global_position + Vector2(0, -data.collision_size.y - 4)
	EventBus.damage_dealt.emit(top, dealt, crit, false)
	AudioManager.play_sfx(&"hit_crit" if crit else &"hit_flesh", global_position)
	AudioManager.play_sfx(data.sound_hurt, global_position, -4.0)
	Fx.hit_spark(get_parent(), global_position + Vector2(0, -data.collision_size.y / 2.0), crit)
	_flash()
	if hp <= 0:
		_die()
		return
	state = State.HURT
	_hurt_timer = 0.25
	if from_pos != Vector2.INF:
		var kb := signf(global_position.x - from_pos.x)
		velocity = Vector2(kb * 120.0, -80.0 if data.behavior != EnemyData.Behavior.FLYER else 0.0)


## Weapon knockback (direction -1/1, force in px/s).
func apply_knockback(dir: float, force: float) -> void:
	velocity.x = dir * force
	if data.behavior != EnemyData.Behavior.FLYER:
		velocity.y = minf(velocity.y, -force * 0.4)


## Damage from statuses (poison, burn, bleed): ignores armor, no hit-stop.
func take_status_damage(amount: int, p_status: StringName, color: Color) -> void:
	amount = roundi(amount * (1.0 - status_resistance(p_status)))
	if _dead or amount <= 0:
		return
	hp -= amount
	hp_bar.visible = true
	hp_bar.max_value = max_hp
	hp_bar.value = hp
	EventBus.floating_text.emit(global_position + Vector2(randf_range(-4, 4), -data.collision_size.y - 2), str(amount), color)
	if hp <= 0:
		_die()


## Freezes the enemy in the HURT state (frost nova and similar effects).
func stun(duration: float) -> void:
	state = State.HURT
	_hurt_timer = duration
	sprite.modulate = Color(0.6, 0.8, 1.4)
	var tw := create_tween()
	tw.tween_property(sprite, "modulate", data.tint, duration)


func _flash() -> void:
	if _flash_tween:
		_flash_tween.kill()
	_set_flash(1.0)
	_flash_tween = create_tween()
	_flash_tween.tween_method(func(v: float) -> void: _set_flash(v), 1.0, 0.0, 0.15)


func is_dead() -> bool:
	return _dead


func _die() -> void:
	_dead = true
	AudioManager.play_sfx(data.sound_death, global_position)
	set_physics_process(false)
	status.clear()
	status.set_physics_process(false)
	remove_from_group("enemies")
	shape.set_deferred("disabled", true)
	hp_bar.visible = false
	EventBus.enemy_killed.emit(data, global_position)
	var xp := roundi((data.xp_reward + floor_number - 1) * (elite.xp_mult if elite else 1.0))
	if GameState.hero:
		GameState.hero.add_xp(xp)
	EventBus.floating_text.emit(global_position + Vector2(0, -data.collision_size.y - 12), "+%d XP" % xp, Color(1.0, 0.85, 0.3))
	var gold := roundi(randi_range(data.gold_min, data.gold_max) * (1.0 + 0.25 * (floor_number - 1)) * (elite.gold_mult if elite else 1.0))
	if gold > 0:
		var coin := ItemDatabase.get_item(&"gold_coin")
		if coin:
			EventBus.spawn_items.emit(global_position + Vector2(0, -8), [{"item": coin, "count": gold}])
	if elite and elite.shard_drop > 0:
		var shard := ItemDatabase.get_item(MetaProgress.SHARD_ITEM)
		if shard:
			EventBus.spawn_items.emit(global_position + Vector2(0, -8), [{"item": shard, "count": elite.shard_drop}])
	if _name_label:
		_name_label.visible = false
	if data.loot_table and (elite != null or randf() < data.loot_chance):
		var loot := data.loot_table.roll(floor_number)
		if not loot.is_empty():
			EventBus.spawn_items.emit(global_position + Vector2(0, -8), loot)
	# Death animation, then the body breaks into particles.
	sprite.play(&"death")
	var parent := get_parent()
	var pos := global_position + Vector2(0, -6)
	var color := data.tint.darkened(0.2)
	sprite.animation_finished.connect(func() -> void:
		Fx.sparks(parent, pos, color, 14, 100.0)
		queue_free(), CONNECT_ONE_SHOT)
