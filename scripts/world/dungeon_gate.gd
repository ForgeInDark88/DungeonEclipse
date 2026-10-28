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
	if GameState.town_return_floor > 0:
		return "Спуститься на этаж %d" % GameState.town_return_floor
	return "Спуститься в подземелье"


func interact(_player: Node) -> void:
	AudioManager.play_sfx(&"portal")
	if Net.active and not Net.is_host:
		# Co-op: only the host moves the party.
		var ns := get_tree().get_first_node_in_group("net_game") as NetSync
		if ns:
			ns.request_floor.rpc_id(1, &"resume" if GameState.town_return_floor > 0 else &"next")
		return
	if Net.active and Net.is_host:
		# Co-op: the party moves together (NetSync waits for everyone).
		var ns := get_tree().get_first_node_in_group("net_game") as NetSync
		if ns:
			ns.host_party_move(Net.multiplayer.get_unique_id(), &"next")
			return
	if GameState.town_return_floor > 0:
		GameState.resume_from_town()
	else:
		GameState.next_floor()
