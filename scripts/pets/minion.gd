class_name Minion
extends CharacterBody2D
## A raised undead servant of the necromancer: walks with the hero, attacks
## monsters it can see, crumbles to dust when its time runs out. Monsters do
## not target minions (they are invulnerable); the limit is the lifetime and
## the number the caster may keep (SummonSkill).
##   WARRIOR - melee skeleton, ARCHER - shoots bone arrows, GOLEM - slams an area.
##
## Co-op: the caster's machine runs the servant (AI, damage); every other
## machine gets a `remote` copy through NetSync (spawn / position / attacks /
## crumble) that only shows it.

enum Kind { WARRIOR, ARCHER, GOLEM }

const GRAVITY := 900.0
const SIGHT := 210.0
const LEASH := 320.0  # further from the hero than this: rise again next to him
const GUARD := 260.0  # targets further than this from the hero are left alone
const JUMP_SPEED := 300.0

var kind: Kind = Kind.WARRIOR
var owner_player: Player
var damage_mult := 0.6
var life := 20.0
var speed := 105.0
## A copy shown on another machine: no AI, no damage.
var remote := false
var net_uid := 0
var _cooldown := 0.6
var _target: Enemy
var _scan := 0.0
var _slot := 0  # place in the column behind the hero
var _attack_anim := 0.0
var _stuck := 0.0
var _last_x := 0.0
var _drop := 0.0  # falling through a one-way platform
var _net_timer := 0.0
var _net_target := Vector2.ZERO
var _net_flip := false
var _data: EnemyData

@onready var sprite: AnimatedSprite2D = AnimatedSprite2D.new()

static var _next_uid := 1


static func spawn(p_owner: Player, p_kind: Kind, mult: float, lifetime: float, slot: int, pos: Vector2) -> Minion:
	var m := Minion.new()
	m.owner_player = p_owner
	m.kind = p_kind
	m.damage_mult = mult
	m.life = lifetime
	m._slot = slot
	_container(p_owner).add_child(m)
	m.global_position = pos
	return m


## Servants live among the level's entities (never in the co-op player
## container, which must hold heroes only).
static func _container(p_owner: Player) -> Node:
	if p_owner.level and is_instance_valid(p_owner.level):
		return p_owner.level.entities
	return p_owner.get_parent()


## Another machine's servant: a visual copy that follows the owner's reports.
static func spawn_remote(p_owner: Player, uid: int, p_kind: Kind, pos: Vector2, parent: Node) -> Minion:
	var m := Minion.new()
	m.owner_player = p_owner
	m.kind = p_kind
	m.remote = true
	m.net_uid = uid
	m._net_target = pos
	parent.add_child(m)
	m.global_position = pos
	return m


func _ready() -> void:
	add_to_group("minions")
	z_index = 1
	collision_layer = 0
	collision_mask = 1 | 2  # world and one-way platforms
	_data = ItemDatabase.enemy_by_id(&"golem" if kind == Kind.GOLEM else &"skeleton")
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(10, 18) if kind != Kind.GOLEM else Vector2(16, 24)
	shape.shape = rect
	shape.position = Vector2(0, -rect.size.y / 2.0)
	add_child(shape)
	add_child(sprite)
	if _data and _data.sheet_layout:
		_data.sheet_layout.apply_to(sprite, _data.sheet)
	# Ghostly green bone: clearly on the hero's side.
	sprite.modulate = Color(0.7, 1.0, 0.75) if kind != Kind.ARCHER else Color(0.75, 0.9, 1.0)
	if kind == Kind.GOLEM:
		scale = Vector2(0.85, 0.85)
	var light := PointLight2D.new()
	light.texture = AssetPaths.tex(AssetPaths.LIGHT)
	light.color = Color(0.4, 1.0, 0.55)
	light.texture_scale = 0.18
	light.energy = 0.6
	light.position = Vector2(0, -16)
	add_child(light)
	_play(&"idle")
	Fx.sparks(get_parent(), global_position + Vector2(0, -6), Color(0.45, 1.0, 0.55), 14, 70.0)
	Fx.dust(get_parent(), global_position, true)
	if remote:
		collision_mask = 0
		return
	var ns := _net()
	if ns:
		net_uid = Net.multiplayer.get_unique_id() * 100000 + _next_uid
		_next_uid += 1
		ns.minion_spawn.rpc(net_uid, kind, global_position)


func _exit_tree() -> void:
	if remote or net_uid == 0:
		return
	var ns := _net()
	if ns:
		ns.minion_gone.rpc(net_uid)


func _net() -> NetSync:
	if not Net.active or not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group("net_game") as NetSync


func _physics_process(delta: float) -> void:
	if owner_player == null or not is_instance_valid(owner_player):
		queue_free()
		return
	_attack_anim = maxf(0.0, _attack_anim - delta)
	if remote:
		_remote_step(delta)
		return
	life -= delta
	if life <= 0.0 or owner_player.dead:
		_crumble()
		return
	_cooldown -= delta
	_scan -= delta
	_drop = maxf(0.0, _drop - delta)
	set_collision_mask_value(2, _drop <= 0.0)
	if _target != null and (not is_instance_valid(_target) or _target.is_dead() or _too_far(_target)):
		_target = null
	if _scan <= 0.0:
		_scan = 0.25
		_pick_target()
	velocity.y = minf(velocity.y + GRAVITY * delta, 420.0)
	var goal: Vector2
	var hurry := 1.0
	if _target:
		var reach := _reach()
		var dx := _target.global_position.x - global_position.x
		var dy := _target.global_position.y - global_position.y
		# Archers keep their distance; melee walks right up to it.
		var keep := reach * 0.6 if kind == Kind.ARCHER else 0.0
		var gx := global_position.x if absf(dx) <= maxf(reach * 0.8, keep + 6.0) and absf(dx) >= keep else _target.global_position.x - signf(dx) * keep
		goal = Vector2(gx, _target.global_position.y)
		sprite.flip_h = dx < 0.0
		var dy_ok := absf(dy) < (60.0 if kind == Kind.ARCHER else 26.0)
		if absf(dx) <= reach and dy_ok and _cooldown <= 0.0 and _can_hit(_target):
			_attack()
	else:
		goal = owner_player.global_position - Vector2(owner_player.facing * (22.0 + _slot * 12.0), 0)
		# Left behind: run to catch up with the hero.
		if global_position.distance_to(owner_player.global_position) > 90.0:
			hurry = 1.6
	var to_x := goal.x - global_position.x
	var spd := speed * hurry
	velocity.x = clampf(to_x * 6.0, -spd, spd) if absf(to_x) > 3.0 else 0.0
	if absf(velocity.x) > 1.0 and _target == null:
		sprite.flip_h = velocity.x < 0.0
	if is_on_floor():
		var to_y := goal.y - global_position.y
		# A step or a wall in the way, or the goal stands on a ledge above
		# within reach: jump. The goal below on a platform: drop through.
		if (is_on_wall() and absf(velocity.x) > 1.0) or (to_y < -20.0 and absf(to_x) < 70.0):
			velocity.y = -JUMP_SPEED
		elif to_y > 20.0 and absf(to_x) < 40.0:
			_drop = 0.25
	move_and_slide()
	_check_stuck(delta)
	_animate()
	_net_timer -= delta
	if _net_timer <= 0.0:
		_net_timer = 0.1
		var ns := _net()
		if ns:
			ns.minion_state.rpc(net_uid, global_position, sprite.flip_h)


func _animate() -> void:
	if _attack_anim > 0.0:
		_play(&"attack")
	elif absf(velocity.x) > 8.0:
		_play(&"walk")
	else:
		_play(&"idle")


## Remote copy: glide to the reported spot, play what the movement shows.
func _remote_step(delta: float) -> void:
	var before := global_position
	if global_position.distance_to(_net_target) > 160.0:
		global_position = _net_target
	else:
		global_position = global_position.lerp(_net_target, minf(1.0, delta * 12.0))
	velocity = (global_position - before) / maxf(delta, 0.0001)
	sprite.flip_h = _net_flip
	_animate()


func net_state(pos: Vector2, flip: bool) -> void:
	_net_target = pos
	_net_flip = flip


## The owner's servant struck: the same swing / arrow / slam, no damage.
func net_attack(at: Vector2) -> void:
	_attack_anim = 0.35
	_net_flip = at.x < global_position.x
	_attack_fx(at, {"amount": 0, "crit": false}, false)


func _too_far(e: Enemy) -> bool:
	return e.global_position.distance_to(owner_player.global_position) > GUARD


func _reach() -> float:
	match kind:
		Kind.ARCHER:
			return 150.0
		Kind.GOLEM:
			return 26.0
	return 18.0


func _can_hit(e: Enemy) -> bool:
	if kind != Kind.ARCHER:
		return true
	return LineOfSight.clear(self, global_position + Vector2(0, -12), e.global_position + Vector2(0, -8))


## The best target: monsters fighting the hero come first, then the nearest
## one the servant can see; nothing too far from the hero (no wandering off).
func _pick_target() -> void:
	var best: Enemy = null
	var best_score := INF
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e == null or e.is_dead() or (e.data and e.data.training_dummy and not GameState.is_town()):
			continue
		var d := e.global_position.distance_to(global_position)
		if d > SIGHT or _too_far(e):
			continue
		if not LineOfSight.clear(self, global_position + Vector2(0, -10), e.global_position + Vector2(0, -8)):
			continue
		var score := d + absf(e.global_position.y - global_position.y) * 1.5
		score += e.global_position.distance_to(owner_player.global_position) * 0.5  # the hero's attackers first
		if e == _target:
			score -= 40.0  # stick to the current one: no dithering between two
		if score < best_score:
			best = e
			best_score = score
	_target = best


func _attack() -> void:
	_attack_anim = 0.35
	var d: Dictionary = owner_player.roll_damage(damage_mult)
	var at := _target.global_position
	_attack_fx(at, d, true)
	var ns := _net()
	if ns:
		ns.minion_attack.rpc(net_uid, at)


## `real`: the owner's servant (deals damage); remote copies only show it.
func _attack_fx(at: Vector2, d: Dictionary, real: bool) -> void:
	match kind:
		Kind.ARCHER:
			_cooldown = 1.2
			var from := global_position + Vector2(0, -12)
			var dir := (at + Vector2(0, -8) - from).normalized()
			var p: Projectile = (load("res://scenes/world/projectile.tscn") as PackedScene).instantiate()
			p.setup(AssetPaths.tex(AssetPaths.SPRITES_DIR + "fx/bone_shard.png"), dir, 240.0, d["amount"], "enemies" if real else "none")
			p.crit = d["crit"]
			get_parent().add_child(p)
			p.global_position = from
			AudioManager.play_sfx(&"enemy_shoot", global_position, -8.0)
		Kind.GOLEM:
			_cooldown = 1.5
			Fx.explosion(get_parent(), global_position + Vector2(0, -4), 34.0, Color(0.55, 1.0, 0.6))
			if real:
				for n in get_tree().get_nodes_in_group("enemies"):
					var e := n as Enemy
					if e and not e.is_dead() and e.global_position.distance_to(global_position) <= 40.0:
						e.take_damage(d["amount"], d["crit"], global_position, 0)
		_:
			_cooldown = 0.8
			var dir := Vector2(signf(at.x - global_position.x), 0)
			SlashTrail.spawn(get_parent(), global_position + Vector2(0, -10), dir if dir.x != 0.0 else Vector2.RIGHT,
					18.0, false, Color(0.6, 1.0, 0.65))
			if real and _target:
				_target.take_damage(d["amount"], d["crit"], global_position, 0)
			AudioManager.play_sfx(&"hit_flesh", global_position, -6.0)


## Stuck behind something or left far behind: rise again next to the hero.
func _check_stuck(delta: float) -> void:
	var far := global_position.distance_to(owner_player.global_position) > LEASH
	if absf(global_position.x - _last_x) < 0.5 and absf(velocity.x) > 10.0:
		_stuck += delta
	else:
		_stuck = 0.0
	_last_x = global_position.x
	if far or _stuck > 1.2:
		_stuck = 0.0
		_target = null
		Fx.dust(get_parent(), global_position, false)
		global_position = owner_player.global_position + Vector2(-owner_player.facing * (16.0 + _slot * 10.0), 0)
		velocity = Vector2.ZERO
		Fx.sparks(get_parent(), global_position + Vector2(0, -6), Color(0.45, 1.0, 0.55), 8, 50.0)


func _crumble() -> void:
	Fx.shards(get_parent(), global_position + Vector2(0, -10), Color(0.85, 0.9, 0.8), 10)
	Fx.sparks(get_parent(), global_position + Vector2(0, -10), Color(0.45, 1.0, 0.55), 8, 40.0)
	queue_free()


func _play(anim: StringName) -> void:
	if sprite.sprite_frames and sprite.sprite_frames.has_animation(anim) and sprite.animation != anim:
		sprite.play(anim)
