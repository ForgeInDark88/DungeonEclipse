extends Node
## Two-process co-op integration test: the host starts a run and descends to
## floor 1; the guest connects mid-run. Both sides then verify that mobs and
## player puppets exist on each machine. The watcher lives directly under the
## tree root so scene changes cannot free it.
##   NET_ROLE=host godot --headless --path . res://tests/net_game_sim.tscn
##   NET_ROLE=client godot --headless --path . res://tests/net_game_sim.tscn


func _ready() -> void:
	var watcher: Node = load("res://tests/net_game_watcher.gd").new()
	watcher.is_host = OS.get_environment("NET_ROLE") == "host"
	get_tree().root.add_child.call_deferred(watcher)
