class_name LineOfSight
extends RefCounted
## "Is there a wall between A and B?" — one rule for every attack in the game
## (hero, monsters, bosses, projectiles, explosions). Only the world layer
## (bricks, bedrock) blocks; one-way platforms and ladders do not.

const WORLD_MASK := 1


## True when nothing solid lies on the segment from → to.
static func clear(node: Node2D, from: Vector2, to: Vector2) -> bool:
	var q := PhysicsRayQueryParameters2D.create(from, to, WORLD_MASK)
	q.hit_from_inside = true
	return node.get_world_2d().direct_space_state.intersect_ray(q).is_empty()


## Points worth aiming at on a body: its center and its upper part.
static func aim_points(body: Node2D) -> PackedVector2Array:
	var h := 20.0
	var data = body.get("data")
	if data is EnemyData:
		h = (data as EnemyData).collision_size.y
	return PackedVector2Array([body.global_position + Vector2(0, -h * 0.5), body.global_position + Vector2(0, -h * 0.85)])


## `from` sees any part of `body`.
static func can_hit(node: Node2D, from: Vector2, body: Node2D) -> bool:
	for p in aim_points(body):
		if clear(node, from, p):
			return true
	return false


## How far one can go from `from` along `dir` before a wall (≤ max_len).
static func free_length(node: Node2D, from: Vector2, dir: Vector2, max_len: float) -> float:
	var q := PhysicsRayQueryParameters2D.create(from, from + dir.normalized() * max_len, WORLD_MASK)
	q.hit_from_inside = true
	var hit := node.get_world_2d().direct_space_state.intersect_ray(q)
	return max_len if hit.is_empty() else from.distance_to(hit["position"])


## Spawn point for a projectile fired from `from` towards `to`: stops in front
## of a wall instead of appearing inside the brick (and flying out behind it).
static func safe_point(node: Node2D, from: Vector2, to: Vector2) -> Vector2:
	var d := to - from
	if d.length() < 0.5:
		return to
	var len := free_length(node, from, d, d.length())
	return from + d.normalized() * maxf(0.0, len - 2.0)
