class_name Minion
extends CharacterBody2D
## A raised undead servant of the necromancer: walks with the hero, attacks
## monsters it can see, crumbles to dust when its time runs out. Monsters do
## not target minions (they are invulnerable); the limit is the lifetime and
## the number the caster may keep (SummonSkill).
##   WARRIOR - melee skeleton, ARCHER - shoots bone arrows, GOLEM - slams an area.

enum Kind { WARRIOR, ARCHER, GOLEM }

const GRAVITY := 900.0
const SIGHT := 170.0
const LEASH := 320.0  # further from the hero than this: rise again next to him

var kind: Kind = Kind.WARRIOR
var owner_player: Player
var damage_mult := 0.6
var life := 20.0
var speed := 95.0
var _cooldown := 0.6
var _target: Enemy
var _scan := 0.0
var _slot := 0  # place in the column behind the hero
var _attack_anim := 0.0
var _stuck := 0.0
var _last_x := 0.0
var _data: EnemyData

@onready var sprite: AnimatedSprite2D = AnimatedSprite2D.new()


static func spawn(p_owner: Player, p_kind: Kind, mult: float, lifetime: float, slot: int, pos: Vector2) -> Minion:
	var m := Minion.new()
	m.owner_player = p_owner
	m.kind = p_kind
	m.damage_mult = mult
	m.life = lifetime
	m._slot = slot
	p_owner.get_parent().add_child(m)
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


func _physics_process(delta: float) -> void:
	if owner_player == null or not is_instance_valid(owner_player):
		queue_free()
		return
	life -= delta
	if life <= 0.0 or owner_player.dead:
		_crumble()
		return
	_cooldown -= delta
	_scan -= delta
	_attack_anim = maxf(0.0, _attack_anim - delta)
	if _target != null and (not is_instance_valid(_target) or _target.is_dead()):
		_target = null
	if _scan <= 0.0:
		_scan = 0.25
		_pick_target()
	velocity.y = minf(velocity.y + GRAVITY * delta, 420.0)
	var goal_x: float
	if _target:
		var reach := _reach()
		var dx := _target.global_position.x - global_position.x
		goal_x = global_position.x if absf(dx) <= reach * 0.8 else _target.global_position.x - signf(dx) * reach * 0.6
		sprite.flip_h = dx < 0.0
		if absf(dx) <= reach and absf(_target.global_position.y - global_position.y) < 26.0 and _cooldown <= 0.0:
			_attack()
	else:
		goal_x = owner_player.global_position.x - owner_player.facing * (22.0 + _slot * 12.0)
	var to_x := goal_x - global_position.x
	velocity.x = clampf(to_x * 6.0, -speed, speed) if absf(to_x) > 3.0 else 0.0
	if absf(velocity.x) > 1.0 and _target == null:
		sprite.flip_h = velocity.x < 0.0
	# A step or a ledge in the way: hop over it.
	if is_on_floor() and is_on_wall() and absf(velocity.x) > 1.0:
		velocity.y = -280.0
	move_and_slide()
	_check_stuck(delta)
	if _attack_anim > 0.0:
		_play(&"attack")
	elif absf(velocity.x) > 8.0:
		_play(&"walk")
	else:
		_play(&"idle")


func _reach() -> float:
	match kind:
		Kind.ARCHER:
			return 140.0
		Kind.GOLEM:
			return 26.0
	return 18.0


func _pick_target() -> void:
	var best: Enemy = null
	var best_d := SIGHT
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e == null or e.is_dead() or (e.data and e.data.training_dummy and not GameState.is_town()):
			continue
		var d := e.global_position.distance_to(global_position)
		if d < best_d and LineOfSight.clear(self, global_position + Vector2(0, -10), e.global_position + Vector2(0, -8)):
			best = e
			best_d = d
	_target = best


func _attack() -> void:
	_attack_anim = 0.35
	var d: Dictionary = owner_player.roll_damage(damage_mult)
	match kind:
		Kind.ARCHER:
			_cooldown = 1.3
			var from := global_position + Vector2(0, -12)
			var dir := (_target.global_position + Vector2(0, -8) - from).normalized()
			var p: Projectile = (load("res://scenes/world/projectile.tscn") as PackedScene).instantiate()
			p.setup(AssetPaths.tex(AssetPaths.SPRITES_DIR + "fx/bone_shard.png"), dir, 230.0, d["amount"], "enemies")
			p.crit = d["crit"]
			get_parent().add_child(p)
			p.global_position = from
			AudioManager.play_sfx(&"enemy_shoot", global_position, -8.0)
		Kind.GOLEM:
			_cooldown = 1.6
			Fx.explosion(get_parent(), global_position + Vector2(0, -4), 34.0, Color(0.55, 1.0, 0.6))
			for n in get_tree().get_nodes_in_group("enemies"):
				var e := n as Enemy
				if e and not e.is_dead() and e.global_position.distance_to(global_position) <= 38.0:
					e.take_damage(d["amount"], d["crit"], global_position, 0)
		_:
			_cooldown = 0.9
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
	if far or _stuck > 1.5:
		_stuck = 0.0
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
