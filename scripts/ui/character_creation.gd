extends BookPageScreen
## Hero creation: pick a race (left page) and a class, preview portrait,
## resulting stats, skills and starting kit (right page).

var _race: RaceData
var _class: ClassData
## Hero or heroine (portrait and body layer only, no effect on stats).
var _female := false
var _race_buttons: Array[Button] = []
var _class_buttons: Array[Button] = []
var _race_desc: Label
var _class_desc: Label
var _portrait_box: Control
var _name_label: Label
var _stats_label: Label
var _skills_row: HBoxContainer
var _items_row: HFlowContainer
var _difficulty: DifficultyData
var _difficulty_desc: Label


func _ready() -> void:
	build_book(Vector2(580, 320))
	AudioManager.play_music(&"menu")
	left_page.add_theme_constant_override("separation", 3)
	right_page.add_theme_constant_override("separation", 3)

	left_page.add_child(UIStyle.label("Раса", 11))
	var race_row := HBoxContainer.new()
	left_page.add_child(race_row)
	var race_group := ButtonGroup.new()
	for r in ItemDatabase.races:
		var b := _toggle(r.display_name, race_group, func() -> void: _select_race(r))
		_lock_if_needed(b, r)
		race_row.add_child(b)
		_race_buttons.append(b)
	_race_desc = _wrap_label()
	_race_desc.custom_minimum_size = Vector2(0, 58)
	left_page.add_child(_race_desc)

	left_page.add_child(UIStyle.label("Класс", 11))
	var class_row := HBoxContainer.new()
	left_page.add_child(class_row)
	var class_group := ButtonGroup.new()
	for c in ItemDatabase.classes:
		var b := _toggle(c.display_name, class_group, func() -> void: _select_class(c))
		_lock_if_needed(b, c)
		class_row.add_child(b)
		_class_buttons.append(b)
	_class_desc = _wrap_label()
	left_page.add_child(_class_desc)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	right_page.add_child(head)
	var frame_box := Control.new()
	frame_box.custom_minimum_size = Vector2(72, 72)
	frame_box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN  # stays square next to the taller text
	frame_box.add_child(UIStyle.frame(AssetPaths.SLOT, 5))
	head.add_child(frame_box)
	_portrait_box = frame_box
	var head_text := VBoxContainer.new()
	head.add_child(head_text)
	_name_label = UIStyle.label("", 11)
	head_text.add_child(_name_label)
	var sex_row := HBoxContainer.new()
	sex_row.add_theme_constant_override("separation", 4)
	head_text.add_child(sex_row)
	var sex_group := ButtonGroup.new()
	var male := _toggle("Мужчина", sex_group, func() -> void: _select_sex(false))
	var female := _toggle("Женщина", sex_group, func() -> void: _select_sex(true))
	for b in [male, female]:
		b.add_theme_font_size_override("font_size", 8)
		sex_row.add_child(b)
	male.button_pressed = true
	_stats_label = UIStyle.label("", 7)
	head_text.add_child(_stats_label)

	right_page.add_child(UIStyle.label("Навыки", 9, UIStyle.INK_SOFT))
	_skills_row = HBoxContainer.new()
	right_page.add_child(_skills_row)
	right_page.add_child(UIStyle.label("Стартовые предметы", 9, UIStyle.INK_SOFT))
	_items_row = HFlowContainer.new()
	_items_row.add_theme_constant_override("h_separation", 1)
	_items_row.add_theme_constant_override("v_separation", 1)
	right_page.add_child(_items_row)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_page.add_child(spacer)
	_build_difficulty_row()
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 8)
	right_page.add_child(buttons)
	buttons.add_child(BookPageScreen.button("Назад", func() -> void: get_tree().change_scene_to_file(GameState.MAIN_MENU)))
	var go := BookPageScreen.button("В подземелье!", func() -> void:
		SaveManager.last_difficulty = String(_difficulty.id) if _difficulty else "normal"
		SaveManager.save_settings()
		# Co-op: puppets build this hero from Net.my_info.
		if Net.active:
			Net.my_info["race"] = _race.id
			Net.my_info["cls"] = _class.id
			Net.my_info["female"] = _female
			if Net.is_host:
				Net.players[1] = Net.my_info.duplicate(true)
				Net.broadcast_players()
		GameState.start_new_run(_race, _class, -1, _female, _difficulty.id if _difficulty else &"normal")
		if Net.active and Net.is_host:
			Net.rpc_start_run(GameState.run_seed, GameState.difficulty.id if GameState.difficulty else &"normal"))
	buttons.add_child(go)

	if not _race_buttons.is_empty():
		_race_buttons[0].button_pressed = true
		_select_race(ItemDatabase.races[0])
	if not _class_buttons.is_empty():
		_class_buttons[0].button_pressed = true
		_select_class(ItemDatabase.classes[0])
	go.grab_focus()


## Difficulty: a row of toggles (data/difficulties) and the description of
## the selected one; the last choice is remembered in the settings.
func _build_difficulty_row() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	right_page.add_child(row)
	row.add_child(UIStyle.label("Сложность", 9, UIStyle.INK_SOFT))
	var group := ButtonGroup.new()
	var last := ItemDatabase.difficulty(StringName(SaveManager.last_difficulty))
	for d in ItemDatabase.difficulties:
		var b := _toggle(d.display_name, group, func() -> void: _select_difficulty(d))
		b.add_theme_font_size_override("font_size", 8)
		row.add_child(b)
		if d == last:
			b.button_pressed = true
	_difficulty_desc = _wrap_label()
	_difficulty_desc.custom_minimum_size = Vector2(240, 18)
	right_page.add_child(_difficulty_desc)
	if last:
		_select_difficulty(last)


func _select_difficulty(d: DifficultyData) -> void:
	_difficulty = d
	_difficulty_desc.text = d.description
	_difficulty_desc.add_theme_color_override("font_color", d.color.darkened(0.55))


## Races / classes not bought in the Sanctum of the Eclipse are shown but locked.
func _lock_if_needed(b: Button, what: Resource) -> void:
	if MetaProgress.is_unlocked(what):
		return
	b.disabled = true
	b.tooltip_text = "Открывается в Святилище Затмения"
	b.modulate = Color(1, 1, 1, 0.55)


func _toggle(text: String, group: ButtonGroup, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.pressed.connect(func() -> void: AudioManager.play_ui(&"ui_click"))
	b.pressed.connect(cb)
	return b


func _wrap_label() -> Label:
	var l := UIStyle.label("", 7)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(240, 0)
	return l


func _bonus_text(bonuses: Dictionary) -> String:
	var parts: Array[String] = []
	for k in bonuses:
		parts.append("%s %s" % [StatTypes.label(k), StatTypes.format_value(k, float(bonuses[k]), true)])
	return ", ".join(parts)


func _select_race(r: RaceData) -> void:
	_race = r
	_race_desc.text = "%s\nБонусы: %s" % [r.description, _bonus_text(r.stat_bonuses)]
	_refresh_preview()


func _select_sex(female: bool) -> void:
	_female = female
	_refresh_preview()


func _select_class(c: ClassData) -> void:
	_class = c
	_class_desc.text = c.description
	_refresh_preview()


func _refresh_preview() -> void:
	if _race == null or _class == null:
		return
	_name_label.text = "%s · %s" % [_race.display_name, _class.display_name]
	for child in _portrait_box.get_children():
		if not (child is PixelFrame):
			child.queue_free()
	var p := UIStyle.portrait(_race, _class, Vector2(64, 64), _female)
	p.position = Vector2(4, 4)
	p.size = Vector2(64, 64)
	_portrait_box.add_child(p)

	var s := Stats.new()
	s.setup(_race, _class)
	var lines: Array[String] = []
	for stat in StatTypes.PRIMARY:
		lines.append("%s: %s" % [StatTypes.label(stat), StatTypes.format_value(stat, s.get_value(stat))])
	lines.append("HP %d · Мана %d · Урон %d" % [s.max_hp(), s.max_mana(), roundi(s.damage())])
	_stats_label.text = "\n".join(lines)

	for child in _skills_row.get_children():
		child.queue_free()
	# With a branch tree: the starting skill of each branch, then the branch names.
	var shown := 0
	for skill in _class.skills:
		var slot: Dictionary = _class.tree_layout.get(String(skill.id), {})
		if not slot.is_empty() and int(slot.get("row", 0)) > 0:
			continue
		_skills_row.add_child(_icon_with_tip(skill.icon, TooltipText.skill(skill, 1, 0), 20))
		shown += 1
	if not _class.branch_names.is_empty():
		_skills_row.add_child(UIStyle.label("+%d в ветвях: %s" % [_class.skills.size() - shown, ", ".join(_class.branch_names)], 6, UIStyle.INK_SOFT))
	for child in _items_row.get_children():
		child.queue_free()
	for id: StringName in _class.starting_items:
		var item := ItemDatabase.get_item(id)
		if item:
			_items_row.add_child(_icon_with_tip(item.icon, TooltipText.item(item, null)))


func _icon_with_tip(tex: Texture2D, tip: String, px := 16) -> Control:
	var box := Control.new()
	box.custom_minimum_size = UIStyle.SLOT_SIZE
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.add_child(UIStyle.frame(AssetPaths.SLOT, 5))
	var t := TextureRect.new()
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE  # before the size, or a 32px texture keeps its own size
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.texture = tex
	var half := (UIStyle.SLOT_SIZE - Vector2(px, px)) / 2.0
	t.position = half
	t.size = Vector2(px, px)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(t)
	box.add_child(UIStyle.icon_border())
	box.mouse_entered.connect(func() -> void: Tooltip.show_text(tip, box))
	box.mouse_exited.connect(func() -> void: Tooltip.hide_tip(box))
	return box
