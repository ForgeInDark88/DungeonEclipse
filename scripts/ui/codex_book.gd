extends BookPageScreen
## "Летопись" (main menu): achievements, bestiary and item encyclopedia.
## Left page: tabs + list / grid, right page: details of the selected entry.
## Entries open up as they are met in runs (Codex autoload).

enum Tab { ACHIEVEMENTS, BESTIARY, ITEMS }

const UNKNOWN := "???"

var _tab: Tab = Tab.ACHIEVEMENTS
var _tab_buttons: Array[Button] = []
var _summary: Label
var _list: Container
var _scroll: ScrollContainer
var _detail_icon: TextureRect
var _detail_title: Label
var _detail_text: RichTextLabel


func _ready() -> void:
	build_book(Vector2(580, 320))
	AudioManager.play_music(&"menu")
	left_page.add_theme_constant_override("separation", 3)
	right_page.add_theme_constant_override("separation", 3)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 3)
	left_page.add_child(tabs)
	var group := ButtonGroup.new()
	for entry in [[Tab.ACHIEVEMENTS, "Достижения"], [Tab.BESTIARY, "Бестиарий"], [Tab.ITEMS, "Предметы"]]:
		var b := BookPageScreen.button(entry[1], func() -> void: select_tab(entry[0]))
		b.toggle_mode = true
		b.button_group = group
		b.add_theme_font_size_override("font_size", 8)
		tabs.add_child(b)
		_tab_buttons.append(b)
	_summary = UIStyle.label("", 7, UIStyle.INK_SOFT)
	left_page.add_child(_summary)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_page.add_child(_scroll)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	right_page.add_child(head)
	var frame_box := Control.new()
	frame_box.custom_minimum_size = Vector2(52, 52)
	frame_box.add_child(UIStyle.frame(AssetPaths.SLOT, 5))
	_detail_icon = TextureRect.new()
	_detail_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_icon.position = Vector2(6, 6)
	_detail_icon.size = Vector2(40, 40)
	_detail_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	frame_box.add_child(_detail_icon)
	head.add_child(frame_box)
	_detail_title = UIStyle.label("", 11)
	_detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_title.custom_minimum_size = Vector2(190, 0)
	_detail_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_detail_title)
	_detail_text = RichTextLabel.new()
	_detail_text.bbcode_enabled = true
	_detail_text.fit_content = false
	_detail_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_text.add_theme_color_override("default_color", UIStyle.INK)
	_detail_text.add_theme_font_size_override("normal_font_size", 7)
	_detail_text.add_theme_font_size_override("bold_font_size", 7)
	_detail_text.add_theme_font_size_override("italics_font_size", 7)
	right_page.add_child(_detail_text)
	var back := BookPageScreen.button("Назад", func() -> void: get_tree().change_scene_to_file(GameState.MAIN_MENU))
	right_page.add_child(back)

	_tab_buttons[0].button_pressed = true
	select_tab(Tab.ACHIEVEMENTS)
	back.grab_focus()


func select_tab(tab: Tab) -> void:
	_tab = tab
	if _list:
		_list.queue_free()
	_show_detail(null, "", "")
	match tab:
		Tab.ACHIEVEMENTS:
			_build_achievements()
		Tab.BESTIARY:
			_build_bestiary()
		Tab.ITEMS:
			_build_items()


func _show_detail(icon: Texture2D, title: String, bbcode: String, dark := false) -> void:
	_detail_icon.texture = icon
	_detail_icon.modulate = Color(0, 0, 0, 0.6) if dark else Color.WHITE
	_detail_title.text = title
	_detail_text.text = bbcode if bbcode != "" else "[color=#%s]Наведите на запись, чтобы прочитать её.[/color]" % UIStyle.INK_SOFT.to_html(false)


# --- Achievements -----------------------------------------------------------

func _build_achievements() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_set_list(box)
	var done := 0
	for a in Codex.achievements:
		var got := Codex.is_achieved(a)
		if got:
			done += 1
		var secret := a.hidden and not got
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_theme_constant_override("separation", 4)
		var icon := TextureRect.new()
		icon.texture = a.icon
		icon.custom_minimum_size = Vector2(16, 16)
		icon.modulate = Color.WHITE if got else Color(0.2, 0.2, 0.2, 0.6)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
		var name_l := UIStyle.label(UNKNOWN if secret else a.display_name, 8, UIStyle.INK if got else UIStyle.INK_SOFT)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_l)
		row.add_child(UIStyle.label("готово" if got else "%d/%d" % [Codex.progress(a), a.target], 7, UIStyle.GOOD if got else UIStyle.INK_SOFT))
		var gap := Control.new()  # room for the scroll bar
		gap.custom_minimum_size = Vector2(12, 0)
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(gap)
		row.mouse_entered.connect(func() -> void: _show_achievement(a))
		box.add_child(row)
	_summary.text = "Получено %d из %d" % [done, Codex.achievements.size()]


func _show_achievement(a: AchievementData) -> void:
	var got := Codex.is_achieved(a)
	if a.hidden and not got:
		_show_detail(a.icon, UNKNOWN, "Тайное достижение. Продолжайте спускаться.", true)
		return
	var lines: Array[String] = [a.description, ""]
	lines.append("Прогресс: %d / %d" % [Codex.progress(a), a.target])
	if a.reward_shards > 0:
		lines.append("Награда: %d осколков Затмения" % a.reward_shards)
	if got:
		var t := Time.get_datetime_string_from_unix_time(int(Codex.achieved[a.id]), true)
		lines.append("[color=%s]Получено %s[/color]" % [UIStyle.GOOD_HEX, t.left(16)])
	_show_detail(a.icon, a.display_name, "\n".join(lines), not got)


# --- Bestiary ---------------------------------------------------------------

func _all_creatures() -> Array[EnemyData]:
	var list: Array[EnemyData] = []
	var sorted := ItemDatabase.enemies.duplicate()
	sorted.sort_custom(func(a: EnemyData, b: EnemyData) -> bool: return a.min_floor < b.min_floor or (a.min_floor == b.min_floor and a.max_hp < b.max_hp))
	list.assign(sorted)
	for b in ItemDatabase.bosses:
		list.append(b)
	return list


func _build_bestiary() -> void:
	var grid := _grid()
	var known := 0
	for e in _all_creatures():
		var is_known := Codex.is_enemy_known(e.id)
		if is_known:
			known += 1
		grid.add_child(_cell(creature_icon(e), not is_known, func() -> void: _show_creature(e)))
	_summary.text = "Изучено %d из %d существ" % [known, ItemDatabase.enemies.size() + ItemDatabase.bosses.size()]


## First idle frame of the creature's sheet (or its static texture).
static func creature_icon(e: EnemyData) -> Texture2D:
	if e.sheet and e.sheet_layout and e.sheet_layout.animations.has("idle"):
		var at := AtlasTexture.new()
		at.atlas = e.sheet
		var fs := e.sheet_layout.frame_size
		at.region = Rect2(0, int(e.sheet_layout.animations["idle"].get("row", 0)) * fs.y, fs.x, fs.y)
		return at
	return e.texture


func _show_creature(e: EnemyData) -> void:
	var kills := int(Codex.enemy_kills.get(e.id, 0))
	if kills <= 0:
		_show_detail(creature_icon(e), UNKNOWN, "Это существо ещё не встречалось вам в бою.\nПобедите его, чтобы узнать больше.", true)
		return
	var lines: Array[String] = []
	if e is BossData:
		lines.append("[b]%s[/b]" % (e as BossData).title)
	if e.description != "":
		lines.append("[i]%s[/i]" % e.description)
	lines.append("")
	lines.append("Побеждено: [b]%d[/b]" % kills)
	lines.append("Здоровье: %d · Урон: %d · Броня: %d" % [e.max_hp, e.damage, e.armor])
	lines.append("Повадки: %s" % ["ходит по земле", "летает", "атакует издалека"][e.behavior])
	var traits: Array[String] = []
	if e.phases_through_walls:
		traits.append("проходит сквозь стены")
	if e.ceiling_ambush:
		traits.append("нападает с потолка")
	if e.aoe_radius > 0.0:
		traits.append("бьёт по площади")
	if e.summon:
		traits.append("призывает: %s" % e.summon.display_name)
	if not traits.is_empty():
		lines.append("Особенности: " + ", ".join(traits))
	var res: Array[String] = []
	var weak: Array[String] = []
	for k in e.resistances:
		var v := float(e.resistances[k])
		if v < 0.0:
			weak.append("%s +%d%%" % [StatTypes.element_name(k), roundi(-v * 100.0)])
		else:
			res.append("%s %d%%" % [StatTypes.label(k), roundi(v * 100.0)])
	if not res.is_empty():
		lines.append("Сопротивления: " + ", ".join(res))
	if not weak.is_empty():
		lines.append("Уязвим к: " + ", ".join(weak))
	if not e.status_immunities.is_empty():
		var names: Array[String] = []
		for s in e.status_immunities:
			names.append(StatusEffects.display_name(s))
		lines.append("Иммунитет: " + ", ".join(names))
	if e is BossData:
		lines.append("Встречается: каждый %d-й этаж" % GameState.BOSS_EVERY)
	else:
		var where: Array[String] = []
		for b in e.biomes:
			where.append(_biome_name(b))
		lines.append("Встречается: с %d этажа%s" % [e.min_floor, (" (" + ", ".join(where) + ")") if not where.is_empty() else ""])
	_show_detail(creature_icon(e), e.display_name, "\n".join(lines))


func _biome_name(id: StringName) -> String:
	for b in ItemDatabase.biomes:
		if b.id == id:
			return b.display_name
	return String(id)


# --- Items ------------------------------------------------------------------

func _all_items() -> Array[ItemData]:
	var list: Array[ItemData] = []
	for item: ItemData in ItemDatabase.items.values():
		if item.currency_value <= 0:
			list.append(item)
	list.sort_custom(func(a: ItemData, b: ItemData) -> bool:
		if a.item_type != b.item_type:
			return a.item_type < b.item_type
		if a.rarity != b.rarity:
			return a.rarity < b.rarity
		return a.display_name < b.display_name)
	return list


func _build_items() -> void:
	var grid := _grid()
	var items := _all_items()
	var known := 0
	for item in items:
		var is_known := Codex.is_item_known(item.id)
		if is_known:
			known += 1
		grid.add_child(_cell(item.icon, not is_known, func() -> void: _show_item(item)))
	_summary.text = "Найдено %d из %d предметов" % [known, items.size()]


func _show_item(item: ItemData) -> void:
	var n := int(Codex.items_found.get(item.id, 0))
	if n <= 0:
		_show_detail(item.icon, UNKNOWN, "%s\nПредмет ещё не найден." % item.type_name(), true)
		return
	var text := TooltipText.item(item, null)
	text += "\n\n[color=#%s]Найдено раз: %d[/color]" % [UIStyle.INK_SOFT.to_html(false), n]
	_show_detail(item.icon, "", text)


# --- Helpers ----------------------------------------------------------------

func _set_list(c: Container) -> void:
	_list = c
	_scroll.add_child(c)


func _grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 9
	grid.add_theme_constant_override("h_separation", 1)
	grid.add_theme_constant_override("v_separation", 1)
	_set_list(grid)
	return grid


func _cell(tex: Texture2D, unknown: bool, on_hover: Callable) -> Control:
	var box := Control.new()
	box.custom_minimum_size = UIStyle.SLOT_SIZE
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.add_child(UIStyle.frame(AssetPaths.SLOT, 5))
	var t := TextureRect.new()
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE  # before size: big sprites must shrink
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture = tex
	t.position = Vector2(4, 4)
	t.size = UIStyle.SLOT_SIZE - Vector2(8, 8)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Undiscovered entries are dark silhouettes.
	t.modulate = Color(0, 0, 0, 0.55) if unknown else Color.WHITE
	box.add_child(t)
	box.mouse_entered.connect(on_hover)
	return box
