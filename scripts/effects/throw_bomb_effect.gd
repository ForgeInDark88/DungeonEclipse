class_name ThrowBombEffect
extends ItemEffect
## Throws a bomb that explodes after a fuse, damaging enemies and breaking
## brick tiles in the radius.

@export var damage: int = 40
@export var radius_tiles: float = 2.2
@export var fuse_time: float = 1.4
@export var throw_velocity: Vector2 = Vector2(160, -170)

const BOMB_SCENE := preload("res://scenes/world/bomb.tscn")


func apply(user: Node) -> bool:
	if user.level == null:
		return false
	var bomb: Node2D = BOMB_SCENE.instantiate()
	bomb.damage = damage
	bomb.radius = radius_tiles * 16.0
	bomb.fuse_time = fuse_time
	bomb.velocity = Vector2(throw_velocity.x * user.facing, throw_velocity.y)
	user.level.add_entity(bomb, user.global_position + Vector2(6 * user.facing, -10))
	return true


func describe() -> String:
	return "Бросок: %d урона по области, ломает кирпич" % damage
