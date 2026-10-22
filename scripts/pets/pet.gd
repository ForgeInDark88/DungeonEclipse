class_name Pet
extends Node2D
## A spirit familiar: floats next to the hero (through walls), attacks
## monsters near the hero when it can see them, picks up gold coins.
## Invulnerable; lives until the end of the run (GameState.pet).

enum Act { FOLLOW, ATTACK, FETCH }

var data: PetData
var player: Player
var _act := Act.FOLLOW
var _cooldown := 0.5
var _target: Node2D
var _bob := 0.0
var _scan := 0.0

@onready var sprite: AnimatedSprite2D = $Sprite


func setup(p_data: PetData, p_player: Player) -> void:
	data = p_data
	player = p_player


func _ready() -> void:
	add_to_group("pets")
	z_index = 5
	AssetPaths.layout(AssetPaths.PET_LAYOUT).apply_to(sprite, AssetPaths.tex(data.sheet))
	sprite.modulate = data.tint
	sprite.play(&"fly")
	sprite.animation_finished.connect(func() -> void: sprite.play(&"fly"))
	global_position = home_position()


func home_position() -> Vector2:
	return player.global_position + Vector2(-player.facing * 16.0, -30.0 + sin(_bob) * 3.0)


func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player) or player.dead:
		return
	_bob += delta * 3.0
	_cooldown -= delta
	_scan -= delta
	# The target may be freed at any moment (dead monster, picked up coin):
	# a freed object is not "== null", so only is_instance_valid() is safe.
	if _act != Act.FOLLOW and not is_instance_valid(_target):
		_target = null
		_act = Act.FOLLOW
	if _act == Act.FOLLOW and _scan <= 0.0:
		_scan = 0.2
		_pick_job()
	match _act:
		Act.FOLLOW:
			_fly_to(home_position(), data.speed, delta)
			# Fell far behind (floor change, teleport): jump to the hero.
			if global_position.distance_to(player.global_position) > 400.0:
				global_position = home_position()
		Act.ATTACK:
			var enemy := _target as Enemy
			if enemy.is_dead() or enemy.global_position.distance_to(player.global_position) > data.attack_range * 1.5:
				_act = Act.FOLLOW
				return
			var aim := _aim(enemy)
			_fly_to(aim, data.speed * 2.2, delta)
			if global_position.distance_to(aim) < 12.0:
				_hit(enemy)
		Act.FETCH:
			var coin := _target as ItemPickup
			if coin.is_queued_for_deletion():
				_act = Act.FOLLOW
				return
			var spot := coin.global_position + Vector2(0, -6)
			_fly_to(spot, data.speed * 1.6, delta)
			if global_position.distance_to(spot) < 10.0:
				coin.collect(player.hero)
				_target = null
				_act = Act.FOLLOW


func _fly_to(pos: Vector2, speed: float, delta: float) -> void:
	var to := pos - global_position
	var dist := to.length()
	if dist > 1.0:
		var step := minf(dist, maxf(speed, dist * 4.0) * delta)
		global_position += to / dist * step
		if absf(to.x) > 2.0:
			sprite.flip_h = to.x < 0.0


func _aim(enemy: Enemy) -> Vector2:
	return enemy.global_position + Vector2(0, -enemy.data.collision_size.y * 0.5)


## Next job: a monster the hero and the pet can see, otherwise a coin.
func _pick_job() -> void:
	if _cooldown <= 0.0:
		var best: Enemy
		var best_d := data.attack_range
		for n in get_tree().get_nodes_in_group("enemies"):
			var e := n as Enemy
			if e == null or e.is_dead():
				continue
			var d := e.global_position.distance_to(player.global_position)
			if d < best_d and LineOfSight.clear(player, player.global_position + Vector2(0, -12), _aim(e)) \
					and LineOfSight.clear(self, global_position, _aim(e)):
				best = e
				best_d = d
		if best:
			_target = best
			_act = Act.ATTACK
			return
	for n in get_tree().get_nodes_in_group("pickups"):
		var p := n as ItemPickup
		if p and p.item and p.item.currency_value > 0 and not p.is_queued_for_deletion() \
				and p.global_position.distance_to(global_position) < data.gold_radius:
			_target = p
			_act = Act.FETCH
			return


func _hit(enemy: Enemy) -> void:
	var lvl := player.hero.level if player.hero else 1
	var dmg := roundi(data.damage * (1.0 + 0.15 * (lvl - 1)))
	enemy.take_damage(dmg, false, global_position, data.damage_type)
	if data.status != &"" and not enemy.is_dead():
		enemy.status.apply(data.status, data.status_duration, data.status_power)
	sprite.play(&"attack")
	AudioManager.play_sfx(&"hit_flesh", global_position)
	_cooldown = data.attack_cooldown
	_target = null
	_act = Act.FOLLOW
