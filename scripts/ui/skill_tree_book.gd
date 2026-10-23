class_name SkillTreeBook
extends CanvasLayer
## Skill tree on the open book (K). Left page: the class tree — with
## ClassData.tree_layout three branches (columns) of tiers; deeper tiers need
## points spent in the branch, paired nodes are a choice of one. Old classes
## without a layout: tiers from SkillData.tree_row, lines to prerequisites.
## Right page: the selected skill and the learn / upgrade button.
## The game is paused while the book is open.

const BOOK_SIZE := Vector2(500, 262)
const BOOK_MARGIN := 15
const NODE_SIZE := Vector2(28, 28)
const ROW_GAP := 62.0
## Tier step in the branch layout.
const BRANCH_ROW_GAP := 34.0
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
var _respec: Button
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
	_respec = BookPageScreen.button("", respec)
	_respec.add_theme_font_size_override("font_size", 7)
	right.add_child(_respec)


## Positions of the tree nodes: rows by tree_row, columns spread evenly.
func _layout() -> Dictionary:
	if hero.skills.has_branches():
		return _branch_layout()
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


## Branch columns; two skills on one tier of a branch (a choice) side by side.
func _branch_layout() -> Dictionary:
	var sk := hero.skills
	var cols := maxi(1, sk.branch_names.size())
	var groups := {}  # "branch:row" -> [skills]
	for s in sk.all:
		var key := "%d:%d" % [sk.branch_of(s), sk.row_of(s)]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(s)
	var pos := {}
	for key: String in groups:
		var list: Array = groups[key]
		var b := int(key.get_slice(":", 0))
		var row := int(key.get_slice(":", 1))
		var cx := _tree_area.size.x * (b + 0.5) / cols
		for i in list.size():
			var dx := (i - (list.size() - 1) / 2.0) * (NODE_SIZE.x + 6.0)
			pos[list[i].id] = Vector2(cx + dx, 20.0 + row * BRANCH_ROW_GAP + NODE_SIZE.y / 2.0)
	return pos


func _line(a: Vector2, b: Vector2, lit: bool) -> void:
	var line := Line2D.new()
	line.width = 2.0
	line.default_color = UIStyle.GOOD if lit else UIStyle.INK_SOFT.lightened(0.3)
	line.add_point(a + Vector2(0, NODE_SIZE.y / 2.0))
	line.add_point(b - Vector2(0, NODE_SIZE.y / 2.0))
	_tree_area.add_child(line)


func _refresh() -> void:
	for c in _tree_area.get_children():
		c.queue_free()
	_nodes.clear()
	var pos := _layout()
	var sk := hero.skills
	if sk.has_branches():
		var cols := maxi(1, sk.branch_names.size())
		for b in sk.branch_names.size():
			var head: Label
			if sk.chosen_branch == b:
				head = UIStyle.label("✦ %s · %d" % [sk.branch_names[b], sk.spent_in(b)], 7, UIStyle.GOLD)
			elif sk.chosen_branch >= 0 and b != sk.chosen_branch:
				head = UIStyle.label("%s · закрыто" % sk.branch_names[b], 7, UIStyle.INK_SOFT)
			else:
				head = UIStyle.label("%s · %d" % [sk.branch_names[b], sk.spent_in(b)], 7, UIStyle.INK)
			head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			head.position = Vector2(_tree_area.size.x * b / cols, 0)
			head.size = Vector2(_tree_area.size.x / cols, 12)
			_tree_area.add_child(head)
		# Each tier is linked to the tier above in the same branch.
		for s in sk.all:
			for o in sk.all:
				if sk.branch_of(o) == sk.branch_of(s) and sk.row_of(o) == sk.row_of(s) - 1:
					_line(pos[o.id], pos[s.id], sk.is_learned(o) and sk.is_learned(s))
	# Prerequisite lines first, so the nodes are drawn over them.
	for s in sk.all:
		if sk.has_branches():
			break
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
	if sk.has_branches():
		if sk.chosen_branch >= 0:
			_points.text += " · путь: «%s»" % sk.branch_name_of(sk.chosen_branch)
		elif sk.skill_points > 0:
			_points.text += " · выбор пути: первая вложенная ветвь закрепится"
	var cost := sk.respec_cost(hero.level)
	_respec.text = "Сбросить навыки — %d з." % cost
	_respec.disabled = sk.spent_total() <= 0 or hero.gold < cost
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
	if rank <= 0 and sk.chosen_rival(s) != null:
		frame.modulate = Color(0.5, 0.45, 0.45)
		icon.modulate = Color(0.3, 0.25, 0.25, 0.7)
	elif rank <= 0 and sk.chosen_branch >= 0 and sk.branch_of(s) != sk.chosen_branch:
		frame.modulate = Color(0.45, 0.45, 0.5)
		icon.modulate = Color(0.3, 0.3, 0.34, 0.65)
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
	var soft := UIStyle.INK_SOFT.to_html(false)
	if sk.required_level(s) > 1:
		text += "\n[color=#%s]Требуется уровень героя: %d[/color]" % [soft, sk.required_level(s)]
	if sk.required_points(s) > 0:
		var b := sk.branch_of(s)
		text += "\n[color=#%s]Нужно вложить в ветвь «%s»: %d (сейчас %d)[/color]" % [soft, sk.branch_names[b], sk.required_points(s), sk.spent_in(b)]
	if sk.choice_of(s) != "":
		var rivals: Array[String] = []
		for o in sk.all:
			if o != s and sk.choice_of(o) == sk.choice_of(s):
				rivals.append(o.display_name)
		text += "\n[color=#%s]Выбор пути: или этот навык, или %s (до сброса)[/color]" % [UIStyle.GOLD.darkened(0.4).to_html(false), ", ".join(rivals)]
	if sk.chosen_branch >= 0 and sk.branch_of(s) == sk.chosen_branch:
		text += "\n[color=%s]Ветка вашего пути[/color]" % UIStyle.GOOD_HEX
	elif sk.chosen_branch >= 0 and sk.branch_of(s) != sk.chosen_branch and rank == 0 and not sk.is_starting(s):
		text += "\n[color=#%s]Закрыто: путь выбран — «%s» (сменить можно сбросом навыков)[/color]" % [UIStyle.BAD.darkened(0.2).to_html(false), sk.branch_name_of(sk.chosen_branch)]
	if not sk.has_branches() and not s.requires.is_empty():
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
			text += "\n[color=#%s]Слот HUD: %s[/color]" % [UIStyle.INK_SOFT.to_html(false), InputBindings.key_for("skill_%d" % (slot + 1))]
	_text.text = text
	var reason := sk.block_reason(s, hero.level)
	_reason.text = reason
	_learn.text = "Изучить" if rank == 0 else "Улучшить"
	_learn.disabled = reason != ""


## Forget every learned skill for gold; the points come back.
func respec() -> void:
	var sk := hero.skills
	var cost := sk.respec_cost(hero.level)
	if sk.spent_total() <= 0 or not hero.spend_gold(cost):
		AudioManager.play_ui(&"chest_locked")
		return
	var back := sk.reset()
	EventBus.message.emit("Навыки сброшены: возвращено %d очк." % back)
	AudioManager.play_ui(&"ui_equip")
	_refresh()


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
