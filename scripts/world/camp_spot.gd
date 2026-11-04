class_name CampSpot
extends Area2D
## The things of a camp (CampBuilder): E uses them.
## fire / fire2 — rest (the first rest of a camp is free, then for gold; a
##   second fire of the temple heals more) and a save point;
## anvil — repair everything (the town's smithy taught the camp's smith);
## workbench — the bag and crafting (the alchemist's table);
## stash — the camp's chest: items kept there wait in every camp of this
##   expedition and come home with a living hero;
## rare — two rare finds of this depth for eclipse shards;
## board — rumours of the roads ahead;
## home — back to the town with the loot (the host decides in co-op);
## road — on along the map (the host; guests mark themselves ready).

const REST_HEAL := 0.45
const REST_MANA := 0.6
const PAID_REST_HEAL := 0.3
const FIRE2_BONUS := 0.15
const STASH_SLOTS := 12
const SPRITES := {
	&"fire": "res://assets/sprites/surface/campfire.png", &"fire2": "res://assets/sprites/surface/campfire.png",
	&"anvil": "res://assets/sprites/surface/anvil.png", &"workbench": "res://assets/sprites/surface/workbench.png",
	&"stash": "res://assets/sprites/surface/stash.png", &"rare": "res://assets/sprites/surface/rare_stall.png",
	&"board": "res://assets/sprites/town/quest_board.png", &"home": "res://assets/sprites/town/signpost.png",
	&"road": "res://assets/sprites/portals/map_exit.png",
}

var kind: StringName = &"fire"
var _menu: CanvasLayer
var _shard_offers: Array[ItemData] = []


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("camp_spots")
	if kind in [&"fire", &"fire2"]:
		add_to_group("camp_fires")
	collision_layer = 16
	collision_mask = 0
	monitoring = false
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(26, 28)
	shape.shape = rect
	shape.position = Vector2(0, -14)
	add_child(shape)
	var s := Sprite2D.new()
	s.texture = AssetPaths.tex(SPRITES.get(kind, SPRITES[&"fire"]))
	if s.texture:
		s.offset = Vector2(0, -s.texture.get_height() / 2.0)
	s.z_index = -1
	add_child(s)
	if kind in [&"fire", &"fire2"]:
		var light := PointLight2D.new()
		light.texture = AssetPaths.tex(AssetPaths.LIGHT)
		light.color = Color(1.0, 0.7, 0.4)
		light.energy = 1.1
		light.texture_scale = 1.1
		light.position = Vector2(0, -8)
		add_child(light)
		var tw := create_tween().set_loops()
		tw.tween_property(light, "energy", 1.3, 0.4)
		tw.tween_property(light, "energy", 0.95, 0.5)
	if kind == &"rare":
		_roll_shard_offers()


func can_interact() -> bool:
	return true


func get_prompt() -> String:
	var h: Hero = GameState.hero
	match kind:
		&"fire", &"fire2":
			return tr("Отдохнуть у костра (бесплатно)") if _rests() == 0 else tr("Отдохнуть ещё (%d з.)") % rest_price()
		&"anvil":
			var p := repair_price()
			return tr("Наковальня: починить всё (%d з.)") % p if p > 0 else tr("Наковальня: снаряжение в порядке")
		&"workbench":
			return tr("Верстак: сумка и ремесло")
		&"stash":
			return tr("Сундук лагеря (%d / %d)") % [_stash().size(), STASH_SLOTS]
		&"rare":
			return tr("Редкое за осколки")
		&"board":
			return tr("Доска слухов")
		&"home":
			return tr("Домой с добычей") + (tr(" (решает хост)") if GameFlow.is_guest() else "")
		&"road":
			if GameFlow.is_guest():
				var me: Dictionary = WorldNet.roster.get(multiplayer.get_unique_id(), {})
				return tr("Я готов идти дальше ✓") if me.get("ready", false) else tr("Я готов идти дальше")
			return tr("Идти дальше по карте") + (tr(" (не все готовы)") if WorldNet.session and not WorldNet.everyone_ready() else "")
	return ""


func interact(_player: Node) -> void:
	match kind:
		&"fire", &"fire2":
			_rest()
		&"anvil":
			_repair()
		&"workbench":
			var inv := InventoryBook.new()
			get_tree().current_scene.add_child(inv)
			inv.setup(GameState.hero)
			inv.open()
		&"stash":
			_open_stash()
		&"rare":
			_open_rare()
		&"board":
			EventBus.message.emit(rumours())
		&"home":
			if GameFlow.is_guest():
				EventBus.message.emit(tr("Это решает хост."))
			else:
				GameFlow.retreat()
		&"road":
			if GameFlow.is_guest():
				WorldNet.toggle_ready()
			else:
				GameFlow.location_cleared()


# --------------------------------------------------------------- the fire
func _rests() -> int:
	return int(GameState.run.loc.get("rests", 0)) if GameState.run else 0


static func rest_price() -> int:
	return 20 + 3 * maxi(1, GameState.depth())


func _rest() -> void:
	var h: Hero = GameState.hero
	var rests := _rests()
	if rests > 0 and not h.spend_gold(rest_price()):
		EventBus.message.emit(tr("Не хватает золота на отдых."))
		return
	var share := (REST_HEAL if rests == 0 else PAID_REST_HEAL) + (FIRE2_BONUS if kind == &"fire2" else 0.0)
	h.stats.heal(roundi(h.stats.max_hp() * share))
	h.stats.mana = mini(h.stats.max_mana(), h.stats.mana + roundi(h.stats.max_mana() * REST_MANA))
	h.stats.mana_changed.emit(h.stats.mana, h.stats.max_mana())
	if GameState.run:
		GameState.run.loc["rests"] = rests + 1
	AudioManager.play_sfx(&"cast_heal", global_position, -6.0)
	EventBus.message.emit(tr("Тепло костра возвращает силы. Поход сохранён."))
	if not GameFlow.is_guest():
		GameFlow.save_expedition("camp")


# -------------------------------------------------------------- the anvil
static func repair_price() -> int:
	var total := 0
	for it: ItemData in GameState.hero.equipment.items.values():
		if it:
			total += int(Smithing.repair_cost(it)["gold"])
	return ceili(total * 1.2)


func _repair() -> void:
	var h: Hero = GameState.hero
	var p := repair_price()
	if p <= 0:
		EventBus.message.emit(tr("Снаряжение в порядке."))
		return
	if not h.spend_gold(p):
		EventBus.message.emit(tr("Не хватает золота на починку."))
		return
	for it: ItemData in h.equipment.items.values():
		if it and it.has_durability and it.is_instance():
			it.durability = it.max_durability
	h.equipment.changed.emit()
	AudioManager.play_sfx(&"attack_mace", global_position, -4.0)
	EventBus.message.emit(tr("Снаряжение как новое."))


# --------------------------------------------------------------- rumours
## What the scouts heard about the next forks of the road.
static func rumours() -> String:
	var run := GameState.run
	if run == null:
		return TranslationServer.translate("На доске пусто.")
	var lines: Array[String] = [TranslationServer.translate("Слухи о дороге впереди:")]
	for id in run.next_choices():
		var n := run.map.node(id)
		var t := ExpeditionMap.type_name(StringName(n["type"]))
		var extra := ""
		var plan := LocationInstance.plan(n)
		if plan:
			extra = TranslationServer.translate(", этажей %d") % plan.floors()
		lines.append(TranslationServer.translate("· %s, глубина %d%s") % [t, int(n["depth"]), extra])
	return "\n".join(lines)


# --------------------------------------------------------------- the stash
## Items kept in the expedition's camps (RunState.flags["camp_stash"]).
static func _stash() -> Array:
	if GameState.run == null:
		return []
	return GameState.run.flags.get("camp_stash", [])


func _close_menu() -> void:
	if _menu and is_instance_valid(_menu):
		_menu.queue_free()
	_menu = null


func _panel(title: String) -> VBoxContainer:
	_close_menu()
	_menu = CanvasLayer.new()
	_menu.layer = 50
	get_tree().current_scene.add_child(_menu)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIStyle.texture_box(AssetPaths.TOOLTIP, 4))
	panel.position = Vector2(180, 50)
	panel.custom_minimum_size = Vector2(280, 0)
	_menu.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	box.add_child(UIStyle.label(title, 9))
	return box


func _open_stash() -> void:
	var h: Hero = GameState.hero
	var box := _panel(tr("Сундук лагеря: вещи ждут в каждом лагере похода и вернутся домой с живым героем"))
	var stash := _stash()
	box.add_child(UIStyle.label(tr("В сундуке:"), 7, UIStyle.INK_SOFT))
	for i in stash.size():
		var it := RunCodec.item_from_dict(stash[i])
		if it == null:
			continue
		var idx := i
		box.add_child(BookPageScreen.button(tr("Забрать: %s") % it.display_name, func() -> void:
			if h.inventory.free_space_for(it) <= 0:
				EventBus.message.emit(tr("Сумка полна."))
				return
			var s := _stash()
			s.remove_at(idx)
			GameState.run.flags["camp_stash"] = s
			h.inventory.add_item(it, 1)
			_open_stash()))
	box.add_child(UIStyle.label(tr("Положить из сумки:"), 7, UIStyle.INK_SOFT))
	var shown := 0
	for i in h.inventory.slots.size():
		var st: ItemStack = h.inventory.slots[i]
		if st == null or st.item.currency_value > 0 or shown >= 8:
			continue
		shown += 1
		var slot := i
		box.add_child(BookPageScreen.button(tr("Положить: %s") % st.item.display_name, func() -> void:
			var s := _stash()
			if s.size() >= STASH_SLOTS:
				EventBus.message.emit(tr("Сундук полон."))
				return
			var taken := h.inventory.take_at(slot, 1)
			if taken:
				s.append(RunCodec.item_to_dict(taken.item))
				GameState.run.flags["camp_stash"] = s
			_open_stash()))
	box.add_child(BookPageScreen.button(tr("Закрыть"), _close_menu))


## A living hero home: the stash's items come back to the bag (the rest,
## if the bag is full, to the town's warehouse resources as their price).
static func unpack_stash(hero: Hero) -> void:
	if GameState.run == null or hero == null:
		return
	for d in _stash():
		var it := RunCodec.item_from_dict(d)
		if it and hero.inventory.free_space_for(it) > 0:
			hero.inventory.add_item(it, 1)
		elif it:
			hero.add_gold(it.price)
	GameState.run.flags.erase("camp_stash")


# ---------------------------------------------------------------- rare goods
func _roll_shard_offers() -> void:
	var depth := maxi(1, GameState.depth())
	var rng := RandomNumberGenerator.new()
	rng.seed = int(GameState.location.get("seed", 0)) + 99
	for table_name in [&"chest_rare", &"chest_epic"]:
		if _shard_offers.size() >= 2:
			break
		var table := ItemDatabase.get_loot_table(table_name)
		if table == null:
			continue
		for e: Dictionary in table.roll(depth, rng):
			var it: ItemData = e["item"]
			if it.currency_value <= 0 and not it.is_stackable() and it.rarity >= ItemData.Rarity.RARE:
				_shard_offers.append(ItemFactory.create(it, depth))
				break


static func shard_price(it: ItemData) -> int:
	return 4 + 4 * it.rarity


func _open_rare() -> void:
	var h: Hero = GameState.hero
	var box := _panel(tr("Редкое за осколки Затмения (у вас %d)") % h.inventory.count_of(MetaProgress.SHARD_ITEM))
	if _shard_offers.is_empty():
		box.add_child(UIStyle.label(tr("Всё разобрали."), 7))
	for it in _shard_offers:
		var cost := shard_price(it)
		var b := BookPageScreen.button(tr("%s — %d оск.") % [it.display_name, cost], func() -> void:
			if h.inventory.count_of(MetaProgress.SHARD_ITEM) < cost or h.inventory.free_space_for(it) <= 0:
				return
			h.inventory.remove_by_id(MetaProgress.SHARD_ITEM, cost)
			h.inventory.add_item(it, 1)
			_shard_offers.erase(it)
			EventBus.item_collected.emit(it, Vector2.ZERO)
			AudioManager.play_ui(&"pickup_epic")
			_open_rare())
		b.disabled = h.inventory.count_of(MetaProgress.SHARD_ITEM) < cost
		box.add_child(b)
	box.add_child(BookPageScreen.button(tr("Закрыть"), _close_menu))
