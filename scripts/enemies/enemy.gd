class_name Enemy
extends CharacterBody2D
## Generic monster driven by an EnemyData resource.
##
## AI state machine: PATROL → ALERT (noticed the hero) → CHASE → ATTACK,
## then SEARCH (goes to the last seen / heard spot) → RETURN (back home) →
## PATROL. HURT is a short stagger. Movement uses the floor navigation
## (DungeonLevel.nav, LevelNav): walkers follow the platform graph (walk, jump,
## fall, drop through platforms, climb ladders) and never step on traps,
## flyers follow a grid A* with ray "whiskers" against walls. Sight needs a
## clear line (bricks block it), the last seen spot is remembered for a few
## seconds, loud fights and explosions are heard (EventBus.noise).
## Anti-stuck: no progress for STUCK_CHECK s → new path → jump / turn →
## teleport to the nearest safe node (logged in AIDebug).
## Deeper floors: monsters call allies, spread around the hero and do not
## rush in one by one (coordination()). Stats scale with the floor number.
## Animations (from EnemyData.sheet): idle, walk|fly, windup, attack, hurt,
## death; hit flash through the flash shader.

enum State { PATROL, CHASE, ATTACK, HURT, ALERT, SEARCH, RETURN }
enum Move { MOVING, ARRIVED, NO_PATH }

const STATE_NAMES := ["patrol", "chase", "attack", "hurt", "alert", "search", "return"]
const GRAVITY := 900.0
const PROJECTILE_SCENE := preload("res://scenes/world/projectile.tscn")
## Monster strength per floor below the first (see docs/BALANCE.md).
const HP_SCALE_PER_FLOOR := 0.4
const DMG_SCALE_PER_FLOOR := 0.22
## Elites drop from this richer table instead of their own.
const ELITE_LOOT_TABLE := &"enemy_rare"
const WORLD_MASK := 1
const PLATFORM_LAYER := 2
## Seconds the hero's last position is remembered after losing sight.
const MEMORY_TIME := 4.0
const ALERT_TIME := 0.45
const SEARCH_LOOK_TIME := 1.6
const REPATH_TIME := 0.6
const CLIMB_SPEED := 55.0
const STUCK_CHECK := 1.2
const STUCK_DIST := 6.0
## Close enough to notice the hero even from behind.
const FEEL_RANGE := 40.0

var data: EnemyData
var floor_number: int = 1
var max_hp: int = 10
var hp: int = 10
var damage: int = 1
## Floor guardian: boosted elite guarding a sealed room.
var champion := false
## Held on its post by the guardian gate: no thinking, no walking, until
## the hero steps into the room and the doors slam.
var held := false
## LAN co-op: on clients enemies are puppets — the host simulates them.
var puppet := false
var net_id := 0
var _net_target := Vector2.ZERO
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
## Periodic re-target to the nearest living hero.
var _retarget := 0.0
var _flash_tween: Tween
## Elite modifier (null for normal monsters).
var elite: EliteAffixData
var _speed_mult := 1.0
var _cooldown_mult := 1.0
var _summons: Array[Node] = []
var _summon_next := true
var _ambushing := false
var _name_label: Label

# --- AI ---
var _clearance := 1
var _climbing := false
var _drop_timer := 0.0
var _jumping := false
var _jump_vx := 0.0
var _air_time := 0.0
## Walkers: [{"cell": Vector2i, "kind": LevelNav.Edge}], flyers: same with kind -1.
var _path: Array = []
var _path_i := 0
var _path_goal := Vector2i(-9999, -9999)
var _path_version := -1
var _repath_timer := 0.0
var _sees_player := false
var _last_seen := Vector2.INF
var _memory := 0.0
var _state_time := 0.0
var _recoil := 0.0
var _hold := false
var _flank := 0.0
var _sep := Vector2.ZERO
var _wants_move := false
var _stuck_anchor := Vector2.ZERO
var _stuck_timer := 0.0
var _stuck_level := 0
var _stuck_origin := Vector2.ZERO
var _still_time := 0.0
var _mark: Label
var _mark_time := 0.0
## Far from the hero and idle: AI and physics sleep (see _sleep_far_away).
const WAKE_RANGE := 520.0
static var _group_cache: Array[Node] = []
static var _group_frame := -1
var _dormant := false
var _dormant_check := 0.0
## Statistics read by tests/ai_sim: longest time it wanted to move but could
## not, and time spent standing in a trap cell.
var _home_set := false
var _last_step := ""
var _patrol_turns := 0.0
var _patrol_idle := 0.0
var _patrol_point := Vector2.INF
var _patrol_check := 0.0
var _patrol_dist := 0.0
var max_still_time := 0.0
var danger_time := 0.0

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var shape: CollisionShape2D = $CollisionShape2D
@onready var hp_bar: ProgressBar = $HpBar
@onready var status: StatusEffects = $StatusEffects


func setup(p_data: EnemyData, p_floor: int, p_elite: EliteAffixData = null, p_champion := false) -> void:
	data = p_data
	floor_number = p_floor
	elite = p_elite
	champion = p_champion
	var f := float(p_floor - 1)
	max_hp = roundi(data.max_hp * (1.0 + HP_SCALE_PER_FLOOR * f))
	damage = roundi(data.damage * (1.0 + DMG_SCALE_PER_FLOOR * f))
	if elite:
		max_hp = roundi(max_hp * elite.hp_mult)
		damage = roundi(damage * elite.damage_mult)
		_speed_mult = elite.speed_mult
		_cooldown_mult = elite.attack_cooldown_mult
	if champion:
		# The floor guardian: a monster of legends behind slammed doors.
		max_hp = roundi(max_hp * 2.4)
		damage = roundi(damage * 1.2)
	# Difficulty and curses of the altars of fate.
	max_hp = maxi(1, roundi(max_hp * (1.0 + GameState.run_effect("enemy_hp"))))
	damage = maxi(1, roundi(damage * (1.0 + GameState.run_effect("enemy_damage"))))
	# Co-op: the party makes the dungeon meaner.
	if Net.active:
		max_hp = maxi(1, roundi(max_hp * Net.enemy_hp_mult()))
		damage = maxi(1, roundi(damage * Net.enemy_damage_mult()))
	hp = max_hp
	if puppet:
		_net_target = global_position
		_play(&"idle")


func display_name() -> String:
	var base := data.display_name
	if elite:
		base = "%s %s" % [elite.prefix(data.gender), base.left(1).to_lower() + base.substr(1)]
	if champion:
		return "Страж этажа: %s" % base
	return base


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
	_float_t = randf() * TAU
	if data.behavior == EnemyData.Behavior.FLYER:
		motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
		# Wings: one-way platforms are no obstacle (the flying grid ignores them too).
		set_collision_mask_value(PLATFORM_LAYER, false)
	if data.phases_through_walls:
		collision_mask = 0
		sprite.self_modulate.a = 0.85
	if elite:
		_setup_elite()
	if champion and not elite:
		scale = Vector2(1.45, 1.45)
	if data.ceiling_ambush:
		_ambushing = true
		call_deferred("_hang_from_ceiling")
	_clearance = 2 if data.collision_size.y > DungeonLevel.TILE else 1
	_stuck_anchor = global_position
	_mark = Label.new()
	_mark.add_theme_font_size_override("font_size", 10)
	_mark.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.02))
	_mark.add_theme_constant_override("outline_size", 3)
	_mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mark.size = Vector2(16, 12)
	_mark.position = Vector2(-8, -data.collision_size.y - 26)
	_mark.visible = false
	add_child(_mark)
	EventBus.noise.connect(_on_noise)


func _setup_elite() -> void:
	add_to_group("elites")
	scale = Vector2(1.45, 1.45) if champion else Vector2(1.2, 1.2)
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



## All monsters, fetched from the scene tree once per physics frame.
func all_enemies() -> Array[Node]:
	var frame := Engine.get_physics_frames()
	if frame != _group_frame:
		_group_frame = frame
		_group_cache = get_tree().get_nodes_in_group("enemies")
	return _group_cache


## Monsters far from the hero that are only patrolling stop thinking and
## moving until the hero comes closer or something wakes them (noise, hit).
func _sleep_far_away(delta: float) -> bool:
	_dormant_check -= delta
	if _dormant_check <= 0.0:
		_dormant_check = 0.5 + randf() * 0.2
		var far := _player == null or global_position.distance_to(_player.global_position) > WAKE_RANGE
		var landed := data.behavior == EnemyData.Behavior.FLYER or (is_on_floor() and absf(velocity.y) < 1.0)
		_dormant = far and landed and state == State.PATROL and not _ambushing
	if not _dormant:
		return false
	velocity = Vector2.ZERO
	_play(&"idle")
	return true


## Co-op: the closest standing hero gets the monster's attention.
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


func _physics_process(delta: float) -> void:
	if puppet:
		# Shell on a client: glide to the host's last word, no thinking,
		# but still animate - windup/attack when the host is, walk when
		# moving, idle at rest.
		var before := global_position
		global_position = global_position.lerp(_net_target, minf(1.0, delta * 12.0))
		var dx: float = (global_position.x - before.x) / maxf(delta, 0.0001)
		_attack_anim_left = maxf(0.0, _attack_anim_left - delta)
		if state == State.ATTACK:
			_play(&"windup")
		elif state == State.HURT:
			_play(&"hurt")
		elif _attack_anim_left > 0.0:
			_play(&"attack")
		elif absf(dx) > 12.0:
			sprite.flip_h = dx < 0.0
			_play(_move_anim())
		else:
			_play(&"idle")
		return
	if not _home_set:
		# The spawn point is known only after DungeonLevel.add_entity placed us.
		_home_set = true
		_home = global_position
		_stuck_anchor = global_position
	# Re-target to the closest living hero periodically: otherwise a mob
	# stays fixated on its first target even when another hero walks up.
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
	if held:
		# On guard: stands still (gravity only), waiting for the hero.
		velocity.x = 0.0
		if data.behavior != EnemyData.Behavior.FLYER:
			velocity.y = minf(velocity.y + GRAVITY * delta, 420.0)
		else:
			velocity.y = move_toward(velocity.y, 0.0, 600.0 * delta)
		move_and_slide()
		_play(&"idle")
		return
	if _update_ambush():
		return
	if _sleep_far_away(delta):
		return
	if not global_position.is_finite() or not velocity.is_finite():
		push_warning("Enemy %s: invalid position, back to spawn (home %s, state %s, vel %s, ambush %s)" % [data.id, _home, state_name(), velocity, _ambushing])
		global_position = _home
		velocity = Vector2.ZERO
	_update_mark(delta)
	if status.is_stunned():
		# Stunned: no thinking, no attacks, just physics.
		_stop_climb()
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
	_state_time += delta
	_recoil = maxf(0.0, _recoil - delta)
	_memory = maxf(0.0, _memory - delta)
	_repath_timer -= delta
	if _drop_timer > 0.0:
		_drop_timer -= delta
		if _drop_timer <= 0.0 and not _climbing:
			set_collision_mask_value(PLATFORM_LAYER, true)
	_think_timer -= delta
	if _think_timer <= 0.0:
		_think_timer = 0.2
		_think()
	_wants_move = false
	match data.behavior:
		EnemyData.Behavior.FLYER:
			_fly(delta)
		_:
			_walk(delta)
	# Slows / swift elites scale this step only: velocity itself is kept, so
	# the factor never compounds frame after frame.
	var slow := status.speed_multiplier() * _speed_mult
	var flyer := data.behavior == EnemyData.Behavior.FLYER
	if slow != 1.0:
		velocity.x *= slow
		if flyer:
			velocity.y *= slow
	move_and_slide()
	if slow != 1.0 and slow > 0.05:
		velocity.x /= slow
		if flyer:
			velocity.y /= slow
	if absf(velocity.x) > 1.0 and not _climbing:
		sprite.flip_h = velocity.x < 0.0
	_check_stuck(delta)
	var lvl := _level()
	if lvl and lvl.nav and lvl.nav.is_forbidden(_feet_cell()) and data.behavior != EnemyData.Behavior.FLYER and is_on_floor():
		_path.clear()  # landed on a trap cell: plan a way off right now
		if danger_time == 0.0 or fmod(danger_time, 1.0) < delta:
			AIDebug.log_event(self, "danger", "%s в клетке ловушки %s (%s, шаг %s, прошлый шаг %s, vel %s, jumping %s)" % [data.id, _feet_cell(), state_name(), _debug_step(), _last_step, velocity, _jumping])
		danger_time += delta
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
	if m:
		m.set_shader_parameter("flash_color", color)
		m.set_shader_parameter("flash", amount)


# ------------------------------------------------------------- perception
## Sight: within aggro range, a clear line through the bricks, and (while
## patrolling) in front of the monster unless the hero is very close.
func _can_see_player() -> bool:
	if _player == null or _player.dead:
		return false
	var to_player := _player.global_position - global_position
	var dist := to_player.length()
	if dist > data.aggro_range:
		return false
	# Invisibility potion: only noticed when bumped into.
	if _player.status.has(&"invisible") and dist > 14.0:
		return false
	if state == State.PATROL and dist > FEEL_RANGE and signf(to_player.x) != _facing():
		return false
	if data.phases_through_walls:
		return true
	return has_line_to(_player.global_position + Vector2(0, -10))


## True when no brick / wall is between the monster's eyes and `target`.
func has_line_to(target: Vector2) -> bool:
	var eye := global_position + Vector2(0, -minf(10.0, data.collision_size.y * 0.6))
	return LineOfSight.clear(self, eye, target)


func _facing() -> float:
	return -1.0 if sprite.flip_h else 1.0


## Kept for the boss and older callers.
func _player_visible() -> bool:
	return _can_see_player()


func _think() -> void:
	_sees_player = _can_see_player()
	if _sees_player:
		_last_seen = _player.global_position
		_memory = MEMORY_TIME
	_update_separation()
	match state:
		State.HURT, State.ATTACK:
			return
		State.PATROL, State.RETURN:
			if _sees_player:
				_notice()
		State.SEARCH:
			if _sees_player:
				_set_state(State.CHASE)
		State.ALERT:
			if _state_time >= ALERT_TIME:
				_set_state(State.CHASE)
		State.CHASE:
			if not _sees_player and (_memory <= 0.0 or _last_seen == Vector2.INF):
				_set_state(State.SEARCH)
			else:
				_update_tactics()


func _set_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	_state_time = 0.0
	_path.clear()
	_hold = false


func _notice() -> void:
	_set_state(State.ALERT)
	_show_mark("!", Color(1.0, 0.85, 0.2))
	# Deeper floors: the monster calls the allies around it.
	var call_range := 70.0 + 110.0 * coordination()
	if coordination() <= 0.0:
		return
	for e in all_enemies():
		var other := e as Enemy
		if other == null or other == self or other.is_dead():
			continue
		if other.global_position.distance_to(global_position) <= call_range:
			other.hear(_player.global_position)


## A sound at `pos` (fight, explosion, an ally calling).
func hear(pos: Vector2) -> void:
	_dormant = false
	_dormant_check = 1.0
	if _dead or state in [State.CHASE, State.ATTACK, State.ALERT, State.HURT]:
		return
	_last_seen = pos
	_memory = MEMORY_TIME * 0.5
	_set_state(State.SEARCH)
	_show_mark("?", Color(0.8, 0.7, 1.0))


func _on_noise(pos: Vector2, radius: float) -> void:
	if not is_inside_tree() or _ambushing:
		return
	if global_position.distance_to(pos) <= radius:
		hear(pos)


func _show_mark(text: String, color: Color) -> void:
	_mark.text = text
	_mark.add_theme_color_override("font_color", color)
	_mark.visible = true
	_mark_time = 0.9


func _update_mark(delta: float) -> void:
	if _mark_time > 0.0:
		_mark_time -= delta
		_mark.visible = _mark_time > 0.0


## 0 on the first floors, 1 from floor 10: calling allies, flanking, waiting
## for the group instead of attacking one by one.
func coordination() -> float:
	return clampf((floor_number - 2) / 8.0, 0.0, 1.0)


## Monsters do not stand inside each other: a small push away from neighbours.
func _update_separation() -> void:
	_sep = Vector2.ZERO
	for e in all_enemies():
		var other := e as Enemy
		if other == null or other == self or other.is_dead():
			continue
		var d := global_position - other.global_position
		if absf(d.x) < 14.0 and absf(d.y) < 14.0:
			var push := signf(d.x) if absf(d.x) > 0.5 else (1.0 if get_instance_id() > other.get_instance_id() else -1.0)
			_sep.x += push
			if data.behavior == EnemyData.Behavior.FLYER:
				_sep.y += signf(d.y) if absf(d.y) > 0.5 else -1.0
	_sep = _sep.limit_length(1.0)


## Flanking and grouping (coordination). Picks the side of the hero to come
## from and whether to wait for allies.
func _update_tactics() -> void:
	_hold = false
	_flank = 0.0
	var c := coordination()
	if c <= 0.0 or _player == null or data.behavior == EnemyData.Behavior.RANGED:
		return
	var left := 0
	var right := 0
	var closer_allies := 0
	var far_allies := 0
	var my_dist := _distance_to_player()
	for e in all_enemies():
		var other := e as Enemy
		if other == null or other == self or other.is_dead() or other.state not in [State.CHASE, State.ATTACK]:
			continue
		var od := other.global_position.distance_to(_player.global_position)
		if od > 220.0:
			continue
		if other.global_position.x < _player.global_position.x:
			left += 1
		else:
			right += 1
		if od < my_dist:
			closer_allies += 1
		else:
			far_allies += 1
	var my_side := -1.0 if global_position.x < _player.global_position.x else 1.0
	# Surround: go to the less crowded side.
	if c >= 0.25 and ((my_side < 0 and left > right + 1) or (my_side > 0 and right > left + 1)):
		_flank = -my_side
	# Do not rush in alone when the pack is still on its way.
	if c >= 0.6 and closer_allies == 0 and far_allies > 0 and _state_time < 2.5 and my_dist > 30.0:
		_hold = true


func _distance_to_player() -> float:
	return global_position.distance_to(_player.global_position) if _player else INF


# ------------------------------------------------------------------ walking
func _walk(delta: float) -> void:
	if not _climbing:
		velocity.y = minf(velocity.y + GRAVITY * delta, 420.0)
	if not is_on_floor() and not _climbing:
		_air_time += delta
	else:
		_air_time = 0.0
	match state:
		State.HURT:
			_stop_climb()
			_hurt_timer -= delta
			velocity.x = move_toward(velocity.x, 0.0, 400.0 * delta)
			if _hurt_timer <= 0.0:
				_set_state(State.CHASE)
				# Melee monsters step back after taking a hit, then come again.
				if data.behavior == EnemyData.Behavior.WALKER and not data.jumps:
					_recoil = 0.35
		State.PATROL:
			_patrol_walk(delta)
		State.ALERT:
			_stop_climb()
			velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
			_face_point(_player.global_position if _player else global_position)
		State.CHASE:
			_chase_walk(delta)
		State.SEARCH:
			_search(delta)
		State.RETURN:
			if _go_to(_home, data.speed, delta) != Move.MOVING:
				_set_state(State.PATROL)
		State.ATTACK:
			velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
			_update_attack(delta)
	# Spread out only while standing (waiting, aiming): never against the walk.
	if state in [State.CHASE, State.SEARCH] and not _jumping and not _climbing and absf(velocity.x) < 4.0 and _sep.x != 0.0:
		var keep := dir
		dir = signf(_sep.x)
		if not _blocked_ahead():
			velocity.x = _sep.x * 25.0
		dir = keep


## Back and forth along the platform; on a tiny ledge (turning again right
## away) the monster stands guard for a while instead of jittering.
func _patrol_walk(delta: float) -> void:
	_stop_climb()
	_patrol_turns = maxf(0.0, _patrol_turns - delta)
	if _patrol_idle > 0.0:
		_patrol_idle -= delta
		velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
		return
	velocity.x = dir * data.speed
	_wants_move = true
	if is_on_floor() and (is_on_wall() or _blocked_ahead()):
		dir = -dir
		_patrol_turns += 1.0
		if _patrol_turns >= 2.0:
			_patrol_turns = 0.0
			_patrol_idle = randf_range(1.5, 3.0)
			velocity.x = 0.0


## Wall, a drop deeper than a step, or a trap right in front of the feet.
func _blocked_ahead() -> bool:
	var lvl := _level()
	if lvl == null:
		return false
	var probe := global_position + Vector2(dir * (data.collision_size.x / 2.0 + 3.0), -2.0)
	var cell := lvl.world_to_cell(probe)
	if lvl.nav == null:
		return not lvl.is_ground_at(probe + Vector2(0, 6))
	return not lvl.nav.standable(cell.x, cell.y, _clearance) or lvl.nav.is_dangerous(cell)


## A trap cell within two cells in front (no playful hops there).
func _danger_near() -> bool:
	var lvl := _level()
	if lvl == null or lvl.nav == null:
		return false
	var c := _feet_cell()
	for i in range(0, 3):
		if lvl.nav.is_dangerous(c + Vector2i(int(dir) * i, 0)):
			return true
	return false


func _ledge_ahead() -> bool:
	return _blocked_ahead()


func _chase_walk(delta: float) -> void:
	if _player == null:
		_set_state(State.SEARCH)
		return
	var target := _player.global_position if _sees_player else _last_seen
	var to_p := _player.global_position - global_position
	var dist := to_p.length()
	if data.behavior == EnemyData.Behavior.RANGED:
		# Keep the distance: back off when the hero is close, shoot when in range.
		var min_range := data.attack_range * 0.45
		if _sees_player and dist < min_range and _retreat(delta):
			_face_point(_player.global_position)
			if _attack_timer <= 0.0 and dist > 18.0:
				_begin_attack()
			return
		if _sees_player and dist <= data.attack_range * 0.9:
			_stop_climb()
			velocity.x = move_toward(velocity.x, 0.0, 800.0 * delta)
			_face_point(_player.global_position)
			if _attack_timer <= 0.0:
				_begin_attack()
			return
		_go_to(target, data.chase_speed, delta)
		return
	if _recoil > 0.0:
		_retreat(delta)
		return
	if _sees_player and _can_melee() and _attack_timer <= 0.0:
		_stop_climb()
		_face_point(_player.global_position)
		_begin_attack()
		return
	if _hold and dist < 70.0:
		velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
		_face_point(_player.global_position)
		return
	if _flank != 0.0 and dist > 36.0:
		target += Vector2(_flank * 24.0, 0)
	var res := _go_to(target, data.chase_speed, delta)
	if res != Move.MOVING:
		# Arrived or unreachable: wait facing the hero instead of pushing a wall.
		velocity.x = move_toward(velocity.x, 0.0, 800.0 * delta)
		_face_point(_player.global_position)
		if res == Move.NO_PATH and not _sees_player and _state_time > 3.0:
			_set_state(State.SEARCH)
	elif data.jumps and is_on_floor() and not _jumping and randf() < 0.02 and not _danger_near():
		velocity.y = -200.0  # slimes keep bouncing (never next to a trap)


## Melee only with a clear line and on (about) the same level.
func _can_melee() -> bool:
	var rel := _player.global_position - global_position
	var reach := data.attack_range + 6.0 + (data.aoe_radius if data.aoe_radius > 0.0 else 0.0) * 0.5
	return absf(rel.x) <= reach and absf(rel.y) < 22.0 and has_line_to(_player.global_position + Vector2(0, -8))


## Steps away from the hero if the ground behind is safe. False = cornered.
func _retreat(_delta: float) -> bool:
	if data.behavior == EnemyData.Behavior.FLYER:
		var away := (global_position - _player.global_position).normalized()
		velocity = velocity.move_toward((away + Vector2(0, -0.6)).normalized() * data.speed, 20.0)
		_wants_move = true
		return true
	var away_dir := -signf(_player.global_position.x - global_position.x)
	if away_dir == 0.0:
		away_dir = -_facing()
	var keep := dir
	dir = away_dir
	var blocked := _blocked_ahead() or (is_on_wall() and signf(get_wall_normal().x) != away_dir)
	dir = keep
	if blocked or not is_on_floor():
		velocity.x = 0.0
		return false
	_stop_climb()
	velocity.x = away_dir * data.speed
	_wants_move = true
	return true


func _search(delta: float) -> void:
	if _last_seen == Vector2.INF:
		_set_state(State.RETURN)
		return
	if _state_time < 8.0 and global_position.distance_to(_last_seen) > 12.0:
		var res := _go_to(_last_seen, data.speed * 1.2, delta)
		if res == Move.MOVING:
			return
		if res == Move.NO_PATH and _state_time < 1.0:
			return
	# At the spot (or it cannot be reached): look around, then go home.
	_stop_climb()
	velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
	if fmod(_state_time, 0.6) < delta:
		sprite.flip_h = not sprite.flip_h
	if _state_time > SEARCH_LOOK_TIME + 1.0 or global_position.distance_to(_last_seen) <= 12.0 and _search_done():
		_last_seen = Vector2.INF
		_set_state(State.RETURN)


var _look_started := -1.0


func _search_done() -> bool:
	if _look_started < 0.0:
		_look_started = _state_time
	if _state_time - _look_started >= SEARCH_LOOK_TIME:
		_look_started = -1.0
		return true
	return false


func _face_point(p: Vector2) -> void:
	if absf(p.x - global_position.x) > 2.0:
		dir = signf(p.x - global_position.x)
		sprite.flip_h = dir < 0.0


# --------------------------------------------------------------- navigation
## Cell under the feet (bottom center of the body).
func _feet_cell() -> Vector2i:
	var lvl := _level()
	return lvl.world_to_cell(global_position + Vector2(0, -2)) if lvl else Vector2i.ZERO


## Moves along the navigation path to `target`. Recomputes the path when the
## goal cell changes, the level changed (dug bricks) or every REPATH_TIME.
func _go_to(target: Vector2, speed: float, delta: float) -> Move:
	if not target.is_finite():
		return Move.NO_PATH
	var lvl := _level()
	if lvl == null or lvl.nav == null or data.phases_through_walls:
		return _go_direct(target, speed)
	var goal := lvl.world_to_cell(target + Vector2(0, -2))
	var grounded := is_on_floor() or _climbing or data.behavior == EnemyData.Behavior.FLYER
	if _jumping and is_on_floor() and velocity.y >= 0.0 and (_path.is_empty() or _path_i >= _path.size()):
		_jumping = false  # landed after the plan changed mid-air
	var outdated := _nav_changed(lvl) or goal != _path_goal or _repath_timer <= 0.0 or _path.is_empty()
	if outdated and grounded and not _jumping:
		_compute_path(lvl, goal)
	if _path.is_empty():
		if data.behavior != EnemyData.Behavior.FLYER:
			velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
		return Move.NO_PATH
	if data.behavior == EnemyData.Behavior.FLYER:
		return _follow_fly(lvl, speed, delta)
	return _follow_ground(lvl, speed, delta)


## The level changed (a brick broke): repath soon, but not all monsters in
## the same frame — the old path stays valid for a moment.
func _nav_changed(lvl: DungeonLevel) -> bool:
	if _path_version == lvl.nav.version:
		return false
	_path_version = lvl.nav.version
	if _path.is_empty():
		return true
	_repath_timer = minf(_repath_timer, randf_range(0.05, 0.5))
	return false


func _compute_path(lvl: DungeonLevel, goal: Vector2i) -> void:
	_path_goal = goal
	_path_version = lvl.nav.version
	_repath_timer = REPATH_TIME
	var start := _feet_cell()
	if data.behavior == EnemyData.Behavior.FLYER:
		var cells := lvl.nav.fly_path(lvl.world_to_cell(global_position + Vector2(0, -6)), goal)
		_path = []
		for c in cells:
			_path.append({"cell": c, "kind": -1})
		_path_i = 1 if _path.size() > 1 else 0
		return
	_path = lvl.nav.ground_path(start, goal, _clearance)
	_path_i = 0
	if not _path.is_empty() and _path[0]["cell"] == start:
		_path_i = 1


func _go_direct(target: Vector2, speed: float) -> Move:
	var d := target - global_position
	if d.length() < 6.0:
		return Move.ARRIVED
	_wants_move = true
	if data.behavior == EnemyData.Behavior.FLYER:
		velocity = velocity.move_toward(d.normalized() * speed, 20.0)
	else:
		velocity.x = signf(d.x) * speed
	return Move.MOVING


func _follow_ground(lvl: DungeonLevel, speed: float, delta: float) -> Move:
	if _path_i >= _path.size():
		_stop_climb()
		velocity.x = move_toward(velocity.x, 0.0, 800.0 * delta)
		return Move.ARRIVED
	_wants_move = true
	var step: Dictionary = _path[_path_i]
	var cell: Vector2i = step["cell"]
	var kind: int = step["kind"]
	var tpos := lvl.cell_bottom(cell)
	var feet := _feet_cell()
	match kind:
		LevelNav.Edge.CLIMB:
			_start_climb()
			global_position.x = move_toward(global_position.x, tpos.x, 160.0 * delta)
			var dy := tpos.y - global_position.y
			velocity = Vector2(0.0, signf(dy) * CLIMB_SPEED)
			if absf(dy) <= CLIMB_SPEED * delta + 0.5:
				global_position.y = tpos.y
				velocity.y = 0.0
				_advance()
				# Leaving the shaft upward: the platform mask must return at
				# once so the body stands on the ladder top instead of sinking
				# back through the one-way tile and re-climbing forever.
				var next_kind: int = _path[_path_i]["kind"] if _path_i < _path.size() else -1
				if dy < 0.0 and next_kind != LevelNav.Edge.CLIMB:
					_stop_climb_on_platform()
		LevelNav.Edge.JUMP:
			_stop_climb()
			if not _jumping:
				if not is_on_floor():
					return Move.MOVING
				var from := lvl.cell_bottom(_path[_path_i - 1]["cell"]) if _path_i > 0 else global_position
				if absf(global_position.x - from.x) > 3.0:
					velocity.x = signf(from.x - global_position.x) * speed
					return Move.MOVING
				_launch(tpos)
			else:
				velocity.x = _jump_vx
				if is_on_floor() and _air_time == 0.0 and velocity.y >= 0.0:
					_jumping = false
					if feet == cell:
						_advance()
					else:
						_path.clear()  # missed the landing: plan again from here
		_:
			if _climbing and kind == LevelNav.Edge.WALK:
				_stop_climb()
			if kind == LevelNav.Edge.DROP and is_on_floor() and feet.y < cell.y and _drop_timer <= 0.0:
				set_collision_mask_value(PLATFORM_LAYER, false)
				_drop_timer = 0.3
				global_position.y += 1.0
			var dx := tpos.x - global_position.x
			var next_kind: int = _path[_path_i + 1]["kind"] if _path_i + 1 < _path.size() else -1
			if feet == cell and (is_on_floor() or _climbing):
				if next_kind == LevelNav.Edge.WALK or absf(dx) < 3.0:
					_advance()
			if absf(dx) > 1.0:
				velocity.x = clampf(dx * 10.0, -speed, speed)
			else:
				velocity.x = 0.0
	return Move.MOVING if _path_i < _path.size() else Move.ARRIVED


## Jump to `tpos` (feet position): enough height for one cell above the higher
## end, horizontal speed to land there.
func _launch(tpos: Vector2) -> void:
	var rise := global_position.y - tpos.y  # > 0: target is higher
	var h := maxf(rise, 0.0) + 14.0
	var v := sqrt(2.0 * GRAVITY * h)
	var t := v / GRAVITY + sqrt(2.0 * maxf(h - rise, 1.0) / GRAVITY)
	_jump_vx = clampf((tpos.x - global_position.x) / t, -260.0, 260.0)
	velocity = Vector2(_jump_vx, -v)
	_jumping = true
	_air_time = 0.0


func _advance() -> void:
	if _path_i < _path.size():
		_last_step = "%s→%s" % [LevelNav.EDGE_NAMES[_path[_path_i]["kind"]] if _path[_path_i]["kind"] >= 0 else "fly", _path[_path_i]["cell"]]
	_path_i += 1


func _start_climb() -> void:
	if _climbing:
		return
	_climbing = true
	set_collision_mask_value(PLATFORM_LAYER, false)


func _stop_climb() -> void:
	if not _climbing:
		return
	_climbing = false
	_drop_timer = 0.15  # the platform mask comes back after leaving the shaft


## Ends climbing standing ON the one-way ladder top: unlike `_stop_climb`, the
## platform mask returns immediately — with the usual grace period gravity
## drops the body back into the shaft before it can walk off the hole.
func _stop_climb_on_platform() -> void:
	if not _climbing and get_collision_mask_value(PLATFORM_LAYER):
		return
	_climbing = false
	_drop_timer = 0.0
	set_collision_mask_value(PLATFORM_LAYER, true)


## Debug overlay: remaining path in world coordinates.
func debug_path_points() -> PackedVector2Array:
	var out := PackedVector2Array()
	var lvl := _level()
	if lvl == null:
		return out
	out.append(global_position)
	for i in range(_path_i, _path.size()):
		var c: Vector2i = _path[i]["cell"]
		out.append(lvl.cell_center(c) if data.behavior == EnemyData.Behavior.FLYER else lvl.cell_bottom(c) + Vector2(0, -2))
	return out


func _debug_step() -> String:
	if _path_i < _path.size():
		var st: Dictionary = _path[_path_i]
		return "%s→%s" % [LevelNav.EDGE_NAMES[st["kind"]] if st["kind"] >= 0 else "fly", st["cell"]]
	return "нет"


func state_name() -> String:
	return STATE_NAMES[state]


func debug_player() -> Player:
	return _player


func debug_sees_player() -> bool:
	return _sees_player


func debug_memory_pos() -> Vector2:
	return _last_seen if _memory > 0.0 or state == State.SEARCH else Vector2.INF


func debug_extra() -> String:
	var parts: Array[String] = []
	if _hold:
		parts.append("ждёт")
	if _flank != 0.0:
		parts.append("фланг")
	if _stuck_level > 0:
		parts.append("застрял %d" % _stuck_level)
	return " ".join(parts)


# -------------------------------------------------------------- anti-stuck
## No progress for STUCK_CHECK seconds while trying to move: 1) plan a new
## path, 2) jump / turn around, 3) teleport to the nearest safe node.
func _check_stuck(delta: float) -> void:
	if not _wants_move or state in [State.ATTACK, State.HURT, State.ALERT]:
		_stuck_timer = 0.0
		_still_time = 0.0
		_stuck_anchor = global_position
		return
	if global_position.distance_to(_stuck_anchor) > STUCK_DIST:
		_stuck_anchor = global_position
		_stuck_timer = 0.0
		_still_time = 0.0
		# Escalation resets only after really getting away (a maneuver's own
		# hop must not start the chain over).
		if _stuck_level > 0 and global_position.distance_to(_stuck_origin) > DungeonLevel.TILE * 2.0:
			_stuck_level = 0
		return
	_stuck_timer += delta
	_still_time += delta
	max_still_time = maxf(max_still_time, _still_time)
	if _stuck_timer >= STUCK_CHECK:
		_stuck_timer = 0.0
		if _stuck_level == 0:
			_stuck_origin = global_position
		_stuck_level += 1
		_unstick()


func _unstick() -> void:
	var lvl := _level()
	match _stuck_level:
		1:
			_path.clear()
			_path_goal = Vector2i(-9999, -9999)
			AIDebug.log_event(self, "repath", "%s: нет движения, новый путь (%s, клетка %s, шаг %s, pos %s, last %s, sees %s)" % [data.id, state_name(), _feet_cell(), _debug_step(), global_position, _last_seen, _sees_player])
		2:
			dir = -dir
			_jumping = false
			if data.behavior == EnemyData.Behavior.FLYER:
				velocity = Vector2.from_angle(randf() * TAU) * data.speed
			elif is_on_floor() or _climbing:
				_stop_climb()
				velocity = Vector2(dir * data.speed, -260.0)
			_path.clear()
			AIDebug.log_event(self, "maneuver", "%s: прыжок и разворот (%s, клетка %s, шаг %s)" % [data.id, state_name(), _feet_cell(), _debug_step()])
		_:
			_stuck_level = 0
			_path.clear()
			if lvl == null or lvl.nav == null:
				return
			var here := _feet_cell()
			var target := Vector2i(-1, -1)
			if data.behavior == EnemyData.Behavior.FLYER:
				target = _free_fly_cell(lvl, lvl.world_to_cell(global_position + Vector2(0, -6)))
			else:
				target = lvl.nav.safe_cell_near(here, _clearance, here)
			if target.x < 0:
				return
			_stop_climb()
			_jumping = false
			velocity = Vector2.ZERO
			global_position = lvl.cell_bottom(target) + (Vector2(0, -4) if data.behavior == EnemyData.Behavior.FLYER else Vector2.ZERO)
			_stuck_anchor = global_position
			Fx.sparks(get_parent(), global_position + Vector2(0, -6), Color(0.7, 0.6, 1.0), 8, 40.0)
			AIDebug.log_event(self, "teleport", "%s: телепорт %s → %s (pos %s, level %s)" % [data.id, here, target, global_position, lvl.global_position])


func _free_fly_cell(lvl: DungeonLevel, from: Vector2i) -> Vector2i:
	for r in range(1, 5):
		for y in range(from.y - r, from.y + r + 1):
			for x in range(from.x - r, from.x + r + 1):
				var c := Vector2i(x, y)
				if lvl.nav.passable(x, y) and lvl.nav.passable(x, y - 1) and not lvl.nav.is_dangerous(c):
					return c
	return Vector2i(-1, -1)


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
				_set_state(State.CHASE)
				_recoil = 0.4  # back off upwards before the next dive
		State.PATROL:
			_patrol_fly(delta)
		State.ALERT:
			velocity = velocity.move_toward(Vector2.ZERO, 300.0 * delta)
			_face_point(_player.global_position if _player else global_position)
		State.CHASE:
			if _player == null:
				_set_state(State.SEARCH)
				return
			if _recoil > 0.0:
				_retreat(delta)
			elif _sees_player and _distance_to_player() <= data.attack_range + 8.0 and _attack_timer <= 0.0 \
					and has_line_to(_player.global_position + Vector2(0, -10)):
				_begin_attack()
			else:
				var target := (_player.global_position if _sees_player else _last_seen) + Vector2(_flank * 20.0, -12.0)
				_fly_to(target, data.chase_speed, delta)
			velocity.y += sin(_float_t * 6.0) * 20.0 * delta * 10.0
		State.SEARCH:
			_search_fly(delta)
		State.RETURN:
			if _fly_to(_home, data.speed, delta) != Move.MOVING:
				_set_state(State.PATROL)
		State.ATTACK:
			velocity = velocity.move_toward(Vector2.ZERO, 200.0 * delta)
			_update_attack(delta)
	if state not in [State.ATTACK, State.HURT]:
		velocity += _sep * 20.0 * delta * 10.0


## Flyers drift between free spots in view of their home.
func _patrol_fly(delta: float) -> void:
	_patrol_idle -= delta
	_patrol_check -= delta
	var d := global_position.distance_to(_patrol_point) if _patrol_point != Vector2.INF else 0.0
	# Not getting closer (walls, other monsters)? Simply choose another spot.
	var blocked := _patrol_check <= 0.0 and d > _patrol_dist - 4.0
	if _patrol_check <= 0.0:
		_patrol_check = 0.8
		_patrol_dist = d
	if _patrol_point == Vector2.INF or _patrol_idle <= 0.0 or d < 6.0 or blocked:
		_patrol_idle = randf_range(2.0, 3.5)
		_patrol_point = _pick_patrol_point()
		_patrol_check = 0.8
		_patrol_dist = global_position.distance_to(_patrol_point) if _patrol_point != Vector2.INF else 0.0
		_stuck_timer = 0.0
	if _patrol_point == Vector2.INF:
		velocity = velocity.move_toward(Vector2(0, sin(_float_t * 2.0) * 8.0), 200.0 * delta)
		return
	_steer(_patrol_point, data.speed, delta)


func _pick_patrol_point() -> Vector2:
	var lvl := _level()
	if lvl == null or lvl.nav == null:
		return Vector2.INF
	var home := lvl.world_to_cell(_home + Vector2(0, -6))
	for i in 8:
		var c := home + Vector2i(randi_range(-4, 4), randi_range(-2, 2))
		if not lvl.nav.passable(c.x, c.y) or not lvl.nav.passable(c.x, c.y - 1) or lvl.nav.is_dangerous(c):
			continue
		var p := lvl.cell_center(c) + Vector2(0, 4)
		if has_line_to(p) and p.distance_to(global_position) > 10.0:
			return p
	return Vector2.INF


func _search_fly(delta: float) -> void:
	if _last_seen == Vector2.INF:
		_set_state(State.RETURN)
		return
	if _state_time < 8.0 and global_position.distance_to(_last_seen) > 14.0 and _fly_to(_last_seen, data.speed, delta) == Move.MOVING:
		return
	velocity = velocity.move_toward(Vector2.ZERO, 200.0 * delta)
	if _search_done() or _state_time > 9.0:
		_last_seen = Vector2.INF
		_set_state(State.RETURN)


## Grid path for flyers; straight flight when the target is in plain view.
func _fly_to(target: Vector2, speed: float, delta: float) -> Move:
	if not target.is_finite():
		return Move.NO_PATH
	# Points on the floor line cannot be reached by wings: aim a bit above.
	var lvl0 := _level()
	if lvl0 and lvl0.is_solid_at(target + Vector2(0, 2)):
		target.y -= 10.0
	if global_position.distance_to(target) < 12.0:
		return Move.ARRIVED
	if data.phases_through_walls or _wide_clear(target):
		_steer(target, speed, delta)
		return Move.MOVING
	var lvl := _level()
	if lvl == null or lvl.nav == null:
		_steer(target, speed, delta)
		return Move.MOVING
	# Feet positions lie on the floor line: aim a bit higher, at a free cell.
	var goal := lvl.world_to_cell(target + Vector2(0, -6))
	if not lvl.nav.passable(goal.x, goal.y) and lvl.nav.passable(goal.x, goal.y - 1):
		goal.y -= 1
	if _nav_changed(lvl) or goal != _path_goal or _repath_timer <= 0.0:
		_compute_path(lvl, goal)
	if _path.is_empty():
		velocity = velocity.move_toward(Vector2.ZERO, 300.0 * delta)
		return Move.NO_PATH
	return _follow_fly(lvl, speed, delta)


## Straight flight only through a corridor as wide as the body (two parallel
## rays): a thin line of sight past a corner is not enough for wings.
func _wide_clear(target: Vector2) -> bool:
	var from := global_position + Vector2(0, -data.collision_size.y * 0.5)
	var d := target - from
	if d.length() < 1.0:
		return true
	var side := d.normalized().orthogonal() * (data.collision_size.x * 0.5 + 1.0)
	return LineOfSight.clear(self, from + side, target + side) and LineOfSight.clear(self, from - side, target - side)


func _follow_fly(lvl: DungeonLevel, speed: float, delta: float) -> Move:
	while _path_i < _path.size() and lvl.cell_center(_path[_path_i]["cell"]).distance_to(global_position + Vector2(0, -6)) < 6.0:
		_path_i += 1
	if _path_i >= _path.size():
		return Move.ARRIVED
	# The grid path already keeps off the walls: no whiskers in tight shafts.
	_steer(lvl.cell_center(_path[_path_i]["cell"]) + Vector2(0, 6), speed, delta, false)
	return Move.MOVING


## Seek `target`, pushed away from walls by three short ray "whiskers".
func _steer(target: Vector2, speed: float, delta: float, whiskers := true) -> void:
	if not target.is_finite():
		return
	_wants_move = true
	var desired := (target - global_position)
	if desired.length() < 1.0:
		velocity = velocity.move_toward(Vector2.ZERO, 300.0 * delta)
		return
	desired = desired.normalized() * speed
	if whiskers and not data.phases_through_walls:
		var space := get_world_2d().direct_space_state
		var origin := global_position + Vector2(0, -data.collision_size.y / 2.0)
		var heading := desired.normalized()
		var avoid := Vector2.ZERO
		for ang in [0.0, 0.7, -0.7]:
			var ray := heading.rotated(ang) * (data.collision_size.x * 0.5 + 10.0)
			var q := PhysicsRayQueryParameters2D.create(origin, origin + ray, WORLD_MASK)
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				avoid += hit["normal"] * (1.4 if ang == 0.0 else 1.0)
		if avoid != Vector2.ZERO:
			desired = (desired.normalized() + avoid.normalized() * 1.2).normalized() * speed
	velocity = velocity.move_toward(desired, 500.0 * delta)


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
		elif has_line_to(_player.global_position + Vector2(0, -10)):
			_shoot()  # no shots into walls: the hero must be in plain view
		_summon_next = not _summon_next
		return
	if data.behavior == EnemyData.Behavior.FLYER:
		velocity = (_player.global_position + Vector2(0, -10) - global_position).normalized() * data.chase_speed * 2.2
	elif data.behavior == EnemyData.Behavior.WALKER:
		velocity.x = dir * data.chase_speed * 1.8  # lunge
	# Never through a wall: the hit needs a clear line to the hero.
	var clear := data.phases_through_walls or has_line_to(_player.global_position + Vector2(0, -8))
	if data.aoe_radius > 0.0:
		# Ground slam: hurts everything around, telegraphed by the wind-up.
		EventBus.screen_shake.emit(4.0)
		EventBus.noise.emit(global_position, 200.0)
		Fx.dust(get_parent(), global_position, true)
		Fx.explosion(get_parent(), global_position + Vector2(0, -4), data.aoe_radius, Color(0.8, 0.75, 0.65))
		if clear and _player.global_position.distance_to(global_position) <= data.aoe_radius:
			_player.take_damage(damage, global_position)
			_apply_hit_effects(_player, damage)
	elif clear and _distance_to_player() <= data.attack_range + 14.0:
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
	_summons.assign(_summons.filter(func(n) -> bool: return is_instance_valid(n) and not n.is_dead()))
	return _summons.size()


func _raise_summons() -> void:
	var level := _level()
	if level == null:
		return
	for i in mini(2, data.max_summons - _alive_summons()):
		var e: Enemy = (load("res://scenes/enemies/enemy.tscn") as PackedScene).instantiate()
		e.setup(data.summon, floor_number)
		# Summons spawn mid-fight: same authoritative id/descriptor path as
		# floor mobs and ambush monsters, or guests never see them.
		level._net_tag(e)
		level.add_entity(e, global_position + Vector2((i * 2 - 1) * 16.0, -4.0))
		level._net_broadcast_enemy(e, null, false)
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
	# Co-op: enemy shots exist only where they are simulated; guests get a
	# visual copy (the damage itself reaches them through player_damage).
	if Net.active and Net.is_host:
		var ns = get_tree().get_first_node_in_group("net_game")
		if ns and data.projectile_texture:
			ns.enemy_projectile.rpc(data.projectile_texture.resource_path, from, dir_v,
					data.projectile_speed, 2.5)


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
	if puppet:
		# Clients never apply damage: the host is the judge.
		var ns := get_tree().get_first_node_in_group("net_game") as NetSync
		if ns:
			ns.request_hit(self, amount, crit, damage_type, from_pos)
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
	_dormant = false
	hp_bar.visible = true
	hp_bar.max_value = max_hp
	hp_bar.value = hp
	var top := global_position + Vector2(0, -data.collision_size.y - 4)
	EventBus.damage_dealt.emit(top, dealt, crit, false)
	# Co-op: only the host rolls enemy damage — echo the number to clients.
	if Net.active and Net.is_host:
		var ns := get_tree().get_first_node_in_group("net_game") as NetSync
		if ns:
			ns.damage_number.rpc(top, dealt, crit)
	EventBus.noise.emit(global_position, 150.0)
	if from_pos != Vector2.INF and state in [State.PATROL, State.RETURN, State.SEARCH]:
		_last_seen = from_pos
		_memory = MEMORY_TIME
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
	var spot := global_position + Vector2(randf_range(-4, 4), -data.collision_size.y - 2)
	EventBus.floating_text.emit(spot, str(amount), color)
	if Net.active and Net.is_host:
		var ns := get_tree().get_first_node_in_group("net_game") as NetSync
		if ns:
			ns.enemy_float_text.rpc(spot, str(amount), color)
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


## Client shell: host says where I am and how hurt.
func net_apply_state(x: float, y: float, new_hp: int, dead: bool, ai_state: int = -1,
		attack_left: float = 0.0) -> void:
	_net_target = Vector2(x, y)
	if dead and not _dead:
		net_die()
		return
	hp = new_hp
	if hp_bar.visible or hp < max_hp:
		hp_bar.visible = true
		hp_bar.max_value = max_hp
		hp_bar.value = hp
	if ai_state >= 0:
		# Host ATTACK (telegraphed) and the 0.25s attack strike are both shown
		# locally through _attack_anim_left - refresh the puppet's timers.
		if ai_state == State.ATTACK and state != State.ATTACK:
			_set_flash(0.35, Color(1.0, 0.2, 0.1))
		elif ai_state != State.ATTACK and state == State.ATTACK:
			_set_flash(0.0)
			_attack_anim_left = maxf(_attack_anim_left, 0.25)
		elif attack_left > 0.0:
			_attack_anim_left = maxf(_attack_anim_left, attack_left)
		state = ai_state


## Client shell: the host says this enemy died — visuals only.
func net_die() -> void:
	if _dead:
		return
	_dead = true
	AudioManager.play_sfx(data.sound_death, global_position)
	set_physics_process(false)
	remove_from_group("enemies")
	shape.set_deferred("disabled", true)
	hp_bar.visible = false
	sprite.play(&"death")
	var parent := get_parent()
	var pos := global_position + Vector2(0, -6)
	var color := data.tint.darkened(0.2)
	sprite.animation_finished.connect(func() -> void:
		Fx.sparks(parent, pos, color, 14, 100.0)
		queue_free(), CONNECT_ONE_SHOT)


func _die() -> void:
	_dead = true
	AudioManager.play_sfx(data.sound_death, global_position)
	set_physics_process(false)
	status.clear()
	status.set_physics_process(false)
	remove_from_group("enemies")
	shape.set_deferred("disabled", true)
	hp_bar.visible = false
	if _mark:
		_mark.visible = false
	if _name_label:
		_name_label.visible = false
	if not data.no_rewards:
		_give_rewards()
	# Death animation, then the body breaks into particles.
	sprite.play(&"death")
	var parent := get_parent()
	var pos := global_position + Vector2(0, -6)
	var color := data.tint.darkened(0.2)
	sprite.animation_finished.connect(func() -> void:
		Fx.sparks(parent, pos, color, 14, 100.0)
		queue_free(), CONNECT_ONE_SHOT)


## XP, gold, loot and kill events (not for illusions and other fakes).
## Co-op: the host keeps the world (loot drops there and is replicated),
## the killer gets the xp/gold through the net, everyone counts the kill.
func _give_rewards() -> void:
	var xp := roundi((data.xp_reward + floor_number - 1) * (elite.xp_mult if elite else 1.0) * maxf(0.0, 1.0 + GameState.run_effect("xp") + GameState.combo_bonus()))
	var gold_find := GameState.hero.stats.get_value(StatTypes.GOLD_FIND) if GameState.hero else 0.0
	var gold := roundi(randi_range(data.gold_min, data.gold_max) * (1.0 + 0.10 * (floor_number - 1)) * (elite.gold_mult if elite else 1.0) * (1.0 + gold_find) * maxf(0.0, 1.0 + GameState.run_effect("gold") + GameState.combo_bonus()))
	if Net.active:
		var ns := get_tree().get_first_node_in_group("net_game") as NetSync
		if ns:
			ns.broadcast_death(self, xp, gold)
		if elite:
			EventBus.elite_killed.emit(data)
	else:
		EventBus.enemy_killed.emit(data, global_position)
		if GameState.hero:
			GameState.hero.add_xp(xp)
		EventBus.floating_text.emit(global_position + Vector2(0, -data.collision_size.y - 12), "+%d XP" % xp, Color(1.0, 0.85, 0.3))
		if elite:
			EventBus.elite_killed.emit(data)
	if gold > 0:
		var coin := ItemDatabase.get_item(&"gold_coin")
		if coin:
			EventBus.spawn_items.emit(global_position + Vector2(0, -8), [{"item": coin, "count": gold}])
	if elite and elite.shard_drop > 0:
		var shard := ItemDatabase.get_item(MetaProgress.SHARD_ITEM)
		if shard:
			EventBus.spawn_items.emit(global_position + Vector2(0, -8), [{"item": shard, "count": elite.shard_drop}])
	var table: LootTable = ItemDatabase.get_loot_table(ELITE_LOOT_TABLE) if elite else data.loot_table
	if table and (elite != null or randf() < data.loot_chance):
		var loot := table.roll(floor_number)
		if not loot.is_empty():
			EventBus.spawn_items.emit(global_position + Vector2(0, -8), loot)
