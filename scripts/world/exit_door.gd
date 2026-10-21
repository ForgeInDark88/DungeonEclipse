class_name ExitDoor
extends Area2D
## Passage to the next floor.


func _ready() -> void:
	add_to_group("interactable")
	$Sprite2D.texture = AssetPaths.tex(AssetPaths.EXIT_DOOR)


func get_prompt() -> String:
	return "Спуститься глубже (этаж %d)" % (GameState.floor_number + 1)


func interact(_player: Node) -> void:
	GameState.next_floor()
