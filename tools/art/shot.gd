extends SceneTree
## Screenshot of one scene, for checking art and UI by eye.
##   xvfb-run -a godot --rendering-driver opengl3 --resolution 1280x720 \
##       -s tools/art/shot.gd -- res://scenes/ui/main_menu.tscn out.png [frames] [locale]
## The scene runs with the game's autoloads; after `frames` frames (default
## 90) the window is saved as PNG.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("usage: -- <scene> <out.png> [frames]")
		quit(1)
		return
	var frames := int(args[2]) if args.size() > 2 else 90
	await process_frame
	if args.size() > 3:
		TranslationServer.set_locale(args[3])
	change_scene_to_file(args[0])
	for i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(args[1])
	print("shot %s -> %s (%dx%d)" % [args[0], args[1], img.get_width(), img.get_height()])
	quit()
