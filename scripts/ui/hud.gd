class_name HUD
extends CanvasLayer
## Bottom panel in the book style (see docs/hud_reference.png):
## portrait on the left, 8 skill slots on top, 7 quick slots below,
## HP / mana / XP bars on the right. Hovering the portrait shows all stats.

const PADDING := 12
const GAP := 3
const PORTRAIT := Vector2(72, 72)
const BARS_W := 104

var hero: Hero
var _skill_slots: Array[SkillSlot] = []
var _quick_slots: Array[ItemSlot] = []
var _hp: StatBar
var _mana: StatBar
var _xp: StatBar
var _level_label: Label
var _floor_label: Label
## Exit seal of the floor: "Печать: 3/8" under the floor plaque.
var _seal_label: Label
var _message: Label
var _hint: Label
var _points_label: Label
var _gold_label: Label
var _portrait_holder: Control
var _message_tween: Tween
var _player: Player
var _status_row: HBoxContainer
var _status_keys: Array[String] = []
var _boss_box: Control
var _boss_bar: StatBar
var _ally_box: VBoxContainer
var _boss_name: Label
var _panel: Control
## Kill streak (GameState.combo): shown from 2 kills, fades as its time runs out.
var _combo: Label


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS


## LAN co-op: small name + hp plates for the party (top right).
func add_ally(name_text: String, ally_hero: Hero) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 4)
	var lbl := UIStyle.outlined_label(name_text, 6, UIStyle.PARCHMENT)
	lbl.custom_minimum_size = Vector2(64, 10)
	row.add_child(lbl)
	var bar := StatBar.create(AssetPaths.BAR_HP, Vector2(60, 8))
	bar.set_values(ally_hero.stats.hp, ally_hero.stats.max_hp())
	ally_hero.stats.hp_changed.connect(func(hp: int, mx: int) -> void:
		bar.set_values(hp, mx)
		lbl.modulate.a = 0.45 if hp <= 0 else 1.0)
	row.add_child(bar)
	_ally_box.add_child(row)


func remove_ally(_peer_id: int) -> void:
	if _ally_box.get_child_count() > 0:
		_ally_box.get_child(_ally_box.get_child_count() - 1).queue_free()


func setup(p_hero: Hero, player: Player) -> void:
	hero = p_hero
	_player = player
	_build()
	_ally_box = VBoxContainer.new()
	_ally_box.position = Vector2(6, 34)  # under the floor plaque and the exit seal line
	_ally_box.add_theme_constant_override("separation", 2)
	_ally_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ally_box)
	hero.stats.hp_changed.connect(func(hp: int, mx: int) -> void: _hp.set_values(hp, mx))
	hero.stats.mana_changed.connect(func(m: int, mx: int) -> void: _mana.set_values(m, mx))
	hero.xp_changed.connect(func(_x: int, _n: int) -> void: _refresh_xp())
	hero.leveled_up.connect(_on_level_up)
	hero.gold_changed.connect(func(g: int) -> void:
		_gold_label.text = str(g)
		_pulse(_gold_label))
	_gold_label.text = str(hero.gold)
	hero.inventory.changed.connect(_refresh_quick)
	hero.quick_bar.changed.connect(_refresh_quick)
	hero.skills.changed.connect(_refresh_skills)
	EventBus.message.connect(show_message)
	SaveManager.settings_changed.connect(_refresh_key_labels)
	SaveManager.settings_changed.connect(_apply_scale)
	_apply_scale()
	EventBus.item_collected.connect(_fly_item)
	EventBus.boss_spawned.connect(_on_boss_spawned)
	EventBus.boss_hp_changed.connect(func(hp: int, mx: int) -> void: _boss_bar.set_values(hp, mx))
	EventBus.boss_defeated.connect(func(_b: BossData, _p: Vector2) -> void: _boss_box.visible = false)
	EventBus.floor_changed.connect(func(_f: int) -> void: _boss_box.visible = false)
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
	# Shrinks towards the bottom edge (Settings → «Размер панели»).
	panel.pivot_offset = Vector2(panel_size.x / 2.0, panel_size.y)
	_panel = panel
	root.add_child(panel)
	panel.add_child(UIStyle.frame(AssetPaths.BOOK_PANEL, 30, 0.5))
	# Metal rivets along the panel border (like the reference HUD).
	var rivet_tex := AssetPaths.tex(AssetPaths.RIVET)
	for x in [8.0, panel_size.x * 0.25, panel_size.x * 0.5, panel_size.x * 0.75, panel_size.x - 13.0]:
		for y in [3.0, panel_size.y - 8.0]:
			var r := TextureRect.new()
			r.texture = rivet_tex
			r.position = Vector2(x, y)
			r.mouse_filter = Control.MOUSE_FILTER_IGNORE
			panel.add_child(r)
	# Active buffs / statuses above the portrait.
	_status_row = HBoxContainer.new()
	_status_row.add_theme_constant_override("separation", 2)
	_status_row.position = Vector2(PADDING, -18)
	_status_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_status_row)

	# Portrait
	var portrait := Control.new()
	portrait.position = Vector2(PADDING, (panel_size.y - PORTRAIT.y) / 2.0)
	portrait.size = PORTRAIT
	portrait.mouse_filter = Control.MOUSE_FILTER_STOP
	portrait.add_child(UIStyle.frame(AssetPaths.SLOT, 5))
	# Living portrait (breathing, blinking, reactions): only in the game HUD.
	var live := AnimatedPortrait.new()
	live.position = Vector2(4, 4)
	live.size = PORTRAIT - Vector2(8, 8)
	portrait.add_child(live)
	live.setup(hero, _player)
	_portrait_holder = live
	portrait.mouse_entered.connect(func() -> void: Tooltip.show_text(TooltipText.hero_stats(hero), portrait))
	portrait.mouse_exited.connect(func() -> void: Tooltip.hide_tip(portrait))
	panel.add_child(portrait)
	hero.stats.stats_changed.connect(func() -> void:
		if Tooltip.is_shown_for(portrait):
			Tooltip.show_text(TooltipText.hero_stats(hero), portrait))

	# Skills (top row) and quick slots (bottom row)
	var x0 := PADDING + PORTRAIT.x + 8
	for i in SkillSet.SLOT_COUNT:
		var s := SkillSlot.create(hero, i, InputBindings.key_for("skill_%d" % (i + 1)))
		s.position = Vector2(x0 + i * (UIStyle.SLOT_SIZE.x + GAP), PADDING)
		panel.add_child(s)
		_skill_slots.append(s)
	var quick_y := PADDING + UIStyle.SLOT_SIZE.y + SkillSlot.DOT_SIZE + 2 + GAP
	var quick_x := x0 + (UIStyle.SLOT_SIZE.x + GAP) / 2.0
	for i in QuickBar.SIZE:
		var q := ItemSlot.create(ItemSlot.Kind.QUICK, hero, i)
		q.key_label = InputBindings.key_for("quick_%d" % (i + 1))
		q.position = Vector2(quick_x + i * (UIStyle.SLOT_SIZE.x + GAP), quick_y)
		panel.add_child(q)
		_quick_slots.append(q)

	# Bars
	var bx := x0 + skills_w + 10
	_level_label = UIStyle.label("", 7, UIStyle.INK)
	_level_label.position = Vector2(bx, PADDING - 3)
	panel.add_child(_level_label)
	var coin := TextureRect.new()
	coin.texture = AssetPaths.tex(AssetPaths.COIN_ICON)
	coin.position = Vector2(bx + BARS_W - 40, PADDING)
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(coin)
	_gold_label = UIStyle.label("0", 7, UIStyle.INK)
	_gold_label.position = Vector2(bx + BARS_W - 30, PADDING - 3)
	panel.add_child(_gold_label)
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
	var plaque := Control.new()
	plaque.position = Vector2(4, 3)
	plaque.size = Vector2(150, 18)
	plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plaque.add_child(UIStyle.frame(AssetPaths.BAR_FRAME, 3))
	root.add_child(plaque)
	_floor_label = UIStyle.outlined_label("", 8, UIStyle.GOLD)
	_floor_label.position = Vector2(6, 2)
	_floor_label.size = Vector2(140, 14)
	plaque.add_child(_floor_label)
	_seal_label = UIStyle.outlined_label("", 7, Color(1.0, 0.55, 0.5))
	_seal_label.position = Vector2(6, 21)
	_seal_label.visible = false
	root.add_child(_seal_label)
	EventBus.seal_changed.connect(_on_seal_changed)
	EventBus.floor_changed.connect(func(_f: int) -> void: _seal_label.visible = false)
	_hint = UIStyle.outlined_label("", 8, UIStyle.PARCHMENT)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.anchor_left = 0.0
	_hint.anchor_right = 1.0
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_top = -panel_size.y - 16
	_hint.offset_bottom = -panel_size.y - 4
	root.add_child(_hint)
	# Boss health bar (top centre).
	_boss_box = Control.new()
	_boss_box.anchor_left = 0.5
	_boss_box.anchor_right = 0.5
	_boss_box.offset_left = -140
	_boss_box.offset_right = 140
	_boss_box.offset_top = 22
	_boss_box.offset_bottom = 48
	_boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_box.visible = false
	root.add_child(_boss_box)
	_boss_name = UIStyle.outlined_label("", 9, UIStyle.GOLD)
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_name.size = Vector2(280, 12)
	_boss_box.add_child(_boss_name)
	_boss_bar = StatBar.create(AssetPaths.BAR_HP, Vector2(280, 12))
	_boss_bar.position = Vector2(0, 13)
	_boss_box.add_child(_boss_bar)
	# Boss intro card and phase banners (over the world, under messages).
	root.add_child(BossStage.new())
	# Co-op: arrows to the allies out of sight (screen space, not the scaled root).
	add_child(AllyArrows.new())
	_message = UIStyle.outlined_label("", 9, Color.WHITE)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.anchor_left = 0.0
	_message.anchor_right = 1.0
	_message.offset_top = 52
	_message.offset_bottom = 66
	root.add_child(_message)
	_combo = UIStyle.outlined_label("", 10, UIStyle.GOLD)
	_combo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_combo.anchor_left = 0.0
	_combo.anchor_right = 1.0
	_combo.offset_top = 68
	_combo.offset_bottom = 82
	_combo.pivot_offset = Vector2(320, 7)
	_combo.visible = false
	root.add_child(_combo)
	EventBus.combo_changed.connect(_on_combo)


func _on_combo(combo: int) -> void:
	_combo.visible = combo >= 2
	if combo < 2:
		return
	_combo.text = "Комбо ×%d  +%d%% опыта и золота" % [combo, roundi(GameState.combo_bonus() * 100.0)]
	_combo.scale = Vector2(1.3, 1.3)
	create_tween().tween_property(_combo, "scale", Vector2.ONE, 0.2)


func _on_boss_spawned(b: Node) -> void:
	var boss := b as Boss
	_boss_name.text = boss.boss.title
	_boss_box.visible = true
	_boss_bar.set_values(boss.hp, boss.max_hp)
	_boss_box.modulate.a = 0.0
	create_tween().tween_property(_boss_box, "modulate:a", 1.0, 0.6)


func _refresh_quick() -> void:
	for q in _quick_slots:
		q.refresh()


func _apply_scale() -> void:
	var k := clampf(SaveManager.hud_scale, 0.6, 1.0)
	_panel.scale = Vector2(k, k)


## Key hints follow the player's bindings (settings → controls).
func _refresh_key_labels() -> void:
	for i in _skill_slots.size():
		_skill_slots[i].set_key_label(InputBindings.key_for("skill_%d" % (i + 1)))
	for i in _quick_slots.size():
		_quick_slots[i].set_key_label(InputBindings.key_for("quick_%d" % (i + 1)))


func _refresh_skills() -> void:
	for s in _skill_slots:
		s.refresh()
	var pts := hero.skills.skill_points
	_points_label.text = ("Очки навыков: %d (K — дерево навыков)" % pts) if pts > 0 else ""


func _refresh_xp() -> void:
	_xp.set_values(hero.xp, hero.xp_to_next(), "XP %d / %d" % [hero.xp, hero.xp_to_next()])
	_level_label.text = "Ур. %d  %s" % [hero.level, hero.class_data.display_name]


func _on_seal_changed(kills: int, required: int) -> void:
	if required <= 0:
		_seal_label.visible = false
		return
	_seal_label.visible = true
	if kills < required:
		_seal_label.text = "Печать выхода: %d / %d" % [kills, required]
		_seal_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5))
	else:
		_seal_label.text = "Выход открыт"
		_seal_label.add_theme_color_override("font_color", Color(0.75, 0.6, 1.0))


func _refresh_floor() -> void:
	var biome := GameState.current_biome()
	_floor_label.text = "Этаж %d · %s" % [GameState.floor_number, biome.display_name] if biome else "Этаж %d" % GameState.floor_number
	if GameState.eclipse_level > 0:
		_floor_label.text += " · Затмение %d" % GameState.eclipse_level
	if GameState.is_town():
		_floor_label.text = biome.display_name if biome else "Город"
	var diff := GameState.difficulty
	if diff and diff.id != &"normal":
		_floor_label.text += " · " + diff.display_name
	var plaque := _floor_label.get_parent() as Control
	plaque.size.x = _floor_label.get_minimum_size().x + 14


func _process(_delta: float) -> void:
	if _combo and _combo.visible:
		_combo.modulate.a = clampf(GameState.combo_time_left() / 1.5, 0.25, 1.0)
	if _player == null or not is_instance_valid(_player):
		return
	var entries := _player.get_buffs()
	for id: StringName in _player.status.active:
		entries.append({"key": "st_" + String(id), "left": _player.status.active[id]["time"],
				"duration": _player.status.active[id]["duration"], "icon": StatusEffects.icon_of(id),
				"tint": StatusEffects.color_of(id), "negative": id in StatusEffects.NEGATIVE})
	_update_status_row(entries)


## Icons of active buffs (and later statuses) with a shrinking timer bar.
func _update_status_row(buffs: Array[Dictionary]) -> void:
	var keys: Array[String] = []
	for b in buffs:
		keys.append(b["key"])
	if keys != _status_keys:
		_status_keys = keys
		for c in _status_row.get_children():
			c.queue_free()
		for b in buffs:
			var box := Control.new()
			box.custom_minimum_size = Vector2(14, 16)
			box.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var bg := ColorRect.new()
			bg.color = Color(0.45, 0.05, 0.05, 0.9) if b.get("negative", false) else Color(0.1, 0.06, 0.04, 0.85)
			bg.size = Vector2(14, 14)
			box.add_child(bg)
			var icon := TextureRect.new()
			icon.texture = b["icon"]
			icon.position = Vector2(1, 1)
			icon.size = Vector2(12, 12)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			box.add_child(icon)
			var bar := ColorRect.new()
			bar.name = "Bar"
			bar.color = b["tint"]
			bar.position = Vector2(0, 14)
			bar.size = Vector2(14, 2)
			box.add_child(bar)
			_status_row.add_child(box)
	var i := 0
	for c in _status_row.get_children():
		if i < buffs.size() and not c.is_queued_for_deletion():
			var bar := c.get_node_or_null("Bar") as ColorRect
			if bar:
				bar.size.x = 14.0 * clampf(buffs[i]["left"] / maxf(0.01, buffs[i]["duration"]), 0.0, 1.0)
			i += 1


func _on_level_up(new_level: int) -> void:
	_refresh_xp()
	_refresh_skills()
	show_message("Получено очко навыка — K: дерево навыков, клик по слоту: улучшить.")
	var banner := LevelUpBanner.new()
	banner.level_number = new_level
	add_child(banner)
	_pulse(_portrait_holder.get_parent() as Control)


## Item icon flies from the world to its quick slot (or to the portrait).
func _fly_item(item: ItemData, world_pos: Vector2) -> void:
	var start := get_viewport().get_canvas_transform() * world_pos
	var target_ctrl: Control = _portrait_holder
	for q in _quick_slots:
		if q.get_item() == item:
			target_ctrl = q
			break
	var target := target_ctrl.get_global_rect().get_center()
	var icon := TextureRect.new()
	icon.texture = item.icon
	icon.size = Vector2(16, 16)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.pivot_offset = Vector2(8, 8)
	icon.position = start - Vector2(8, 8)
	add_child(icon)
	var dur := 0.5
	var tw := create_tween().set_parallel()
	tw.tween_property(icon, "position:x", target.x - 8.0, dur).set_trans(Tween.TRANS_SINE)
	# Arc: first up, then down into the slot.
	var up := create_tween()
	up.tween_property(icon, "position:y", minf(start.y, target.y) - 30.0, dur * 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	up.tween_property(icon, "position:y", target.y - 8.0, dur * 0.6).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(icon, "scale", Vector2(1.4, 1.4), dur * 0.4)
	tw.chain().tween_callback(func() -> void:
		icon.queue_free()
		if target_ctrl is ItemSlot:
			(target_ctrl as ItemSlot).pop()
		else:
			_pulse(target_ctrl.get_parent() as Control))


func _pulse(ctrl: Control) -> void:
	if ctrl == null:
		return
	ctrl.pivot_offset = ctrl.size / 2.0
	ctrl.scale = Vector2(1.12, 1.12)
	create_tween().tween_property(ctrl, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func show_message(text: String) -> void:
	_message.text = text
	_message.modulate.a = 1.0
	if _message_tween:
		_message_tween.kill()
	_message_tween = create_tween()
	_message_tween.tween_interval(2.0)
	_message_tween.tween_property(_message, "modulate:a", 0.0, 0.6)
