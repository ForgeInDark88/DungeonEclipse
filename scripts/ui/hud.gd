class_name HUD
extends CanvasLayer
## Bottom panel in the book style (see docs/hud_reference.png):
## portrait on the left, 8 skill slots on top, 7 quick slots below,
## HP / mana / XP bars on the right. Hovering the portrait shows all stats.

const PADDING := 12
const GAP := 3
const PORTRAIT := Vector2(56, 56)
const BARS_W := 104
const SKILL_KEYS := ["Q", "E", "R", "F", "", "", "", ""]

var hero: Hero
var _skill_slots: Array[SkillSlot] = []
var _quick_slots: Array[ItemSlot] = []
var _hp: StatBar
var _mana: StatBar
var _xp: StatBar
var _level_label: Label
var _floor_label: Label
var _message: Label
var _hint: Label
var _points_label: Label
var _portrait_holder: Control
var _message_tween: Tween


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS


func setup(p_hero: Hero, player: Player) -> void:
	hero = p_hero
	_build()
	hero.stats.hp_changed.connect(func(hp: int, mx: int) -> void: _hp.set_values(hp, mx))
	hero.stats.mana_changed.connect(func(m: int, mx: int) -> void: _mana.set_values(m, mx))
	hero.xp_changed.connect(func(_x: int, _n: int) -> void: _refresh_xp())
	hero.leveled_up.connect(_on_level_up)
	hero.inventory.changed.connect(_refresh_quick)
	hero.quick_bar.changed.connect(_refresh_quick)
	hero.skills.changed.connect(_refresh_skills)
	EventBus.message.connect(show_message)
	EventBus.floor_changed.connect(func(_f: int) -> void: _refresh_floor())
	player.interact_hint_changed.connect(func(t: String) -> void: _hint.text = t)
	_hp.set_values(hero.stats.hp, hero.stats.max_hp())
	_mana.set_values(hero.stats.mana, hero.stats.max_mana())
	_refresh_xp()
	_refresh_floor()
	_refresh_skills()


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var skills_w := SkillSet.SLOT_COUNT * UIStyle.SLOT_SIZE.x + (SkillSet.SLOT_COUNT - 1) * GAP
	var panel_size := Vector2(PADDING * 2 + PORTRAIT.x + 8 + skills_w + 10 + BARS_W,
			PADDING * 2 + UIStyle.SLOT_SIZE.y * 2 + SkillSlot.DOT_SIZE + 2 + GAP + 2)
	var panel := Control.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -panel_size.x / 2.0
	panel.offset_right = panel_size.x / 2.0
	panel.offset_top = -panel_size.y
	root.add_child(panel)
	panel.add_child(UIStyle.frame(AssetPaths.BOOK_PANEL, 30, 0.5))

	# Portrait
	var portrait := Control.new()
	portrait.position = Vector2(PADDING, (panel_size.y - PORTRAIT.y) / 2.0)
	portrait.size = PORTRAIT
	portrait.mouse_filter = Control.MOUSE_FILTER_STOP
	portrait.add_child(UIStyle.frame(AssetPaths.SLOT, 5))
	_portrait_holder = UIStyle.portrait(hero.race, hero.class_data, PORTRAIT - Vector2(8, 8))
	_portrait_holder.position = Vector2(4, 4)
	_portrait_holder.size = PORTRAIT - Vector2(8, 8)
	portrait.add_child(_portrait_holder)
	portrait.mouse_entered.connect(func() -> void: Tooltip.show_text(TooltipText.hero_stats(hero), portrait))
	portrait.mouse_exited.connect(func() -> void: Tooltip.hide_tip(portrait))
	panel.add_child(portrait)
	hero.stats.stats_changed.connect(func() -> void:
		if Tooltip.is_shown_for(portrait):
			Tooltip.show_text(TooltipText.hero_stats(hero), portrait))

	# Skills (top row) and quick slots (bottom row)
	var x0 := PADDING + PORTRAIT.x + 8
	for i in SkillSet.SLOT_COUNT:
		var s := SkillSlot.create(hero, i, SKILL_KEYS[i])
		s.position = Vector2(x0 + i * (UIStyle.SLOT_SIZE.x + GAP), PADDING)
		panel.add_child(s)
		_skill_slots.append(s)
	var quick_y := PADDING + UIStyle.SLOT_SIZE.y + SkillSlot.DOT_SIZE + 2 + GAP
	var quick_x := x0 + (UIStyle.SLOT_SIZE.x + GAP) / 2.0
	for i in QuickBar.SIZE:
		var q := ItemSlot.create(ItemSlot.Kind.QUICK, hero, i)
		q.key_label = str(i + 1)
		q.position = Vector2(quick_x + i * (UIStyle.SLOT_SIZE.x + GAP), quick_y)
		panel.add_child(q)
		_quick_slots.append(q)

	# Bars
	var bx := x0 + skills_w + 10
	_level_label = UIStyle.label("", 7, UIStyle.INK)
	_level_label.position = Vector2(bx, PADDING - 3)
	panel.add_child(_level_label)
	_hp = StatBar.create(AssetPaths.BAR_HP, Vector2(BARS_W, 12))
	_hp.position = Vector2(bx, PADDING + 9)
	panel.add_child(_hp)
	_mana = StatBar.create(AssetPaths.BAR_MANA, Vector2(BARS_W, 12))
	_mana.position = Vector2(bx, PADDING + 23)
	panel.add_child(_mana)
	_xp = StatBar.create(AssetPaths.BAR_XP, Vector2(BARS_W, 10))
	_xp.position = Vector2(bx, PADDING + 37)
	panel.add_child(_xp)
	_points_label = UIStyle.label("", 6, UIStyle.GOOD)
	_points_label.position = Vector2(bx, PADDING + 48)
	panel.add_child(_points_label)

	# Texts over the game
	_floor_label = UIStyle.outlined_label("", 9, UIStyle.GOLD)
	_floor_label.position = Vector2(8, 6)
	root.add_child(_floor_label)
	_hint = UIStyle.outlined_label("", 8, UIStyle.PARCHMENT)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.anchor_left = 0.0
	_hint.anchor_right = 1.0
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_top = -panel_size.y - 16
	_hint.offset_bottom = -panel_size.y - 4
	root.add_child(_hint)
	_message = UIStyle.outlined_label("", 9, Color.WHITE)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.anchor_left = 0.0
	_message.anchor_right = 1.0
	_message.offset_top = 22
	_message.offset_bottom = 36
	root.add_child(_message)


func _refresh_quick() -> void:
	for q in _quick_slots:
		q.refresh()


func _refresh_skills() -> void:
	for s in _skill_slots:
		s.refresh()
	var pts := hero.skills.skill_points
	_points_label.text = ("Очки навыков: %d (клик по навыку)" % pts) if pts > 0 else ""


func _refresh_xp() -> void:
	_xp.set_values(hero.xp, hero.xp_to_next(), "XP %d / %d" % [hero.xp, hero.xp_to_next()])
	_level_label.text = "Ур. %d  %s" % [hero.level, hero.class_data.display_name]


func _refresh_floor() -> void:
	_floor_label.text = "Этаж %d" % GameState.floor_number


func _on_level_up(new_level: int) -> void:
	_refresh_xp()
	_refresh_skills()
	show_message("Новый уровень: %d! Получено очко навыка." % new_level)


func show_message(text: String) -> void:
	_message.text = text
	_message.modulate.a = 1.0
	if _message_tween:
		_message_tween.kill()
	_message_tween = create_tween()
	_message_tween.tween_interval(2.0)
	_message_tween.tween_property(_message, "modulate:a", 0.0, 0.6)
