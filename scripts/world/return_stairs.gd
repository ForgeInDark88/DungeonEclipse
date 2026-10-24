class_name ReturnStairs
extends Area2D
## Stone stairs going up, spawned near the floor entrance of every dungeon
## floor: interact to climb back to the town street (the run continues, the
## town gate leads back to this floor).

const UP_SFX := &"portal"


func _ready() -> void:
	add_to_group("interactable")
	collision_layer = 16
	collision_mask = 0
	monitoring = false
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(28, 26)
	shape.shape = rect
	shape.position = Vector2(0, -13)
	add_child(shape)
	# A warm torch glow so the way up is easy to spot in the dark.
	var light := PointLight2D.new()
	light.texture = AssetPaths.tex(AssetPaths.LIGHT)
	light.color = Color(1.0, 0.75, 0.45)
	light.energy = 0.9
	light.texture_scale = 0.5
	light.position = Vector2(0, -16)
	add_child(light)
	var tw := create_tween().set_loops()
	tw.tween_property(light, "energy", 1.15, 1.0).set_trans(Tween.TRANS_SINE)
	tw.tween_property(light, "energy", 0.65, 1.0).set_trans(Tween.TRANS_SINE)


func get_prompt() -> String:
	return "Вернуться в город"


func interact(_player: Node) -> void:
	AudioManager.play_sfx(UP_SFX, global_position)
	EventBus.message.emit("Ты поднимаешься по лестнице на поверхность...")
	GameState.return_to_town()
