extends SceneTree
## Ponds of the surface (water + swimming): the hero dropped into a pond
## swims (held up, not on the bottom like a stone), jump strokes bring them
## to the surface, a jump at the surface leaps out onto the bank; the pond
## splashes; a monster that walks into a pond walks out (stepped banks).
##   godot --headless -s tests/water_test.gd

var fails := 0


func check(c: bool, what: String) -> void:
	print(("PASS: " if c else "FAIL: ") + what)
	if not c:
		fails += 1


func wait_scene(state: int) -> void:
	var flow = root.get_node("GameFlow")
	for i in 600:
		await process_frame
		if flow.state == state and not flow.is_busy() and current_scene != null:
			for k in 10:
				await process_frame
			return


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func _initialize() -> void:
	await process_frame
	var sm = root.get_node("SaveManager")
	var flow = root.get_node("GameFlow")
	var gs = root.get_node("GameState")
	var idb = root.get_node("ItemDatabase")
	sm.saves_dir = "user://test_water/"
	sm.remember_slot = false
	sm.delete_slot(1)
	sm.use_slot(1)
	flow.create_hero(idb.races[0], idb.classes[0], false, &"normal", 0)
	await wait_scene(flow.State.TOWN)
	var found := false
	for k in 30:
		flow.open_map()
		await wait_scene(flow.State.EXPEDITION_MAP)
		var id: int = gs.run.next_choices()[0]
		gs.run.map.nodes[id]["type"] = &"level"
		gs.run.map.nodes[id]["seed"] = 777 + k * 131
		flow.enter_node(id)
		await wait_scene(flow.State.LOCATION)
		var lvl = current_scene.level
		if not lvl.water_bodies.is_empty():
			found = true
			break
		flow.retreat()
		await wait_scene(flow.State.RUN_RESULT)
		flow.back_to_town()
		await wait_scene(flow.State.TOWN)
	check(found, "a surface with a pond")
	if not found:
		quit(1)
		return
	var lvl = current_scene.level
	var p = current_scene.player
	p._invulnerable = 9999.0
	for e in get_nodes_in_group("enemies"):
		e.queue_free()
	var body: ColorRect = lvl.water_bodies[0]
	var mid := body.global_position + Vector2(body.size.x / 2.0, 0)
	check(lvl.water_depth_at(mid + Vector2(0, 20)) > 10.0 and lvl.water_depth_at(mid + Vector2(0, -30)) < 0.0,
			"water_depth_at: deep inside the pond, dry above it")
	p.global_position = mid + Vector2(0, -24)
	p.velocity = Vector2.ZERO
	await frames(50)
	check(p.swimming, "dropped in, the hero swims")
	var sink_speed: float = p.velocity.y
	check(sink_speed <= p.SWIM_MAX_SINK + 1.0, "the water holds the hero up (sinks at %.0f px/s)" % sink_speed)
	# dive to the bottom, then stroke up
	Input.action_press("move_down")
	await frames(60)
	Input.action_release("move_down")
	var low: float = lvl.water_depth_at(p.global_position)
	Input.action_press("jump")
	await frames(70)
	var high: float = lvl.water_depth_at(p.global_position)
	check(low > high + 4.0, "jump strokes bring the hero up (depth %.0f -> %.0f)" % [low, high])
	Input.action_release("jump")
	# out onto the bank: swim right and leap at the surface
	Input.action_press("move_right")
	var out := false
	for i in 30:
		Input.action_press("jump")
		await frames(4)
		Input.action_release("jump")
		await frames(8)
		if not p.swimming and p.is_on_floor():
			out = true
			break
	Input.action_release("move_right")
	check(out, "a jump at the surface leaps out onto the bank")
	# rain rings and a splash do not break anything
	lvl.set_rain(1.0)
	lvl.splash(mid + Vector2(0, 2), true)
	await frames(10)
	check(true, "rain on the ponds and a splash")
	flow.retreat()
	await wait_scene(flow.State.RUN_RESULT)
	sm.delete_slot(1)
	print("FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)
