extends BookPageScreen
## Title screen: new run, daily run, Sanctum, chronicle, settings, meta statistics.

func _ready() -> void:
	get_tree().paused = false
	build_book(Vector2(440, 260))
	AudioManager.play_music(&"menu")

	# The living title: a violet glow breathes behind it and the letters
	# shimmer, like the eclipse itself.
	var glow := TextureRect.new()
	glow.texture = load("res://assets/ui/title_glow.png")
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.custom_minimum_size = Vector2(200, 72)
	glow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	glow.modulate = Color(1, 1, 1, 0.0)
	left_page.add_child(glow)
	var title := TextureRect.new()
	title.texture = load("res://assets/ui/title.png")
	title.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	title.custom_minimum_size = Vector2(184, 66)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	left_page.add_child(title)
	var tw := title.create_tween().set_loops()
	tw.tween_property(glow, "modulate:a", 0.75, 1.6).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(title, "modulate", Color(1.12, 1.05, 1.25), 1.6).set_trans(Tween.TRANS_SINE)
	tw.tween_property(glow, "modulate:a", 0.35, 1.6).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(title, "modulate", Color.WHITE, 1.6).set_trans(Tween.TRANS_SINE)
	var sub := UIStyle.label("Рогалик в тёмном подземелье", 8, UIStyle.INK_SOFT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left_page.add_child(sub)
	left_page.add_child(_spacer(14))
	var meta := UIStyle.label("Лучший этаж: %d\nЗабегов: %d\nВсего убито: %d" % [SaveManager.best_floor, SaveManager.total_runs, SaveManager.total_kills], 8)
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left_page.add_child(meta)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_page.add_child(fill)
	var version := UIStyle.label("Версия %s" % ProjectSettings.get_setting("application/config/version", "0.1"), 7, UIStyle.INK_SOFT)
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left_page.add_child(version)

	right_page.add_theme_constant_override("separation", 4)
	right_page.add_child(_spacer(4))
	var cont: Button = null
	if SaveManager.has_run():
		var d := SaveManager.run_data()
		cont = BookPageScreen.button("Продолжить — %s, ур. %d, этаж %d" % [d.get("class_name", "?"), int(d.get("hero_level", 1)), int(d.get("floor", 1))],
			func() -> void:
				if not GameState.continue_run():
					get_tree().change_scene_to_file(GameState.CHARACTER_CREATION))
		right_page.add_child(cont)
	var start := BookPageScreen.button("Новый забег", func() -> void: get_tree().change_scene_to_file(GameState.CHARACTER_CREATION))
	right_page.add_child(start)
	right_page.add_child(BookPageScreen.button("Ежедневный забег", func() -> void: get_tree().change_scene_to_file(GameState.DAILY)))
	right_page.add_child(BookPageScreen.button("Святилище Затмения (%d оск.)" % MetaProgress.shards,
		func() -> void: get_tree().change_scene_to_file(GameState.SANCTUM)))
	right_page.add_child(BookPageScreen.button("Летопись (%d/%d)" % [Codex.achieved.size(), Codex.achievements.size()],
		func() -> void: get_tree().change_scene_to_file(GameState.CODEX)))
	right_page.add_child(BookPageScreen.button("Настройки", open_settings))
	right_page.add_child(BookPageScreen.button("Выход", func() -> void: get_tree().quit()))
	if cont:
		cont.grab_focus()
	else:
		start.grab_focus()


func open_settings() -> SettingsBook:
	var sb := SettingsBook.new()
	add_child(sb)
	return sb


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c
