class_name ShopSlot
extends Control
## Merchant goods: icon in a slot + price; click to buy.

signal buy_requested(index: int)

var item: ItemData
var index: int
var hero: Hero

var _price: Label


func _ready() -> void:
	custom_minimum_size = UIStyle.SLOT_SIZE + Vector2(0, 9)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := Control.new()
	box.size = UIStyle.SLOT_SIZE
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	var frame := UIStyle.frame(AssetPaths.SLOT, 5)
	if item.rarity > ItemData.Rarity.COMMON:
		frame.modulate = item.rarity_color().lerp(Color.WHITE, 0.5)
	box.add_child(frame)
	var icon := TextureRect.new()
	icon.texture = item.icon
	icon.position = Vector2(5, 5)
	icon.size = UIStyle.SLOT_SIZE - Vector2(10, 10)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon)
	_price = UIStyle.label("", 6)
	_price.position = Vector2(0, UIStyle.SLOT_SIZE.y - 1)
	_price.size = Vector2(UIStyle.SLOT_SIZE.x, 9)
	_price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_price)
	mouse_entered.connect(_tip)
	mouse_exited.connect(func() -> void: Tooltip.hide_tip(self))
	refresh()


func refresh() -> void:
	var p := item.buy_price()
	_price.text = tr("%d з.") % p
	_price.add_theme_color_override("font_color", UIStyle.INK if hero.gold >= p else UIStyle.BAD)


func _tip() -> void:
	var p := item.buy_price()
	var col := UIStyle.GOOD_HEX if hero.gold >= p else UIStyle.BAD_HEX
	Tooltip.show_text(TooltipText.item(item, hero) + tr("\n[color=%s]Купить за %d з. (клик)[/color]") % [col, p], self)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and (mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT):
		accept_event()
		buy_requested.emit(index)
