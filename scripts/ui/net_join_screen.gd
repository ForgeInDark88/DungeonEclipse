extends BookPageScreen
## Join screen: finds hosted games on the LAN by broadcast, lets the player
## pick a hero, and connects. When the host starts, everyone is pulled into
## the run.

const FIND_TIME := 3.0

var _servers: ItemList
var _status: Label
var _race_buttons: Array[Button] = []
var _class_buttons: Array[Button] = []
var _female := false
var _race: RaceData
var _cls: ClassData
var _find_left := FIND_TIME


func _ready() -> void:
	build_book(Vector2(560, 300))
	AudioManager.play_music(&"menu")
	left_page.add_child(UIStyle.label("Присоединиться (LAN)", 11))
	left_page.add_child(UIStyle.label("Игры в сети:", 9, UIStyle.INK_SOFT))
	_servers = ItemList.new()
	_servers.custom_minimum_size = Vector2(230, 90)
	_servers.add_theme_font_size_override("font_size", 8)
	left_page.add_child(_servers)
	_status = UIStyle.label("Ищем хостов...", 8)
	left_page.add_child(_status)

	right_page.add_child(UIStyle.label("Ваш герой", 10))
	var race_row := HBoxContainer.new()
	right_page.add_child(race_row)
	var race_group := ButtonGroup.new()
	for r in ItemDatabase.races:
		if not MetaProgress.is_unlocked(r):
			continue
		var b := _toggle(r.display_name, race_group)
		b.pressed.connect(func() -> void: _race = r)
		race_row.add_child(b)
		_race_buttons.append(b)
	var class_row := HBoxContainer.new()
	right_page.add_child(class_row)
	var class_group := ButtonGroup.new()
	for c in ItemDatabase.classes:
		if not MetaProgress.is_unlocked(c):
			continue
		var b := _toggle(c.display_name, class_group)
		b.pressed.connect(func() -> void: _cls = c)
		class_row.add_child(b)
		_class_buttons.append(b)
	var sex_row := HBoxContainer.new()
	right_page.add_child(sex_row)
	var sex_group := ButtonGroup.new()
	var male := _toggle("Мужчина", sex_group)
	var female := _toggle("Женщина", sex_group)
	male.button_pressed = true
	female.pressed.connect(func() -> void: _female = true)
	sex_row.add_child(male)
	sex_row.add_child(female)
	if not _race_buttons.is_empty():
		_race_buttons[0].button_pressed = true
		_race = ItemDatabase.races[0]
	if not _class_buttons.is_empty():
		_class_buttons[0].button_pressed = true
		_cls = ItemDatabase.classes[0]

	right_page.add_child(BookPageScreen.button("Подключиться", _join))
	right_page.add_child(BookPageScreen.button("Обновить список", func() -> void:
		Net.start_discovery(true)
		_find_left = FIND_TIME))
	right_page.add_child(BookPageScreen.button("Назад", func() -> void:
		Net.start_discovery(false)
		Net.leave()
		get_tree().change_scene_to_file(GameState.MAIN_MENU)))

	Net.start_discovery(true)
	multiplayer.connected_to_server.connect(func() -> void:
		_status.text = "Подключено! Ждём, пока хост начнёт забег...")
		AudioManager.play_ui(&"ui_book_open"))


func _process(delta: float) -> void:
	if not Net._discovering:
		return
	_find_left -= delta
	if _find_left <= 0.0:
		_find_left = 1.5
		_refresh_servers()


func _refresh_servers() -> void:
	_servers.clear()
	for s in Net.discovered():
		_servers.add_item("Хост: %s — игроков: %d" % [s["names"], s["count"]])
	if _servers.item_count == 0:
		_status.text = "Игр не найдено. Хост должен нажать «Создать игру»."


func _join() -> void:
	if _servers.item_count == 0:
		_status.text = "Сначала найдите игру в списке"
		return
	var picked := _servers.get_selected_items()
	var idx := picked[0] if not picked.is_empty() else 0
	var ip: String = Net.discovered()[idx]["ip"]
	Net.my_info = {"name": "Игрок-%d" % (randi() % 90 + 10),
			"race": _race.id, "cls": _cls.id, "female": _female}
	if not Net.join_game(ip):
		_status.text = "Не удалось подключиться"


func _toggle(text: String, group: ButtonGroup) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.add_theme_font_size_override("font_size", 8)
	b.pressed.connect(func() -> void: AudioManager.play_ui(&"ui_click"))
	return b


func _exit_tree() -> void:
	Net.start_discovery(false)
