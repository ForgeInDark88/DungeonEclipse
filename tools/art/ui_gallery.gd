extends SceneTree
## Every themed control on one page, to check the interface skin by eye.
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 \
##       --resolution 1280x720 -s tools/art/ui_gallery.gd -- out.png

func _initialize() -> void:
	await process_frame
	var bg := ColorRect.new()
	bg.color = Color(0.96, 0.85, 0.59)
	bg.size = Vector2(640, 360)
	root.add_child(bg)
	var col := VBoxContainer.new()
	col.position = Vector2(16, 12)
	col.add_theme_constant_override("separation", 6)
	root.add_child(col)
	var b := Button.new(); b.text = "Кнопка"; col.add_child(b)
	var c1 := CheckBox.new(); c1.text = "Тени блоков"; c1.button_pressed = true; col.add_child(c1)
	var c2 := CheckBox.new(); c2.text = "Тряска экрана"; col.add_child(c2)
	var t := CheckButton.new(); t.text = "Субтитры"; t.button_pressed = true; col.add_child(t)
	var s := HSlider.new(); s.custom_minimum_size = Vector2(160, 10); s.value = 60; col.add_child(s)
	var le := LineEdit.new(); le.placeholder_text = "IP или домен хоста"; le.custom_minimum_size = Vector2(160, 0); col.add_child(le)
	var le2 := LineEdit.new(); le2.text = "Гость-7"; col.add_child(le2)
	var sp := SpinBox.new(); sp.value = 7777; sp.max_value = 65535; col.add_child(sp)
	var ob := OptionButton.new(); ob.add_item("Обычная"); ob.add_item("Тяжёлая"); col.add_child(ob)
	var pb := ProgressBar.new(); pb.value = 45; pb.custom_minimum_size = Vector2(160, 10); col.add_child(pb)
	var right := VBoxContainer.new()
	right.position = Vector2(260, 12)
	root.add_child(right)
	var il := ItemList.new(); il.custom_minimum_size = Vector2(180, 80)
	for n in ["Мир 1 — 3 игрока", "Подземелье друзей", "Тихая гавань", "Ещё один мир"]:
		il.add_item(n)
	il.select(1)
	right.add_child(il)
	var sc := ScrollContainer.new(); sc.custom_minimum_size = Vector2(180, 90)
	var inner := VBoxContainer.new()
	for i in 14:
		var l := Label.new(); l.text = "Строка списка %d" % i; inner.add_child(l)
	sc.add_child(inner)
	right.add_child(sc)
	var pc := PanelContainer.new()
	var pl := Label.new(); pl.text = "Панель с текстом"; pc.add_child(pl)
	right.add_child(pc)
	for i in 30:
		await process_frame
	ob.show_popup()
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	quit()
