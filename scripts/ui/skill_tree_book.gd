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
const NODE_SIZE := Vector2(22, 22)
## Tier-5 capstones get the big octagon frame.
const KEYSTONE_SIZE := Vector2(30, 30)
const ROW_GAP := 62.0
## Tier step of the trident fan (row 0 under the crest, capstones at the bottom).
const BRANCH_ROW_GAP := 26.0
const PASSIVE_TINT := Color(0.75, 0.6, 1.0)
## Red / green / orange branches of the eclipse tree (by branch index).
const BRANCH_COLORS: Array[Color] = [
	Color(0.92, 0.32, 0.35),
	Color(0.45, 0.85, 0.50),
	Color(1.0, 0.68, 0.30),
]

const CREST_TEX := preload("res://assets/ui/tree_crest.png")
const NODE_TEX := preload("res://assets/ui/tree_node.png")
const KEYSTONE_TEX := preload("res://assets/ui/tree_keystone.png")
const BG_TEX := preload("res://assets/ui/tree_bg.png")

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
	# Night-town backdrop instead of the parchment book.
	var bg := TextureRect.new()
	bg.texture = BG_TEX
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)

	var page_w := BOOK_SIZE.x / 2.0 - BOOK_MARGIN - 8
	var page_h := BOOK_SIZE.y - BOOK_MARGIN * 2
	var head := UIStyle.outlined_label("Навыки: %s" % hero.class_data.display_name, 10, UIStyle.PARCHMENT)
	head.position = Vector2(BOOK_MARGIN + 4, BOOK_MARGIN - 6)
	head.size = Vector2(page_w, 14)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(head)
	_tree_area = Control.new()
	_tree_area.position = Vector2(BOOK_MARGIN + 4, BOOK_MARGIN + 24)
	_tree_area.size = Vector2(page_w, page_h - 40)
	_tree_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_tree_area)
	_points = UIStyle.outlined_label("", 7, UIStyle.PARCHMENT)
	_points.position = Vector2(BOOK_MARGIN + 4, BOOK_SIZE.y - BOOK_MARGIN - 14)
	_points.size = Vector2(page_w, 12)
	_points.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_points)

	var right := VBoxContainer.new()
	right.position = Vector2(BOOK_SIZE.x / 2.0 + 8, BOOK_MARGIN)
	right.size = Vector2(page_w - 4, page_h)
	right.add_theme_constant_override("separation", 3)
	_root.add_child(right)
	# Translucent notice board over the night backdrop.
	var board := ColorRect.new()
	board.color = Color(0.07, 0.05, 0.1, 0.72)
	board.position = right.position - Vector2(6, 4)
	board.size = right.size + Vector2(12, 8)
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(board)
	_root.move_child(board, _root.get_child_count() - 2)
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
	_title = UIStyle.label("", 10, UIStyle.PARCHMENT)
	_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_title)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.add_theme_color_override("default_color", UIStyle.PARCHMENT)
	for k in ["normal_font_size", "bold_font_size", "italics_font_size"]:
		_text.add_theme_font_size_override(k, 7)
	right.add_child(_text)
	_reason = UIStyle.label("", 7, Color(1.0, 0.45, 0.4))
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


## Three straight streets under the eclipse crest: a column per branch,
## one node per tier (choice pairs side by side), capstones at the bottom.
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
			var dx := (i - (list.size() - 1) / 2.0) * 26.0
			pos[list[i].id] = Vector2(cx + dx, 44.0 + row * BRANCH_ROW_GAP)
	return pos


func branch_color(b: int) -> Color:
	return BRANCH_COLORS[b % BRANCH_COLORS.size()] if b >= 0 else Color.WHITE


func _is_keystone(s: SkillData) -> bool:
	return hero.skills.row_of(s) >= 5


func _node_size(s: SkillData) -> Vector2:
	return KEYSTONE_SIZE if _is_keystone(s) else NODE_SIZE


func _line(a: Vector2, b: Vector2, lit: bool, color: Color = UIStyle.GOOD) -> void:
	var line := Line2D.new()
	line.width = 2.0
	line.default_color = color if lit else Color(color.r, color.g, color.b, 0.32)
	line.add_point(a)
	line.add_point(b)
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
				head = UIStyle.label("✦ %s · %d" % [sk.branch_names[b], sk.spent_in(b)], 7, branch_color(b))
			elif sk.chosen_branch >= 0 and b != sk.chosen_branch:
				head = UIStyle.label("%s · закрыто" % sk.branch_names[b], 7, Color(0.75, 0.72, 0.68))
			else:
				head = UIStyle.label("%s · %d" % [sk.branch_names[b], sk.spent_in(b)], 7, branch_color(b).darkened(0.25))
			head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			head.position = Vector2(_tree_area.size.x * b / cols, 0)
			head.size = Vector2(_tree_area.size.x / cols, 12)
			_tree_area.add_child(head)
		# The eclipse crest at the top, roots of the three branches.
		var crest := TextureRect.new()
		crest.texture = CREST_TEX
		crest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		crest.position = Vector2(_tree_area.size.x / 2.0 - 10.0, 16.0)
		crest.size = Vector2(20, 20)
		crest.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tree_area.add_child(crest)
		# Branch spines: crest -> tier 0 -> ... -> capstone, in the branch color.
		var mids := {}  # Vector2i(branch, row) -> center of the tier
		for s in sk.all:
			var k := Vector2i(sk.branch_of(s), sk.row_of(s))
			if mids.has(k):
				mids[k] = (mids[k] + pos[s.id]) / 2.0
			else:
				mids[k] = pos[s.id]
		var learned_row := {}  # Vector2i(branch, row) -> any skill learned
		for s in sk.all:
			var k2 := Vector2i(sk.branch_of(s), sk.row_of(s))
			learned_row[k2] = learned_row.get(k2, false) or sk.is_learned(s)
		var crest_center := Vector2(_tree_area.size.x / 2.0, 26.0)
		for b in sk.branch_names.size():
			var col := branch_color(b)
			var prev := crest_center
			var rows := []
			for k3: Vector2i in mids:
				if k3.x == b:
					rows.append(k3.y)
			rows.sort()
			for r in rows:
				var to: Vector2 = mids[Vector2i(b, r)]
				_line(prev, to, learned_row.get(Vector2i(b, r), false), col)
				prev = to
	# Prerequisite lines first, so the nodes are drawn over them.
	for s in sk.all:
		if sk.has_branches():
			break
		for r in s.requires:
			if r == null or not pos.has(r.id):
				continue
			var line := Line2D.new()
			line.width = 2.0
			line.default_color = "#7ddc7d" if sk.is_learned(r) else Color(0.8, 0.75, 0.7, 0.5)
			line.add_point(pos[r.id] + Vector2(0, NODE_SIZE.y / 2.0))
			line.add_point(pos[s.id] - Vector2(0, NODE_SIZE.y / 2.0))
			_tree_area.add_child(line)
	for s in sk.all:
		var node := _node(s)
		node.position = pos[s.id] - _node_size(s) / 2.0
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
	var col := branch_color(sk.branch_of(s))
	var size := _node_size(s)
	var box := Control.new()
	box.size = size
	box.custom_minimum_size = size
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	var frame := TextureRect.new()
	frame.texture = KEYSTONE_TEX if _is_keystone(s) else NODE_TEX
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.size = size
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if rank <= 0 and sk.chosen_rival(s) != null:
		frame.modulate = Color(0.42, 0.4, 0.44, 0.6)  # choice lost to the rival
	elif rank <= 0 and sk.chosen_branch >= 0 and sk.branch_of(s) != sk.chosen_branch:
		frame.modulate = Color(0.42, 0.42, 0.48, 0.55)  # branch closed by the choice
	elif rank > 0:
		frame.modulate = col  # learned: full branch color
	elif available:
		frame.modulate = col.lightened(0.18)
	else:
		frame.modulate = Color(col.darkened(0.45).r, col.darkened(0.45).g, col.darkened(0.45).b, 0.62)
	box.add_child(frame)
	var icon := TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.texture = s.icon
	var inset := Vector2(3, 3) if not _is_keystone(s) else Vector2(5, 5)
	icon.position = inset
	icon.size = size - inset * 2.0
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if rank <= 0:
		icon.modulate = Color(1, 1, 1, 0.8) if available else Color(0.3, 0.3, 0.34, 0.7)
	box.add_child(icon)
	var lvl := UIStyle.outlined_label("%d/%d" % [rank, s.max_level], 6, UIStyle.GOLD if rank > 0 else UIStyle.PARCHMENT)
	lvl.position = Vector2(size.x - 15, size.y - 9)
	box.add_child(lvl)
	if available:
		var plus := UIStyle.outlined_label("+", 9, Color(0.4, 1.0, 0.4))
		plus.position = Vector2(size.x - 7, -4)
		box.add_child(plus)
	if s == _selected:
		var sel := ColorRect.new()
		sel.color = Color(1, 0.9, 0.4, 0.25)
		sel.position = Vector2(3, 3)
		sel.size = size - Vector2(6, 6)
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
	var soft := UIStyle.PARCHMENT.darkened(0.35).to_html(false)
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
		text += "\n[color=%s]Ветка вашего пути[/color]"  % "#7ddc7d"
	elif sk.chosen_branch >= 0 and sk.branch_of(s) != sk.chosen_branch and rank == 0:
		text += "\n[color=#%s]Закрыто: путь выбран — «%s» (сменить можно сбросом навыков)[/color]" % [UIStyle.BAD.darkened(0.2).to_html(false), sk.branch_name_of(sk.chosen_branch)]
	if not sk.has_branches() and not s.requires.is_empty():
		var names: Array[String] = []
		for r in s.requires:
			if r:
				names.append(r.display_name)
		text += "\n[color=#%s]После: %s[/color]" % [UIStyle.PARCHMENT.darkened(0.35).to_html(false), ", ".join(names)]
	var w := hero.weapon()
	if s.has_synergy(w):
		text += "\n[color=%s]Синергия активна: %s[/color]" % ["#7ddc7d", w.display_name]
	if not s.is_passive():
		var slot := sk.skills.find(s)
		if slot >= 0:
			text += "\n[color=#%s]Слот HUD: %s[/color]" % [UIStyle.PARCHMENT.darkened(0.35).to_html(false), InputBindings.key_for("skill_%d" % (slot + 1))]
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
