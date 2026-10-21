class_name InventoryBook
extends CanvasLayer
## Inventory drawn on the open book (assets/ui/book.png).
## Left page: hero doll with equipment slots + live stats.
## Right page: backpack grid. Game is paused while the book is open.
## Dropping an item outside the book throws it on the floor.

const BOOK_SIZE := Vector2(500, 262)
const BOOK_MARGIN := 15  # border thickness on screen (texture margin * scale)
const GRID_COLUMNS := 6
const DOLL_AREA := Vector2(118, 150)
const HUD_HEIGHT := 88

var hero: Hero
var is_open := false

var _root: Control
var _catcher: DropCatcher
var _page: ColorRect
var _anim: Tween
var _inv_slots: Array[ItemSlot] = []
var _equip_slots: Array[ItemSlot] = []
var _stat_labels: Dictionary = {}  # stat -> Label
var _capacity_label: Label
var _title_label: Label


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func setup(p_hero: Hero) -> void:
	hero = p_hero
	_build()
	hero.inventory.changed.connect(_refresh_inventory)
	hero.equipment.changed.connect(_refresh_equipment)
	hero.equipment.changed.connect(func() -> void:
		if is_open:
			AudioManager.play_ui(&"ui_equip"))
	hero.stats.stats_changed.connect(_refresh_stats)
	hero.stats.hp_changed.connect(func(_a: int, _b: int) -> void: _refresh_stats())
	hero.leveled_up.connect(func(_l: int) -> void: _refresh_stats())
	_refresh_inventory()
	_refresh_equipment()
	_refresh_stats()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		toggle()
		get_viewport().set_input_as_handled()
	elif is_open and event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func open() -> void:
	var player := get_tree().get_first_node_in_group("player") as Player
	if is_open or hero == null or (player and player.dead) or get_tree().paused:
		return
	is_open = true
	visible = true
	get_tree().paused = true
	_refresh_inventory()
	_refresh_equipment()
	_refresh_stats()
	_animate_open()
	AudioManager.play_ui(&"ui_book_open")
	EventBus.inventory_toggled.emit(true)


func close() -> void:
	if not is_open:
		return
	is_open = false
	get_tree().paused = false
	Tooltip.hide_tip()
	_animate_close()
	AudioManager.play_ui(&"ui_book_close")
	EventBus.inventory_toggled.emit(false)


# --------------------------------------------------------------- animation
## Book grows in, the background darkens and a page turns over the spine.
func _animate_open() -> void:
	if _anim:
		_anim.kill()
	_catcher.modulate.a = 0.0
	_root.modulate.a = 0.0
	_root.pivot_offset = BOOK_SIZE / 2.0
	_root.scale = Vector2(0.92, 0.92)
	_anim = create_tween().set_parallel()
	_anim.tween_property(_catcher, "modulate:a", 1.0, 0.2)
	_anim.tween_property(_root, "modulate:a", 1.0, 0.12)
	_anim.tween_property(_root, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_page.visible = true
	_page.scale = Vector2.ONE
	_page.color = UIStyle.PARCHMENT
	_anim.tween_property(_page, "scale:x", -1.0, 0.32).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT).set_delay(0.05)
	_anim.tween_property(_page, "color", UIStyle.PARCHMENT.darkened(0.35), 0.16).set_delay(0.05)
	_anim.chain().tween_callback(func() -> void: _page.visible = false)


func _animate_close() -> void:
	if _anim:
		_anim.kill()
	_root.pivot_offset = BOOK_SIZE / 2.0
	_anim = create_tween().set_parallel()
	_anim.tween_property(_catcher, "modulate:a", 0.0, 0.15)
	_anim.tween_property(_root, "modulate:a", 0.0, 0.15)
	_anim.tween_property(_root, "scale", Vector2(0.94, 0.94), 0.15)
	_anim.chain().tween_callback(func() -> void:
		if not is_open:
			visible = false)


# ------------------------------------------------------------------- build
func _build() -> void:
	# Dim background that also catches items dropped outside the book.
	var catcher := DropCatcher.new()
	catcher.hero = hero
	catcher.color = Color(0, 0, 0, 0.55)
	catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Leave the HUD (quick slots) uncovered so items can be dropped there.
	catcher.offset_bottom = -HUD_HEIGHT
	add_child(catcher)
	_catcher = catcher

	_root = Control.new()
	_root.anchor_left = 0.5
	_root.anchor_right = 0.5
	_root.offset_left = -BOOK_SIZE.x / 2.0
	_root.offset_right = BOOK_SIZE.x / 2.0
	_root.offset_top = 4
	_root.offset_bottom = 4 + BOOK_SIZE.y
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_root.add_child(UIStyle.frame(AssetPaths.BOOK, 30, 0.5))

	var page_w := BOOK_SIZE.x / 2.0 - BOOK_MARGIN - 8
	var left := Control.new()
	left.position = Vector2(BOOK_MARGIN + 4, BOOK_MARGIN)
	left.size = Vector2(page_w, BOOK_SIZE.y - BOOK_MARGIN * 2)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(left)
	var right := Control.new()
	right.position = Vector2(BOOK_SIZE.x / 2.0 + 6, BOOK_MARGIN)
	right.size = left.size
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(right)
	_build_left_page(left)
	_build_right_page(right)
	# Page that flips over the spine when the book opens.
	_page = ColorRect.new()
	_page.position = Vector2(BOOK_SIZE.x / 2.0, BOOK_MARGIN - 2)
	_page.size = Vector2(BOOK_SIZE.x / 2.0 - BOOK_MARGIN, BOOK_SIZE.y - BOOK_MARGIN * 2 + 4)
	_page.pivot_offset = Vector2(0, _page.size.y / 2.0)
	_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page.visible = false
	_root.add_child(_page)


func _build_left_page(page: Control) -> void:
	_title_label = UIStyle.label("", 10)
	_title_label.position = Vector2(0, 0)
	_title_label.size = Vector2(page.size.x, 14)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(_title_label)

	var doll_area := Control.new()
	doll_area.position = Vector2(0, 18)
	doll_area.size = DOLL_AREA
	doll_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(doll_area)
	var doll := TextureRect.new()
	doll.texture = AssetPaths.tex(AssetPaths.DOLL)
	doll.size = Vector2(40, 64) * 1.5
	doll.position = (DOLL_AREA - doll.size) / 2.0 + Vector2(0, -6)
	doll.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	doll.modulate = Color(1, 1, 1, 0.6)
	doll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	doll_area.add_child(doll)
	for def in hero.equipment.slot_defs():
		var s := ItemSlot.create(ItemSlot.Kind.EQUIPMENT, hero, -1, def.id)
		s.hint = def.label
		s.placeholder = def.placeholder
		s.position = def.page_position
		doll_area.add_child(s)
		_equip_slots.append(s)

	# Stats block to the right of the doll.
	var stats_box := VBoxContainer.new()
	stats_box.position = Vector2(DOLL_AREA.x + 6, 20)
	stats_box.size = Vector2(page.size.x - DOLL_AREA.x - 6, page.size.y - 20)
	stats_box.add_theme_constant_override("separation", 0)
	stats_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(stats_box)
	var header := UIStyle.label("Характеристики", 8, UIStyle.INK_SOFT)
	stats_box.add_child(header)
	for stat in ["level"] + StatTypes.PRIMARY + ["hp", "mana"] + [StatTypes.DAMAGE, StatTypes.ARMOR, StatTypes.SPEED, StatTypes.CRIT_CHANCE]:
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var name_l := UIStyle.label("", 7, UIStyle.INK_SOFT)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var value_l := UIStyle.label("", 7, UIStyle.INK)
		value_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(name_l)
		row.add_child(value_l)
		stats_box.add_child(row)
		_stat_labels[stat] = [name_l, value_l]

	var help := UIStyle.label("ПКМ / двойной клик — надеть или использовать.\nПеретащите предмет за книгу — выбросить.\nВ быстрые слоты (1–7) — перетащите вниз.", 6, UIStyle.INK_SOFT)
	help.position = Vector2(0, DOLL_AREA.y + 22)
	help.size = Vector2(page.size.x, 30)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(help)


func _build_right_page(page: Control) -> void:
	var title := UIStyle.label("Рюкзак", 10)
	title.size = Vector2(page.size.x, 14)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(title)
	var grid := GridContainer.new()
	grid.columns = GRID_COLUMNS
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	var grid_w := GRID_COLUMNS * (UIStyle.SLOT_SIZE.x + 2) - 2
	grid.position = Vector2((page.size.x - grid_w) / 2.0, 20)
	page.add_child(grid)
	for i in hero.inventory.capacity():
		var s := ItemSlot.create(ItemSlot.Kind.INVENTORY, hero, i)
		grid.add_child(s)
		_inv_slots.append(s)
	_capacity_label = UIStyle.label("", 7, UIStyle.INK_SOFT)
	var rows := ceili(float(hero.inventory.capacity()) / GRID_COLUMNS)
	_capacity_label.position = Vector2(grid.position.x, 20 + rows * (UIStyle.SLOT_SIZE.y + 2) + 2)
	page.add_child(_capacity_label)


# ----------------------------------------------------------------- refresh
func _refresh_inventory() -> void:
	for s in _inv_slots:
		s.refresh()
	if _capacity_label:
		var used := 0
		for st in hero.inventory.slots:
			if st != null:
				used += 1
		_capacity_label.text = "Занято: %d / %d" % [used, hero.inventory.capacity()]


func _refresh_equipment() -> void:
	for s in _equip_slots:
		s.refresh()


func _refresh_stats() -> void:
	if _stat_labels.is_empty():
		return
	var st := hero.stats
	_title_label.text = "%s · %s" % [hero.race.display_name, hero.class_data.display_name]
	for key: String in _stat_labels:
		var labels: Array = _stat_labels[key]
		match key:
			"level":
				labels[0].text = "Уровень"
				labels[1].text = "%d (%d/%d XP)" % [hero.level, hero.xp, hero.xp_to_next()]
			"hp":
				labels[0].text = "Здоровье"
				labels[1].text = "%d / %d" % [st.hp, st.max_hp()]
			"mana":
				labels[0].text = "Мана"
				labels[1].text = "%d / %d" % [st.mana, st.max_mana()]
			_:
				labels[0].text = StatTypes.label(key)
				labels[1].text = StatTypes.format_value(key, st.get_value(key))
