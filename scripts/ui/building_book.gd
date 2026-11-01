class_name BuildingBook
extends CanvasLayer
## The book of a town building. Left page: the building, its level, what
## this and the next level give, the cost and «Построить / Улучшить» (or
## what is missing). Right page: what the building does — trade, the
## smith, healing and curses, rumours and companions, potions, knowledge,
## the Sanctum, the warehouse, the hall of fame.

const SIZE := Vector2(520, 290)
const UNCURSE_PRICE := 60
const RUMOUR_PRICE := 30
const COMPANION_PRICE := 80

var building: TownBuilding
var data: BuildingData
var _left: VBoxContainer
var _right: VBoxContainer
var _status: Label
var _paused_here := false
var _view := &"main"


func _ready() -> void:
	layer = 22
	process_mode = Node.PROCESS_MODE_ALWAYS


func open(p_building: TownBuilding) -> void:
	building = p_building
	data = building.data
	if not get_tree().paused:
		get_tree().paused = true
		_paused_here = true
	_build()
	_refresh()


func close() -> void:
	if _paused_here:
		get_tree().paused = false
	AudioManager.play_ui(&"ui_book_close")
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		if _view != &"main":
			_view = &"main"
			_refresh()
		else:
			close()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_CENTER)
	root.offset_left = -SIZE.x / 2.0
	root.offset_right = SIZE.x / 2.0
	root.offset_top = -SIZE.y / 2.0
	root.offset_bottom = SIZE.y / 2.0
	add_child(root)
	root.add_child(UIStyle.frame(AssetPaths.BOOK, 30, 0.5))
	var page := Vector2(SIZE.x / 2.0 - 30, SIZE.y - 36)
	_left = VBoxContainer.new()
	_left.position = Vector2(22, 18)
	_left.size = page
	_left.add_theme_constant_override("separation", 3)
	root.add_child(_left)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(SIZE.x / 2.0 + 8, 18)
	scroll.size = page
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_right = VBoxContainer.new()
	_right.custom_minimum_size = Vector2(page.x - 10, 0)
	_right.add_theme_constant_override("separation", 3)
	scroll.add_child(_right)


func _clear(box: Control) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _refresh() -> void:
	_clear(_left)
	_clear(_right)
	_fill_left()
	match _view:
		&"warehouse":
			_fill_warehouse()
		&"guest_safe":
			_fill_guest_safe()
		&"hall":
			_fill_hall()
		&"companions":
			_fill_companions()
		_:
			_fill_actions()
	_focus_first.call_deferred()


func _focus_first() -> void:
	for box in [_right, _left]:
		for c in box.get_children():
			if c is Button and not (c as Button).disabled:
				(c as Button).grab_focus()
				return


# ------------------------------------------------------------- left page
func _fill_left() -> void:
	var lvl := Buildings.level(data.id)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	var icon := TextureRect.new()
	icon.texture = AssetPaths.building_icon(data.id)
	icon.custom_minimum_size = Vector2(16, 16)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	head.add_child(icon)
	head.add_child(UIStyle.label(data.display_name, 12))
	_left.add_child(head)
	var stars := "★".repeat(lvl) + "☆".repeat(data.max_level - lvl)
	_left.add_child(UIStyle.label(stars if lvl > 0 else tr("Руины"), 9, UIStyle.INK_SOFT))
	_left.add_child(_wrap(data.description, 7))
	if lvl > 0 and lvl <= data.level_texts.size():
		_left.add_child(_wrap(tr("Сейчас: %s") % data.level_texts[lvl - 1], 7))
	if lvl < data.max_level:
		var next := lvl + 1
		var what := data.level_texts[next - 1] if next <= data.level_texts.size() else ""
		_left.add_child(_wrap(tr("Уровень %d: %s") % [next, what], 7, UIStyle.INK_SOFT))
		_left.add_child(_wrap(tr("Цена: %s") % _cost_text(Buildings.cost(data, next)), 7))
		var reason := Buildings.block_reason(data)
		var b := BookPageScreen.button(tr("Построить") if lvl == 0 else tr("Улучшить"), _on_build)
		b.disabled = reason != ""
		_left.add_child(b)
		if reason != "":
			_left.add_child(_wrap(reason, 7, Color(0.55, 0.15, 0.1)))
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_left.add_child(fill)
	var t := GameState.town
	_left.add_child(_wrap(tr("Золото: %d · %s") % [GameState.hero.gold, TownResources.describe(t.resources) if not t.resources.is_empty() else tr("ресурсов нет")], 6, UIStyle.INK_SOFT))
	_status = UIStyle.label("", 7, UIStyle.INK_SOFT)
	_left.add_child(_status)
	_left.add_child(BookPageScreen.button(tr("Закрыть"), close))


func _cost_text(c: Dictionary) -> String:
	var parts: Array[String] = []
	if int(c.get("gold", 0)) > 0:
		parts.append(tr("%d з.") % int(c["gold"]))
	for k in c:
		if k != "gold" and int(c[k]) > 0:
			parts.append("%s %d" % [TownResources.display_name(StringName(k)), int(c[k])])
	return ", ".join(parts) if not parts.is_empty() else tr("бесплатно")


func _on_build() -> void:
	if GameFlow.is_guest():
		# the town is the world's: the host builds it (the guest pays its gold)
		if not Buildings.may_build():
			_say(tr("Строить может только хост."))
			return
		WorldNet.town_net.request_build(data.id)
		close()
		return
	if not Buildings.build(data):
		return
	WorldNet.town_net.push_town()
	GameFlow.save_town()
	building.play_built()
	for b in get_tree().get_nodes_in_group("town_buildings"):
		(b as TownBuilding).refresh()
	_refresh()
	_say(tr("%s: уровень %d!") % [data.display_name, Buildings.level(data.id)])


func _wrap(text: String, size: int, color := UIStyle.INK) -> Label:
	var l := UIStyle.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(SIZE.x / 2.0 - 40, 0)
	return l


func _say(text: String) -> void:
	if _status:
		_status.text = text


# ------------------------------------------------------------ right page
func _fill_actions() -> void:
	var lvl := Buildings.level(data.id)
	if lvl == 0:
		_right.add_child(_wrap(tr("Здесь пока руины. Постройте здание, чтобы им пользоваться."), 7, UIStyle.INK_SOFT))
		return
	var hero := GameState.hero
	if GameFlow.is_guest() and data.action in [&"sanctum", &"hall", &"quests"]:
		_right.add_child(_wrap(tr("Этим зданием мира распоряжается хост."), 7, UIStyle.INK_SOFT))
		return
	match data.action:
		&"shop":
			_action(tr("Торговать"), func() -> void: _open_merchant(_town_merchant()))
		&"smith":
			_action(tr("Кузня: ремонт, улучшение, зачарование"), func() -> void:
				close()
				EventBus.smith_requested.emit(building, _player()))
		&"quests":
			_action(tr("Задания гильдии"), func() -> void:
				close()
				EventBus.quest_requested.emit(building, _player()))
		&"temple":
			var heal := Merchant.heal_cost(hero)
			_action(tr("Лечение (бесплатно)") if heal > 0 else tr("Вы здоровы"), func() -> void:
				hero.stats.heal(hero.stats.max_hp())
				hero.stats.mana = hero.stats.max_mana()
				hero.stats.mana_changed.emit(hero.stats.mana, hero.stats.max_mana())
				_say(tr("Раны затянулись."))
				_refresh()).disabled = heal <= 0
			var cursed := _cursed_items()
			var price := UNCURSE_PRICE * cursed.size()
			_action(tr("Снять проклятия: %d шт. (%d з.)") % [cursed.size(), price], func() -> void:
				if hero.spend_gold(price):
					for it in cursed:
						it.lift_curse()
					hero.equipment.changed.emit()
					hero.inventory.changed.emit()
					_say(tr("Проклятия сняты."))
				_refresh()).disabled = cursed.is_empty() or hero.gold < price
			if lvl >= 2:
				var scroll := ItemDatabase.get_item(&"revive_scroll")
				if scroll:
					_action(tr("Свиток воскрешения (%d з.)") % scroll.shop_price(), func() -> void:
						if hero.inventory.free_space_for(scroll) > 0 and hero.spend_gold(scroll.shop_price()):
							hero.inventory.add_item(scroll, 1)
							_say(tr("Свиток в сумке."))
						_refresh()).disabled = hero.gold < scroll.shop_price()
		&"tavern":
			var price := 0 if lvl >= 3 else RUMOUR_PRICE
			var bought: bool = GameState.town.flag("rumours", false)
			_action(tr("Слухи уже собраны") if bought else tr("Послушать слухи (%d з.)") % price, func() -> void:
				if hero.spend_gold(price) or price == 0:
					GameState.town.set_flag("rumours")
					_say(tr("Все знаки на карте следующего похода будут понятны."))
				_refresh()).disabled = bought or hero.gold < price
			if lvl >= 2:
				_action(tr("Нанять спутника на поход"), func() -> void:
					_view = &"companions"
					_refresh())
		&"alchemist":
			_action(tr("Лавка зелий"), func() -> void: _open_merchant(_alchemist_merchant()))
		&"library":
			_action(tr("Бестиарий и находки"), func() -> void:
				close()
				GameFlow.change_scene(GameState.CODEX, GameFlow.State.TOWN))
			_action(tr("Летопись"), func() -> void:
				close()
				var cb := ChroniclerBook.new()
				get_tree().current_scene.add_child(cb)
				cb.open())
			if lvl >= 2:
				var unid := _unidentified()
				_action(tr("Опознать всё (%d)") % unid.size(), func() -> void:
					for it in unid:
						it.identify()
					hero.inventory.changed.emit()
					_say(tr("Всё опознано."))
					_refresh()).disabled = unid.is_empty()
			_right.add_child(_wrap(_blueprints_text(), 7, UIStyle.INK_SOFT))
		&"sanctum":
			_action(tr("Войти в святилище (%d оск.)") % MetaProgress.shards, func() -> void:
				close()
				GameFlow.change_scene(GameState.SANCTUM, GameFlow.State.TOWN))
		&"warehouse":
			if GameFlow.is_guest():
				_action(tr("Мой сейф"), func() -> void:
					_view = &"guest_safe"
					WorldNet.town_net.request_safe())
			else:
				_action(tr("Открыть склад (%d / %d)") % [GameState.town.warehouse.size(), Buildings.warehouse_slots()], func() -> void:
					_view = &"warehouse"
					_refresh())
		&"hall":
			_action(tr("Трофеи (%d / %d)") % [GameState.town.trophies.size(), Buildings.trophy_slots()], func() -> void:
				_view = &"hall"
				_refresh())
		&"scout":
			_right.add_child(_wrap(tr("На карте похода типы мест видны на %d шагов вперёд.") % (3 + lvl), 7))


func _action(text: String, cb: Callable) -> Button:
	var b := BookPageScreen.button(text, cb)
	b.add_theme_font_size_override("font_size", 8)
	_right.add_child(b)
	return b


func _player() -> Player:
	return get_tree().get_first_node_in_group("player") as Player


func _town_merchant() -> Merchant:
	return get_tree().get_first_node_in_group("merchants") as Merchant


func _open_merchant(m: Merchant) -> void:
	if m == null:
		return
	close()
	EventBus.shop_requested.emit(m, _player())


## The alchemist's counter: a hidden merchant with potions only.
func _alchemist_merchant() -> Merchant:
	var m := building.get_node_or_null("Counter") as Merchant
	if m == null:
		m = (load("res://scenes/npc/merchant.tscn") as PackedScene).instantiate()
		m.name = "Counter"
		m.visible = false
		building.add_child(m)
		m.remove_from_group("interactable")
		m.remove_from_group("merchants")
		m.stock.clear()
		var lvl := Buildings.level(&"alchemist")
		for it: ItemData in ItemDatabase.items.values():
			var u := it as UsableItemData
			if u == null:
				continue
			var sid := String(it.id)
			if ("potion" in sid or "elixir" in sid or sid == "antidote" or "mana" in sid) and (it.rarity <= ItemData.Rarity.RARE or lvl >= 2):
				m.stock.append(it)
	return m


func _cursed_items() -> Array[ItemData]:
	var out: Array[ItemData] = []
	var hero := GameState.hero
	for it: ItemData in hero.equipment.items.values():
		if it and it.cursed:
			out.append(it)
	for st in hero.inventory.slots:
		if st and st.item and st.item.cursed:
			out.append(st.item)
	return out


func _unidentified() -> Array[ItemData]:
	var out: Array[ItemData] = []
	for st in GameState.hero.inventory.slots:
		if st and st.item and st.item.unidentified:
			out.append(st.item)
	return out


func _blueprints_text() -> String:
	var t := GameState.town
	var names: Array[String] = []
	for id in t.blueprints:
		var b := ItemDatabase.building(id)
		names.append(b.display_name if b else String(id))
	return tr("Чертежи: %s") % (", ".join(names) if not names.is_empty() else tr("пока нет (их хранят стражи и логова)"))


# -------------------------------------------------------------- sub views
## The warehouse: items here never leave town and survive the hero's death.
func _fill_warehouse() -> void:
	var t := GameState.town
	var hero := GameState.hero
	var cap := Buildings.warehouse_slots()
	_right.add_child(UIStyle.label(tr("Склад: %d / %d") % [t.warehouse.size(), cap], 9))
	for i in t.warehouse.size():
		var st := RunCodec._item_from_dict(t.warehouse[i])
		if st == null:
			continue
		_item_row(st, tr("Взять"), func() -> void:
			if hero.inventory.free_space_for(st.item) >= st.count:
				hero.inventory.add_item(st.item, st.count)
				t.warehouse.remove_at(i)
				GameFlow.save_town()
			else:
				_say(tr("Сумка полна."))
			_refresh())
	_right.add_child(UIStyle.label(tr("В сумке:"), 8, UIStyle.INK_SOFT))
	for idx in hero.inventory.slots.size():
		var st2: ItemStack = hero.inventory.slots[idx]
		if st2 == null or st2.item == null:
			continue
		var b := _item_row(st2, tr("На склад"), func() -> void:
			var taken := hero.inventory.take_at(idx)
			if taken:
				t.warehouse.append(RunCodec._item_to_dict(taken))
				GameFlow.save_town()
			_refresh())
		b.disabled = t.warehouse.size() >= cap
	_right.add_child(BookPageScreen.button(tr("Назад"), func() -> void:
		_view = &"main"
		_refresh()))


## A guest's personal safe (kept by the host in the guest's profile).
func _fill_guest_safe() -> void:
	var hero := GameState.hero
	var tn: Node = WorldNet.town_net
	if not tn.safe_changed.is_connected(_on_safe):
		tn.safe_changed.connect(_on_safe)
	var items: Array = tn.safe_cache
	_right.add_child(UIStyle.label(tr("Мой сейф: %d / %d") % [items.size(), Buildings.warehouse_slots()], 9))
	for i in items.size():
		var st := RunCodec._item_from_dict(items[i])
		if st:
			_item_row(st, tr("Взять"), func() -> void: tn.take(i))
	_right.add_child(UIStyle.label(tr("В сумке:"), 8, UIStyle.INK_SOFT))
	for idx in hero.inventory.slots.size():
		var st2: ItemStack = hero.inventory.slots[idx]
		if st2 == null or st2.item == null:
			continue
		var b := _item_row(st2, tr("В сейф"), func() -> void:
			var taken := hero.inventory.take_at(idx)
			if taken:
				tn.put(taken))
		b.disabled = items.size() >= Buildings.warehouse_slots()
	_right.add_child(BookPageScreen.button(tr("Назад"), func() -> void:
		_view = &"main"
		_refresh()))


func _on_safe(_items: Array, _cap: int) -> void:
	if is_inside_tree() and _view == &"guest_safe":
		_refresh()


## The hall of fame: rare finds on display strengthen every expedition.
func _fill_hall() -> void:
	var t := GameState.town
	var hero := GameState.hero
	var cap := Buildings.trophy_slots()
	_right.add_child(UIStyle.label(tr("Зал славы: %d / %d") % [t.trophies.size(), cap], 9))
	_right.add_child(_wrap(tr("Каждый трофей: +%d к здоровью и +%d к урону.") % [Buildings.TROPHY_HP, Buildings.TROPHY_DAMAGE], 7, UIStyle.INK_SOFT))
	for i in t.trophies.size():
		var st := RunCodec._item_from_dict(t.trophies[i])
		if st == null:
			continue
		_item_row(st, tr("Снять"), func() -> void:
			if hero.inventory.free_space_for(st.item) > 0:
				hero.inventory.add_item(st.item, 1)
				t.trophies.remove_at(i)
				Buildings.apply_trophies(hero)
				GameFlow.save_town()
			_refresh())
	_right.add_child(UIStyle.label(tr("Достойно витрины (редкое и лучше):"), 8, UIStyle.INK_SOFT))
	for idx in hero.inventory.slots.size():
		var st2: ItemStack = hero.inventory.slots[idx]
		if st2 == null or st2.item == null or st2.item.rarity < ItemData.Rarity.RARE or st2.item.is_stackable():
			continue
		var b := _item_row(st2, tr("Выставить"), func() -> void:
			var taken := hero.inventory.take_at(idx, 1)
			if taken:
				t.trophies.append(RunCodec._item_to_dict(taken))
				t.prosperity = Buildings.prosperity(t)
				Buildings.apply_trophies(hero)
				GameFlow.save_town()
				for tb in get_tree().get_nodes_in_group("town_buildings"):
					(tb as TownBuilding).refresh()
			_refresh())
		b.disabled = t.trophies.size() >= cap
	_right.add_child(BookPageScreen.button(tr("Назад"), func() -> void:
		_view = &"main"
		_refresh()))


## Companions for hire: a pet follows the hero for the next expedition.
func _fill_companions() -> void:
	var hero := GameState.hero
	var price := COMPANION_PRICE / 2 if Buildings.level(&"tavern") >= 3 else COMPANION_PRICE
	_right.add_child(UIStyle.label(tr("Спутники на поход"), 9))
	if GameState.pet:
		_right.add_child(_wrap(tr("С вами пойдёт: %s") % GameState.pet.display_name, 7))
	for id in ItemDatabase.pets:
		var p: PetData = ItemDatabase.pets[id]
		var b := _action(tr("%s — %d з.") % [p.display_name, price], func() -> void:
			if hero.spend_gold(price):
				GameState.set_pet(p)
				_say(tr("%s пойдёт с вами в поход.") % p.display_name)
			_refresh())
		b.disabled = hero.gold < price or GameState.pet == p
	_right.add_child(BookPageScreen.button(tr("Назад"), func() -> void:
		_view = &"main"
		_refresh()))


func _item_row(st: ItemStack, verb: String, cb: Callable) -> Button:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	var icon := TextureRect.new()
	icon.texture = st.item.icon
	icon.custom_minimum_size = Vector2(14, 14)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)
	var name := st.item.display_name + (" ×%d" % st.count if st.count > 1 else "")
	var l := UIStyle.label(name, 7, st.item.rarity_color().darkened(0.35) if st.item.rarity > 0 else UIStyle.INK)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	row.add_child(l)
	var b := BookPageScreen.button(verb, cb)
	b.add_theme_font_size_override("font_size", 7)
	row.add_child(b)
	_right.add_child(row)
	return b
