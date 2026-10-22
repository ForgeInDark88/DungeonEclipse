class_name ShopBook
extends CanvasLayer
## Merchant UI on the book: goods and services on the left page, the hero's
## backpack on the right (right click / double click sells). Game paused.

const BOOK_SIZE := Vector2(500, 262)
const MARGIN := 15

var hero: Hero
var merchant: Merchant
var _left: VBoxContainer
var _goods: GridContainer
var _gold: Label
var _repair: Button
var _heal: Button
var _inv_slots: Array[ItemSlot] = []


func _ready() -> void:
	layer = 21
	process_mode = Node.PROCESS_MODE_ALWAYS


func open(p_merchant: Merchant, p_hero: Hero) -> void:
	merchant = p_merchant
	hero = p_hero
	get_tree().paused = true
	_build()
	hero.gold_changed.connect(_on_gold)
	hero.inventory.changed.connect(_refresh_inventory)
	AudioManager.play_ui(&"ui_book_open")


func close() -> void:
	if hero.gold_changed.is_connected(_on_gold):
		hero.gold_changed.disconnect(_on_gold)
	if hero.inventory.changed.is_connected(_refresh_inventory):
		hero.inventory.changed.disconnect(_refresh_inventory)
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
	dim.offset_bottom = -InventoryBook.HUD_HEIGHT
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
	_left = VBoxContainer.new()
	_left.position = Vector2(MARGIN + 4, MARGIN)
	_left.size = Vector2(page_w, BOOK_SIZE.y - MARGIN * 2)
	_left.add_theme_constant_override("separation", 3)
	root.add_child(_left)
	var title := UIStyle.label("Лавка странствующего торговца", 10)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_left.add_child(title)
	_gold = UIStyle.label("", 8, UIStyle.INK)
	_gold.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_left.add_child(_gold)
	_goods = GridContainer.new()
	_goods.columns = 6
	_goods.add_theme_constant_override("h_separation", 6)
	_goods.add_theme_constant_override("v_separation", 2)
	_left.add_child(_goods)
	var services := HBoxContainer.new()
	services.alignment = BoxContainer.ALIGNMENT_CENTER
	services.add_theme_constant_override("separation", 4)
	_left.add_child(services)
	_repair = BookPageScreen.button("", _do_repair)
	_heal = BookPageScreen.button("", _do_heal)
	services.add_child(_repair)
	services.add_child(_heal)
	var close_btn := BookPageScreen.button("Уйти", close)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_left.add_child(close_btn)

	var right := Control.new()
	right.position = Vector2(BOOK_SIZE.x / 2.0 + 6, MARGIN)
	right.size = Vector2(page_w, BOOK_SIZE.y - MARGIN * 2)
	root.add_child(right)
	var rt := UIStyle.label("Рюкзак — ПКМ: продать", 10)
	rt.size = Vector2(page_w, 14)
	rt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right.add_child(rt)
	var grid := GridContainer.new()
	grid.columns = InventoryBook.GRID_COLUMNS
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	var grid_w := InventoryBook.GRID_COLUMNS * (UIStyle.SLOT_SIZE.x + 2) - 2
	grid.position = Vector2((page_w - grid_w) / 2.0, 20)
	right.add_child(grid)
	for i in hero.inventory.capacity():
		var s := ItemSlot.create(ItemSlot.Kind.INVENTORY, hero, i)
		s.shop = self
		grid.add_child(s)
		_inv_slots.append(s)
	_refresh_goods()
	_on_gold(hero.gold)


func _refresh_goods() -> void:
	for c in _goods.get_children():
		c.queue_free()
	for i in merchant.stock.size():
		var s := ShopSlot.new()
		s.item = merchant.stock[i]
		s.index = i
		s.hero = hero
		s.buy_requested.connect(buy)
		_goods.add_child(s)


func _refresh_inventory() -> void:
	for s in _inv_slots:
		s.refresh()


func _on_gold(gold: int) -> void:
	_gold.text = "Ваше золото: %d" % gold
	for s in _goods.get_children():
		if s is ShopSlot and not s.is_queued_for_deletion():
			s.refresh()
	var rc := Merchant.repair_cost(hero)
	_repair.text = "Починить всё — %d з." % rc if rc > 0 else "Ремонт не нужен"
	_repair.disabled = rc <= 0 or hero.gold < rc
	var hc := Merchant.heal_cost(hero)
	_heal.text = "Вылечить — %d з." % hc if hc > 0 else "Вы здоровы"
	_heal.disabled = hc <= 0 or hero.gold < hc


func buy(index: int) -> void:
	if index < 0 or index >= merchant.stock.size():
		return
	var item := merchant.stock[index]
	var price := item.buy_price()
	if hero.gold < price:
		EventBus.message.emit("Не хватает золота")
		AudioManager.play_ui(&"chest_locked")
		return
	if hero.inventory.free_space_for(item) <= 0:
		EventBus.message.emit("Рюкзак полон")
		return
	hero.spend_gold(price)
	hero.inventory.add_item(item if item.is_stackable() else ItemFactory.create(item, merchant.floor_number))
	if not item.is_stackable() and item.is_instance():
		merchant.stock.remove_at(index)  # unique item: sold out
		_refresh_goods()
	AudioManager.play_ui(&"coin")
	EventBus.item_bought.emit(item)
	Tooltip.hide_tip()


## Sells one piece from a backpack slot (the merchant keeps unique items).
func sell(index: int) -> void:
	var stack := hero.inventory.stack_at(index)
	if stack == null:
		return
	var item := stack.item
	var price := item.sell_price()
	hero.inventory.take_at(index, 1)
	hero.add_gold(price)
	if not item.is_stackable() and merchant.stock.size() < 18:
		merchant.stock.append(item)
		_refresh_goods()
	AudioManager.play_ui(&"coin")
	EventBus.message.emit("Продано: %s (+%d з.)" % [item.display_name, price])


func _do_repair() -> void:
	var cost := Merchant.repair_cost(hero)
	if cost <= 0 or not hero.spend_gold(cost):
		return
	for item: EquipmentItemData in hero.equipment.items.values():
		if item and item.has_durability and item.is_instance():
			item.durability = item.max_durability
	hero.equipment.changed.emit()
	_on_gold(hero.gold)


func _do_heal() -> void:
	var cost := Merchant.heal_cost(hero)
	if cost <= 0 or not hero.spend_gold(cost):
		return
	hero.stats.heal(hero.stats.max_hp())
	_on_gold(hero.gold)
