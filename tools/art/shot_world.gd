extends SceneTree
## Screenshots of the living world for checking art by eye: the town, then a
## surface location (the hero placed at a few points along it).
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 \
##       --resolution 1280x720 -s tools/art/shot_world.gd -- <out_dir> [seed] [hour]
## Writes <out_dir>/town.png, surface_0.png .. surface_2.png, floor.png.
## hour 0..1 sets the surface sky phase (0.5 = noon), default: as generated.
## Uses its own save folder (user://shot_saves/), never the player's.

var out := "."


func wait_scene(state: int) -> void:
	var flow = root.get_node("GameFlow")
	for i in 900:
		await process_frame
		if flow.state == state and not flow.is_busy() and current_scene != null:
			for k in 40:
				await process_frame
			return


func shot(name: String) -> void:
	for k in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := out.path_join(name)
	root.get_texture().get_image().save_png(path)
	print("shot ", path)


func place(game, cell: Vector2i) -> void:
	var p = game.player
	p.global_position = Vector2(cell.x * 16 + 8, cell.y * 16)
	p.velocity = Vector2.ZERO


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else "."
	if args.size() > 1:
		seed(int(args[1]))
	var hour := float(args[2]) if args.size() > 2 else -1.0
	await process_frame
	var sm = root.get_node("SaveManager")
	var flow = root.get_node("GameFlow")
	var gs = root.get_node("GameState")
	var idb = root.get_node("ItemDatabase")
	TranslationServer.set_locale("ru")
	sm.saves_dir = "user://shot_saves/"
	sm.remember_slot = false
	sm.delete_slot(1)
	sm.use_slot(1)
	flow.create_hero(idb.races[0], idb.classes[0], false, &"normal", 0)
	await wait_scene(flow.State.TOWN)
	current_scene.player._invulnerable = 99999.0
	await shot("town.png")
	flow.open_map()
	await wait_scene(flow.State.EXPEDITION_MAP)
	var id: int = gs.run.next_choices()[0]
	gs.run.map.nodes[id]["type"] = &"level"
	flow.enter_node(id)
	await wait_scene(flow.State.LOCATION)
	var game = current_scene
	game.player._invulnerable = 99999.0
	if hour >= 0.0:
		var sky = game.find_child("SurfaceSky", true, false)
		if sky and "phase" in sky:
			sky.phase = hour
	var sub = game.level.layout.bands[0]["layout"]
	for i in 3:
		var x: int = 8 + i * (sub.width - 16) / 2
		var y := 1
		while y < sub.height - 1 and not sub.get_tile(x, y + 1) in [1, 2]:
			y += 1
		place(game, Vector2i(x, y))
		await shot("surface_%d.png" % i)
	# First floor of the dungeon under it.
	if game.level.layout.bands.size() > 1:
		var r: Rect2i = game.level.layout.bands[1]["rect"]
		var c := Vector2i(r.position.x + r.size.x / 2, r.position.y + r.size.y / 2)
		place(game, c)
		await shot("floor.png")
	sm.delete_slot(1)
	quit()
