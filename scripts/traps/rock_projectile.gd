class_name RockProjectile
extends Sprite2D
## Falling rock (pressure plate shower): falls with gravity, hurts the hero
## on contact, shatters on the ground.

var damage := 10
var velocity := Vector2.ZERO


func _physics_process(delta: float) -> void:
	velocity.y = minf(velocity.y + 700.0 * delta, 500.0)
	position += velocity * delta
	rotation += delta * 6.0
	var p: Player = null
	for n in get_tree().get_nodes_in_group("player"):
		var pl := n as Player
		if pl != null and not pl.puppet:
			p = pl
			break
	if p and not p.dead and p.global_position.distance_to(global_position + Vector2(0, 10)) < 12.0:
		p.take_damage(damage, global_position)
		_shatter()
		return
	var level := get_parent().get_parent() as DungeonLevel
	if level and level.is_solid_at(global_position + Vector2(0, 6)):
		_shatter()


func _shatter() -> void:
	Fx.shards(get_parent(), global_position, Color(0.5, 0.45, 0.42), 8)
	queue_free()
