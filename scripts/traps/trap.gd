class_name Trap
extends Area2D
## Generic trap driven by TrapData. Avoid it, or press E nearby to try to
## disarm it (chance depends on difficulty and Agility; failure sets it off).
##  SPIKES:         rise shortly after something steps on them, hurt while up.
##  FALLING_ROCK:   hangs on the ceiling, cracks and drops when the hero passes.
##  ARROW_WALL:     shoots arrows along its row when the hero is in line.
##  ACID_POOL:      hurts and poisons whatever stands in it (cannot be disarmed).
##  PRESSURE_PLATE: fires the linked arrow wall, or drops rocks on the hero.

const K = TrapData.Kind
const PROJECTILE_SCENE := preload("res://scenes/world/projectile.tscn")
const ROCK_GRAVITY := 700.0

var data: TrapData
var floor_number: int = 1
## ARROW_WALL: 1 = shoots right, -1 = shoots left.
var facing: float = 1.0
## PRESSURE_PLATE: the arrow wall it fires (optional).
var linked: Trap
var disarmed := false
## LAN co-op: deterministic trap identity (disarm requests and echo).
var net_seq := 0

var _cooldown := 0.0
var _phase := ""
var _phase_time := 0.0
var _rock: Sprite2D
var _rock_speed := 0.0
var _hit_this_cycle: Array[Node] = []

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var shape: CollisionShape2D = $CollisionShape2D


func setup(p_data: TrapData, p_floor: int) -> void:
	data = p_data
	floor_number = p_floor


func _ready() -> void:
	add_to_group("traps")
	if data.can_disarm:
		add_to_group("interactable")
	sprite.modulate = data.tint
	if data.sheet and data.sheet_layout:
		data.sheet_layout.apply_to(sprite, data.sheet)
	var rect := RectangleShape2D.new()
	match data.kind:
		K.SPIKES:
			rect.size = Vector2(14, 8)
			shape.position = Vector2(0, -4)
			_play(&"hidden")
		K.ACID_POOL:
			rect.size = Vector2(14, 6)
			shape.position = Vector2(0, -3)
			_play(&"bubble")
		K.PRESSURE_PLATE:
			rect.size = Vector2(12, 4)
			shape.position = Vector2(0, -2)
			_play(&"up")
		K.ARROW_WALL:
			rect.size = Vector2(14, 14)
			shape.position = Vector2(0, -8)
			sprite.flip_h = facing < 0.0
			_play(&"idle")
		K.FALLING_ROCK:
			# Hangs from the ceiling: origin is the ceiling line.
			rect.size = Vector2(12, 12)
			shape.position = Vector2(0, 8)
			sprite.visible = false
			var crack := Sprite2D.new()
			crack.texture = AssetPaths.tex(AssetPaths.TRAP_CRACK)
			crack.position = Vector2(0, 2)
			add_child(crack)
			_rock = Sprite2D.new()
			_rock.texture = data.texture
			_rock.position = Vector2(0, 8)
			add_child(_rock)
	shape.shape = rect
	_cooldown = randf_range(0.0, 1.0)


func _play(anim: StringName) -> void:
	if sprite.sprite_frames and sprite.sprite_frames.has_animation(anim):
		sprite.play(anim)


func _player() -> Player:
	# Traps are local per machine: aim them at the real hero, never at puppets.
	for n in get_tree().get_nodes_in_group("player"):
		var p := n as Player
		if p != null and not p.puppet:
			return p
	return null


func _physics_process(delta: float) -> void:
	if disarmed:
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	match data.kind:
		K.SPIKES:
			_spikes(delta)
		K.ACID_POOL:
			_acid()
		K.PRESSURE_PLATE:
			_plate()
		K.ARROW_WALL:
			_arrow_wall()
		K.FALLING_ROCK:
			_falling_rock(delta)


# ------------------------------------------------------------------ spikes
func _spikes(delta: float) -> void:
	_phase_time -= delta
	match _phase:
		"":
			if _cooldown <= 0.0 and _victims().size() > 0:
				_phase = "warn"
				_phase_time = 0.3
				_shake()
		"warn":
			if _phase_time <= 0.0:
				_phase = "up"
				_phase_time = 0.8
				_hit_this_cycle.clear()
				_play(&"rise")
				sprite.animation_finished.connect(func() -> void: _play(&"up"), CONNECT_ONE_SHOT)
				AudioManager.play_sfx(&"dig", global_position, -6.0)
		"up":
			for v in _victims():
				if v not in _hit_this_cycle:
					_hit_this_cycle.append(v)
					_hurt(v)
			if _phase_time <= 0.0:
				_phase = ""
				_cooldown = data.cooldown
				_play(&"retract")
				sprite.animation_finished.connect(func() -> void: _play(&"hidden"), CONNECT_ONE_SHOT)


func _victims() -> Array[Node]:
	var out: Array[Node] = []
	for b in get_overlapping_bodies():
		# Monsters know their dungeon: traps never hurt them (see README).
		if b.is_in_group("player") and not b.dead:
			out.append(b)
	return out


# -------------------------------------------------------------------- acid
func _acid() -> void:
	if _cooldown > 0.0:
		return
	var hit := false
	for v in _victims():
		_hurt(v)
		hit = true
	if hit:
		_cooldown = 0.5


# ------------------------------------------------------------------ plates
func _plate() -> void:
	if _phase == "down":
		if _victims().is_empty():
			_phase = ""
			_play(&"up")
		return
	if _victims().any(func(v: Node) -> bool: return v.is_in_group("player")):
		_phase = "down"
		_play(&"down")
		AudioManager.play_sfx(&"chest_locked", global_position, -4.0)
		if _cooldown <= 0.0:
			_cooldown = data.cooldown
			trigger()


## Sets the trap off (also called on a failed disarm).
func trigger() -> void:
	match data.kind:
		K.SPIKES:
			_phase = "warn"
			_phase_time = 0.05
		K.ARROW_WALL:
			_fire_arrow()
		K.FALLING_ROCK:
			if _phase == "":
				_phase = "crack"
				_phase_time = 0.15
		K.PRESSURE_PLATE:
			if linked and is_instance_valid(linked) and not linked.disarmed:
				linked.trigger()
			else:
				_rock_shower()


func _rock_shower() -> void:
	var p := _player()
	if p == null or p.level == null:
		return
	EventBus.message.emit("Сверху сыплются камни!")
	for i in 3:
		var rock := RockProjectile.new()
		rock.texture = AssetPaths.tex(AssetPaths.TRAP_ROCK)
		rock.damage = data.damage_for_floor(floor_number)
		rock.velocity = Vector2(randf_range(-20, 20), 0)
		p.level.add_entity(rock, p.global_position + Vector2(randf_range(-30, 30), -90 - i * 20))


# --------------------------------------------------------------- arrow wall
func _arrow_wall() -> void:
	if _cooldown > 0.0:
		return
	var p := _player()
	if p == null or p.dead:
		return
	var rel := p.global_position - global_position
	if absf(rel.y) < 18.0 and signf(rel.x) == facing and absf(rel.x) <= data.trigger_range:
		_fire_arrow()


func _fire_arrow() -> void:
	_cooldown = data.cooldown
	_play(&"fire")
	var level := get_parent().get_parent() as DungeonLevel
	if level == null:
		return
	var p: Projectile = PROJECTILE_SCENE.instantiate()
	p.setup(data.projectile_texture, Vector2(facing, 0), data.projectile_speed, data.damage_for_floor(floor_number), "player")
	p.damage_type = data.damage_type
	p.blast_color = data.tint
	p.local_damage_only = true
	p.lifetime = data.trigger_range / data.projectile_speed + 0.6
	p.on_hit = func(target: Node, dmg: int) -> void: _apply_effects(target, dmg)
	level.add_entity(p, global_position + Vector2(facing * 9.0, -8.0))
	AudioManager.play_sfx(&"attack_bow", global_position, -3.0)


# ------------------------------------------------------------- falling rock
func _falling_rock(delta: float) -> void:
	match _phase:
		"":
			if _cooldown > 0.0:
				return
			var p := _player()
			if p and not p.dead:
				var rel := p.global_position - global_position
				if absf(rel.x) < data.trigger_range * 0.25 and rel.y > 0.0 and rel.y < data.trigger_range * 3.0:
					_phase = "crack"
					_phase_time = 0.45
		"crack":
			_phase_time -= delta
			_rock.position.x = sin(_phase_time * 80.0) * 1.5
			if _phase_time <= 0.0:
				_phase = "fall"
				_rock_speed = 0.0
				_hit_this_cycle.clear()
				AudioManager.play_sfx(&"dig", global_position, -6.0)
		"fall":
			_rock_speed = minf(_rock_speed + ROCK_GRAVITY * delta, 500.0)
			_rock.position.y += _rock_speed * delta
			shape.position.y = _rock.position.y
			for v in _victims():
				if v not in _hit_this_cycle:
					_hit_this_cycle.append(v)
					_hurt(v)
			var level := get_parent().get_parent() as DungeonLevel
			if level == null or level.is_ground_at(global_position + Vector2(0, _rock.position.y + 7.0)) or _rock.position.y > 400.0:
				Fx.shards(get_parent(), global_position + Vector2(0, _rock.position.y), Color(0.5, 0.45, 0.42), 10)
				EventBus.screen_shake.emit(2.0)
				_rock.visible = false
				_phase = "gone"
				_phase_time = data.cooldown
		"gone":
			_phase_time -= delta
			if _phase_time <= 0.0:
				_rock.position = Vector2(0, 8)
				shape.position.y = 8
				_rock.visible = true
				_phase = ""


# -------------------------------------------------------------------- hits
func _hurt(victim: Node) -> void:
	if victim.puppet:
		return  # every machine runs this trap; the authority applies its own
	var dmg := data.damage_for_floor(floor_number)
	if victim.is_in_group("player"):
		victim.take_damage(dmg, global_position, data.damage_type)
	else:
		victim.take_damage(dmg, false, global_position, data.damage_type)
	_apply_effects(victim, dmg)


func _apply_effects(target: Node, dmg: int) -> void:
	if not is_instance_valid(target):
		return
	for e in data.hit_effects:
		if e:
			e.try_apply(self, target, dmg)


func _shake() -> void:
	var tw := create_tween()
	for i in 3:
		tw.tween_property(sprite, "position:x", 1.0, 0.04)
		tw.tween_property(sprite, "position:x", -1.0, 0.04)
	tw.tween_property(sprite, "position:x", 0.0, 0.04)


# --------------------------------------------------------------- disarming
func can_interact() -> bool:
	return not disarmed and data.can_disarm


func disarm_chance(hero: Hero) -> float:
	return clampf(1.0 - data.disarm_difficulty + hero.stats.get_value(StatTypes.AGILITY) * 0.02, 0.1, 0.95)


func get_prompt() -> String:
	var p := _player()
	var chance := disarm_chance(p.hero) if p else 0.5
	return "Обезвредить: %s (%d%%)" % [data.display_name, roundi(chance * 100.0)]


func interact(player: Node) -> void:
	if disarmed:
		return
	if Net.active and not Net.is_host:
		# The attempt is rolled with the disarmer's own hero; the shared
		# "disarmed" verdict comes back from the host.
		if randf() <= disarm_chance(player.hero):
			var ns = get_tree().get_first_node_in_group("net_game")
			if ns:
				ns.request_trap_disarm.rpc_id(1, net_seq)
		else:
			# A failed attempt springs the trap: the host's copy decides.
			var ns2 = get_tree().get_first_node_in_group("net_game")
			if ns2:
				ns2.request_trap_spring.rpc_id(1, net_seq)
			EventBus.message.emit("Не вышло! Ловушка сработала")
		return
	if randf() <= disarm_chance(player.hero):
		_apply_disarmed()
		player.hero.add_xp(data.xp_for_disarm)
		_net_disarm_broadcast()
	else:
		EventBus.message.emit("Не вышло! Ловушка сработала")
		trigger()


func _apply_disarmed() -> void:
	disarmed = true
	modulate = Color(0.5, 0.5, 0.5, 0.8)
	remove_from_group("interactable")
	if _rock:
		_rock.visible = false
	EventBus.message.emit("Ловушка обезврежена")
	EventBus.trap_disarmed.emit(data)
	AudioManager.play_sfx(&"ui_equip", global_position)


func _net_disarm_broadcast() -> void:
	if Net.active and Net.is_host:
		var ns = get_tree().get_first_node_in_group("net_game")
		if ns:
			ns.trap_disarmed_net.rpc(net_seq)
		trigger()
