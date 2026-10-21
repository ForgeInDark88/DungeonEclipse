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

@onready var sprite: Sprite2D = $Sprite2D
@onready var camera: Camera2D = $Camera2D
@onready var light: PointLight2D = $PointLight2D
@onready var attack_area: Area2D = $AttackArea
@onready var interact_area: Area2D = $InteractArea
@onready var swing: Sprite2D = $Swing


func _ready() -> void:
	add_to_group("player")
	light.texture = AssetPaths.tex(AssetPaths.LIGHT)
	light.texture_scale = BASE_LIGHT_SCALE
	swing.visible = false


func setup(p_hero: Hero, p_level: DungeonLevel) -> void:
	hero = p_hero
	level = p_level
	sprite.texture = hero.class_data.sprite
	if not hero.stats.died.is_connected(_on_died):
		hero.stats.died.connect(_on_died)
	_update_swing_texture()
	if not hero.equipment.changed.is_connected(_update_swing_texture):
		hero.equipment.changed.connect(_update_swing_texture)


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
	if input_x != 0.0:
		facing = signf(input_x)
		sprite.flip_h = facing < 0.0
		attack_area.scale.x = facing

	if _dash_time > 0.0:
		_dash_time -= delta
		velocity.y = 0.0
		move_and_slide()
		return

	_update_ladder_state()
	if climbing:
		_climb(input_x)
	else:
		_walk(input_x, delta)
	velocity += _external_velocity
	_external_velocity = Vector2.ZERO
	move_and_slide()
	_update_interact_hint()


func _tick_timers(delta: float) -> void:
	_coyote = COYOTE_TIME if is_on_floor() else maxf(0.0, _coyote - delta)
	_jump_buffer = maxf(0.0, _jump_buffer - delta)
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	if _invulnerable > 0.0:
		_invulnerable -= delta
		sprite.modulate.a = 0.4 if int(_invulnerable * 20.0) % 2 == 0 else 1.0
		if _invulnerable <= 0.0:
			sprite.modulate.a = 1.0
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
				sprite.self_modulate = Color.WHITE
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
	_attack_cooldown = hero.class_data.attack_cooldown
	_play_swing()
	for body in attack_area.get_overlapping_bodies():
		if body.is_in_group("enemies") and body.has_method("take_damage"):
			var d := roll_damage()
			body.take_damage(d["amount"], d["crit"], global_position)


func _play_swing() -> void:
	swing.visible = true
	swing.position = Vector2(8 * facing, -10)
	swing.flip_h = facing < 0.0
	var from := -100.0 if facing > 0.0 else 100.0
	var to := 40.0 if facing > 0.0 else -40.0
	swing.rotation_degrees = from
	var tw := create_tween()
	tw.tween_property(swing, "rotation_degrees", to, 0.12)
	tw.tween_callback(func() -> void: swing.visible = false)


func _update_swing_texture() -> void:
	var weapon := hero.equipment.get_item(&"weapon") if hero else null
	swing.texture = weapon.icon if weapon else AssetPaths.tex("res://assets/sprites/items/rusty_sword.png")


## Called by enemies, enemy projectiles and traps.
func take_damage(amount: int, from_pos: Vector2 = Vector2.INF) -> void:
	if dead or _invulnerable > 0.0 or _dash_time > 0.0:
		return
	var lost := hero.stats.take_damage(amount)
	EventBus.floating_text.emit(global_position + Vector2(0, -24), str(lost), Color(1.0, 0.3, 0.3))
	EventBus.screen_shake.emit(3.0)
	_invulnerable = INVULNERABLE_TIME
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
	sprite.modulate = Color(0.6, 0.1, 0.1)
	var tw := create_tween()
	tw.tween_property(sprite, "rotation_degrees", 90.0 * facing, 0.4)
	EventBus.player_died.emit()


func push(impulse: Vector2) -> void:
	_external_velocity += impulse


## Dash: short invulnerable horizontal burst (used by skills).
func dash(speed: float, duration: float) -> void:
	if climbing:
		_stop_climbing()
	velocity = Vector2(facing * speed, 0.0)
	_dash_time = duration


func apply_buff(key: String, bonuses: Dictionary, duration: float, tint := Color.WHITE) -> void:
	hero.stats.set_modifier(key, bonuses)
	_buffs[key] = duration
	sprite.self_modulate = tint


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
		return hero.equip_from_inventory(hero.inventory.find_index(item.id))
	if not (item is UsableItemData):
		return false
	if _item_cooldowns.has(item.id):
		return false
	var usable := item as UsableItemData
	if not usable.use(self):
		return false
	_item_cooldowns[item.id] = usable.cooldown
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
