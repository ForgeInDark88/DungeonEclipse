class_name Player
extends CharacterBody2D
## Hero body in the world: platformer movement (coyote time, jump buffer,
## drop through one-way platforms, ladders), melee attack, skills, quick
## items, interaction. All persistent data lives in `hero` (GameState.hero).
## The node origin is at the feet.

signal interact_hint_changed(text: String)

const GRAVITY := 900.0
const MAX_FALL_SPEED := 420.0
const JUMP_VELOCITY := -345.0
const JUMP_CUT := 0.45
const ACCELERATION := 1400.0
const AIR_ACCELERATION := 900.0
const FRICTION := 1600.0
const COYOTE_TIME := 0.1
const JUMP_BUFFER_TIME := 0.12
const DROP_THROUGH_TIME := 0.25
const CLIMB_SPEED := 75.0
const INVULNERABLE_TIME := 0.7
const PLATFORM_LAYER := 2
const BASE_LIGHT_SCALE := 1.4
const PROJECTILE_SCENE := preload("res://scenes/world/projectile.tscn")

var hero: Hero
var level: DungeonLevel
var facing: float = 1.0
var dead := false
var climbing := false

var _coyote := 0.0
var _jump_buffer := 0.0
var _drop_timer := 0.0
var _invulnerable := 0.0
var _attack_cooldown := 0.0
var _item_cooldowns: Dictionary = {}  # item id -> seconds
var _buffs: Dictionary = {}  # modifier key -> seconds left
var _external_velocity := Vector2.ZERO
var _light_tween: Tween
var _hint := ""
var _dash_time := 0.0
var _afterimage_timer := 0.0
var _run_dust_timer := 0.0

@onready var visual: HeroVisual = $Visual
@onready var animator: HeroAnimator = $Animator
@onready var camera: Camera2D = $Camera2D
@onready var light: PointLight2D = $PointLight2D
@onready var interact_area: Area2D = $InteractArea


func _ready() -> void:
	add_to_group("player")
	light.texture = AssetPaths.tex(AssetPaths.LIGHT)
	light.texture_scale = BASE_LIGHT_SCALE
	animator.setup(visual)


func setup(p_hero: Hero, p_level: DungeonLevel) -> void:
	hero = p_hero
	level = p_level
	if not hero.stats.died.is_connected(_on_died):
		hero.stats.died.connect(_on_died)
	visual.refresh_from(hero)
	if not hero.leveled_up.is_connected(_on_leveled_up):
		hero.leveled_up.connect(_on_leveled_up)
	if not hero.equipment.changed.is_connected(_on_equipment_changed):
		hero.equipment.changed.connect(_on_equipment_changed)


func _on_leveled_up(_level: int) -> void:
	visual.flash(Color(1.0, 0.9, 0.4), 0.5)
	visual.squash_to(Vector2(0.8, 1.25), 0.3)
	Fx.sparks(get_parent(), global_position + Vector2(0, -12), Color(1.0, 0.85, 0.3), 24, 120.0)


func _on_equipment_changed() -> void:
	visual.refresh_from(hero)


func set_level(p_level: DungeonLevel) -> void:
	level = p_level
	velocity = Vector2.ZERO
	climbing = false
	var b := level.bounds_px()
	camera.limit_left = int(b.position.x)
	camera.limit_top = int(b.position.y)
	camera.limit_right = int(b.end.x)
	# Leave room for the HUD panel at the bottom of the screen.
	camera.limit_bottom = int(b.end.y) + 70
	camera.reset_smoothing()


# ------------------------------------------------------------------ physics
func _physics_process(delta: float) -> void:
	if hero == null or dead:
		return
	_tick_timers(delta)
	var input_x := Input.get_axis("move_left", "move_right")
	if input_x != 0.0 and not animator.is_busy():
		facing = signf(input_x)
		visual.facing = facing

	if _dash_time > 0.0:
		_dash_time -= delta
		velocity.y = 0.0
		move_and_slide()
		_afterimage_timer -= delta
		if _afterimage_timer <= 0.0:
			_afterimage_timer = 0.035
			Fx.afterimage(visual, get_parent())
		animator.update(delta, is_on_floor(), velocity, false, true)
		return

	_update_ladder_state()
	if climbing:
		_climb(input_x)
	else:
		_walk(input_x, delta)
	velocity += _external_velocity
	_external_velocity = Vector2.ZERO
	var was_on_floor := is_on_floor()
	var fall_speed := velocity.y
	move_and_slide()
	if not was_on_floor and is_on_floor() and not climbing:
		_on_landed(fall_speed)
	elif is_on_floor() and absf(velocity.x) > 60.0:
		_run_dust_timer -= delta
		if _run_dust_timer <= 0.0:
			_run_dust_timer = 0.28
			Fx.dust(get_parent(), global_position - Vector2(facing * 5.0, 0))
	animator.update(delta, is_on_floor(), velocity, climbing, false)
	_update_interact_hint()


func _on_landed(fall_speed: float) -> void:
	if fall_speed < 60.0:
		return
	var k := clampf(fall_speed / MAX_FALL_SPEED, 0.2, 1.0)
	visual.squash_to(Vector2(1.0 + 0.35 * k, 1.0 - 0.3 * k), 0.2)
	animator.landed()
	Fx.dust(get_parent(), global_position, k > 0.6)
	if k > 0.8:
		EventBus.screen_shake.emit(1.5)


func _tick_timers(delta: float) -> void:
	_coyote = COYOTE_TIME if is_on_floor() else maxf(0.0, _coyote - delta)
	_jump_buffer = maxf(0.0, _jump_buffer - delta)
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	if _invulnerable > 0.0:
		_invulnerable -= delta
		visual.alpha = 0.4 if int(_invulnerable * 20.0) % 2 == 0 else 1.0
		if _invulnerable <= 0.0:
			visual.alpha = 1.0
	if _drop_timer > 0.0:
		_drop_timer -= delta
		if _drop_timer <= 0.0 and not climbing:
			set_collision_mask_value(PLATFORM_LAYER, true)
	for id in _item_cooldowns.keys():
		_item_cooldowns[id] -= delta
		if _item_cooldowns[id] <= 0.0:
			_item_cooldowns.erase(id)
	for key in _buffs.keys():
		_buffs[key] -= delta
		if _buffs[key] <= 0.0:
			_buffs.erase(key)
			hero.stats.remove_modifier(key)
			if _buffs.is_empty():
				visual.tint = Color.WHITE
	hero.skills.tick(delta)


func _update_ladder_state() -> void:
	if level == null:
		climbing = false
		return
	var on_ladder := level.is_ladder_at(global_position + Vector2(0, -10)) \
			or level.is_ladder_at(global_position + Vector2(0, -2))
	if climbing:
		if not on_ladder:
			_stop_climbing()
		return
	if on_ladder and Input.is_action_pressed("move_up"):
		_start_climbing()
	elif Input.is_action_just_pressed("move_down") and is_on_floor():
		if level.is_ladder_at(global_position + Vector2(0, 4)):
			_start_climbing()  # climb down from the top of a ladder
		else:
			# Drop through a one-way platform.
			set_collision_mask_value(PLATFORM_LAYER, false)
			_drop_timer = DROP_THROUGH_TIME
	elif on_ladder and Input.is_action_pressed("move_down") and not is_on_floor():
		_start_climbing()


func _start_climbing() -> void:
	climbing = true
	_jump_buffer = 0.0
	velocity = Vector2.ZERO
	set_collision_mask_value(PLATFORM_LAYER, false)
	global_position.x = level.ladder_center_x(global_position + Vector2(0, -2) if level.is_ladder_at(global_position + Vector2(0, -2)) else global_position + Vector2(0, 4))


func _stop_climbing() -> void:
	climbing = false
	set_collision_mask_value(PLATFORM_LAYER, true)


func _climb(input_x: float) -> void:
	var dir_y := Input.get_axis("move_up", "move_down")
	velocity = Vector2(input_x * CLIMB_SPEED * 0.7, dir_y * CLIMB_SPEED)
	if Input.is_action_just_pressed("jump") and not Input.is_action_pressed("move_up"):
		_stop_climbing()
		velocity.y = JUMP_VELOCITY * 0.8
	elif dir_y > 0.0 and is_on_floor() and not level.is_ladder_at(global_position + Vector2(0, 4)):
		_stop_climbing()


func _walk(input_x: float, delta: float) -> void:
	velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL_SPEED)
	var target := input_x * hero.stats.speed()
	var accel := ACCELERATION if is_on_floor() else AIR_ACCELERATION
	if input_x == 0.0:
		accel = FRICTION if is_on_floor() else AIR_ACCELERATION * 0.5
	velocity.x = move_toward(velocity.x, target, accel * delta)

	if Input.is_action_just_pressed("jump"):
		_jump_buffer = JUMP_BUFFER_TIME
	if _jump_buffer > 0.0 and _coyote > 0.0:
		velocity.y = JUMP_VELOCITY
		_jump_buffer = 0.0
		_coyote = 0.0
		visual.squash_to(Vector2(0.75, 1.25), 0.22)
		Fx.dust(get_parent(), global_position)
	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= JUMP_CUT


# -------------------------------------------------------------------- input
func _unhandled_input(event: InputEvent) -> void:
	if hero == null or dead:
		return
	if event.is_action_pressed("interact") and try_interact():
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("attack"):
		attack()
		get_viewport().set_input_as_handled()
		return
	for i in 4:
		if event.is_action_pressed("skill_%d" % (i + 1)):
			use_skill(i)
			get_viewport().set_input_as_handled()
			return
	for i in QuickBar.SIZE:
		if event.is_action_pressed("quick_%d" % (i + 1)):
			use_quick_slot(i)
			get_viewport().set_input_as_handled()
			return


# ------------------------------------------------------------------ combat
func roll_damage(multiplier := 1.0) -> Dictionary:
	var dmg := hero.stats.damage() * multiplier * randf_range(0.85, 1.15)
	var crit := randf() < hero.stats.crit_chance()
	if crit:
		dmg *= 2.0
	return {"amount": maxi(1, roundi(dmg)), "crit": crit}


func attack() -> void:
	if _attack_cooldown > 0.0 or climbing:
		return
	var w := hero.weapon()
	var interval := hero.attack_interval()
	_attack_cooldown = interval
	# Fists use the quick jab; weapons their own animation.
	animator.play_action(w.animation() if w else &"attack_quick", interval * 0.95)
	# The hit lands on the "active" part of the swing.
	var delay := clampf(interval * 0.35, 0.04, 0.22)
	get_tree().create_timer(delay, false).timeout.connect(_perform_attack.bind(w, facing))


func _perform_attack(w: WeaponItemData, dir: float) -> void:
	if dead or not is_inside_tree():
		return
	if w and w.is_ranged():
		_shoot(w, dir)
		return
	var reach := w.reach if w else 16.0
	var thrust := w != null and w.attack_pattern == WeaponItemData.Pattern.THRUST
	var color := w.damage_color() if w else Color.WHITE
	SlashTrail.spawn(get_parent(), global_position + Vector2(dir * 4.0, -12.0), dir, reach, thrust, color)
	var hits := _melee_targets(reach, thrust, dir)
	for enemy in hits:
		hit_enemy(enemy, w, 1.0)
	if not hits.is_empty() and w:
		hero.wear_weapon(1)


## Enemies inside the weapon hit shape: a long narrow box for thrusts,
## a half circle in front for swings.
func _melee_targets(reach: float, thrust: bool, dir: float) -> Array[Node]:
	var query := PhysicsShapeQueryParameters2D.new()
	query.collision_mask = 8
	query.collide_with_bodies = true
	var center: Vector2
	if thrust:
		var rect := RectangleShape2D.new()
		rect.size = Vector2(reach, 14)
		query.shape = rect
		center = global_position + Vector2(dir * (reach / 2.0 + 3.0), -11.0)
	else:
		var circle := CircleShape2D.new()
		circle.radius = reach
		query.shape = circle
		center = global_position + Vector2(dir * reach * 0.3, -12.0)
	query.transform = Transform2D(0.0, center)
	var result: Array[Node] = []
	for hit in get_world_2d().direct_space_state.intersect_shape(query, 16):
		var body: Node = hit["collider"]
		if body.is_in_group("enemies") and body not in result:
			if thrust or (body.global_position.x - global_position.x) * dir > -6.0:
				result.append(body)
	return result


## Applies damage, knockback and the weapon's on-hit effects.
func hit_enemy(enemy: Node, w: WeaponItemData, multiplier: float) -> void:
	var d := roll_damage(multiplier)
	enemy.take_damage(d["amount"], d["crit"], global_position)
	if not is_instance_valid(enemy) or enemy.is_dead():
		return
	if w:
		enemy.apply_knockback(signf(enemy.global_position.x - global_position.x), w.knockback)
		for e in w.on_hit_effects:
			if e:
				e.try_apply(self, enemy, d["amount"])


func _shoot(w: WeaponItemData, dir: float) -> void:
	if level == null:
		return
	var p: Projectile = PROJECTILE_SCENE.instantiate()
	var d := roll_damage()
	p.setup(w.projectile_texture, Vector2(dir, 0), w.projectile_speed, d["amount"], "enemies")
	p.crit = d["crit"]
	p.pierce = w.projectile_pierce
	p.blast_radius = w.projectile_blast_radius
	p.blast_color = w.damage_color()
	p.lifetime = w.reach / maxf(1.0, w.projectile_speed) + 0.4
	p.on_hit = func(enemy: Node, _dmg: int) -> void:
		if is_instance_valid(enemy) and not enemy.is_dead():
			enemy.apply_knockback(dir, w.knockback)
			for e in w.on_hit_effects:
				if e:
					e.try_apply(self, enemy, _dmg)
		hero.wear_weapon(1)
	level.add_entity(p, global_position + Vector2(dir * 10.0, -13.0))


## Called by enemies, enemy projectiles and traps.
func take_damage(amount: int, from_pos: Vector2 = Vector2.INF) -> void:
	if dead or _invulnerable > 0.0 or _dash_time > 0.0:
		return
	var lost := hero.stats.take_damage(amount)
	hero.wear_armor(1)
	EventBus.damage_dealt.emit(global_position + Vector2(0, -24), lost, false, true)
	_invulnerable = INVULNERABLE_TIME
	visual.flash(Color(1.0, 0.3, 0.3))
	if not dead:
		animator.hurt()
	if from_pos != Vector2.INF:
		var dir := signf(global_position.x - from_pos.x)
		if dir == 0.0:
			dir = -facing
		velocity = Vector2(dir * 160.0, -150.0)
		if climbing:
			_stop_climbing()


func _on_died() -> void:
	if dead:
		return
	dead = true
	velocity = Vector2.ZERO
	visual.alpha = 1.0
	animator.die()
	Fx.sparks(get_parent(), global_position + Vector2(0, -10), Color(0.7, 0.1, 0.1), 16, 80.0)
	EventBus.player_died.emit()


func push(impulse: Vector2) -> void:
	_external_velocity += impulse


## Dash: short invulnerable horizontal burst (used by skills).
func dash(speed: float, duration: float) -> void:
	if climbing:
		_stop_climbing()
	velocity = Vector2(facing * speed, 0.0)
	_dash_time = duration
	visual.squash_to(Vector2(1.25, 0.85), duration + 0.1)


func apply_buff(key: String, bonuses: Dictionary, duration: float, tint := Color.WHITE) -> void:
	hero.stats.set_modifier(key, bonuses)
	_buffs[key] = duration
	visual.tint = tint


func boost_light(scale_mult: float, duration: float) -> void:
	if _light_tween:
		_light_tween.kill()
	_light_tween = create_tween()
	_light_tween.tween_property(light, "texture_scale", BASE_LIGHT_SCALE * scale_mult, 0.5)
	_light_tween.tween_interval(duration)
	_light_tween.tween_property(light, "texture_scale", BASE_LIGHT_SCALE, 2.0)


# ------------------------------------------------------- skills and items
func use_skill(index: int) -> void:
	if dead:
		return
	var skills := hero.skills
	var skill := skills.get_skill(index)
	if skill == null or skill.effect == null:
		return
	if not skills.is_ready(index):
		return
	if hero.stats.mana < skill.mana_cost:
		EventBus.message.emit("Недостаточно маны")
		return
	if skill.effect.execute(self, skills.get_level(index)):
		hero.stats.spend_mana(skill.mana_cost)
		skills.start_cooldown(index)
		if skill.cast_animation != &"":
			animator.play_action(skill.cast_animation, 0.4)


func use_quick_slot(index: int) -> void:
	var item := hero.quick_bar.get_item(index)
	if item != null:
		use_item(item)


## Uses or equips an item that is in the backpack.
func use_item(item: ItemData) -> bool:
	if dead:
		return false
	if hero.inventory.count_of(item.id) <= 0:
		EventBus.message.emit("Нет предмета: %s" % item.display_name)
		return false
	if item is EquipmentItemData:
		return hero.equip_from_inventory(hero.inventory.find_item(item))
	if not (item is UsableItemData):
		return false
	if _item_cooldowns.has(item.id):
		return false
	var usable := item as UsableItemData
	if not usable.use(self):
		return false
	_item_cooldowns[item.id] = usable.cooldown
	if usable.use_animation != &"":
		animator.play_action(usable.use_animation, 0.45)
		visual.hold_temporarily(usable.icon, 0.45)
	if usable.consume_on_use:
		hero.inventory.remove_by_id(item.id, 1)
	return true


# -------------------------------------------------------------- interaction
func _nearest_interactable() -> Node:
	var best: Node = null
	var best_d := INF
	for area in interact_area.get_overlapping_areas():
		var target: Node = area if area.is_in_group("interactable") else area.get_parent()
		if target == null or not target.is_in_group("interactable"):
			continue
		if target.has_method("can_interact") and not target.can_interact():
			continue
		var d := global_position.distance_to(target.global_position)
		if d < best_d:
			best_d = d
			best = target
	return best


func try_interact() -> bool:
	var target := _nearest_interactable()
	if target == null:
		return false
	if target is Chest:
		animator.play_action(&"interact", 0.35)
	target.interact(self)
	return true


func _update_interact_hint() -> void:
	var target := _nearest_interactable()
	var text := ""
	if target != null:
		text = "[E] " + target.get_prompt()
	if text != _hint:
		_hint = text
		interact_hint_changed.emit(text)
