class_name SettingsBook
extends CanvasLayer
## Settings on the open book, shared by the main menu and the pause menu.
## Left page: sound, screen and game options. Right page: key rebinding
## (InputBindings). Everything is saved by SaveManager right away.

signal closed

const BOOK_SIZE := Vector2(560, 310)

var _root: Control
var _bind_buttons: Dictionary = {}  # action -> Button
var _waiting_action := ""
var _status: Label
var _fullscreen: CheckButton


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_CENTER)
	_root.offset_left = -BOOK_SIZE.x / 2.0
	_root.offset_right = BOOK_SIZE.x / 2.0
	_root.offset_top = -BOOK_SIZE.y / 2.0
	_root.offset_bottom = BOOK_SIZE.y / 2.0
	add_child(_root)
	_root.add_child(UIStyle.frame(AssetPaths.BOOK, 30, 0.5))
	var margin := 18.0
	var page := Vector2(BOOK_SIZE.x / 2.0 - margin - 10, BOOK_SIZE.y - margin * 2)
	var left := VBoxContainer.new()
	left.position = Vector2(margin + 4, margin)
	left.size = page
	left.add_theme_constant_override("separation", 3)
	_root.add_child(left)
	var right := VBoxContainer.new()
	right.position = Vector2(BOOK_SIZE.x / 2.0 + 8, margin)
	right.size = page
	right.add_theme_constant_override("separation", 3)
	_root.add_child(right)

	left.add_child(UIStyle.label("Настройки", 12))
	for entry in [["Общая", "master_volume"], ["Музыка", "music_volume"], ["Звуки", "sfx_volume"], ["Интерфейс", "ui_volume"]]:
		left.add_child(_volume_row(entry[0], entry[1]))
	left.add_child(_slider_row("Яркость", "brightness", 0.6, 1.5))
	left.add_child(_slider_row("Размер панели", "hud_scale", 0.6, 1.0))
	_fullscreen = _check("Полный экран", SaveManager.fullscreen, func(on: bool) -> void:
		SaveManager.fullscreen = on
		SaveManager.apply_settings())
	left.add_child(_fullscreen)
	# switches two per row, the page stays inside the book
	var checks := [
		_check("Свечение", SaveManager.bloom, func(on: bool) -> void:
			SaveManager.bloom = on
			get_tree().call_group("graphics_listeners", "apply_graphics")),
		_check("Тени блоков", SaveManager.block_shadows, func(on: bool) -> void:
			SaveManager.block_shadows = on
			get_tree().call_group("graphics_listeners", "apply_graphics")),
		_check("Числа урона", SaveManager.show_damage_numbers, func(on: bool) -> void: SaveManager.show_damage_numbers = on),
		_check("Подсказки", SaveManager.show_hints, func(on: bool) -> void: SaveManager.show_hints = on),
	]
	for k in range(0, checks.size(), 2):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 3)
		for c: CheckButton in checks.slice(k, k + 2):
			c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(c)
		left.add_child(row)
	left.add_child(BookPageScreen.button("Показать подсказки заново", func() -> void:
		SaveManager.seen_hints.clear()
		SaveManager.save_settings()
		_status.text = "Подсказки будут показаны снова"))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(spacer)
	var done := BookPageScreen.button("Готово", close)
	left.add_child(done)

	right.add_child(UIStyle.label("Управление", 12))
	_status = UIStyle.label("Клик по клавише — переназначить. Геймпад работает всегда.", 6, UIStyle.INK_SOFT)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(page.x, 0)
	right.add_child(_status)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 1)
	scroll.add_child(list)
	for entry in InputBindings.REBINDABLE:
		var row := HBoxContainer.new()
		var l := UIStyle.label(entry[1], 7)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var action: String = entry[0]
		var b := BookPageScreen.button("", func() -> void: _start_capture(action))
		b.add_theme_font_size_override("font_size", 7)
		b.custom_minimum_size = Vector2(70, 0)
		row.add_child(b)
		var gap := Control.new()  # room for the scroll bar
		gap.custom_minimum_size = Vector2(10, 0)
		row.add_child(gap)
		list.add_child(row)
		_bind_buttons[action] = b
	right.add_child(BookPageScreen.button("Клавиши по умолчанию", func() -> void:
		InputBindings.reset_all()
		SaveManager.save_settings()
		_refresh_bindings()
		_status.text = "Клавиши сброшены"))
	_refresh_bindings()
	done.grab_focus()


func _volume_row(text: String, property: String) -> Control:
	return _slider_row(text, property, 0.0, 1.0)


func _slider_row(text: String, property: String, min_v: float, max_v: float) -> Control:
	var row := HBoxContainer.new()
	var l := UIStyle.label(text, 7)
	l.custom_minimum_size = Vector2(60, 0)
	row.add_child(l)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
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


func _check(text: String, value: bool, on_toggle: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = value
	c.add_theme_font_size_override("font_size", 8)
	c.add_theme_color_override("font_color", UIStyle.INK)
	c.add_theme_color_override("font_pressed_color", UIStyle.INK)
	c.add_theme_color_override("font_hover_color", UIStyle.INK_SOFT)
	c.toggled.connect(func(on: bool) -> void:
		on_toggle.call(on)
		SaveManager.save_settings()
		AudioManager.play_ui(&"ui_click"))
	return c


func _refresh_bindings() -> void:
	for action: String in _bind_buttons:
		var b: Button = _bind_buttons[action]
		var names: Array[String] = []
		for ev in InputBindings.keyboard_events(action):
			names.append(InputBindings.event_text(ev))
		b.text = " / ".join(names) if not names.is_empty() else "—"


func _start_capture(action: String) -> void:
	_waiting_action = action
	_refresh_bindings()
	(_bind_buttons[action] as Button).text = "..."
	_status.text = "Нажмите клавишу или кнопку мыши (Esc — отмена)"


func _input(event: InputEvent) -> void:
	if _waiting_action == "":
		if event.is_action_pressed("pause"):
			close()
			get_viewport().set_input_as_handled()
		return
	var key := event as InputEventKey
	var mouse := event as InputEventMouseButton
	if (key == null or not key.pressed or key.echo) and (mouse == null or not mouse.pressed):
		return
	get_viewport().set_input_as_handled()
	if key and key.physical_keycode == KEY_ESCAPE:
		_status.text = "Отменено"
	else:
		var ev: InputEvent
		if key:
			ev = InputEventKey.new()
			(ev as InputEventKey).physical_keycode = key.physical_keycode if key.physical_keycode != 0 else key.keycode
		else:
			ev = InputEventMouseButton.new()
			(ev as InputEventMouseButton).button_index = mouse.button_index
		rebind(_waiting_action, ev)
	_waiting_action = ""
	_refresh_bindings()


## Also used by tests.
func rebind(action: String, ev: InputEvent) -> void:
	InputBindings.rebind(action, ev)
	SaveManager.save_settings()
	_status.text = "%s: %s" % [_label_of(action), InputBindings.event_text(ev)]
	AudioManager.play_ui(&"ui_equip")


func _label_of(action: String) -> String:
	for entry in InputBindings.REBINDABLE:
		if entry[0] == action:
			return entry[1]
	return action


func close() -> void:
	if _waiting_action != "":
		return
	closed.emit()
	queue_free()
