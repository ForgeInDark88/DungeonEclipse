class_name Bomb
extends CharacterBody2D
## Thrown bomb: bounces, then explodes, hurting enemies in plain view and
## breaking bricks in the radius.

const GRAVITY := 700.0

var damage: int = 40
var radius: float = 36.0
var fuse_time: float = 1.4
var damage_type: int = 0
var status: StringName = &""
var status_duration: float = 3.0
var status_power: float = 3.0
var sticky := false
var breaks_tiles := true
var color := Color(1.0, 0.6, 0.2)
## Networked visual copy on the guest: it explodes for the effect but does
## no damage and no tile changes — the host's real bomb did the work.
var visual_only := false
## Who threw it (co-op friendly fire spares the thrower).
var thrower_peer := 1
var _stuck := false
var _t := 0.0

@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	sprite.texture = AssetPaths.tex(AssetPaths.BOMB)


func _physics_process(delta: float) -> void:
	_t += delta
	if _stuck:
		velocity = Vector2.ZERO
	else:
		velocity.y = minf(velocity.y + GRAVITY * delta, 400.0)
	var before := velocity
	move_and_slide()
	if sticky and not _stuck and get_slide_collision_count() > 0:
		_stuck = true  # sticky bomb: stays where it touched
		velocity = Vector2.ZERO
	if is_on_floor():
		velocity.x = move_toward(velocity.x, 0.0, 300.0 * delta)
		if before.y > 80.0:
			velocity.y = -before.y * 0.35
	if is_on_wall():
		velocity.x = -before.x * 0.5
	# Blink faster near the end of the fuse.
	var speed := 6.0 if _t < fuse_time * 0.6 else 18.0
	sprite.modulate = Color(1, 0.4, 0.3) if sin(_t * speed) > 0.0 else Color.WHITE
	if _t >= fuse_time:
		explode()


func explode() -> void:
	set_physics_process(false)
	if visual_only:
		Fx.explosion(get_parent(), global_position, radius, color)
		queue_free()
		return
	# Damage only in plain view, checked against the walls as they were:
	# bricks in the radius still break, but they shield what is behind them.
	var center := global_position + Vector2(0, -4)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.global_position.distance_to(global_position) <= radius + 8.0 and LineOfSight.can_hit(self, center, enemy):
			enemy.take_damage(damage, false, global_position, damage_type)
			if status != &"" and is_instance_valid(enemy) and not enemy.is_dead():
				var st: StatusEffects = enemy.get_node_or_null("StatusEffects")
				if st:
					st.apply(status, status_duration, status_power)
	_friendly_fire(center)
	var level := get_parent().get_parent() as DungeonLevel
	if level:
		if breaks_tiles:
			level.explode(global_position, radius)
		else:
			EventBus.noise.emit(global_position, 260.0)
	Fx.explosion(get_parent(), global_position, radius, color)
	EventBus.screen_shake.emit(6.0)
	queue_free()


## A world session whose friendly fire is on: allies in the blast are hurt
## (CoopRules.friendly_bomb_mult of the damage), the thrower is spared.
func _friendly_fire(center: Vector2) -> void:
	if not (Net.world_session and Net.is_host) or WorldNet.setting("friendly_fire") == "off":
		return
	var game := get_tree().current_scene
	if game == null or not game.has_method("party"):
		return
	var ns := get_tree().get_first_node_in_group("net_game") as NetSync
	var amount := roundi(damage * Net.rules().friendly_bomb_mult)
	for p: Player in game.party():
		if p.peer_id == thrower_peer or p.dead or p.global_position.distance_to(global_position) > radius + 6.0:
			continue
		if not LineOfSight.can_hit(self, center, p):
			continue
		if p.peer_id == multiplayer.get_unique_id():
			p.net_take_damage(amount, global_position, damage_type)
		elif ns:
			ns.player_damage.rpc_id(p.peer_id, amount, global_position, damage_type)
