extends BookPageScreen
## Host lobby: open the LAN game, see who joined, then pick a hero and start.

var _list: Label
var _status: Label


func _ready() -> void:
	build_book(Vector2(560, 300))
	AudioManager.play_music(&"menu")
	left_page.add_child(UIStyle.label("Игра по сети — хост", 11))
	_status = UIStyle.label("", 8)
	left_page.add_child(_status)
	left_page.add_child(UIStyle.label("Игроки в лобби:", 9, UIStyle.INK_SOFT))
	_list = UIStyle.label("", 8)
	left_page.add_child(_list)

	var ip := _local_ip()
	right_page.add_child(UIStyle.label("Друзья находят игру сами через «Присоединиться»", 7, UIStyle.INK_SOFT))
	if ip != "":
		right_page.add_child(UIStyle.label("Ваш адрес: %s (порт %d)" % [ip, Net.GAME_PORT], 7, UIStyle.INK_SOFT))
	var hint := UIStyle.label("До 4 игроков. Враги становятся сильнее за каждого героя в отряде.", 7, UIStyle.INK_SOFT)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(220, 0)
	right_page.add_child(hint)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	right_page.add_child(buttons)
	var create := BookPageScreen.button("Создать игру", func() -> void:
		if Net.host_game():
			_status.text = "Игра открыта. Ждём друзей..."
			_refresh()
		else:
			_status.text = "Не удалось открыть порт (занят?)")
	buttons.add_child(create)
	var start := BookPageScreen.button("Выбрать героя и начать", func() -> void:
		if Net.active and Net.is_host:
			get_tree().change_scene_to_file(GameState.CHARACTER_CREATION))
	right_page.add_child(start)
	right_page.add_child(BookPageScreen.button("Назад", func() -> void:
		Net.leave()
		get_tree().change_scene_to_file(GameState.MAIN_MENU)))

	Net.players_changed.connect(_refresh)
	if Net.active and Net.is_host:
		_status.text = "Игра открыта."
	_refresh()


func _refresh() -> void:
	var lines: Array[String] = []
	for id in Net.players:
		lines.append("• %s" % Net.players[id].get("name", "Игрок"))
	_list.text = "\n".join(lines) if not lines.is_empty() else "(пока никто)"
	AudioManager.play_ui(&"ui_click")


func _exit_tree() -> void:
	if Net.players_changed.is_connected(_refresh):
		Net.players_changed.disconnect(_refresh)


func _local_ip() -> String:
	for a in IP.get_local_addresses():
		if a.begins_with("192.168.") or a.begins_with("10.") or a.begins_with("172."):
			return a
	return ""
