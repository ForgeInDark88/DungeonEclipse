extends BookPageScreen
## Join a world session. Left page: address (IP or domain), port, nickname,
## password, the worlds found on the LAN (UDP broadcast) and the status of
## the attempt (connecting, wrong version, wrong password, full, nickname
## taken, waiting for the host to bind this device). Right page: the hero
## to make if this nickname has no profile in that world yet.

const FIND_EVERY := 1.5

var _servers: ItemList
var _ip: LineEdit
var _port: LineEdit
var _nick: LineEdit
var _pass: LineEdit
var _status: Label
var _connect: Button
var _female := false
var _race: RaceData
var _cls: ClassData
var _find_left := 0.5
var _found: Array = []


func _ready() -> void:
	build_book(Vector2(560, 300))
	AudioManager.play_music(&"menu")
	left_page.add_theme_constant_override("separation", 3)
	left_page.add_child(UIStyle.label(tr("Присоединиться к миру"), 11))
	_ip = _field(tr("Адрес:"), "127.0.0.1", tr("IP или домен хоста"))
	_port = _field(tr("Порт:"), str(WorldNet.DEFAULT_PORT), "7777")
	_nick = _field(tr("Ник:"), SaveManager.last_name, tr("Ваш ник"))
	_nick.max_length = WorldNet.NICK_MAX
	_pass = _field(tr("Пароль:"), "", tr("если есть"))
	_pass.secret = true
	left_page.add_child(UIStyle.label(tr("Миры в локальной сети:"), 8, UIStyle.INK_SOFT))
	_servers = ItemList.new()
	_servers.custom_minimum_size = Vector2(230, 56)
	_servers.add_theme_font_size_override("font_size", 7)
	_servers.item_selected.connect(func(i: int) -> void:
		if i < _found.size():
			_ip.text = String(_found[i]["ip"])
			_port.text = str(int(_found[i].get("port", WorldNet.DEFAULT_PORT))))
	left_page.add_child(_servers)
	_status = UIStyle.label(tr("Ищем миры в сети…"), 7)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(230, 0)
	left_page.add_child(_status)

	right_page.add_theme_constant_override("separation", 3)
	right_page.add_child(UIStyle.label(tr("Новый герой"), 10))
	var hint := UIStyle.label(tr("Если в этом мире у вашего ника уже есть герой, вы получите его со всем снаряжением. Иначе хост создаст этого:"), 7, UIStyle.INK_SOFT)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(240, 0)
	right_page.add_child(hint)
	_row(ItemDatabase.races, func(r: RaceData) -> void: _race = r)
	_row(ItemDatabase.classes, func(c: ClassData) -> void: _cls = c)
	var sex := HBoxContainer.new()
	var sg := ButtonGroup.new()
	var m := _toggle(tr("Мужчина"), sg)
	m.button_pressed = true
	m.pressed.connect(func() -> void: _female = false)
	var f := _toggle(tr("Женщина"), sg)
	f.pressed.connect(func() -> void: _female = true)
	sex.add_child(m)
	sex.add_child(f)
	right_page.add_child(sex)
	_race = ItemDatabase.races[0]
	_cls = ItemDatabase.classes[0]
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_page.add_child(fill)
	_connect = BookPageScreen.button(tr("Подключиться"), _join)
	right_page.add_child(_connect)
	right_page.add_child(BookPageScreen.button(tr("Назад"), func() -> void:
		Net.start_discovery(false)
		if Net.active:
			Net.leave()
		WorldNet.session = false
		get_tree().change_scene_to_file(GameState.MAIN_MENU)))
	WorldNet.join_result.connect(_on_result)
	WorldNet.hero_needed.connect(func() -> void:
		_status.text = tr("Новый ник в этом мире: хост создаёт вашего героя…")
		PlayerProfiles.create_hero(_race.id, _cls.id, _female))
	Net.start_discovery(true)
	_connect.grab_focus()


func _field(label: String, value: String, placeholder: String) -> LineEdit:
	var row := HBoxContainer.new()
	var l := UIStyle.label(label, 8)
	l.custom_minimum_size = Vector2(48, 0)
	row.add_child(l)
	var e := LineEdit.new()
	e.text = value
	e.placeholder_text = placeholder
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.add_theme_font_size_override("font_size", 8)
	row.add_child(e)
	left_page.add_child(row)
	return e


func _row(list: Array, cb: Callable) -> void:
	var row := HFlowContainer.new()
	var g := ButtonGroup.new()
	var first := true
	for d in list:
		if not MetaProgress.is_unlocked(d):
			continue
		var b := _toggle(d.display_name, g)
		b.pressed.connect(func() -> void: cb.call(d))
		if first:
			b.button_pressed = true
			first = false
		row.add_child(b)
	right_page.add_child(row)


func _toggle(text: String, group: ButtonGroup) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.add_theme_font_size_override("font_size", 8)
	b.pressed.connect(func() -> void: AudioManager.play_ui(&"ui_click"))
	return b


func _process(delta: float) -> void:
	_find_left -= delta
	if _find_left <= 0.0 and Net._discovering:
		_find_left = FIND_EVERY
		_found = Net.discovered().filter(func(s: Dictionary) -> bool: return s.has("world"))
		_servers.clear()
		for s in _found:
			_servers.add_item("%s%s — %d/%d · %s" % ["🔒 " if s.get("locked", false) else "", s["world"],
					int(s["count"]), int(s["max"]), s["names"]])
		if _found.is_empty() and not WorldNet.session:
			_status.text = tr("В локальной сети миров не найдено. Введите адрес хоста вручную.")


func _join() -> void:
	var nick := WorldNet.normalize_nick(_nick.text)
	if nick == "":
		_status.text = WorldNet.fail_text("nick_bad")
		return
	SaveManager.last_name = nick
	SaveManager.save_settings()
	Net.start_discovery(false)
	_status.text = tr("Подключение к %s:%s…") % [_ip.text.strip_edges(), _port.text.strip_edges()]
	_connect.disabled = true
	if not WorldNet.join_world(_ip.text.strip_edges(), int(_port.text), nick, _pass.text):
		_connect.disabled = false


func _on_result(ok: bool, reason: String) -> void:
	if not is_inside_tree():
		return
	if reason == "pending":
		_status.text = tr("Этот ник в мире привязан к другому устройству. Ждём, подтвердит ли хост…")
		return
	_connect.disabled = false
	if ok:
		_status.text = tr("Подключено!")
	else:
		_status.text = WorldNet.fail_text(reason)
		Net.start_discovery(true)
