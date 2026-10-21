class_name ItemSlot
extends Control
## One item cell, used by the backpack, the equipment page and the quick bar.
## Handles drag & drop, right click / double click and tooltips; all actual
## changes go through Hero / Inventory / QuickBar (the slot only displays).

enum Kind { INVENTORY, EQUIPMENT, QUICK }

var kind: Kind = Kind.INVENTORY
var index: int = -1
var slot_id: StringName
var hero: Hero
## Tooltip of an empty equipment slot.
var hint := ""
## Faded icon of an empty equipment slot.
var placeholder: Texture2D
var key_label := ""

var _frame: PixelFrame
var _icon: TextureRect
var _count: Label
var _placeholder: TextureRect
var _key: Label
var _hovered := false


static func create(p_kind: Kind, p_hero: Hero, p_index: int = -1, p_slot_id: StringName = StringName()) -> ItemSlot:
	var s := ItemSlot.new()
	s.kind = p_kind
	s.hero = p_hero
	s.index = p_index
	s.slot_id = p_slot_id
	return s


func _ready() -> void:
	custom_minimum_size = UIStyle.SLOT_SIZE
	size = UIStyle.SLOT_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	_frame = UIStyle.frame(AssetPaths.SLOT_EMPTY, 5)
	add_child(_frame)
	_placeholder = TextureRect.new()
	_placeholder.texture = placeholder
	_placeholder.set_anchors_preset(Control.PRESET_FULL_RECT)
	_placeholder.offset_left = 5
	_placeholder.offset_top = 5
	_placeholder.offset_right = -5
	_placeholder.offset_bottom = -5
	_placeholder.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_placeholder.modulate = Color(0.25, 0.15, 0.08, 0.3)
	_placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_placeholder)
	_icon = TextureRect.new()
	_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_icon.offset_left = 5
	_icon.offset_top = 5
	_icon.offset_right = -5
	_icon.offset_bottom = -5
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)
	_count = UIStyle.outlined_label("", 7, Color.WHITE)
	_count.set_anchors_preset(Control.PRESET_FULL_RECT)
	_count.offset_right = -3
	_count.offset_bottom = 1
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	add_child(_count)
	_key = UIStyle.outlined_label(key_label, 6, UIStyle.GOLD)
	_key.position = Vector2(3, 0)
	add_child(_key)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	refresh()


func get_item() -> ItemData:
	if hero == null:
		return null
	match kind:
		Kind.INVENTORY:
			var st := hero.inventory.stack_at(index)
			return st.item if st else null
		Kind.EQUIPMENT:
			return hero.equipment.get_item(slot_id)
		Kind.QUICK:
			return hero.quick_bar.get_item(index)
	return null


func get_count() -> int:
	match kind:
		Kind.INVENTORY:
			var st := hero.inventory.stack_at(index)
			return st.count if st else 0
		Kind.QUICK:
			var it := get_item()
			return hero.inventory.count_of(it.id) if it else 0
	return 1 if get_item() else 0


func refresh() -> void:
	if _icon == null:
		return
	var item := get_item()
	var c := get_count()
	_icon.texture = item.icon if item else null
	# Quick slot whose item ran out: show it faded.
	_icon.modulate = Color(1, 1, 1, 0.35) if (item and c == 0) else Color.WHITE
	_count.text = ""
	if item and kind == Kind.INVENTORY and c > 1:
		_count.text = str(c)
	elif item and kind == Kind.QUICK and item.max_stack > 1:
		_count.text = str(c)
	_placeholder.visible = item == null
	var tex := AssetPaths.SLOT_EMPTY if item == null else AssetPaths.SLOT
	if _hovered:
		tex = AssetPaths.SLOT_HOVER
	_frame.texture = AssetPaths.tex(tex)
	_frame.modulate = item.rarity_color().lerp(Color.WHITE, 0.55) if item and item.rarity > ItemData.Rarity.COMMON else Color.WHITE
	if _hovered and item:
		Tooltip.show_text(TooltipText.item(item, hero, kind == Kind.EQUIPMENT), self)


func _on_mouse_entered() -> void:
	_hovered = true
	refresh()
	if get_item() == null:
		if kind == Kind.EQUIPMENT and hint != "":
			Tooltip.show_text(hint, self)


func _on_mouse_exited() -> void:
	_hovered = false
	Tooltip.hide_tip(self)
	refresh()


# ---------------------------------------------------------------- clicking
func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_RIGHT or (mb.button_index == MOUSE_BUTTON_LEFT and mb.double_click):
		accept_event()
		activate(mb.button_index == MOUSE_BUTTON_RIGHT)
	elif mb.button_index == MOUSE_BUTTON_LEFT and kind == Kind.QUICK and not _in_inventory_mode():
		accept_event()
		activate(false)


func _in_inventory_mode() -> bool:
	return get_tree().paused


## Right click / double click: equip, use, unequip, clear quick slot.
func activate(right_click: bool) -> void:
	var item := get_item()
	if item == null:
		return
	var player := get_tree().get_first_node_in_group("player") as Player
	match kind:
		Kind.INVENTORY:
			if item is EquipmentItemData:
				hero.equip_from_inventory(index)
			elif item is UsableItemData and player:
				player.use_item(item)
		Kind.EQUIPMENT:
			hero.unequip_to_inventory(slot_id)
		Kind.QUICK:
			if right_click and _in_inventory_mode():
				hero.quick_bar.clear(index)
			elif player:
				player.use_item(item)
	Tooltip.hide_tip(self)


# ------------------------------------------------------------- drag & drop
func _get_drag_data(_at_position: Vector2) -> Variant:
	var item := get_item()
	if item == null:
		return null
	var preview := Control.new()
	var tr := TextureRect.new()
	tr.texture = item.icon
	tr.size = Vector2(16, 16)
	tr.position = Vector2(-8, -8)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.add_child(tr)
	set_drag_preview(preview)
	Tooltip.hide_tip(self)
	return {"type": "item_slot", "kind": kind, "index": index, "slot_id": slot_id, "item": item}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary) or data.get("type") != "item_slot":
		return false
	var item: ItemData = data["item"]
	var src: Kind = data["kind"]
	match kind:
		Kind.INVENTORY:
			if src == Kind.EQUIPMENT:
				var target := get_item()
				return target == null or hero.equipment.can_equip_in(target, data["slot_id"])
			return src == Kind.INVENTORY
		Kind.EQUIPMENT:
			return src != Kind.QUICK and hero.equipment.can_equip_in(item, slot_id)
		Kind.QUICK:
			return src == Kind.INVENTORY or src == Kind.QUICK
	return false


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var src: Kind = data["kind"]
	match kind:
		Kind.INVENTORY:
			if src == Kind.INVENTORY:
				hero.inventory.move(data["index"], index)
			elif src == Kind.EQUIPMENT:
				hero.unequip_to_inventory(data["slot_id"], index)
		Kind.EQUIPMENT:
			if src == Kind.INVENTORY:
				hero.equip_from_inventory(data["index"], slot_id)
			elif src == Kind.EQUIPMENT:
				hero.move_equipment(data["slot_id"], slot_id)
		Kind.QUICK:
			if src == Kind.INVENTORY:
				hero.quick_bar.assign(index, data["item"])
			elif src == Kind.QUICK:
				hero.quick_bar.swap(data["index"], index)
