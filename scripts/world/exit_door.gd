class_name ExitDoor
extends Area2D
## Passage to the next floor.


func _ready() -> void:
	add_to_group("interactable")
	var portal: AnimatedSprite2D = $Portal
	AssetPaths.layout(AssetPaths.PORTAL_LAYOUT).apply_to(portal, AssetPaths.tex(AssetPaths.PORTAL_SHEET))
	portal.play(&"swirl")
	# Pulsing portal light.
	var light: PointLight2D = $PointLight2D
	var tw := create_tween().set_loops()
	tw.tween_property(light, "energy", 1.4, 0.8).set_trans(Tween.TRANS_SINE)
	tw.tween_property(light, "energy", 0.6, 0.8).set_trans(Tween.TRANS_SINE)


func get_prompt() -> String:
	return "Спуститься глубже (этаж %d)" % (GameState.floor_number + 1)


func interact(player: Node) -> void:
	AudioManager.play_sfx(&"portal")
	if Net.active and not Net.is_host:
		var ns := get_tree().get_first_node_in_group("net_game") as NetSync
		if ns:
			ns.request_floor.rpc_id(1, &"next")
		return
	if Net.active and Net.is_host:
		# Co-op: the whole living party must be gathered at the door.
		var ns := get_tree().get_first_node_in_group("net_game") as NetSync
		if ns and not ns.party_at(player.global_position, 220.0):
			EventBus.message.emit("Все живые герои должны подойти к выходу!")
			return
	GameState.next_floor()
