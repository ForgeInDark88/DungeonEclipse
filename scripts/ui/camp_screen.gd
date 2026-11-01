extends BookPageScreen
## A camp on the road: the fire, a trader, the workbench — and the key
## choice of the expedition: go home with the loot, or on into the dark.
## Left page: the fire and the hero. Right page: what can be done here.

## The first rest at a fire is free (heals this share of health / mana).
const REST_HEAL := 0.45
const REST_MANA := 0.6
## More rests cost gold: base + per depth; they heal less.
const PAID_REST_HEAL := 0.3
## The trader's rare goods for eclipse shards.
const SHARD_OFFERS := 2

var _status: Label
var _hero_box: VBoxContainer
var _merchant: Merchant
var _inventory: InventoryBook
var _shard_offers: Array[ItemData] = []


func _ready() -> void:
	get_tree().paused = false
	build_book(Vector2(520, 290))
	AudioManager.play_music(&"town")
	left_page.add_theme_constant_override("separation", 4)
	right_page.add_theme_constant_override("separation", 3)
	left_page.add_child(UIStyle.label(tr("Лагерь"), 12))
	var fire := Campfire.new()
	fire.custom_minimum_size = Vector2(0, 80)
	left_page.add_child(fire)
	_hero_box = VBoxContainer.new()
	left_page.add_child(_hero_box)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_page.add_child(fill)
	_status = UIStyle.label("", 7, UIStyle.INK_SOFT)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(book_size.x / 2.0 - 40, 0)
	left_page.add_child(_status)
	# the camp's trader: goods of this depth, more with the town's shop
	_merchant = (load("res://scenes/npc/merchant.tscn") as PackedScene).instantiate()
	_merchant.floor_number = maxi(1, GameState.depth())
	_merchant.extra_rolls = Buildings.level(&"shop")
	_merchant.visible = false
	add_child(_merchant)
	_merchant.remove_from_group("interactable")
	_merchant.remove_from_group("merchants")
	_roll_shard_offers()
	_inventory = InventoryBook.new()
	add_child(_inventory)
	_inventory.setup(GameState.hero)
	_refresh()


func _refresh() -> void:
	for c in _hero_box.get_children():
		c.queue_free()
	for c in right_page.get_children():
		c.queue_free()
	var h := GameState.hero
	_hero_box.add_child(UIStyle.label(tr("Здоровье %d / %d · Мана %d / %d") % [h.stats.hp, h.stats.max_hp(), h.stats.mana, h.stats.max_mana()], 7))
	_hero_box.add_child(UIStyle.label(tr("Золото %d · Осколки %d") % [h.gold, h.inventory.count_of(MetaProgress.SHARD_ITEM)], 7))
	var res := GameState.run.resources if GameState.run else {}
	if not res.is_empty():
		var l := UIStyle.label(tr("Добыча для города: %s") % TownResources.describe(res), 7, UIStyle.INK_SOFT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(book_size.x / 2.0 - 40, 0)
		_hero_box.add_child(l)
	right_page.add_child(UIStyle.label(tr("У костра"), 10))
	var rests := int(GameState.run.loc.get("rests", 0)) if GameState.run else 0
	var price := rest_price()
	var rest := _action(tr("Отдохнуть (бесплатно)") if rests == 0 else tr("Отдохнуть ещё (%d з.)") % price, _rest)
	rest.disabled = rests > 0 and h.gold < price
	_action(tr("Торговец"), func() -> void:
		var shop := ShopBook.new()
		add_child(shop)
		shop.open(_merchant, h)
		shop.tree_exited.connect(_refresh))
	var repair := repair_price()
	_action(tr("Починить снаряжение (%d з.)") % repair if repair > 0 else tr("Снаряжение в порядке"), _repair).disabled = repair <= 0 or h.gold < repair
	_action(tr("Сумка и ремесло (I)"), func() -> void: _inventory.open())
	if not _shard_offers.is_empty():
		right_page.add_child(UIStyle.label(tr("Редкое за осколки"), 8, UIStyle.INK_SOFT))
		for it in _shard_offers:
			var cost := shard_price(it)
			var b := _action(tr("%s — %d оск.") % [it.display_name, cost], func() -> void: _buy_for_shards(it))
			b.disabled = h.inventory.count_of(MetaProgress.SHARD_ITEM) < cost or h.inventory.free_space_for(it) <= 0
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_page.add_child(fill)
	var home := _action(tr("Домой с добычей"), func() -> void: GameFlow.retreat())
	home.tooltip_text = tr("Поход закончится: всё найденное и спасённые доберутся до города.")
	var on := _action(tr("Идти дальше"), func() -> void: GameFlow.location_cleared())
	_action(tr("Сохранить и выйти"), func() -> void: GameFlow.save_and_quit())
	on.grab_focus()


func _action(text: String, cb: Callable) -> Button:
	var b := BookPageScreen.button(text, cb)
	b.add_theme_font_size_override("font_size", 8)
	right_page.add_child(b)
	return b


func rest_price() -> int:
	return 20 + 3 * maxi(1, GameState.depth())


## Gold for repairing everything worn (the smith's rates, a little dearer).
static func repair_price() -> int:
	var total := 0
	for it: ItemData in GameState.hero.equipment.items.values():
		if it:
			total += int(Smithing.repair_cost(it)["gold"])
	return ceili(total * 1.2)


static func shard_price(it: ItemData) -> int:
	return 4 + 4 * it.rarity


func _rest() -> void:
	var h := GameState.hero
	var run := GameState.run
	var rests := int(run.loc.get("rests", 0)) if run else 0
	if rests > 0 and not h.spend_gold(rest_price()):
		return
	var share := REST_HEAL if rests == 0 else PAID_REST_HEAL
	h.stats.heal(roundi(h.stats.max_hp() * share))
	h.stats.mana = mini(h.stats.max_mana(), h.stats.mana + roundi(h.stats.max_mana() * REST_MANA))
	h.stats.mana_changed.emit(h.stats.mana, h.stats.max_mana())
	if run:
		run.loc["rests"] = rests + 1
	_status.text = tr("Тепло костра возвращает силы.")
	AudioManager.play_ui(&"ui_equip")
	_refresh()


func _repair() -> void:
	var h := GameState.hero
	if not h.spend_gold(repair_price()):
		return
	for it: ItemData in h.equipment.items.values():
		if it and it.has_durability and it.is_instance():
			it.durability = it.max_durability
	h.equipment.changed.emit()
	_status.text = tr("Снаряжение как новое.")
	_refresh()


## Two rare finds of this depth for eclipse shards (once per camp).
func _roll_shard_offers() -> void:
	var depth := maxi(1, GameState.depth())
	var rng := RandomNumberGenerator.new()
	rng.seed = int(GameState.location.get("seed", 0)) + 99
	for table_name in [&"chest_rare", &"chest_epic"]:
		if _shard_offers.size() >= SHARD_OFFERS:
			break
		var table := ItemDatabase.get_loot_table(table_name)
		if table == null:
			continue
		for e: Dictionary in table.roll(depth, rng):
			var it: ItemData = e["item"]
			if it.currency_value <= 0 and not it.is_stackable() and it.rarity >= ItemData.Rarity.RARE:
				_shard_offers.append(ItemFactory.create(it, depth))
				break


func _buy_for_shards(it: ItemData) -> void:
	var h := GameState.hero
	var cost := shard_price(it)
	if h.inventory.count_of(MetaProgress.SHARD_ITEM) < cost or h.inventory.free_space_for(it) <= 0:
		return
	h.inventory.remove_by_id(MetaProgress.SHARD_ITEM, cost)
	h.inventory.add_item(it, 1)
	_shard_offers.erase(it)
	EventBus.item_collected.emit(it, Vector2.ZERO)
	_status.text = tr("Куплено: %s") % it.display_name
	AudioManager.play_ui(&"pickup_epic")
	_refresh()


## A little fire: logs, a flickering flame, embers.
class Campfire extends Control:
	var _t := 0.0

	func _ready() -> void:
		var p := CPUParticles2D.new()
		p.amount = 18
		p.lifetime = 1.6
		p.preprocess = 1.6
		p.position = Vector2(110, 34)
		p.direction = Vector2.UP
		p.spread = 20.0
		p.gravity = Vector2(0, -20)
		p.initial_velocity_min = 10.0
		p.initial_velocity_max = 25.0
		p.color = Color(1.0, 0.6, 0.2, 0.8)
		add_child(p)

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var c := Vector2(110, 46)
		draw_circle(c + Vector2(0, 2), 28.0, Color(1.0, 0.6, 0.2, 0.12 + 0.04 * sin(_t * 7.0)))
		draw_line(c + Vector2(-16, 6), c + Vector2(16, -2), Color(0.4, 0.25, 0.12), 4.0)
		draw_line(c + Vector2(-16, -2), c + Vector2(16, 6), Color(0.35, 0.2, 0.1), 4.0)
		for i in 3:
			var h := 18.0 + 6.0 * sin(_t * (8.0 + i * 3.0) + i)
			var w := 9.0 - i * 2.5
			var col: Color = [Color(0.95, 0.35, 0.1), Color(1.0, 0.62, 0.15), Color(1.0, 0.9, 0.45)][i]
			draw_colored_polygon(PackedVector2Array([c + Vector2(-w, 2), c + Vector2(0, -h), c + Vector2(w, 2)]), col)
