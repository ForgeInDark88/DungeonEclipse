extends BookPageScreen
## Host lobby: open the LAN game, see who joined, then pick a hero and start.

var _list: Label
var _name_edit: LineEdit
var _status: Label


func _ready() -> void:
	build_book(Vector2(560, 300))
	AudioManager.play_music(&"menu")
	left_page.add_child(UIStyle.label(tr("Игра по сети — хост"), 11))
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	name_row.add_child(UIStyle.label(tr("Ник:"), 8))
	_name_edit = LineEdit.new()
	_name_edit.text = SaveManager.last_name
	_name_edit.placeholder_text = tr("Ваш ник")
	_name_edit.custom_minimum_size = Vector2(140, 0)
	_name_edit.max_length = 16
	name_row.add_child(_name_edit)
	left_page.add_child(name_row)
	_status = UIStyle.label("", 8)
	left_page.add_child(_status)
	left_page.add_child(UIStyle.label(tr("Игроки в лобби:"), 9, UIStyle.INK_SOFT))
	_list = UIStyle.label("", 8)
	left_page.add_child(_list)

	var ip := _local_ip()
	right_page.add_child(UIStyle.label(tr("Друзья находят игру сами через «Присоединиться»"), 7, UIStyle.INK_SOFT))
	if ip != "":
		right_page.add_child(UIStyle.label(tr("Ваш адрес: %s (порт %d)") % [ip, Net.GAME_PORT], 7, UIStyle.INK_SOFT))
	var hint := UIStyle.label(tr("До 4 игроков. Враги становятся сильнее за каждого героя в отряде."), 7, UIStyle.INK_SOFT)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(220, 0)
	right_page.add_child(hint)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	right_page.add_child(buttons)
	var create := BookPageScreen.button(tr("Создать игру"), func() -> void:
		SaveManager.last_name = _name_edit.text.strip_edges()
		SaveManager.save_settings()
		Net.my_info["name"] = SaveManager.last_name if SaveManager.last_name != "" else tr("Хост")
		if Net.host_game():
			_status.text = tr("Игра открыта. Ждём друзей...")
			_refresh()
		else:
			_status.text = tr("Не удалось открыть порт (занят?)"))
	buttons.add_child(create)
	var start := BookPageScreen.button(tr("Выбрать героя и начать"), func() -> void:
		if Net.active and Net.is_host:
			get_tree().change_scene_to_file(GameState.CHARACTER_CREATION))
	right_page.add_child(start)
	right_page.add_child(BookPageScreen.button(tr("Назад"), func() -> void:
		Net.leave()
		get_tree().change_scene_to_file(GameState.MAIN_MENU)))

	Net.players_changed.connect(_refresh)
	if Net.active and Net.is_host:
		_status.text = tr("Игра открыта.")
	_refresh()
	create.grab_focus()


func _refresh() -> void:
	var lines: Array[String] = []
	for id in Net.players:
		lines.append("• %s" % Net.players[id].get("name", tr("Игрок")))
	_list.text = "\n".join(lines) if not lines.is_empty() else tr("(пока никто)")
	AudioManager.play_ui(&"ui_click")


func _exit_tree() -> void:
	if Net.players_changed.is_connected(_refresh):
		Net.players_changed.disconnect(_refresh)


func _local_ip() -> String:
	for a in IP.get_local_addresses():
		if a.begins_with("192.168.") or a.begins_with("10.") or a.begins_with("172."):
			return a
	return ""
