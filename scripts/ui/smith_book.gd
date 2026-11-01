class_name SmithBook
extends CanvasLayer
## Forge UI on the book. Right page: worn gear and gear in the backpack
## (click = select). Left page: the selected item and the four services —
## upgrade, enchant, smelt (backpack only), repair. Rules: Smithing.

const BOOK_SIZE := Vector2(500, 262)
const MARGIN := 15

var hero: Hero
var _sel_item: ItemData
## Backpack index of the selection (-1 = worn item).
var _sel_index := -1
var _info: RichTextLabel
var _wallet: Label
var _grid: GridContainer
var _btn_upgrade: Button
var _btn_enchant: Button
var _btn_smelt: Button
var _btn_smelt_junk: Button
var _btn_repair: Button


func _ready() -> void:
	layer = 21
	process_mode = Node.PROCESS_MODE_ALWAYS


func open(p_hero: Hero) -> void:
	hero = p_hero
	get_tree().paused = true
	_build()
	_refresh()
	AudioManager.play_ui(&"ui_book_open")


func close() -> void:
	Tooltip.hide_tip()
	AudioManager.play_ui(&"ui_book_close")
	get_tree().paused = false
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("inventory") or event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		close()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var root := Control.new()
	root.anchor_left = 0.5
	root.anchor_right = 0.5
	root.offset_left = -BOOK_SIZE.x / 2.0
	root.offset_right = BOOK_SIZE.x / 2.0
	root.offset_top = 4
	root.offset_bottom = 4 + BOOK_SIZE.y
	add_child(root)
	root.add_child(UIStyle.frame(AssetPaths.BOOK, 30, 0.5))
	var page_w := BOOK_SIZE.x / 2.0 - MARGIN - 8
	var left := VBoxContainer.new()
	left.position = Vector2(MARGIN + 4, MARGIN)
	left.size = Vector2(page_w, BOOK_SIZE.y - MARGIN * 2)
	left.add_theme_constant_override("separation", 3)
	root.add_child(left)
	var title := UIStyle.label(tr("Кузница"), 11)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(title)
	_wallet = UIStyle.label("", 7, UIStyle.INK_SOFT)
	_wallet.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_wallet.custom_minimum_size = Vector2(page_w, 0)
	left.add_child(_wallet)
	_info = RichTextLabel.new()
	_info.bbcode_enabled = true
	_info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_info.add_theme_color_override("default_color", UIStyle.INK)
	for k in ["normal_font_size", "bold_font_size", "italics_font_size"]:
		_info.add_theme_font_size_override(k, 7)
	left.add_child(_info)
	_btn_upgrade = _service(left, _do_upgrade)
	_btn_enchant = _service(left, _do_enchant)
	_btn_smelt = _service(left, _do_smelt)
	_btn_repair = _service(left, _do_repair)
	_btn_smelt_junk = _service(left, _do_smelt_junk)
	left.add_child(BookPageScreen.button(tr("Уйти"), close))

	var right := VBoxContainer.new()
	right.position = Vector2(BOOK_SIZE.x / 2.0 + 8, MARGIN)
	right.size = Vector2(page_w, BOOK_SIZE.y - MARGIN * 2)
	root.add_child(right)
	var rt := UIStyle.label(tr("Снаряжение (надетое и в рюкзаке)"), 9)
	rt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right.add_child(rt)
	_grid = GridContainer.new()
	_grid.columns = 7
	_grid.add_theme_constant_override("h_separation", 2)
	_grid.add_theme_constant_override("v_separation", 2)
	right.add_child(_grid)


func _service(parent: Control, cb: Callable) -> Button:
	var b := BookPageScreen.button("", cb)
	b.add_theme_font_size_override("font_size", 7)
	parent.add_child(b)
	return b


func _refresh() -> void:
	var ore := hero.inventory.count_of(&"iron_ore")
	var gold_ore := hero.inventory.count_of(&"gold_ore")
	var ess := hero.inventory.count_of(&"ember_essence") + hero.inventory.count_of(&"frost_essence") + hero.inventory.count_of(&"moon_crystal")
	_wallet.text = tr("Золото: %d · железная руда: %d · золотая руда: %d · эссенции: %d") % [hero.gold, ore, gold_ore, ess]
	for c in _grid.get_children():
		c.queue_free()
	for item: EquipmentItemData in hero.equipment.items.values():
		if item:
			_grid.add_child(_cell(item, -1))
	var junk := 0
	for i in hero.inventory.capacity():
		var st := hero.inventory.stack_at(i)
		if st and Smithing.is_smithable(st.item):
			_grid.add_child(_cell(st.item, i))
			if st.junk:
				junk += 1
	_show()
	_btn_smelt_junk.text = tr("Переплавить весь мусор (%d)") % junk if junk > 0 else tr("Мусор: Ctrl+ЛКМ в рюкзаке")
	_btn_smelt_junk.disabled = junk == 0


func _cell(item: ItemData, index: int) -> Control:
	var box := Control.new()
	box.custom_minimum_size = UIStyle.SLOT_SIZE
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	var frame := UIStyle.frame(AssetPaths.SLOT, 5)
	if item == _sel_item:
		frame.modulate = Color(1.4, 1.2, 0.6)
	elif index < 0:
		frame.modulate = Color(0.8, 1.0, 0.8)  # worn
	box.add_child(frame)
	var t := TextureRect.new()
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.texture = item.icon
	t.position = Vector2(4, 4)
	t.size = UIStyle.SLOT_SIZE - Vector2(8, 8)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(t)
	if item.upgrade_level > 0:
		var lv := UIStyle.outlined_label("+%d" % item.upgrade_level, 6, UIStyle.GOLD)
		lv.position = Vector2(UIStyle.SLOT_SIZE.x - 12, UIStyle.SLOT_SIZE.y - 10)
		box.add_child(lv)
	box.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_sel_item = item
			_sel_index = index
			AudioManager.play_ui(&"ui_click")
			_refresh())
	box.mouse_entered.connect(func() -> void: Tooltip.show_text(TooltipText.item(item, hero, index < 0), box))
	box.mouse_exited.connect(func() -> void: Tooltip.hide_tip(box))
	return box


func _show() -> void:
	var it := _sel_item
	if it == null:
		_info.text = tr("Выберите предмет справа.\n\nУлучшение: +15% к бонусам и +12% к урону оружия за уровень (до +5).\nЗачарование: случайный бонус, по одному на предмет.\nПереплавка: руда и немного золота.")
		for b in [_btn_upgrade, _btn_enchant, _btn_smelt, _btn_repair]:
			b.text = "—"
			b.disabled = true
		return
	_info.text = TooltipText.item(it, hero, _sel_index < 0)
	if it.upgrade_level >= Smithing.MAX_UPGRADE:
		_btn_upgrade.text = tr("Улучшение: максимум")
		_btn_upgrade.disabled = true
	else:
		var uc := Smithing.upgrade_cost(it)
		_btn_upgrade.text = tr("Улучшить до +%d: %s") % [it.upgrade_level + 1, Smithing.cost_text(uc)]
		_btn_upgrade.disabled = not Smithing.can_afford(hero, uc)
	var ess := Smithing.available_essence(hero)
	if not it.enchant_bonuses.is_empty():
		_btn_enchant.text = tr("Уже зачаровано")
		_btn_enchant.disabled = true
	elif ess == &"":
		_btn_enchant.text = tr("Зачаровать: нужна эссенция или лунный кристалл")
		_btn_enchant.disabled = true
	else:
		var ec := Smithing.enchant_cost(it, ess)
		_btn_enchant.text = tr("Зачаровать: %s") % Smithing.cost_text(ec)
		_btn_enchant.disabled = not Smithing.can_afford(hero, ec)
	if _sel_index < 0:
		_btn_smelt.text = tr("Переплавка: сначала снимите предмет")
		_btn_smelt.disabled = true
	else:
		_btn_smelt.text = tr("Переплавить → %s") % Smithing.cost_text(Smithing.smelt_result(it))
		_btn_smelt.disabled = false
	var rc := Smithing.repair_cost(it)
	_btn_repair.text = tr("Починить: %s") % Smithing.cost_text(rc) if int(rc["gold"]) > 0 else tr("Ремонт не нужен")
	_btn_repair.disabled = int(rc["gold"]) <= 0 or not Smithing.can_afford(hero, rc)


func _done(ok: bool, text: String) -> void:
	AudioManager.play_sfx(&"dig" if ok else &"chest_locked")
	if ok:
		EventBus.message.emit(text)
	Tooltip.hide_tip()
	_refresh()


func _do_upgrade() -> void:
	var res := Smithing.upgrade(hero, _sel_item)
	if res:
		_sel_item = res
	_done(res != null, tr("Готово: %s") % (res.display_name if res else ""))


func _do_enchant() -> void:
	var res := Smithing.enchant(hero, _sel_item)
	if res:
		_sel_item = res
	_done(res != null, tr("Предмет зачарован"))


## Every smithable item marked as junk becomes ore and a little gold.
func _do_smelt_junk() -> void:
	var idx := hero.inventory.junk_indices()
	idx.reverse()
	var n := 0
	for i in idx:
		var st := hero.inventory.stack_at(i)
		if st and Smithing.is_smithable(st.item):
			while hero.inventory.stack_at(i) == st and Smithing.smelt(hero, i):
				n += 1
	_sel_item = null
	_sel_index = -1
	_done(n > 0, tr("Переплавлено предметов: %d") % n)


func _do_smelt() -> void:
	var ok := Smithing.smelt(hero, _sel_index)
	_sel_item = null
	_sel_index = -1
	_done(ok, tr("Переплавлено"))


func _do_repair() -> void:
	_done(Smithing.repair(hero, _sel_item), tr("Починено"))
