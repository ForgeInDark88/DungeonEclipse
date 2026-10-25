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
const PROJECTILE_SCENE := preload("res://scenes/world/projectile.tscn")

var hero: Hero
var level: DungeonLevel
var facing: float = 1.0
## Aiming with the mouse: shots and projectile skills fly to the cursor.
## Turned off by keyboard / gamepad attacks (they shoot where the hero faces).
var mouse_aim := true
var dead := false
## LAN co-op: true on machines that only render this player (its owner
## simulates and broadcasts the state).
var puppet := false
var peer_id := 1
var _net_target := Vector2.ZERO
var _net_timer := 0.0
## Co-op: damage variance/crit dice for the host's authoritative recompute.
var _net_dice := RandomNumberGenerator.new()
## Pending guest attacks awaiting the host's confirmed damage.
var _pending_hit_effects: Array[Dictionary] = []
## Pet id shown on this puppet (visual follower, no combat on copies).
var _net_pet_id := ""
var climbing := false

var _coyote := 0.0
var _jump_buffer := 0.0
var _air_jumps := 0
var _regen_acc := 0.0
var _drop_timer := 0.0
var _invulnerable := 0.0
var _attack_cooldown := 0.0
var _item_cooldowns: Dictionary = {}  # item id -> seconds
var _buffs: Dictionary = {}  # modifier key -> seconds left
var _buff_info: Dictionary = {}  # modifier key -> {"icon": Texture2D, "duration": float}
var _casting_icon: Texture2D
## Multiplier of the skill being cast (weapon synergy, SkillData.power_with); read by skill effects.
var skill_power := 1.0
var _external_velocity := Vector2.ZERO
var _hint := ""
var _dash_time := 0.0
var _afterimage_timer := 0.0
var _run_dust_timer := 0.0
var _step_timer := 0.0
var _reveal_timer := 0.0
## Minimap reveal radius in cells.
const REVEAL_RADIUS := 7

@onready var visual: HeroVisual = $Visual
@onready var animator: HeroAnimator = $Animator
@onready var camera: Camera2D = $Camera2D
@onready var interact_area: Area2D = $InteractArea
@onready var status: StatusEffects = $StatusEffects


func _ready() -> void:
	add_to_group("player")
	_net_dice.seed = hash([Net.multiplayer.get_unique_id() if Net.active else 1, randi()])
	animator.setup(visual)
	var sv := StatusVisual.new()
	add_child(sv)
	sv.setup(status, visual, 22.0)


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


func apply_biome(biome: BiomeData) -> void:
	var p := $AmbientDust as CPUParticles2D
	p.color = biome.ambient_particles
	# Motion by BiomeData.particle_style; glowing kinds ignore the ambient light.
	var glow := biome.particle_style in [&"spores", &"embers", &"sparkles"]
	var m := CanvasItemMaterial.new()
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED if glow else CanvasItemMaterial.LIGHT_MODE_NORMAL
	p.material = m
	p.scale_amount_min = 1.0
	p.scale_amount_max = 1.0
	p.gravity = Vector2.ZERO
	match biome.particle_style:
		&"spores":
			p.amount = 45
			p.direction = Vector2(0, -1)
			p.spread = 180.0
			p.initial_velocity_min = 2.0
			p.initial_velocity_max = 6.0
			p.scale_amount_max = 2.0
		&"pollen":
			p.amount = 40
			p.direction = Vector2(1, 0.3)
			p.spread = 20.0
			p.initial_velocity_min = 8.0
			p.initial_velocity_max = 16.0
		&"embers":
			p.amount = 55
			p.direction = Vector2(0.2, -1)
			p.spread = 25.0
			p.initial_velocity_min = 10.0
			p.initial_velocity_max = 24.0
			p.gravity = Vector2(0, -4)
		&"sparkles":
			p.amount = 50
			p.direction = Vector2(0, 1)
			p.spread = 180.0
			p.initial_velocity_min = 1.0
			p.initial_velocity_max = 4.0
			p.scale_amount_max = 2.0
		_:
			p.amount = 40
			p.direction = Vector2(0.3, 1)
			p.spread = 30.0
			p.initial_velocity_min = 3.0
			p.initial_velocity_max = 10.0
	# Sparkles twinkle (several alpha peaks); the rest fade in and out.
	var g := Gradient.new()
	if biome.particle_style == &"sparkles":
		g.offsets = PackedFloat32Array([0.0, 0.15, 0.3, 0.45, 0.6, 0.75, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.1), Color(1, 1, 1, 0.8),
				Color(1, 1, 1, 0.1), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0)])
	else:
		g.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.6 if glow else 0.5), Color(1, 1, 1, 0)])
	p.color_ramp = g


func _on_leveled_up(_level: int) -> void:
	AudioManager.play_ui(&"level_up")
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
	if puppet:
		_net_puppet_step(delta)
		return
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

	if status.is_stunned():
		# Stunned: physics only, no control.
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL_SPEED)
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
		move_and_slide()
		animator.update(delta, is_on_floor(), velocity, false, false)
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
	elif is_on_floor() and absf(velocity.x) > 30.0:
		_step_timer -= delta
		if _step_timer <= 0.0:
			_step_timer = 0.28
			AudioManager.play_sfx(_step_sound(), global_position, -6.0, 0.15)
	if is_on_floor() and absf(velocity.x) > 60.0:
		_run_dust_timer -= delta
		if _run_dust_timer <= 0.0:
			_run_dust_timer = 0.28
			Fx.dust(get_parent(), global_position - Vector2(facing * 5.0, 0))
	animator.update(delta, is_on_floor(), velocity, climbing, false)
	# Holding the attack button (mouse or key) keeps attacking at the weapon's rate.
	if Input.is_action_pressed("attack"):
		attack()
	_net_broadcast(delta)
	_update_interact_hint()


## Footstep by the tile under the feet: wood on platforms/ladders,
## the biome's step sound on bricks.
func _step_sound() -> StringName:
	if level == null:
		return &"step_stone"
	var kind := level.kind_at(global_position + Vector2(0, 2))
	if kind == LevelLayout.Tile.PLATFORM or LevelLayout.is_ladder(kind):
		return &"step_wood"
	return level.biome.step_sound if level.biome else &"step_stone"


func _on_landed(fall_speed: float) -> void:
	if fall_speed < 60.0:
		return
	AudioManager.play_sfx(&"land", global_position, -4.0)
	var k := clampf(fall_speed / MAX_FALL_SPEED, 0.2, 1.0)
	visual.squash_to(Vector2(1.0 + 0.35 * k, 1.0 - 0.3 * k), 0.2)
	animator.landed()
	Fx.dust(get_parent(), global_position, k > 0.6)
	if k > 0.8:
		EventBus.screen_shake.emit(1.5)


func _tick_timers(delta: float) -> void:
	_reveal_timer -= delta
	if _reveal_timer <= 0.0 and level:
		_reveal_timer = 0.15
		level.reveal_around(global_position + Vector2(0, -10), REVEAL_RADIUS)
	_coyote = COYOTE_TIME if is_on_floor() else maxf(0.0, _coyote - delta)
	_jump_buffer = maxf(0.0, _jump_buffer - delta)
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	var regen := hero.stats.get_value(StatTypes.HP_REGEN)
	if regen > 0.0 and not dead and hero.stats.hp < hero.stats.max_hp():
		_regen_acc += regen * delta
		if _regen_acc >= 1.0:
			hero.stats.heal(int(_regen_acc))
			_regen_acc -= int(_regen_acc)
	if _invulnerable > 0.0:
		_invulnerable -= delta
		visual.alpha = 0.4 if int(_invulnerable * 20.0) % 2 == 0 else 1.0
		if _invulnerable <= 0.0:
			visual.alpha = 1.0
	elif status.has(&"invisible"):
		visual.alpha = 0.35
	elif visual.alpha < 1.0:
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
		elif velocity.y < 0.0 and not level.is_ladder_at(global_position + Vector2(0, -6)) \
				and level.kind_at(global_position + Vector2(0, 1)) == LevelLayout.Tile.LADDER_TOP:
			# Reached the top: stand on the ladder top platform instead of
			# stopping a few pixels inside it and falling back through.
			var top := level.cell_bottom(level.world_to_cell(global_position + Vector2(0, 1))).y - DungeonLevel.TILE
			global_position.y = top
			velocity.y = 0.0
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
	var target := input_x * hero.stats.speed() * status.speed_multiplier()
	var accel := ACCELERATION if is_on_floor() else AIR_ACCELERATION
	if input_x == 0.0:
		accel = FRICTION if is_on_floor() else AIR_ACCELERATION * 0.5
	velocity.x = move_toward(velocity.x, target, accel * delta)

	if Input.is_action_just_pressed("jump"):
		_jump_buffer = JUMP_BUFFER_TIME
	if is_on_floor():
		_air_jumps = int(hero.stats.get_value(StatTypes.EXTRA_JUMPS))
	if _jump_buffer > 0.0 and _coyote <= 0.0 and _air_jumps > 0 and not is_on_floor():
		# Extra jumps in the air (relics, rings).
		_air_jumps -= 1
		_jump_buffer = 0.0
		velocity.y = JUMP_VELOCITY * 0.9
		Fx.sparks(get_parent(), global_position, Color(0.8, 0.9, 1.0), 6, 40.0)
		AudioManager.play_sfx(&"jump", global_position, -6.0)
	if _jump_buffer > 0.0 and _coyote > 0.0:
		velocity.y = JUMP_VELOCITY
		_jump_buffer = 0.0
		_coyote = 0.0
		visual.squash_to(Vector2(0.75, 1.25), 0.22)
		Fx.dust(get_parent(), global_position)
		AudioManager.play_sfx(&"jump", global_position, -6.0)
	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= JUMP_CUT


# -------------------------------------------------------------------- input
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		mouse_aim = true
	elif event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5):
		mouse_aim = false
	elif event is InputEventKey and event.is_action_pressed("attack"):
		mouse_aim = false
	# HUD slot controls (MOUSE_FILTER_STOP) swallow key events before
	# _unhandled_input, so gameplay keys are handled here, before the GUI -
	# but only while the game is actually running (no book is open).
	# Puppets never take input: only the local hero owns the keyboard.
	if puppet or not (event is InputEventKey) or hero == null or dead or status.is_stunned():
		return
	if get_tree().paused or get_viewport().gui_is_dragging():
		return
	if event.is_action_pressed("interact") and try_interact():
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("attack"):
		attack()
		get_viewport().set_input_as_handled()
		return
	for i in SkillSet.SLOT_COUNT:
		if event.is_action_pressed("skill_%d" % (i + 1)):
			use_skill(i)
			get_viewport().set_input_as_handled()
			return
	for i in QuickBar.SIZE:
		if event.is_action_pressed("quick_%d" % (i + 1)):
			use_quick_slot(i)
			get_viewport().set_input_as_handled()
			return


## Direction of a shot from `origin`: to the mouse cursor, or straight ahead.
func aim_vector(origin: Vector2) -> Vector2:
	if mouse_aim:
		var to := get_global_mouse_position() - origin
		if to.length() > 4.0:
			return to.normalized()
	return Vector2(facing, 0)


## Turns the hero to the cursor before a shot / cast.
func face_aim() -> void:
	if mouse_aim:
		var dx := get_global_mouse_position().x - global_position.x
		if absf(dx) > 2.0:
			facing = signf(dx)
			visual.facing = facing


## Co-op (puppet side): turn toward the caster's aim direction.
func face_aim_to(aim: Vector2) -> void:
	if absf(aim.x) > 0.01:
		facing = signf(aim.x)
		visual.facing = facing


func _unhandled_input(event: InputEvent) -> void:
	if puppet or hero == null or dead or status.is_stunned():
		return
	if event.is_action_pressed("interact") and try_interact():
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("attack"):
		attack()
		get_viewport().set_input_as_handled()
		return


# ------------------------------------------------------------------ combat
func roll_damage(multiplier := 1.0) -> Dictionary:
	var dmg := hero.stats.damage() * multiplier * skill_power * _net_dice.randf_range(0.85, 1.15)
	var crit := _net_dice.randf() < hero.stats.crit_chance()
	if crit:
		dmg *= 2.0
	return {"amount": maxi(1, roundi(dmg)), "crit": crit}


func attack() -> void:
	if _attack_cooldown > 0.0 or climbing:
		return
	status.remove(&"invisible")  # attacking reveals the hero
	var w := hero.weapon()
	# Melee and ranged alike: turn to the cursor and strike toward it
	# (keyboard / gamepad: straight ahead, as before).
	face_aim()
	var aim := aim_vector(_attack_origin())
	var interval := hero.attack_interval()
	_attack_cooldown = interval
	# Fists use the quick jab; weapons their own animation.
	var anim := w.animation() if w else &"attack_quick"
	animator.play_action(anim, interval * 0.95)
	AudioManager.play_sfx(AssetPaths.WEAPON_SFX[w.weapon_type] if w else &"attack_dagger", global_position, -2.0)
	if Net.active:
		var ns := get_tree().get_first_node_in_group("net_game") as NetSync
		if ns:
			# Ranged weapons echo the animation only: their projectile already
			# flies to the other machines as a visual copy (no slash trail).
			var ranged := w != null and w.is_ranged()
			var reach := (w.reach if w else 16.0) if not ranged else 0.0
			var thrust := w != null and not ranged and w.attack_pattern == WeaponItemData.Pattern.THRUST
			ns.broadcast_attack(peer_id, anim, aim_vector(_attack_origin()), reach,
					thrust, w.damage_color() if w else Color.WHITE)
	# The hit lands on the "active" part of the swing.
	var delay := clampf(interval * 0.35, 0.04, 0.22)
	get_tree().create_timer(delay, false).timeout.connect(_perform_attack.bind(w, aim))


## `aim`: unit direction of the strike (to the cursor, or straight ahead).
func _perform_attack(w: WeaponItemData, aim: Vector2) -> void:
	if dead or not is_inside_tree():
		return
	if w and w.is_ranged():
		_shoot(w, signf(aim.x) if absf(aim.x) > 0.01 else facing)
		return
	var reach := w.reach if w else 16.0
	var thrust := w != null and w.attack_pattern == WeaponItemData.Pattern.THRUST
	var color := w.damage_color() if w else Color.WHITE
	var origin := _attack_origin()
	# The weapon stops at the wall: shorter swing, sparks where it hits the brick.
	var free := LineOfSight.free_length(self, origin, aim, reach + 4.0)
	if free < reach:
		reach = maxf(free, 4.0)
		Fx.sparks(get_parent(), origin + aim * free, Color(1.0, 0.9, 0.6), 4, 50.0)
		AudioManager.play_sfx(&"dig", global_position, -10.0)
	SlashTrail.spawn(get_parent(), origin + aim * 4.0, aim, reach, thrust, color)
	var hits := _melee_targets(reach, thrust, aim)
	for enemy in hits:
		hit_enemy(enemy, w, 1.0)
	if not hits.is_empty() and w:
		hero.wear_weapon(1)


## Enemies inside the weapon hit shape, turned toward `aim`: a long narrow
## box for thrusts, a half circle in front for swings.
func _melee_targets(reach: float, thrust: bool, aim: Vector2) -> Array[Node]:
	var query := PhysicsShapeQueryParameters2D.new()
	query.collision_mask = 8
	query.collide_with_bodies = true
	var origin := _attack_origin()
	var center: Vector2
	var angle := 0.0
	if thrust:
		var rect := RectangleShape2D.new()
		rect.size = Vector2(reach, 14)
		query.shape = rect
		center = origin + aim * (reach / 2.0 + 3.0)
		angle = aim.angle()
	else:
		var circle := CircleShape2D.new()
		circle.radius = reach
		query.shape = circle
		center = origin + aim * reach * 0.3
	query.transform = Transform2D(angle, center)
	var result: Array[Node] = []
	for hit in get_world_2d().direct_space_state.intersect_shape(query, 16):
		var body: Node = hit["collider"]
		if body.is_in_group("enemies") and body not in result:
			if (thrust or (body.global_position + Vector2(0, -8) - origin).dot(aim) > -6.0) \
					and LineOfSight.can_hit(self, _attack_origin(), body):
				result.append(body)
	return result


## Where the weapon starts: the hero's hands.
func _attack_origin() -> Vector2:
	return global_position + Vector2(0, -12)


## Applies damage, knockback and the weapon's on-hit effects.
func hit_enemy(enemy: Node, w: WeaponItemData, multiplier: float) -> void:
	var d := roll_damage(multiplier)
	if Net.active and not Net.is_host and enemy is Enemy and enemy.puppet:
		# The host is the judge: send the attack claim, not the damage.
		var ns := get_tree().get_first_node_in_group("net_game") as NetSync
		if ns:
			ns.request_player_hit.rpc_id(1, enemy.net_id, d["amount"], d["crit"],
					w.damage_type if w else 0, _attack_origin(),
					w.knockback if w else 120.0)
			# Owner-local side effects of the hit (weapon wear, procs) run on
			# the confirmed amount that arrives in hit_confirmed.
			_pending_hit_effects.append({"enemy": enemy, "weapon": w, "seq": d["amount"]})
			if w:
				hero.wear_weapon(1)
		return
	enemy.take_damage(d["amount"], d["crit"], global_position, w.damage_type if w else 0)
	if not is_instance_valid(enemy) or enemy.is_dead():
		return
	if w:
		enemy.apply_knockback(signf(enemy.global_position.x - global_position.x), w.knockback)
		for e in w.on_hit_effects:
			if e:
				e.try_apply(self, enemy, d["amount"])
	if is_instance_valid(enemy) and not enemy.is_dead():
		hero.apply_passive_hits(self, enemy, d["amount"])


func _shoot(w: WeaponItemData, dir: float) -> void:
	if level == null:
		return
	var p: Projectile = PROJECTILE_SCENE.instantiate()
	var d := roll_damage()
	var origin := global_position + Vector2(0, -13.0)
	var aim := aim_vector(origin) if mouse_aim else Vector2(dir, 0)
	dir = signf(aim.x) if absf(aim.x) > 0.01 else dir
	p.setup(w.projectile_texture, aim, w.projectile_speed, d["amount"], "enemies")
	p.crit = d["crit"]
	p.damage_type = w.damage_type
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
			if is_instance_valid(enemy) and not enemy.is_dead():
				hero.apply_passive_hits(self, enemy, _dmg)
		hero.wear_weapon(1)
	level.add_entity(p, LineOfSight.safe_point(self, origin, origin + aim * 10.0))
	# Co-op: the others see a visual copy (hits are claimed per-target).
	if Net.active and w.projectile_texture:
		var ns := get_tree().get_first_node_in_group("net_game") as NetSync
		if ns and w.projectile_texture.resource_path != "":
			ns.projectile_fx.rpc(w.projectile_texture.resource_path, origin, aim,
					w.projectile_speed, w.reach / maxf(1.0, w.projectile_speed) + 0.4,
					w.damage_color())


## Called by enemies, enemy projectiles and traps. Elemental damage
## (damage_type > 0) is reduced by resistances, then a shield absorbs it.
## The owner broadcasts its state ~20 times a second; puppets glide along.
func _net_broadcast(delta: float) -> void:
	if puppet or not Net.active:
		return
	_net_timer -= delta
	if _net_timer <= 0.0:
		_net_timer = 0.05
		net_state.rpc(global_position, facing, hero.stats.hp if hero else 0,
				hero.stats.max_hp() if hero else 0, dead, _net_costume())


@rpc("any_peer", "call_remote", "unreliable")
func net_state(pos: Vector2, p_facing: float, hp: int, max_hp: int, is_dead: bool,
		costume: Dictionary = {}) -> void:
	if not puppet or multiplayer.get_remote_sender_id() != peer_id:
		return
	_net_target = pos
	visual.facing = p_facing
	facing = p_facing
	if hero:
		hero.stats.hp = hp
	_net_apply_costume(costume)
	if is_dead and not dead:
		dead = true
		animator.die()
	elif not is_dead and dead:
		revive()


## Host enemies hit a puppet → the owner applies the damage for real.
func net_take_damage(amount: int, from_pos: Vector2, damage_type: int) -> void:
	take_damage(amount, from_pos, damage_type)


func _net_puppet_step(delta: float) -> void:
	var before := global_position
	global_position = global_position.lerp(_net_target, minf(1.0, delta * 14.0))
	var est := (global_position - before) / maxf(delta, 0.0001)
	velocity = Vector2(est.x, 0.0)
	animator.update(delta, true, velocity, false, false)


func take_damage(amount: int, from_pos: Vector2 = Vector2.INF, damage_type: int = 0) -> void:
	# Puppets forward the hit to their owner's machine.
	if puppet:
		if dead:
			return  # corpses are not beaten
		var ns := get_tree().get_first_node_in_group("net_game") as NetSync
		if ns:
			ns.player_damage.rpc_id(peer_id, amount, from_pos, damage_type)
		return
	if dead or _invulnerable > 0.0 or _dash_time > 0.0:
		return
	if damage_type > 0:
		amount = roundi(amount * (1.0 - hero.stats.resistance(damage_type)))
	if status.has(&"curse"):
		amount = roundi(amount * StatusEffects.CURSE_DAMAGE_MULT)
	amount = status.absorb(amount)
	if amount <= 0:
		visual.flash(Color(0.6, 0.8, 1.0), 0.12)
		_invulnerable = INVULNERABLE_TIME * 0.5
		EventBus.floating_text.emit(global_position + Vector2(0, -26), "Поглощено", Color(0.6, 0.8, 1.0))
		return
	var lost := hero.stats.take_damage(amount)
	hero.wear_armor(1)
	EventBus.damage_dealt.emit(global_position + Vector2(0, -24), lost, false, true)
	_invulnerable = INVULNERABLE_TIME
	visual.flash(Color(1.0, 0.3, 0.3))
	AudioManager.play_sfx(&"player_hurt", global_position)
	if not dead:
		animator.hurt()
	if from_pos != Vector2.INF:
		var dir := signf(global_position.x - from_pos.x)
		if dir == 0.0:
			dir = -facing
		velocity = Vector2(dir * 160.0, -150.0)
		if climbing:
			_stop_climbing()


## Co-op: the host confirmed my hit's damage — apply my weapon's on-hit
## effects against the enemy shell (statuses land through the host's copy).
func net_confirm_hit(enemy: Enemy, amount: int) -> void:
	for i in range(_pending_hit_effects.size() - 1, -1, -1):
		var entry: Dictionary = _pending_hit_effects[i]
		var e: Enemy = entry["enemy"]
		if e == enemy or not is_instance_valid(e):
			_pending_hit_effects.remove_at(i)
			if e == enemy:
				var w: WeaponItemData = entry["weapon"]
				if w:
					for eff in w.on_hit_effects:
						if eff:
							eff.try_apply(self, e, amount)
				hero.apply_passive_hits(self, e, amount)
				return
	if is_instance_valid(enemy) and not enemy.is_dead():
		hero.apply_passive_hits(self, enemy, amount)


## Co-op: the hero's look — ids of everything `refresh_from` renders from.
func _net_costume() -> Dictionary:
	if hero == null:
		return {}
	var c := {"female": hero.female}
	for slot_id in hero.equipment.items:
		var it: EquipmentItemData = hero.equipment.items[slot_id]
		c[String(slot_id)] = String(it.id) if it else ""
	# Other players see the pet (a visual follower shell on their machines).
	c["pet"] = String(GameState.pet.id) if GameState.pet else ""
	return c


## Co-op (puppet side): rebuild the mirrored hero's equipment from ids so
## `refresh_from` shows the same armor/weapon layers as the owner.
func _net_apply_costume(c: Dictionary) -> void:
	if hero == null or c.is_empty() or _net_costume() == c:
		return
	hero.female = bool(c.get("female", false))
	_net_apply_pet(String(c.get("pet", "")))
	for slot_id in hero.equipment.items.keys():
		var want := String(c.get(String(slot_id), ""))
		var cur: EquipmentItemData = hero.equipment.items[slot_id]
		if (String(cur.id) if cur else "") == want:
			continue
		if want == "":
			hero.equipment.unequip(slot_id)
			continue
		var item: ItemData = ItemDatabase.get_item(StringName(want))
		if item is EquipmentItemData:
			hero.equipment.equip(item, slot_id)
	visual.refresh_from(hero)


## Co-op (puppet side): a decorative pet copy following this hero's puppet.
func _net_apply_pet(pet_id: String) -> void:
	if pet_id == _net_pet_id:
		return
	_net_pet_id = pet_id
	var cur := get_tree().get_first_node_in_group("pets_%d" % peer_id) as Node2D
	if cur:
		cur.queue_free()
	if pet_id == "":
		return
	var data: PetData = null
	if ItemDatabase.pets.has(StringName(pet_id)):
		data = ItemDatabase.pets[StringName(pet_id)]
	if data == null:
		return
	var pet: Node2D = (load(AssetPaths.PET_SCENE) as PackedScene).instantiate()
	pet.setup(data, self)
	pet.add_to_group("pets_%d" % peer_id)
	if get_parent():
		get_parent().add_child(pet)
		pet.global_position = global_position


## Co-op: the fallen hero rises at the next floor's entrance.
func revive() -> void:
	if hero == null:
		return
	dead = false
	hero.revive()
	_invulnerable = 2.0
	visual.alpha = 1.0
	animator.revive()
	if Net.active:
		var hpns = get_tree().get_first_node_in_group("net_game")
		if hpns:
			hpns.broadcast_player_hp(Net.multiplayer.get_unique_id(),
					hero.stats.hp, hero.stats.max_hp(), false)
	# The camera kept spectating while dead: put it back on this hero.
	if camera:
		camera.global_position = global_position
		camera.make_current()



func _on_died() -> void:
	if dead:
		return
	if hero.try_second_chance():
		_invulnerable = 2.0
		Fx.sparks(get_parent(), global_position + Vector2(0, -10), Color(1.0, 0.75, 0.3), 24, 120.0)
		AudioManager.play_sfx(&"level_up", global_position)
		return
	dead = true
	velocity = Vector2.ZERO
	visual.alpha = 1.0
	animator.die()
	# Co-op: the death must reach the other machines instantly — the 1s
	# ceremony in _on_player_died_coop is too late for mobs and puppets.
	if Net.active:
		var hpns = get_tree().get_first_node_in_group("net_game")
		if hpns:
			hpns.broadcast_player_hp(Net.multiplayer.get_unique_id(), 0,
					hero.stats.max_hp() if hero else 0, true)
	AudioManager.play_sfx(&"player_death", global_position)
	Fx.sparks(get_parent(), global_position + Vector2(0, -10), Color(0.7, 0.1, 0.1), 16, 80.0)
	EventBus.player_died.emit()


## Damage over time from statuses: ignores armor and invulnerability.
func take_status_damage(amount: int, p_status: StringName, color: Color) -> void:
	if dead:
		return
	amount = roundi(amount * (1.0 - status_resistance(p_status)))
	if amount <= 0:
		return
	hero.stats.lose_hp(amount)
	EventBus.floating_text.emit(global_position + Vector2(randf_range(-4, 4), -26), str(amount), color)


func heal_status(amount: int) -> void:
	if dead or hero.stats.hp >= hero.stats.max_hp():
		return
	hero.stats.heal(amount)
	EventBus.floating_text.emit(global_position + Vector2(0, -26), "+%d" % amount, Color(0.4, 1.0, 0.5))


func status_resistance(id: StringName) -> float:
	return hero.stats.resistance(StatusEffects.damage_type_of(id))


func push(impulse: Vector2) -> void:
	_external_velocity += impulse


## Dash: short invulnerable horizontal burst (used by skills).
func dash(speed: float, duration: float) -> void:
	if climbing:
		_stop_climbing()
	velocity = Vector2(facing * speed, 0.0)
	_dash_time = duration
	AudioManager.play_sfx(&"dash", global_position)
	visual.squash_to(Vector2(1.25, 0.85), duration + 0.1)


func apply_buff(key: String, bonuses: Dictionary, duration: float, tint := Color.WHITE) -> void:
	hero.stats.set_modifier(key, bonuses)
	_buffs[key] = duration
	_buff_info[key] = {"icon": _casting_icon, "duration": duration, "tint": tint}
	visual.tint = tint


## Active buffs for the HUD: [{key, left, duration, icon, tint}].
func get_buffs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for key: String in _buffs:
		var info: Dictionary = _buff_info.get(key, {})
		out.append({"key": key, "left": _buffs[key], "duration": info.get("duration", 1.0),
				"icon": info.get("icon"), "tint": info.get("tint", Color.WHITE)})
	return out


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
	_casting_icon = skill.icon
	face_aim()  # skills that act in front of the hero turn to the cursor too
	skill_power = skill.power_with(hero.weapon())
	var fired := skill.effect.execute(self, skills.get_level(index))
	skill_power = 1.0
	_casting_icon = null
	if fired:
		hero.stats.spend_mana(skill.mana_cost)
		skills.start_cooldown(index)
		if skill.cast_animation != &"":
			animator.play_action(skill.cast_animation, 0.4)
		var snd := skill.cast_sound if skill.cast_sound != &"" else &"skill_cast"
		AudioManager.play_sfx(snd, global_position, -4.0)
		if Net.active:
			var ns := get_tree().get_first_node_in_group("net_game") as NetSync
			if ns:
				ns.broadcast_cast(peer_id, skill.id, aim_vector(_attack_origin()))


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
	AudioManager.play_sfx(usable.use_sound, global_position)
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
		text = "[%s] %s" % [InputBindings.key_for("interact"), target.get_prompt()]
	if text != _hint:
		_hint = text
		interact_hint_changed.emit(text)
