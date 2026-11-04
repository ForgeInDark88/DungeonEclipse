extends SceneTree
## The living surface: its music plays; butterflies by day, fireflies at
## night; birds perched in the crowns take off when a hero comes near; the
## grass is there; the foreground branch shows under the sky and hides
## underground; the backgrounds follow the hour (night on the sky shader).
##   godot --headless -s tests/surface_life_test.gd

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
		await process_frame


func _count(life, kind: StringName) -> int:
	return life._flyers.filter(func(f): return f["kind"] == kind).size()


func _initialize() -> void:
	await process_frame
	var sm = root.get_node("SaveManager")
	var flow = root.get_node("GameFlow")
	var gs = root.get_node("GameState")
	var idb = root.get_node("ItemDatabase")
	var am = root.get_node("AudioManager")
	sm.saves_dir = "user://test_life/"
	sm.remember_slot = false
	sm.delete_slot(1)
	sm.use_slot(1)
	flow.create_hero(idb.races[0], idb.classes[0], false, &"normal", 0)
	await wait_scene(flow.State.TOWN)
	flow.open_map()
	await wait_scene(flow.State.EXPEDITION_MAP)
	var id: int = gs.run.next_choices()[0]
	gs.run.map.nodes[id]["type"] = &"level"
	gs.run.map.nodes[id]["seed"] = 4242
	flow.enter_node(id)
	await wait_scene(flow.State.LOCATION)
	var lm = current_scene.location
	var p = current_scene.player
	p._invulnerable = 9999.0
	check(String(am.current_music()).begins_with("surface_"), "the surface plays its own music (%s)" % am.current_music())
	check(lm.life != null and lm.grass != null, "the surface has its small life and its grass")
	check(not lm.grass._blades.is_empty(), "grass grows along the ground (%d columns)" % lm.grass._blades.size())
	var front = current_scene.get_node_or_null("FrontParallax")
	check(front != null and front.visible, "a foreground branch under the open sky")
	# day
	lm.sky.phase = 0.3
	await frames(40)
	check(_count(lm.life, &"butterfly") > 0 and _count(lm.life, &"firefly") == 0, "butterflies by day (%d)" % _count(lm.life, &"butterfly"))
	var sky_mat = (current_scene.get_node("Parallax").get_child(0).get_child(0) as Sprite2D).material
	check(sky_mat != null and float(sky_mat.get_shader_parameter("night")) < 0.01, "a day sky")
	# night
	lm.sky.phase = 0.8
	await frames(120)
	check(_count(lm.life, &"firefly") > 0, "fireflies at night (%d)" % _count(lm.life, &"firefly"))
	check(float(sky_mat.get_shader_parameter("night")) > 0.9, "the sky goes dark at night, the stars come out")
	lm.sky.phase = 0.3
	# birds: go to a perch, they fly off
	var perches: Array = lm.life._perches.filter(func(q): return not q["birds"].is_empty())
	check(not perches.is_empty(), "birds sit in the crowns (%d trees)" % perches.size())
	if not perches.is_empty():
		var pos: Vector2 = perches[0]["pos"]
		p.global_position = Vector2(pos.x - 30, pos.y + 70)
		await frames(10)
		check(perches[0]["birds"].is_empty() and _count(lm.life, &"bird") > 0, "a hero near: the birds take off")
	# underground the decoration sleeps and the front hides
	lm.travel(&"f1_up")  # down onto the first floor
	await create_timer(1.2).timeout
	check(not lm.life.active and not lm.grass.active, "underground the life of the surface sleeps")
	check(front == null or not front.visible, "no foreground branch underground")
	flow.retreat()
	await wait_scene(flow.State.RUN_RESULT)
	sm.delete_slot(1)
	print("FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)
