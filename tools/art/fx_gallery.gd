extends SceneTree
## The sprite shader (assets/shaders/flash.gdshader) on real sprites:
## plain, elite outline, dissolve 0.3 / 0.6 / 0.85, the use highlight.
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 \
##       --resolution 1280x720 -s tools/art/fx_gallery.gd -- out.png

func _initialize() -> void:
	await process_frame
	var bg := ColorRect.new()
	bg.color = Color(0.2, 0.17, 0.2)
	bg.size = Vector2(640, 360)
	root.add_child(bg)
	var idb = root.get_node("ItemDatabase")
	var row := 0
	var picked := []
	for e in idb.enemies:
		if e.sheet != null and e.sheet_layout != null and picked.size() < 3 and String(e.id) in ["skeleton", "slime", "bat", "spider", "ghost"]:
			picked.append(e)
	for e in picked:
		var cfg := [["plain", {}], ["elite", {"outline_color": Color(1, 0.4, 0.2, 0.95)}],
			["0.3", {"dissolve": 0.3, "dissolve_edge": e.tint.lightened(0.45)}],
			["0.6", {"dissolve": 0.6, "dissolve_edge": e.tint.lightened(0.45)}],
			["0.85", {"dissolve": 0.85, "dissolve_edge": e.tint.lightened(0.45)}]]
		for i in cfg.size():
			var s := AnimatedSprite2D.new()
			e.sheet_layout.apply_to(s, e.sheet)
			s.play(&"idle")
			s.modulate = e.tint
			var m: ShaderMaterial = load("res://scripts/core/asset_paths.gd").flash_material()
			for k in cfg[i][1]:
				m.set_shader_parameter(k, cfg[i][1][k])
			s.material = m
			s.position = Vector2(60 + i * 80, 60 + row * 90)
			s.scale = Vector2(2, 2)
			root.add_child(s)
			var l := Label.new()
			l.text = String(cfg[i][0])
			l.position = s.position + Vector2(-16, 34)
			root.add_child(l)
		row += 1
	var npc := Sprite2D.new()
	npc.texture = load("res://assets/sprites/npc/elder.png")
	npc.position = Vector2(500, 120)
	npc.scale = Vector2(3, 3)
	var hm: ShaderMaterial = load("res://scripts/core/asset_paths.gd").flash_material()
	hm.set_shader_parameter("outline_color", Color(1.0, 0.92, 0.62, 0.9))
	npc.material = hm
	root.add_child(npc)
	for i in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	quit()
