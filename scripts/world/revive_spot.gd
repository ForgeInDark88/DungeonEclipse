class_name ReviveSpot
extends Area2D
## Beside a fallen ally of a world session: E raises them (WorldNet.revive,
## the host checks that the helper stands next to them).

var target: Player


func _ready() -> void:
	collision_layer = 16
	collision_mask = 0
	monitoring = false
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(26, 26)
	shape.shape = rect
	shape.position = Vector2(0, -12)
	add_child(shape)


func _process(_delta: float) -> void:
	var dead := target != null and target.dead
	if dead and not is_in_group("interactable"):
		add_to_group("interactable")
	elif not dead and is_in_group("interactable"):
		remove_from_group("interactable")


func can_interact() -> bool:
	return target != null and target.dead


func get_prompt() -> String:
	return tr("Поднять союзника: %s") % String(Net.players.get(target.peer_id, {}).get("name", "?"))


func interact(_player: Node) -> void:
	if can_interact():
		WorldNet.revive(target.peer_id)
