class_name BlobShadow
extends Sprite2D
## Soft shadow on the ground under a creature (raycast down to the floor).

const MAX_DISTANCE := 96.0

var _parent: Node2D


func _ready() -> void:
	texture = AssetPaths.tex(AssetPaths.SHADOW)
	top_level = true
	z_index = -1
	_parent = get_parent() as Node2D


func _physics_process(_delta: float) -> void:
	if _parent == null:
		return
	var from := _parent.global_position + Vector2(0, -4)
	var q := PhysicsRayQueryParameters2D.create(from, from + Vector2(0, MAX_DISTANCE), 3)
	var hit := _parent.get_world_2d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		visible = false
		return
	visible = _parent.visible
	global_position = hit["position"] + Vector2(0, -1)
	var k := 1.0 - clampf((hit["position"].y - _parent.global_position.y) / MAX_DISTANCE, 0.0, 1.0)
	scale = Vector2.ONE * (0.5 + 0.5 * k)
	modulate.a = 0.3 + 0.7 * k
