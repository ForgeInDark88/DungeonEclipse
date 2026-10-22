extends BookPageScreen
## Daily run: today's fixed dungeon (seed, race and class from the date) and
## the local leaderboard (Leaderboard). Sanctum upgrades do not apply.

var date := GameState.today()


func _ready() -> void:
	build_book(Vector2(580, 320))
	AudioManager.play_music(&"menu")
	left_page.add_theme_constant_override("separation", 4)
	right_page.add_theme_constant_override("separation", 2)
	var d := GameState.daily_setup(date)

	left_page.add_child(UIStyle.label("Ежедневный забег", 12))
	left_page.add_child(UIStyle.label(date, 9, UIStyle.INK_SOFT))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	left_page.add_child(head)
	var frame_box := Control.new()
	frame_box.custom_minimum_size = Vector2(60, 60)
	frame_box.add_child(UIStyle.frame(AssetPaths.SLOT, 5))
	var p := UIStyle.portrait(d["race"], d["class"], Vector2(48, 48))
	p.position = Vector2(6, 6)
	p.size = Vector2(48, 48)
	frame_box.add_child(p)
	head.add_child(frame_box)
	var info := UIStyle.label("Герой дня:\n%s · %s\nЗерно: %d" % [d["race"].display_name, d["class"].display_name, d["seed"]], 8)
	head.add_child(info)
	var rules := UIStyle.label("Сегодня у всех одинаковое подземелье, тот же герой и та же добыча. "
		+ "Улучшения Святилища не действуют. Очки: этаж ×100, страж ×300, враг ×5, "
		+ "половина золота и уровень героя ×20. Попыток сколько угодно — в таблицу идёт лучшее.", 7, UIStyle.INK_SOFT)
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules.custom_minimum_size = Vector2(250, 0)
	left_page.add_child(rules)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_page.add_child(spacer)
	var go := BookPageScreen.button("Начать забег дня", func() -> void: GameState.start_daily_run(date))
	left_page.add_child(go)

	right_page.add_child(UIStyle.label("Лучшие за сегодня", 11))
	var today_list: Array = Leaderboard.top(date)
	if today_list.is_empty():
		right_page.add_child(UIStyle.label("Пока пусто — будьте первым!", 7, UIStyle.INK_SOFT))
	for i in today_list.size():
		var e: Dictionary = today_list[i]
		right_page.add_child(_row("%d." % (i + 1), "%d" % e["score"],
			"эт. %d · убито %d · %s" % [e["floor"], e["kills"], _time(int(e["time_s"]))], i == 0))
	right_page.add_child(UIStyle.label("Прошлые дни", 9, UIStyle.INK_SOFT))
	var shown := 0
	for pair in Leaderboard.best_by_day(6):
		if pair[0] == date:
			continue
		right_page.add_child(_row(String(pair[0]).substr(5), "%d" % pair[1]["score"], "эт. %d" % pair[1]["floor"], false))
		shown += 1
	if shown == 0:
		right_page.add_child(UIStyle.label("—", 7, UIStyle.INK_SOFT))
	var spacer2 := Control.new()
	spacer2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_page.add_child(spacer2)
	right_page.add_child(BookPageScreen.button("Назад", func() -> void: get_tree().change_scene_to_file(GameState.MAIN_MENU)))
	go.grab_focus()


func _row(place: String, score: String, details: String, best: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var col := UIStyle.GOOD if best else UIStyle.INK
	var a := UIStyle.label(place, 8, col)
	a.custom_minimum_size = Vector2(30, 0)
	row.add_child(a)
	var b := UIStyle.label(score, 8, col)
	b.custom_minimum_size = Vector2(44, 0)
	row.add_child(b)
	row.add_child(UIStyle.label(details, 7, UIStyle.INK_SOFT))
	return row


static func _time(sec: int) -> String:
	return "%d:%02d" % [sec / 60, sec % 60]
