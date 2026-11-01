class_name TradeBook
extends CanvasLayer
## The trade window of a world session (WorldNet.trade): my backpack (click
## to offer / take back), my offer and gold, the other player's offer, both
## confirmations. Any change unconfirms both; when both confirm, the items
## change hands (two-phase on the host - nothing is lost or doubled).

const SIZE := Vector2(540, 290)

var _other := ""
var _mine: VBoxContainer
var _bag: VBoxContainer
var _theirs: VBoxContainer
var _gold: SpinBox
var _status: Label
var _confirm: Button
var _their_items: Array = []


func _ready() -> void:
	layer = 24
	process_mode = Node.PROCESS_MODE_ALWAYS
	var t: Node = WorldNet.trade
	t.state_changed.connect(_on_state)
	t.closed.connect(_on_closed)


func open(other_nick: String) -> void:
	_other = other_nick
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
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
	var left := VBoxContainer.new()
	left.position = Vector2(22, 16)
	left.size = Vector2(SIZE.x / 2.0 - 30, SIZE.y - 32)
	root.add_child(left)
	var right := VBoxContainer.new()
	right.position = Vector2(SIZE.x / 2.0 + 8, 16)
	right.size = Vector2(SIZE.x / 2.0 - 30, SIZE.y - 32)
	root.add_child(right)
	left.add_child(UIStyle.label(tr("Обмен с %s") % _other, 11))
	left.add_child(UIStyle.label(tr("Сумка (нажмите, чтобы предложить):"), 7, UIStyle.INK_SOFT))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	_bag = VBoxContainer.new()
	_bag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_bag)
	_gold = SpinBox.new()
	_gold.prefix = tr("Золото:")
	_gold.max_value = GameState.hero.gold
	_gold.value_changed.connect(func(_v: float) -> void: _send_offer())
	left.add_child(_gold)
	right.add_child(UIStyle.label(tr("Вы отдаёте:"), 8))
	_mine = VBoxContainer.new()
	right.add_child(_mine)
	right.add_child(UIStyle.label(tr("%s отдаёт:") % _other, 8))
	_theirs = VBoxContainer.new()
	right.add_child(_theirs)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(fill)
	_status = UIStyle.label("", 7, UIStyle.INK_SOFT)
	right.add_child(_status)
	_confirm = BookPageScreen.button(tr("Подтвердить"), func() -> void: WorldNet.trade.confirm())
	right.add_child(_confirm)
	right.add_child(BookPageScreen.button(tr("Отмена"), func() -> void: WorldNet.trade.cancel()))
	_refresh_bag()


func _refresh_bag() -> void:
	for c in _bag.get_children():
		c.queue_free()
	for c in _mine.get_children():
		c.queue_free()
	var offer: Array = WorldNet.trade.my_offer
	var slots := GameState.hero.inventory.slots
	for i in slots.size():
		var st: ItemStack = slots[i]
		if st == null or st.item == null:
			continue
		var text := st.item.display_name + (" ×%d" % st.count if st.count > 1 else "")
		var b := BookPageScreen.button(text, func() -> void:
			var o: Array = WorldNet.trade.my_offer.duplicate()
			if i in o:
				o.erase(i)
			elif o.size() < 12:
				o.append(i)
			WorldNet.trade.my_offer = o
			_send_offer())
		b.add_theme_font_size_override("font_size", 7)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		(_mine if i in offer else _bag).add_child(b)


func _send_offer() -> void:
	WorldNet.trade.set_offer(WorldNet.trade.my_offer, int(_gold.value))
	_refresh_bag()


func _on_state(_mine_idx: Array, _mine_gold: int, theirs: Array, theirs_gold: int, my_ok: bool, their_ok: bool) -> void:
	for c in _theirs.get_children():
		c.queue_free()
	_theirs.add_child(UIStyle.label(tr("%d вещей, %d золота") % [theirs.size(), theirs_gold], 7))
	_status.text = tr("Вы: %s · %s: %s") % [tr("готов") if my_ok else tr("думает"), _other, tr("готов") if their_ok else tr("думает")]
	_confirm.disabled = my_ok


func _on_closed(reason: String) -> void:
	var text := {"done": tr("Обмен состоялся."), "cancel": tr("Обмен отменён."), "changed": tr("Обмен сорван: вещи изменились, всё вернулось."),
			"left": tr("Обмен сорван: игрок вышел.")}
	EventBus.message.emit(text.get(reason, tr("Обмен закрыт.")))
	queue_free()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		WorldNet.trade.cancel()
