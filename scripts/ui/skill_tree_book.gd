class_name SkillTreeBook
extends CanvasLayer
## Skill tree on the open book (K). Left page: the class tree — tiers from
## SkillData.tree_row, columns in ClassData.skills order, lines to prerequisites.
## Right page: the selected skill and the learn / upgrade button.
## The game is paused while the book is open.

const BOOK_SIZE := Vector2(500, 262)
const BOOK_MARGIN := 15
const NODE_SIZE := Vector2(28, 28)
const ROW_GAP := 62.0
const PASSIVE_TINT := Color(0.75, 0.6, 1.0)

var hero: Hero
var is_open := false

var _root: Control
var _tree_area: Control
var _points: Label
var _title: Label
var _icon: TextureRect
var _text: RichTextLabel
var _learn: Button
var _reason: Label
var _selected: SkillData
var _nodes: Dictionary = {}  # skill id -> Control


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func setup(p_hero: Hero) -> void:
	hero = p_hero
	_build()
	hero.skills.changed.connect(func() -> void:
		if is_open:
			_refresh())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("skill_tree"):
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
	if _selected == null and not hero.skills.all.is_empty():
		_selected = hero.skills.all[0]
	_refresh()
	_root.modulate.a = 0.0
	_root.pivot_offset = BOOK_SIZE / 2.0
	_root.scale = Vector2(0.92, 0.92)
	var tw := create_tween().set_parallel()
	tw.tween_property(_root, "modulate:a", 1.0, 0.12)
	tw.tween_property(_root, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	AudioManager.play_ui(&"ui_book_open")


func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	get_tree().paused = false
	Tooltip.hide_tip()
	AudioManager.play_ui(&"ui_book_close")


# ------------------------------------------------------------------- build
func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
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
	var page_h := BOOK_SIZE.y - BOOK_MARGIN * 2
	var head := UIStyle.label("Навыки: %s" % hero.class_data.display_name, 10)
	head.position = Vector2(BOOK_MARGIN + 4, BOOK_MARGIN)
	head.size = Vector2(page_w, 14)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(head)
	_tree_area = Control.new()
	_tree_area.position = Vector2(BOOK_MARGIN + 4, BOOK_MARGIN + 24)
	_tree_area.size = Vector2(page_w, page_h - 40)
	_tree_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_tree_area)
	_points = UIStyle.label("", 7, UIStyle.GOOD)
	_points.position = Vector2(BOOK_MARGIN + 4, BOOK_SIZE.y - BOOK_MARGIN - 14)
	_points.size = Vector2(page_w, 12)
	_points.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_points)

	var right := VBoxContainer.new()
	right.position = Vector2(BOOK_SIZE.x / 2.0 + 8, BOOK_MARGIN)
	right.size = Vector2(page_w - 4, page_h)
	right.add_theme_constant_override("separation", 3)
	_root.add_child(right)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	right.add_child(top)
	var frame_box := Control.new()
	frame_box.custom_minimum_size = Vector2(34, 34)
	frame_box.add_child(UIStyle.frame(AssetPaths.SLOT, 5))
	_icon = TextureRect.new()
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.position = Vector2(5, 5)
	_icon.size = Vector2(24, 24)
	frame_box.add_child(_icon)
	top.add_child(frame_box)
	_title = UIStyle.label("", 10)
	_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_title)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.add_theme_color_override("default_color", UIStyle.INK)
	for k in ["normal_font_size", "bold_font_size", "italics_font_size"]:
		_text.add_theme_font_size_override(k, 7)
	right.add_child(_text)
	_reason = UIStyle.label("", 7, UIStyle.BAD)
	right.add_child(_reason)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	right.add_child(buttons)
	_learn = BookPageScreen.button("Изучить", func() -> void: learn(_selected))
	_learn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(_learn)
	buttons.add_child(BookPageScreen.button("Закрыть", close))


## Positions of the tree nodes: rows by tree_row, columns spread evenly.
func _layout() -> Dictionary:
	var rows := {}
	for s in hero.skills.all:
		if not rows.has(s.tree_row):
			rows[s.tree_row] = []
		rows[s.tree_row].append(s)
	var pos := {}
	for r: int in rows:
		var list: Array = rows[r]
		for i in list.size():
			var x := _tree_area.size.x * float(i + 1) / float(list.size() + 1)
			pos[list[i].id] = Vector2(x, 14.0 + r * ROW_GAP + NODE_SIZE.y / 2.0)
	return pos


func _refresh() -> void:
	for c in _tree_area.get_children():
		c.queue_free()
	_nodes.clear()
	var pos := _layout()
	var sk := hero.skills
	# Prerequisite lines first, so the nodes are drawn over them.
	for s in sk.all:
		for r in s.requires:
			if r == null or not pos.has(r.id):
				continue
			var line := Line2D.new()
			line.width = 2.0
			line.default_color = UIStyle.GOOD if sk.is_learned(r) else UIStyle.INK_SOFT.lightened(0.3)
			line.add_point(pos[r.id] + Vector2(0, NODE_SIZE.y / 2.0))
			line.add_point(pos[s.id] - Vector2(0, NODE_SIZE.y / 2.0))
			_tree_area.add_child(line)
	for s in sk.all:
		var node := _node(s)
		node.position = pos[s.id] - NODE_SIZE / 2.0
		_tree_area.add_child(node)
		_nodes[s.id] = node
	_points.text = "Очков навыков: %d · уровень героя %d" % [sk.skill_points, hero.level]
	_show(_selected)


func _node(s: SkillData) -> Control:
	var sk := hero.skills
	var rank := sk.rank(s)
	var available := sk.block_reason(s, hero.level) == ""
	var box := Control.new()
	box.size = NODE_SIZE
	box.custom_minimum_size = NODE_SIZE
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	var frame := UIStyle.frame(AssetPaths.SLOT if rank > 0 else AssetPaths.SLOT_EMPTY, 5)
	if s.is_passive():
		frame.modulate = PASSIVE_TINT
	box.add_child(frame)
	var icon := TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.texture = s.icon
	icon.position = Vector2(5, 5)
	icon.size = NODE_SIZE - Vector2(10, 10)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if rank <= 0:
		icon.modulate = Color(1, 1, 1, 0.75) if available else Color(0.25, 0.25, 0.3, 0.8)
	box.add_child(icon)
	var lvl := UIStyle.outlined_label("%d/%d" % [rank, s.max_level], 6, UIStyle.GOLD if rank > 0 else UIStyle.PARCHMENT)
	lvl.position = Vector2(NODE_SIZE.x - 14, NODE_SIZE.y - 9)
	box.add_child(lvl)
	if available:
		var plus := UIStyle.outlined_label("+", 9, Color(0.4, 1.0, 0.4))
		plus.position = Vector2(NODE_SIZE.x - 7, -4)
		box.add_child(plus)
	if s == _selected:
		var sel := ColorRect.new()
		sel.color = Color(1, 0.9, 0.4, 0.25)
		sel.position = Vector2(3, 3)
		sel.size = NODE_SIZE - Vector2(6, 6)
		sel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(sel)
	box.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.double_click:
				learn(s)
			else:
				_selected = s
				AudioManager.play_ui(&"ui_click")
				_refresh())
	return box


func _show(s: SkillData) -> void:
	if s == null:
		return
	var sk := hero.skills
	var rank := sk.rank(s)
	_icon.texture = s.icon
	_title.text = "Пассивный навык" if s.is_passive() else "Активный навык"
	var text := TooltipText.skill(s, rank, 0)
	if s.required_level > 1:
		text += "\n[color=#%s]Требуется уровень героя: %d[/color]" % [UIStyle.INK_SOFT.to_html(false), s.required_level]
	if not s.requires.is_empty():
		var names: Array[String] = []
		for r in s.requires:
			if r:
				names.append(r.display_name)
		text += "\n[color=#%s]После: %s[/color]" % [UIStyle.INK_SOFT.to_html(false), ", ".join(names)]
	var w := hero.weapon()
	if s.has_synergy(w):
		text += "\n[color=%s]Синергия активна: %s[/color]" % [UIStyle.GOOD_HEX, w.display_name]
	if not s.is_passive():
		var slot := sk.skills.find(s)
		if slot >= 0:
			text += "\n[color=#%s]Слот HUD: %s[/color]" % [UIStyle.INK_SOFT.to_html(false), HUD.SKILL_KEYS[slot]]
	_text.text = text
	var reason := sk.block_reason(s, hero.level)
	_reason.text = reason
	_learn.text = "Изучить" if rank == 0 else "Улучшить"
	_learn.disabled = reason != ""


func learn(s: SkillData) -> bool:
	if s == null:
		return false
	var ok := hero.skills.learn(s, hero.level)
	AudioManager.play_ui(&"ui_equip" if ok else &"chest_locked")
	if ok:
		_selected = s
	_refresh()
	var node: Control = _nodes.get(s.id)
	if ok and node:
		Fx.sparks(_root, _tree_area.position + node.position + NODE_SIZE / 2.0, UIStyle.GOLD, 10, 40.0)
	return ok
