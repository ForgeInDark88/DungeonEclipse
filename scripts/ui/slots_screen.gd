class_name SlotsScreen
extends BookPageScreen
## The worlds (save slots). Left page: the slots. Right page: the chosen
## one - its miniature, name, last save, time played, region, heroes,
## prosperity, whether an expedition is under way - and what can be done:
## play / create, rename, delete (asks twice), restore from the backup.
## `mode` "load" (main menu «Загрузить»), "new" («Новая игра») or "host"
## («Хостить»: the chosen world opens for the network).

const SCENE := "res://scenes/ui/slots.tscn"

## Set before the scene opens (static: survives the scene change).
static var mode := "load"

var _selected := 1
var _slot_buttons: Array[Button] = []
var _details: VBoxContainer
var _name_edit: LineEdit
var _status: Label


func _ready() -> void:
	get_tree().paused = false
	build_book(Vector2(540, 300))
	AudioManager.play_music(&"menu")
	left_page.add_theme_constant_override("separation", 3)
	left_page.add_child(UIStyle.label(tr("Новая игра: выберите слот") if mode == "new" \
			else (tr("Хостить: выберите мир") if mode == "host" else tr("Миры")), 12))
	for n in range(1, SaveManager.SLOT_COUNT + 1):
		var b := BookPageScreen.button("", func() -> void: _select(n))
		b.add_theme_font_size_override("font_size", 8)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		left_page.add_child(b)
		_slot_buttons.append(b)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_page.add_child(fill)
	left_page.add_child(BookPageScreen.button(tr("Назад"), func() -> void:
		GameFlow.change_scene(GameState.MAIN_MENU, GameFlow.State.MAIN_MENU)))
	_details = VBoxContainer.new()
	_details.add_theme_constant_override("separation", 3)
	_details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_page.add_child(_details)
	_status = UIStyle.label("", 7, Color(0.55, 0.15, 0.1))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(book_size.x / 2.0 - 40, 0)
	right_page.add_child(_status)
	var start := SaveManager.last_slot if SaveManager.last_slot > 0 else 1
	if mode == "new" and SaveManager.free_slot() > 0:
		start = SaveManager.free_slot()
	_refresh_list()
	_select(start)


func _refresh_list() -> void:
	for i in _slot_buttons.size():
		var info := SaveManager.slot_info(i + 1)
		var text := tr("Слот %d — пусто") % (i + 1)
		if info.get("broken", false):
			text = tr("Слот %d — повреждён") % (i + 1)
		elif info["exists"]:
			text = "%d. %s · %s" % [i + 1, info["name"], _date(int(info["updated"]))]
		_slot_buttons[i].text = text


func _select(n: int) -> void:
	_selected = n
	for i in _slot_buttons.size():
		_slot_buttons[i].button_pressed = i + 1 == n
	_status.text = ""
	for c in _details.get_children():
		c.queue_free()
	var info := SaveManager.slot_info(n)
	if info.get("broken", false):
		_details.add_child(UIStyle.label(tr("Слот %d повреждён") % n, 10))
		_details.add_child(_wrap(tr("Файл мира не читается, резервной копии тоже нет или она испорчена. Игра не загрузит этот мир.")))
		_details.add_child(_button(tr("Удалить слот"), func() -> void: _confirm_delete(n)))
		return
	if not info["exists"]:
		_details.add_child(UIStyle.label(tr("Слот %d — пусто") % n, 10))
		_name_field(tr("Мир %d") % n)
		_details.add_child(_button(tr("Создать мир"), func() -> void: GameFlow.new_game(n, _name_edit.text)))
		return
	var thumb := SaveManager.slot_thumbnail(n)
	if thumb:
		var tr_ := TextureRect.new()
		tr_.texture = thumb
		tr_.custom_minimum_size = Vector2(128, 72)
		tr_.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr_.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_details.add_child(tr_)
	_details.add_child(UIStyle.label(String(info["name"]), 10))
	var secs := int(info.get("playtime", 0))
	_details.add_child(_wrap(tr("Сохранено: %s\nВремя игры: %d:%02d\nРегион: %s · %s\nГероев: %d · Процветание: %d") % [
		_date(int(info["updated"])), secs / 3600, (secs / 60) % 60, info.get("region", ""), info.get("state", ""),
		int(info.get("heroes", 1)), int(info.get("prosperity", 0))]))
	if info.get("backup", false):
		_details.add_child(_wrap(tr("Основной файл повреждён: мир загрузится из резервной копии."), Color(0.55, 0.15, 0.1)))
	if mode == "new":
		_name_field(tr("Мир %d") % n)
		_details.add_child(_button(tr("Стереть и создать новый мир"), func() -> void: _confirm_overwrite(n)))
		return
	if mode == "host":
		_host_form(n)
		return
	var play := _button(tr("Играть"), func() -> void:
		if not GameFlow.continue_game(n):
			_status.text = tr("Мир не загрузился: файл повреждён."))
	_details.add_child(play)
	play.grab_focus()
	_details.add_child(_button(tr("Играть по сети (хост)"), func() -> void:
		mode = "host"
		_select(n)))
	_name_field(String(info["name"]))
	_details.add_child(_button(tr("Переименовать"), func() -> void:
		if SaveManager.rename_slot(n, _name_edit.text):
			_refresh_list()
			_select(n)))
	_details.add_child(_button(tr("Удалить мир"), func() -> void: _confirm_delete(n)))


## Hosting the world of slot `n`: port, password, seats, LAN visibility.
func _host_form(n: int) -> void:
	var port := _labeled_edit(tr("Порт"), str(NetSettings.get_value("port")))
	var pw := _labeled_edit(tr("Пароль"), String(NetSettings.get_value("password")))
	pw.placeholder_text = tr("необязательно")
	pw.secret = true
	var seats := SpinBox.new()
	seats.min_value = 2
	seats.max_value = Net.MAX_PLAYERS
	seats.value = int(NetSettings.get_value("seats"))
	seats.prefix = tr("Игроков:")
	_details.add_child(seats)
	var lan := CheckBox.new()
	lan.text = tr("Виден в локальной сети")
	lan.button_pressed = bool(NetSettings.get_value("lan"))
	lan.add_theme_font_size_override("font_size", 8)
	lan.add_theme_color_override("font_color", UIStyle.INK)
	_details.add_child(lan)
	_details.add_child(UIStyle.label(tr("Правила сессии — в «Мультиплеер» → «Сетевые настройки» и в лобби (F1)."), 6, UIStyle.INK_SOFT))
	var go := _button(tr("Открыть мир для сети"), func() -> void:
		if not port.text.is_valid_int() or int(port.text) <= 0 or int(port.text) > 65535:
			_status.text = tr("Порт — число от 1 до 65535.")
			return
		NetSettings.set_value("port", int(port.text))
		NetSettings.set_value("password", pw.text)
		NetSettings.set_value("seats", int(seats.value))
		NetSettings.set_value("lan", lan.button_pressed)
		var err := WorldNet.host_world(n, int(port.text), pw.text, int(seats.value), lan.button_pressed, NetSettings.rules())
		if err == "load":
			_status.text = tr("Мир не загрузился: файл повреждён.")
		elif err == "port":
			_status.text = tr("Порт %s занят или недоступен.") % port.text)
	_details.add_child(go)
	go.grab_focus()


func _labeled_edit(label: String, value: String) -> LineEdit:
	var row := HBoxContainer.new()
	var l := UIStyle.label(label, 8)
	l.custom_minimum_size = Vector2(56, 0)
	row.add_child(l)
	var e := LineEdit.new()
	e.text = value
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.add_theme_font_size_override("font_size", 8)
	row.add_child(e)
	_details.add_child(row)
	return e


func _name_field(text: String) -> void:
	_name_edit = LineEdit.new()
	_name_edit.text = text
	_name_edit.max_length = 32
	_name_edit.placeholder_text = tr("Название мира")
	_name_edit.add_theme_font_size_override("font_size", 8)
	_details.add_child(_name_edit)


## A second press confirms (the button says what will happen).
func _confirm_delete(n: int) -> void:
	var b := _details.get_child(_details.get_child_count() - 1) as Button
	if b and not b.has_meta("armed"):
		b.set_meta("armed", true)
		b.text = tr("Точно удалить мир навсегда?")
		return
	SaveManager.delete_slot(n)
	_refresh_list()
	_select(n)


func _confirm_overwrite(n: int) -> void:
	var b := _details.get_child(_details.get_child_count() - 1) as Button
	if b and not b.has_meta("armed"):
		b.set_meta("armed", true)
		b.text = tr("Точно стереть «%s»?") % SaveManager.slot_info(n).get("name", "")
		return
	GameFlow.new_game(n, _name_edit.text)


func _button(text: String, cb: Callable) -> Button:
	var b := BookPageScreen.button(text, cb)
	b.add_theme_font_size_override("font_size", 8)
	return b


func _wrap(text: String, color := UIStyle.INK) -> Label:
	var l := UIStyle.label(text, 7, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(book_size.x / 2.0 - 40, 0)
	return l


func _date(unix: int) -> String:
	if unix <= 0:
		return "—"
	var d := Time.get_datetime_dict_from_unix_time(unix + int(Time.get_time_zone_from_system().get("bias", 0)) * 60)
	return "%02d.%02d.%d %02d:%02d" % [d["day"], d["month"], d["year"], d["hour"], d["minute"]]
