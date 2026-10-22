extends BookPageScreen
## Sanctum of the Eclipse: spend shards and banked gold on permanent upgrades
## (left page) and unlock races / classes (right page). Data: MetaProgress.

var _currency: Label
var _upgrade_list: VBoxContainer
var _unlock_list: VBoxContainer
var _info: Label


func _ready() -> void:
	build_book(Vector2(580, 320))
	AudioManager.play_music(&"menu")
	left_page.add_theme_constant_override("separation", 3)
	right_page.add_theme_constant_override("separation", 3)

	left_page.add_child(UIStyle.label("Святилище Затмения", 12))
	var cur_row := HBoxContainer.new()
	cur_row.add_child(_icon(AssetPaths.tex(AssetPaths.ECLIPSE_SHARD_ICON)))
	_currency = UIStyle.label("", 9)
	cur_row.add_child(_currency)
	left_page.add_child(cur_row)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_page.add_child(scroll)
	_upgrade_list = VBoxContainer.new()
	_upgrade_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_upgrade_list.add_theme_constant_override("separation", 2)
	scroll.add_child(_upgrade_list)

	right_page.add_child(UIStyle.label("Открытия", 11))
	_unlock_list = VBoxContainer.new()
	_unlock_list.add_theme_constant_override("separation", 2)
	right_page.add_child(_unlock_list)
	_info = UIStyle.label("", 7, UIStyle.INK_SOFT)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(240, 0)
	_info.text = "Осколки Затмения падают с элитных монстров и стражей. Печати Стража стоят 5 осколков. После забега осколки из рюкзака, глубина и четверть собранного золота уходят сюда."
	right_page.add_child(_info)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_page.add_child(spacer)
	var back := BookPageScreen.button("Назад", func() -> void: get_tree().change_scene_to_file(GameState.MAIN_MENU))
	right_page.add_child(back)

	MetaProgress.changed.connect(_refresh)
	_refresh()
	back.grab_focus()


func _refresh() -> void:
	_currency.text = "%d осколков   ·   %d золота в казне" % [MetaProgress.shards, MetaProgress.gold]
	for c in _upgrade_list.get_children():
		c.queue_free()
	for up in MetaProgress.upgrades:
		_upgrade_list.add_child(_upgrade_row(up))
	for c in _unlock_list.get_children():
		c.queue_free()
	var any := false
	for r in ItemDatabase.races:
		if r.unlock_shards > 0 or r.unlock_gold > 0:
			_unlock_list.add_child(_unlock_row(r, "Раса"))
			any = true
	for c in ItemDatabase.classes:
		if c.unlock_shards > 0 or c.unlock_gold > 0:
			_unlock_list.add_child(_unlock_row(c, "Класс"))
			any = true
	if not any:
		_unlock_list.add_child(UIStyle.label("Всё уже доступно", 7, UIStyle.INK_SOFT))


func _upgrade_row(up: MetaUpgradeData) -> Control:
	var lv := MetaProgress.level_of(up.id)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.add_child(_icon(up.icon))
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_child(UIStyle.label("%s  %d/%d" % [up.display_name, lv, up.max_level], 8))
	var eff := up.describe(maxi(lv, 1))
	text.add_child(UIStyle.label(("Сейчас: " if lv > 0 else "Ур.1: ") + eff, 6, UIStyle.INK_SOFT))
	row.add_child(text)
	var b: Button
	if lv >= up.max_level:
		b = BookPageScreen.button("Макс.", func() -> void: pass)
		b.disabled = true
	else:
		var sc := up.shard_cost(lv + 1)
		var gc := up.gold_cost(lv + 1)
		b = BookPageScreen.button(_price(sc, gc), func() -> void: _buy(MetaProgress.buy_upgrade(up)))
		b.disabled = not MetaProgress.can_afford(sc, gc)
	b.add_theme_font_size_override("font_size", 7)
	b.custom_minimum_size = Vector2(62, 0)
	b.mouse_entered.connect(func() -> void: _info.text = "%s\n%s\nСледующий уровень: %s" % [
		up.display_name, up.description, up.describe(mini(lv + 1, up.max_level))])
	row.add_child(b)
	return row


## `what` is RaceData or ClassData.
func _unlock_row(what: Resource, kind: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var done := MetaProgress.is_unlocked(what)
	var l := UIStyle.label("%s: %s" % [kind, what.display_name], 8, UIStyle.INK if done else UIStyle.INK_SOFT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var b: Button
	if done:
		b = BookPageScreen.button("Открыто", func() -> void: pass)
		b.disabled = true
	else:
		b = BookPageScreen.button(_price(what.unlock_shards, what.unlock_gold), func() -> void: _buy(MetaProgress.unlock(what)))
		b.disabled = not MetaProgress.can_afford(what.unlock_shards, what.unlock_gold)
	b.add_theme_font_size_override("font_size", 7)
	b.custom_minimum_size = Vector2(62, 0)
	b.mouse_entered.connect(func() -> void: _info.text = "%s\n%s" % [what.display_name, what.description])
	row.add_child(b)
	return row


func _buy(ok: bool) -> void:
	AudioManager.play_ui(&"coin" if ok else &"chest_locked")


func _price(shards: int, gold: int) -> String:
	var parts: Array[String] = []
	if shards > 0:
		parts.append("%d оск." % shards)
	if gold > 0:
		parts.append("%d з." % gold)
	return " + ".join(parts) if not parts.is_empty() else "Даром"


func _icon(tex: Texture2D) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex
	t.custom_minimum_size = Vector2(16, 16)
	t.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return t
