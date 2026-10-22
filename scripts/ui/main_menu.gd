extends BookPageScreen
## Title screen: new run, daily run, Sanctum, chronicle, settings, meta statistics.

func _ready() -> void:
	get_tree().paused = false
	build_book(Vector2(440, 260))
	AudioManager.play_music(&"menu")

	var title := UIStyle.label("Dungeon\nEclipse", 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left_page.add_child(title)
	var sub := UIStyle.label("Рогалик в тёмном подземелье", 8, UIStyle.INK_SOFT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left_page.add_child(sub)
	left_page.add_child(_spacer(14))
	var meta := UIStyle.label("Лучший этаж: %d\nЗабегов: %d\nВсего убито: %d" % [SaveManager.best_floor, SaveManager.total_runs, SaveManager.total_kills], 8)
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left_page.add_child(meta)

	right_page.add_theme_constant_override("separation", 4)
	right_page.add_child(_spacer(4))
	var start := BookPageScreen.button("Новый забег", func() -> void: get_tree().change_scene_to_file(GameState.CHARACTER_CREATION))
	right_page.add_child(start)
	right_page.add_child(BookPageScreen.button("Ежедневный забег", func() -> void: get_tree().change_scene_to_file(GameState.DAILY)))
	right_page.add_child(BookPageScreen.button("Святилище Затмения (%d оск.)" % MetaProgress.shards,
		func() -> void: get_tree().change_scene_to_file(GameState.SANCTUM)))
	right_page.add_child(BookPageScreen.button("Летопись (%d/%d)" % [Codex.achieved.size(), Codex.achievements.size()],
		func() -> void: get_tree().change_scene_to_file(GameState.CODEX)))
	right_page.add_child(BookPageScreen.button("Настройки", open_settings))
	right_page.add_child(BookPageScreen.button("Выход", func() -> void: get_tree().quit()))
	start.grab_focus()


func open_settings() -> SettingsBook:
	var sb := SettingsBook.new()
	add_child(sb)
	return sb


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c
