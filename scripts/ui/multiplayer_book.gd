class_name MultiplayerBook
extends CanvasLayer
## Main menu → «Мультиплеер». Left page: host / join and «Мои профили» (the
## default nickname, this computer's token and its reset, my heroes in other
## people's worlds). Right page: the network settings, the defaults of every
## session I host (NetSettings). Everything is saved right away.

signal closed

const BOOK_SIZE := Vector2(560, 310)

var _left: VBoxContainer
var _right: VBoxContainer
var _token_label: Label
var _reset: Button
var _reset_armed := false


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_CENTER)
	root.offset_left = -BOOK_SIZE.x / 2.0
	root.offset_right = BOOK_SIZE.x / 2.0
	root.offset_top = -BOOK_SIZE.y / 2.0
	root.offset_bottom = BOOK_SIZE.y / 2.0
	add_child(root)
	root.add_child(UIStyle.frame(AssetPaths.BOOK, 30, 0.5))
	var margin := 18.0
	var page := Vector2(BOOK_SIZE.x / 2.0 - margin - 10, BOOK_SIZE.y - margin * 2)
	_left = VBoxContainer.new()
	_left.position = Vector2(margin + 4, margin)
	_left.size = page
	_left.add_theme_constant_override("separation", 3)
	root.add_child(_left)
	_right = VBoxContainer.new()
	_right.position = Vector2(BOOK_SIZE.x / 2.0 + 8, margin)
	_right.size = page
	_right.add_theme_constant_override("separation", 3)
	root.add_child(_right)
	_build_left()
	_build_right()
	AudioManager.play_ui(&"ui_book_open")


func _build_left() -> void:
	_left.add_child(UIStyle.label(tr("Мультиплеер"), 12))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	for entry in [[tr("Хостить"), func() -> void:
				SlotsScreen.mode = "host"
				GameFlow.change_scene(SlotsScreen.SCENE, GameFlow.State.MAIN_MENU)],
			[tr("Присоединиться"), func() -> void:
				get_tree().change_scene_to_file("res://scenes/ui/net_join.tscn")]]:
		var b := BookPageScreen.button(entry[0], entry[1])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.disabled = not Net.lan_available()
		row.add_child(b)
	_left.add_child(row)
	if not Net.lan_available():
		_left.add_child(UIStyle.label(tr("В браузерной версии кооператив недоступен: скачайте игру для Windows или Linux."), 6, UIStyle.INK_SOFT))

	_left.add_child(UIStyle.label(tr("Мои профили"), 10))
	var nick := _edit(_left, tr("Ник"), String(NetSettings.get_value("nick")) if String(NetSettings.get_value("nick")) != "" else SaveManager.last_name)
	nick.max_length = WorldNet.NICK_MAX
	nick.placeholder_text = tr("ник по умолчанию")
	nick.text_changed.connect(func(t: String) -> void: NetSettings.set_value("nick", WorldNet.normalize_nick(t)))
	_token_label = UIStyle.label("", 7, UIStyle.INK_SOFT)
	_left.add_child(_token_label)
	_show_token()
	_reset = BookPageScreen.button(tr("Сбросить токен"), _on_reset)
	_left.add_child(_reset)
	var hint := UIStyle.label(tr("Токен связывает ваши профили с этим компьютером. После сброса хосты спросят, привязать ли вас заново."), 6, UIStyle.INK_SOFT)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(230, 0)
	_left.add_child(hint)
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(230, 52)
	list.add_theme_font_size_override("font_size", 7)
	for p in NetSettings.local_profiles():
		var cls: ClassData = _find(ItemDatabase.classes, StringName(p["class"]))
		list.add_item(tr("%s — %s, ур. %d · мир «%s»") % [p["nick"], tr(cls.display_name) if cls else p["class"], p["level"], p["world"]])
	if list.item_count == 0:
		list.add_item(tr("Вы ещё не играли в чужих мирах."))
	_left.add_child(list)


func _build_right() -> void:
	_right.add_child(UIStyle.label(tr("Сетевые настройки"), 12))
	_right.add_child(UIStyle.label(tr("Для миров, которые вы хостите:"), 7, UIStyle.INK_SOFT))
	var port := _edit(_right, tr("Порт"), str(NetSettings.get_value("port")))
	port.text_changed.connect(func(t: String) -> void:
		if t.is_valid_int() and int(t) > 0 and int(t) < 65536:
			NetSettings.set_value("port", int(t)))
	var pw := _edit(_right, tr("Пароль"), String(NetSettings.get_value("password")))
	pw.placeholder_text = tr("необязательно")
	pw.secret = true
	pw.text_changed.connect(func(t: String) -> void: NetSettings.set_value("password", t))
	var seats := SpinBox.new()
	seats.min_value = 2
	seats.max_value = Net.MAX_PLAYERS
	seats.value = int(NetSettings.get_value("seats"))
	seats.prefix = tr("Игроков:")
	seats.value_changed.connect(func(v: float) -> void: NetSettings.set_value("seats", int(v)))
	_right.add_child(seats)
	var lan := CheckBox.new()
	lan.text = tr("Виден в локальной сети")
	lan.button_pressed = bool(NetSettings.get_value("lan"))
	lan.add_theme_font_size_override("font_size", 8)
	lan.add_theme_color_override("font_color", UIStyle.INK)
	lan.toggled.connect(func(on: bool) -> void: NetSettings.set_value("lan", on))
	_right.add_child(lan)
	for opt in rule_options():
		_right.add_child(_option(opt[0], opt[1], opt[2]))
	_right.add_child(UIStyle.label(tr("Правила можно менять и в лобби сессии (F1)."), 6, UIStyle.INK_SOFT))
	_right.add_child(BookPageScreen.button(tr("Закрыть"), close))


## [setting key, caption, [[value, label], ...]] for the session rules.
static func rule_options() -> Array:
	return [
		["path", TranslationServer.translate("Путь по карте"), [["vote", TranslationServer.translate("голосование")], ["host", TranslationServer.translate("решает хост")]]],
		["friendly_fire", TranslationServer.translate("Огонь по своим"), [["bombs", TranslationServer.translate("бомбы")], ["off", TranslationServer.translate("нет")], ["all", TranslationServer.translate("все")]]],
		["build_rule", TranslationServer.translate("Кто строит"), [["all", TranslationServer.translate("все")], ["host", TranslationServer.translate("только хост")]]],
	]


func _option(key: String, caption: String, values: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := UIStyle.label(caption, 8)
	l.custom_minimum_size = Vector2(90, 0)
	row.add_child(l)
	var ob := OptionButton.new()
	ob.add_theme_font_size_override("font_size", 8)
	var current := String(NetSettings.get_value(key))
	for v in values:
		ob.add_item(v[1])
		if v[0] == current:
			ob.select(ob.item_count - 1)
	ob.item_selected.connect(func(i: int) -> void: NetSettings.set_value(key, values[i][0]))
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(ob)
	return row


func _edit(parent: Control, label: String, value: String) -> LineEdit:
	var row := HBoxContainer.new()
	var l := UIStyle.label(label, 8)
	l.custom_minimum_size = Vector2(56, 0)
	row.add_child(l)
	var e := LineEdit.new()
	e.text = value
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.add_theme_font_size_override("font_size", 8)
	row.add_child(e)
	parent.add_child(row)
	return e


func _show_token() -> void:
	_token_label.text = tr("Токен этого компьютера: %s…") % PlayerProfiles.hash_token(PlayerProfiles.local_token()).left(10)


## A second press confirms: a new token, the old profiles need the hosts' yes.
func _on_reset() -> void:
	if not _reset_armed:
		_reset_armed = true
		_reset.text = tr("Точно сбросить? Нажмите ещё раз")
		return
	_reset_armed = false
	PlayerProfiles.reset_token()
	_show_token()
	_reset.text = tr("Сбросить токен")
	EventBus.message.emit(tr("Токен сброшен."))


func _find(list: Array, id: StringName) -> Resource:
	for r in list:
		if r.id == id:
			return r
	return null


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func close() -> void:
	AudioManager.play_ui(&"ui_book_close")
	closed.emit()
	queue_free()
