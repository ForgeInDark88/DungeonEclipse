extends BookPageScreen
## Title screen: new run, settings, meta statistics.

var _fullscreen_button: Button


func _ready() -> void:
	get_tree().paused = false
	build_book(Vector2(440, 250))
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
	right_page.add_child(BookPageScreen.button("Святилище Затмения (%d оск.)" % MetaProgress.shards,
		func() -> void: get_tree().change_scene_to_file(GameState.SANCTUM)))
	_fullscreen_button = BookPageScreen.button("", _toggle_fullscreen)
	right_page.add_child(_fullscreen_button)
	for entry in [["Общая", "master_volume"], ["Музыка", "music_volume"], ["Звуки", "sfx_volume"], ["Интерфейс", "ui_volume"]]:
		right_page.add_child(_volume_row(entry[0], entry[1]))
	right_page.add_child(BookPageScreen.button("Выход", func() -> void: get_tree().quit()))
	_update_fullscreen_text()
	start.grab_focus()


## Label + slider bound to a SaveManager volume property.
func _volume_row(text: String, property: String) -> Control:
	var row := HBoxContainer.new()
	var l := UIStyle.label(text, 7)
	l.custom_minimum_size = Vector2(56, 0)
	row.add_child(l)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = SaveManager.get(property)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(v: float) -> void:
		SaveManager.set(property, v)
		SaveManager.apply_settings()
		SaveManager.save_settings())
	slider.drag_ended.connect(func(_changed: bool) -> void: AudioManager.play_ui(&"ui_click"))
	row.add_child(slider)
	return row


func _toggle_fullscreen() -> void:
	SaveManager.fullscreen = not SaveManager.fullscreen
	SaveManager.apply_settings()
	SaveManager.save_settings()
	_update_fullscreen_text()


func _update_fullscreen_text() -> void:
	_fullscreen_button.text = "Полный экран: %s" % ("вкл" if SaveManager.fullscreen else "выкл")


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c
