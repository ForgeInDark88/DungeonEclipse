extends BookPageScreen
## The end of an expedition: how it ended, the road walked (node icons),
## then line by line what it brought - kills, gold, finds, town resources,
## people saved, guardians beaten, blueprints, the Sanctum's shards, the
## town's prosperity - or, after a death, what was lost. «В город».

const ROW_DELAY := 0.28

var _rows: Array[Control] = []


func _ready() -> void:
	get_tree().paused = false
	build_book(Vector2(540, 300))
	var r := GameFlow.last_result
	var outcome: int = r.get("outcome", 0)
	AudioManager.play_sting(&"death" if outcome == RunState.Outcome.DEATH else &"victory", &"town")
	var titles := {RunState.Outcome.VICTORY: tr("Победа над Затмением!"), RunState.Outcome.RETREAT: tr("Возвращение домой"),
			RunState.Outcome.DEATH: tr("Герой пал")}
	var subtitles := {RunState.Outcome.VICTORY: tr("Дорога пройдена до конца. Свет возвращается."),
			RunState.Outcome.RETREAT: tr("Вы вернулись живым, и всё найденное — ваше."),
			RunState.Outcome.DEATH: tr("Снаряжение и добыча похода потеряны. Город, жители и склад остались.")}
	left_page.add_theme_constant_override("separation", 3)
	right_page.add_theme_constant_override("separation", 2)
	left_page.add_child(UIStyle.label(titles.get(outcome, tr("Поход окончен")), 12,
			Color(0.55, 0.12, 0.08) if outcome == RunState.Outcome.DEATH else UIStyle.INK))
	left_page.add_child(_wrap(subtitles.get(outcome, ""), 7, UIStyle.INK_SOFT))
	left_page.add_child(UIStyle.label(tr("Пройденный путь"), 8))
	left_page.add_child(_path_row(r.get("path", [])))
	var secs := int(r.get("seconds", 0))
	_row(left_page, tr("Узлов пройдено"), str(int(r.get("nodes", 0))))
	_row(left_page, tr("Глубина"), str(int(r.get("depth", 0))))
	_row(left_page, tr("Время"), "%d:%02d" % [secs / 60, secs % 60])
	_row(left_page, tr("Убито врагов"), str(int(r.get("kills", 0))))
	_row(left_page, tr("Золото"), "%+d" % int(r.get("gold", 0)))
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_page.add_child(fill)
	var go := BookPageScreen.button(tr("В город"), func() -> void: GameFlow.back_to_town())
	left_page.add_child(go)
	go.grab_focus()
	# right page: what it brought (or cost)
	right_page.add_child(UIStyle.label(tr("Итоги для города"), 10))
	if outcome == RunState.Outcome.DEATH:
		var lost: Array = r.get("lost", [])
		_line(tr("Потеряно: %s") % (", ".join(lost) if not lost.is_empty() else tr("ничего ценного")), Color(0.55, 0.15, 0.1))
	else:
		var res: Dictionary = r.get("resources", {})
		_line(tr("Ресурсы: %s") % (TownResources.describe(res) if not res.is_empty() else tr("нет")))
		for id in r.get("rescued", []):
			var n: NpcData = ItemDatabase.npcs.get(StringName(id))
			_line(tr("Новый житель: %s, %s") % [n.display_name, n.profession] if n else tr("Спасён горожанин"), Color(0.15, 0.4, 0.15))
		for id in r.get("blueprints", []):
			var b := ItemDatabase.building(StringName(id))
			_line(tr("Чертёж: %s") % (b.display_name if b else String(id)))
	var finds: Array = r.get("finds", [])
	if not finds.is_empty():
		var names: Array[String] = []
		for id in finds.slice(0, 6):
			var it := ItemDatabase.get_item(StringName(id))
			if it:
				names.append(it.display_name)
		_line(tr("Находки: %s") % ", ".join(names))
	for id in r.get("bosses", []):
		var bd := ItemDatabase.boss_by_id(StringName(id))
		_line(tr("Побеждён страж: %s") % (bd.display_name if bd else String(id)), Color(0.45, 0.2, 0.5))
	if r.get("region_opened", false):
		_line(tr("Открыт регион: %s") % String(r.get("region", "")), Color(0.45, 0.2, 0.5))
	var sanctum: Dictionary = r.get("sanctum", {})
	if not sanctum.is_empty() and (int(sanctum.get("shards", 0)) > 0 or int(sanctum.get("gold", 0)) > 0):
		_line(tr("Святилище: +%d осколков, +%d золота") % [int(sanctum["shards"]), int(sanctum["gold"])])
	var pr: Array = r.get("prosperity", [0, 0])
	_line(tr("Процветание города: %d → %d") % [int(pr[0]), int(pr[1])], UIStyle.INK_SOFT)
	_animate()


func _wrap(text: String, size: int, color := UIStyle.INK) -> Label:
	var l := UIStyle.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(book_size.x / 2.0 - 40, 0)
	return l


func _row(parent: Control, label: String, value: String) -> void:
	var row := HBoxContainer.new()
	var l := UIStyle.label(label + ":", 7, UIStyle.INK_SOFT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	row.add_child(UIStyle.label(value, 8))
	parent.add_child(row)
	_rows.append(row)


func _line(text: String, color := UIStyle.INK) -> void:
	var l := _wrap(text, 7, color)
	right_page.add_child(l)
	_rows.append(l)


## The road as a row of the nodes' icons (the last ones if it is long).
func _path_row(types: Array) -> Control:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 1)
	for t in types.slice(maxi(0, types.size() - 14)):
		var icon := TextureRect.new()
		icon.texture = AssetPaths.map_icon(StringName(t))
		icon.custom_minimum_size = Vector2(16, 16)
		row.add_child(icon)
		_rows.append(icon)
	return row


## Lines appear one after another.
func _animate() -> void:
	var tw := create_tween()
	for c in _rows:
		c.modulate.a = 0.0
		tw.tween_property(c, "modulate:a", 1.0, ROW_DELAY)
		tw.tween_callback(func() -> void: AudioManager.play_ui(&"ui_click"))
