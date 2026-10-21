class_name Bomb
extends CharacterBody2D
## Thrown bomb: bounces, then explodes, hurting enemies and breaking bricks.

const GRAVITY := 700.0

var damage: int = 40
var radius: float = 36.0
var fuse_time: float = 1.4
var _t := 0.0

@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	sprite.texture = AssetPaths.tex(AssetPaths.BOMB)


func _physics_process(delta: float) -> void:
	_t += delta
	velocity.y = minf(velocity.y + GRAVITY * delta, 400.0)
	var before := velocity
	move_and_slide()
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
	var level := get_parent().get_parent() as DungeonLevel
	if level:
		level.explode(global_position, radius)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.global_position.distance_to(global_position) <= radius + 8.0:
			enemy.take_damage(damage, false, global_position)
	Fx.explosion(get_parent(), global_position, radius, Color(1.0, 0.6, 0.2))
	EventBus.screen_shake.emit(6.0)
	queue_free()
