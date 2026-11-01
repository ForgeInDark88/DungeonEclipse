extends SceneTree
## FPS on the widest surface (12 screens): a location of 12 screens at
## depth 20, the hero walks it end to end (and goes down to a floor), FPS
## sampled every 0.25 s. With rendering:
##   xvfb-run -a godot --rendering-driver opengl3 -s tests/perf_surface.gd
## Prints the numbers for docs/PERFORMANCE.md.

func wait_scene(state: int) -> void:
	var flow = root.get_node("GameFlow")
	for i in 600:
		await process_frame
		if flow.state == state and not flow.is_busy() and current_scene != null:
			for k in 30:
				await process_frame
			return


func _initialize() -> void:
	await process_frame
	var sm = root.get_node("SaveManager")
	var flow = root.get_node("GameFlow")
	var gs = root.get_node("GameState")
	var idb = root.get_node("ItemDatabase")
	sm.saves_dir = "user://perf_saves/"
	sm.remember_slot = false
	sm.delete_slot(1)
	sm.use_slot(1)
	flow.create_hero(idb.races[0], idb.classes[0], false, &"normal", 0)
	await wait_scene(flow.State.TOWN)
	flow.open_map()
	await wait_scene(flow.State.EXPEDITION_MAP)
	var def = idb.locations[&"level"]
	def.surface_screens_min = 12
	def.surface_screens_max = 12
	var id: int = gs.run.next_choices()[0]
	gs.run.map.nodes[id]["type"] = &"level"
	gs.run.map.nodes[id]["depth"] = 20
	var t0 := Time.get_ticks_msec()
	flow.enter_node(id)
	await wait_scene(flow.State.LOCATION)
	var load_ms := Time.get_ticks_msec() - t0
	var game = current_scene
	var p = game.player
	p._invulnerable = 99999.0
	var lvl = game.level
	var sub = lvl.layout.bands[0]["layout"]
	print("surface %dx%d cells, whole location %dx%d, layers %d" % [sub.width, sub.height, lvl.layout.width, lvl.layout.height, lvl.layout.bands.size()])
	print("nodes in tree: %d, monsters: %d, load %d ms" % [root.get_child_count(), game.get_tree().get_nodes_in_group("enemies").size(), load_ms])
	var samples: Array[float] = []
	var steps := 80
	for k in steps:
		var x: int = 6 + k * (sub.width - 12) / steps
		var gy := 0
		for y in range(2, sub.height):
			if LevelLayout.is_solid(sub.get_tile(x, y)):
				gy = y
				break
		p.global_position = lvl.cell_bottom(Vector2i(x, gy - 1))
		await create_timer(0.25).timeout
		samples.append(Engine.get_frames_per_second())
	samples.sort()
	var avg := 0.0
	for s in samples:
		avg += s
	avg /= samples.size()
	var awake := 0
	for e in game.get_tree().get_nodes_in_group("enemies"):
		if e.process_mode != Node.PROCESS_MODE_DISABLED and not e._dormant:
			awake += 1
	print("surface FPS: avg %.1f, min %.1f, median %.1f (awake monsters at the end: %d)" % [avg, samples[0], samples[samples.size() / 2], awake])
	game.location.travel(&"f1_up")
	await create_timer(1.5).timeout
	var s2: Array[float] = []
	for k in 20:
		await create_timer(0.25).timeout
		s2.append(Engine.get_frames_per_second())
	var a2 := 0.0
	for s in s2:
		a2 += s
	print("first floor FPS: avg %.1f" % (a2 / s2.size()))
	sm.delete_slot(1)
	quit()
