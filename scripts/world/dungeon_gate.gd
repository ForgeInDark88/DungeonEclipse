class_name DungeonGate
extends Area2D
## Entrance to the dungeon at the end of the town street: going in starts
## floor 1. The crypt itself is a town prop (dungeon_gate.png).


func _ready() -> void:
	add_to_group("interactable")
	collision_layer = 16
	collision_mask = 0
	monitoring = false
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(36, 34)
	shape.shape = rect
	shape.position = Vector2(0, -17)
	add_child(shape)
	# Violet light of the eclipse from the depths.
	var light := PointLight2D.new()
	light.texture = AssetPaths.tex(AssetPaths.LIGHT)
	light.color = Color(0.7, 0.45, 1.0)
	light.energy = 1.0
	light.texture_scale = 0.6
	light.position = Vector2(0, -14)
	add_child(light)
	var tw := create_tween().set_loops()
	tw.tween_property(light, "energy", 1.4, 1.2).set_trans(Tween.TRANS_SINE)
	tw.tween_property(light, "energy", 0.7, 1.2).set_trans(Tween.TRANS_SINE)


func get_prompt() -> String:
	return "Спуститься в подземелье"


func interact(_player: Node) -> void:
	AudioManager.play_sfx(&"portal")
	GameState.next_floor()
