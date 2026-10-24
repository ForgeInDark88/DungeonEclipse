extends Node
## Regression: does E-interact and LMB-attack reach the player in a live scene?


func _ready() -> void:
	var game := (load("res://scenes/game/game.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().create_timer(1.0).timeout
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null:
		print("INPUT CHECK: no player")
		get_tree().quit(1)
		return
	# Teleport next to the dungeon gate (end of the street) and face it.
	var gate: Node2D = null
	for n in get_tree().get_nodes_in_group("interactable"):
		if n is ExitDoor:
			gate = n
			break
	print("exit door found: ", gate != null)
	if gate:
		player.global_position = gate.global_position + Vector2(-14, 0)
		# Let the physics engine refresh the overlap lists first.
		await get_tree().physics_frame
		await get_tree().physics_frame
		await get_tree().physics_frame
		var floor_before := GameState.floor_number
		print("nearest: ", player._nearest_interactable())
		var direct: bool = player.try_interact()
		await get_tree().process_frame
		await get_tree().process_frame
		print("direct try_interact: ", direct, " -> floor ", GameState.floor_number)
		# Inject E (physical key 69).
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_E
		ev.pressed = true
		Input.parse_input_event(ev)
		await get_tree().process_frame
		await get_tree().process_frame
		print("floor after E: ", GameState.floor_number, " (was ", floor_before, ")")
		print("INPUT CHECK: ", "OK" if GameState.floor_number != floor_before else "E DID NOT INTERACT")
	get_tree().quit(0)
