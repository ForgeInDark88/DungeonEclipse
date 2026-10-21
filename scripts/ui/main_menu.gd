extends BookPageScreen
## Title screen: new run, settings, meta statistics.

var _fullscreen_button: Button


func _ready() -> void:
	get_tree().paused = false
	build_book(Vector2(440, 250))

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

	right_page.add_theme_constant_override("separation", 6)
	right_page.add_child(_spacer(10))
	var start := BookPageScreen.button("Новый забег", func() -> void: get_tree().change_scene_to_file(GameState.CHARACTER_CREATION))
	right_page.add_child(start)
	_fullscreen_button = BookPageScreen.button("", _toggle_fullscreen)
	right_page.add_child(_fullscreen_button)
	var vol_label := UIStyle.label("Громкость", 8)
	right_page.add_child(vol_label)
	var vol := HSlider.new()
	vol.min_value = 0.0
	vol.max_value = 1.0
	vol.step = 0.05
	vol.value = SaveManager.master_volume
	vol.value_changed.connect(func(v: float) -> void:
		SaveManager.master_volume = v
		SaveManager.apply_settings()
		SaveManager.save_settings())
	right_page.add_child(vol)
	right_page.add_child(BookPageScreen.button("Выход", func() -> void: get_tree().quit()))
	_update_fullscreen_text()
	start.grab_focus()


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
