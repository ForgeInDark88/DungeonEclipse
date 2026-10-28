class_name BlobShadow
extends Sprite2D
## Soft shadow on the ground under a creature (raycast down to the floor).
## Cheap: a creature standing on the floor needs no ray, an airborne one casts
## every other frame, and off-screen shadows only look every few frames.

const MAX_DISTANCE := 96.0
const OFFSCREEN_MARGIN := 48.0

var _parent: Node2D
var _body: CharacterBody2D
var _skip := 0


func _ready() -> void:
	texture = AssetPaths.tex(AssetPaths.SHADOW)
	top_level = true
	z_index = -1
	_parent = get_parent() as Node2D
	_body = _parent as CharacterBody2D
	_skip = randi() % 4  # spread the casts of a crowd over frames


func _physics_process(_delta: float) -> void:
	if _parent == null:
		return
	if _skip > 0:
		_skip -= 1
		return
	if not _on_screen():
		visible = false
		_skip = 8
		return
	if _body and _body.is_on_floor():
		visible = _parent.visible
		global_position = _parent.global_position + Vector2(0, -1)
		scale = Vector2.ONE
		modulate.a = 1.0
		return
	_skip = 1
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


func _on_screen() -> bool:
	var screen := get_viewport().get_visible_rect().grow(OFFSCREEN_MARGIN)
	return screen.has_point(_parent.get_global_transform_with_canvas().origin)
