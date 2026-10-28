class_name Projectile
extends Area2D
## Straight-flying projectile. `target_group` is "enemies" (hero shots) or
## "player" (enemy shots). Dies on walls (bricks, bedrock): nothing flies
## through them, explosions on impact hit only targets in plain view.

var direction := Vector2.RIGHT
var speed: float = 200.0
var damage: int = 10
var crit := false
## WeaponItemData.DamageType of the hit.
var damage_type: int = 0
var target_group := "enemies"
var pierce := 0
var lifetime: float = 2.5
## Optional: explodes on impact with this radius (0 = no explosion).
var blast_radius: float = 0.0
var blast_color := Color(1.0, 0.5, 0.2)
## Optional: called as on_hit.call(target, damage) for each target hit.
var on_hit: Callable
## Trap arrows exist on every machine: each one hurts only its local hero.
## Mob shots exist only on the host and reach guests through player_damage.
var local_damage_only := false

var _hit: Array[Node] = []
var _finished := false
## A short glowing trail and a soft halo (magic, fire, ice, poison shots and
## blasts; plain arrows and knives get only a faint streak).
var _trail: Line2D
var _halo: Sprite2D

@onready var sprite: Sprite2D = $Sprite2D


func setup(tex: Texture2D, dir: Vector2, p_speed: float, p_damage: int, group: String) -> void:
	direction = dir.normalized()
	speed = p_speed
	damage = p_damage
	target_group = group
	if is_node_ready():
		sprite.texture = tex
	else:
		ready.connect(func() -> void: sprite.texture = tex, CONNECT_ONE_SHOT)
	# world + the target's layer
	collision_mask = 1 | (4 | Minion.LAYER if group == "player" else 8)


func _ready() -> void:
	rotation = direction.angle()
	body_entered.connect(_on_body_entered)
	sprite.modulate = Color.WHITE.lerp(blast_color, 0.15)  # (no light per shot: cheaper)
	var magic := damage_type != 0 or blast_radius > 0.0
	_trail = Line2D.new()
	_trail.top_level = true
	_trail.z_index = 18
	_trail.width = 4.0 if magic else 1.5
	_trail.default_color = Color(blast_color.r, blast_color.g, blast_color.b, 0.85 if magic else 0.45)
	Fx._beam(_trail)
	var taper := Curve.new()  # thin at the tail (point 0), full at the shot
	taper.add_point(Vector2(0, 0.0))
	taper.add_point(Vector2(1, 1.0))
	_trail.width_curve = taper
	add_child(_trail)
	if magic:
		_halo = Sprite2D.new()
		_halo.texture = AssetPaths.tex(AssetPaths.LIGHT)
		_halo.modulate = Color(blast_color.r, blast_color.g, blast_color.b, 0.55)
		_halo.scale = Vector2.ONE * 0.09
		_halo.material = Fx._glow()
		_halo.z_index = -1
		add_child(_halo)


func _physics_process(delta: float) -> void:
	# Walls are checked with a ray along this frame's step: no tunnelling and
	# no reliance on Area2D overlaps with the tile layer.
	var step := direction * speed * delta
	var q := PhysicsRayQueryParameters2D.create(global_position, global_position + step, LineOfSight.WORLD_MASK)
	q.hit_from_inside = true
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		global_position = hit["position"] - direction
		_finish()
		return
	position += step
	if _trail:
		_trail.add_point(global_position)
		if _trail.get_point_count() > 9:
			_trail.remove_point(0)
	if _halo:
		_halo.scale = Vector2.ONE * (0.085 + sin(lifetime * 40.0) * 0.012)
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()


func _on_body_entered(body: Node) -> void:
	if body in _hit:
		return
	if body.is_in_group(target_group):
		_hit.append(body)
		_damage(body)
		if pierce <= 0:
			_finish()
		pierce -= 1
	elif body is Minion and target_group == "player":
		# Enemy shots hit the necromancer's servants too.
		_hit.append(body)
		(body as Minion).take_damage(damage, global_position)
		_finish()
	elif body is TileMapLayer:
		_finish()


func _damage(body: Node) -> void:
	if target_group == "player":
		if local_damage_only and body.puppet:
			return
		body.take_damage(damage, global_position, damage_type)
	else:
		body.take_damage(damage, crit, global_position, damage_type)
	if on_hit.is_valid():
		on_hit.call(body, damage)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	if blast_radius > 0.0:
		# The blast reaches only what it can see: a brick between shields.
		var center := global_position - direction * 3.0
		for enemy in get_tree().get_nodes_in_group(target_group):
			if enemy not in _hit and enemy.global_position.distance_to(global_position) <= blast_radius \
					and LineOfSight.can_hit(self, center, enemy):
				_damage(enemy)
		Fx.explosion(get_parent(), global_position, blast_radius, blast_color)
	else:
		Fx.sparks(get_parent(), global_position, blast_color, 5, 60.0)
	set_deferred("monitoring", false)
	# the trail lingers a moment after the shot is gone
	if _trail and _trail.get_point_count() > 1 and get_parent():
		var t := _trail
		remove_child(t)
		get_parent().add_child(t)
		var tw := t.create_tween()
		tw.tween_property(t, "modulate:a", 0.0, 0.18)
		tw.tween_callback(t.queue_free)
	queue_free()
