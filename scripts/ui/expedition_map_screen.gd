extends Control
## The expedition map on parchment: regions side by side, the road's forks,
## nodes done / open / out of reach, the fog beyond the scouts' sight, signs
## on some nodes, the hero's banner walking to the picked node. Only the
## nodes next to the hero can be picked; there is no way back on the map
## (home goes through a camp, or right after a region guardian).
## Debug builds show the map seed; F5 rerolls a map not yet walked.

const COL_W := 46.0
const LANE_H := 50.0
const TOP := 34.0
const LEFT := 40.0
## Steps ahead whose node types are seen (+1 per level of the scout tower).
const BASE_SIGHT := 3

var _run: RunState
var _canvas: MapCanvas
var _scroll: ScrollContainer
var _buttons: Dictionary = {}  # node id -> Button
var _hero_marker: TextureRect
var _moving := false
var _inventory: InventoryBook
var _menu: Control
var _seed_label: Label


func _ready() -> void:
	get_tree().paused = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_run = GameState.run
	if _run == null:
		return
	AudioManager.play_music(&"menu")
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.035, 0.06)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# One whole parchment sheet (book_panel: no spine down the middle).
	var sheet := UIStyle.frame(AssetPaths.BOOK_PANEL, 30, 0.5)
	sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	sheet.offset_left = 6
	sheet.offset_top = 6
	sheet.offset_right = -6
	sheet.offset_bottom = -6
	add_child(sheet)
	_build_top_bar()
	_build_hero_panel()
	_build_map()
	_inventory = InventoryBook.new()
	add_child(_inventory)
	_inventory.setup(GameState.hero)
	_center_on_hero.call_deferred()


# ------------------------------------------------------------------ layout
func _build_top_bar() -> void:
	var bar := HBoxContainer.new()
	bar.position = Vector2(24, 18)
	bar.size = Vector2(592, 16)
	bar.add_theme_constant_override("separation", 6)
	add_child(bar)
	var here := _run.current_node()
	var reg: RegionData = _run.map.region_of(int(here["id"])) if not here.is_empty() else _run.map.regions[0]
	var title := UIStyle.label(tr("Карта похода — %s") % reg.display_name, 10)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(title)
	if OS.is_debug_build():
		_seed_label = UIStyle.label(tr("сид %d (F5 — новая карта)") % _run.seed_value, 6, UIStyle.INK_SOFT)
		bar.add_child(_seed_label)
	bar.add_child(_small_button(tr("Сумка (I)"), func() -> void: _inventory.toggle()))
	if _can_go_home():
		var home_text := tr("Вернуться в город") if _run.node_id < 0 else tr("Домой с добычей")
		bar.add_child(_small_button(home_text, func() -> void: GameFlow.retreat()))
	bar.add_child(_small_button(tr("Меню"), _toggle_menu))


## Home from the map: before the first step (nothing is lost) or right
## after a region guardian (the reward of the road).
func _can_go_home() -> bool:
	return _run.node_id < 0 or StringName(_run.current_node().get("type", &"")) == &"boss"


func _small_button(text: String, cb: Callable) -> Button:
	var b := BookPageScreen.button(text, cb)
	b.add_theme_font_size_override("font_size", 7)
	b.focus_mode = Control.FOCUS_NONE
	return b


func _build_hero_panel() -> void:
	var hero := GameState.hero
	var box := VBoxContainer.new()
	box.position = Vector2(24, 40)
	box.size = Vector2(104, 290)
	box.add_theme_constant_override("separation", 2)
	add_child(box)
	box.add_child(UIStyle.label("%s %s" % [hero.race.display_name, hero.class_data.display_name], 8))
	box.add_child(UIStyle.label(tr("Уровень %d") % hero.level, 7, UIStyle.INK_SOFT))
	box.add_child(UIStyle.label(tr("Здоровье: %d / %d") % [hero.stats.hp, hero.stats.max_hp()], 7))
	box.add_child(UIStyle.label(tr("Мана: %d / %d") % [hero.stats.mana, hero.stats.max_mana()], 7))
	box.add_child(UIStyle.label(tr("Золото: %d") % hero.gold, 7))
	box.add_child(UIStyle.label(tr("Узлов пройдено: %d") % _run.path.size(), 7))
	var res := ""
	for k in _run.resources:
		res += "%s: %d\n" % [TownResources.display_name(StringName(k)), int(_run.resources[k])]
	if res != "":
		box.add_child(UIStyle.label(tr("Найдено для города:"), 7, UIStyle.INK_SOFT))
		box.add_child(UIStyle.label(res.strip_edges(), 7))
	if not _run.rescued.is_empty():
		box.add_child(UIStyle.label(tr("Спасено: %d") % _run.rescued.size(), 7))
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(fill)
	var legend := UIStyle.label(tr("Выберите соседний узел.\nНазад по карте пути нет."), 6, UIStyle.INK_SOFT)
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	legend.custom_minimum_size = Vector2(104, 0)
	box.add_child(legend)


func _build_map() -> void:
	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(132, 38)
	_scroll.size = Vector2(486, 290)
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_canvas = MapCanvas.new()
	_canvas.screen = self
	_canvas.custom_minimum_size = Vector2(LEFT + (_run.map.columns() + 0.5) * COL_W, 280)
	_scroll.add_child(_canvas)
	var open := _run.next_choices()
	var first_open: Button = null
	for n in _run.map.nodes:
		var id: int = n["id"]
		var b := Button.new()
		b.flat = true
		b.focus_mode = Control.FOCUS_ALL
		b.custom_minimum_size = Vector2(18, 18)
		b.size = Vector2(18, 18)
		b.position = node_pos(id) - Vector2(9, 9)
		for style in ["normal", "hover", "pressed", "disabled"]:
			b.add_theme_stylebox_override(style, StyleBoxEmpty.new())
		b.add_theme_stylebox_override("focus", _focus_box())
		var icon := TextureRect.new()
		icon.texture = AssetPaths.map_icon(_icon_kind(n))
		icon.position = Vector2(1, 1)
		icon.size = Vector2(16, 16)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(icon)
		var state := _state(id, open)
		match state:
			&"done":
				b.modulate = Color(0.75, 0.68, 0.6, 0.85)
			&"locked":
				b.modulate = Color(0.62, 0.58, 0.55, 0.75)
		b.disabled = state != &"open"
		b.pressed.connect(func() -> void: _walk_to(id))
		b.mouse_entered.connect(func() -> void: Tooltip.show_text(_tooltip(id), b))
		b.mouse_exited.connect(func() -> void: Tooltip.hide_tip(b))
		b.focus_entered.connect(func() -> void: Tooltip.show_text(_tooltip(id), b))
		b.focus_exited.connect(func() -> void: Tooltip.hide_tip(b))
		_canvas.add_child(b)
		_buttons[id] = b
		if state == &"open":
			var tw := b.create_tween().set_loops()
			tw.tween_property(b, "scale", Vector2(1.12, 1.12), 0.5).set_trans(Tween.TRANS_SINE)
			tw.tween_property(b, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_SINE)
			b.pivot_offset = Vector2(9, 9)
			if first_open == null:
				first_open = b
		var hint := StringName(n["hint"])
		if hint != &"" and _hint_seen(id):
			var h := TextureRect.new()
			h.texture = AssetPaths.map_hint(hint)
			h.position = node_pos(id) + Vector2(4, -13)
			h.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_canvas.add_child(h)
	_hero_marker = TextureRect.new()
	_hero_marker.texture = AssetPaths.tex(AssetPaths.MAP_HERO)
	_hero_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero_marker.position = _hero_pos() - Vector2(6, 26)
	_canvas.add_child(_hero_marker)
	if first_open:
		first_open.grab_focus()


func _focus_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = Color(0.75, 0.15, 0.1)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(9)
	return sb


# ----------------------------------------------------------------- queries
func node_pos(id: int) -> Vector2:
	var n := _run.map.node(id)
	return Vector2(LEFT + int(n["col"]) * COL_W, TOP + 12.0 + int(n["lane"]) * LANE_H)


## The town gate, left of the first step.
func gate_pos() -> Vector2:
	return Vector2(LEFT - COL_W * 0.6, TOP + 12.0 + 1.5 * LANE_H)


func _hero_pos() -> Vector2:
	return node_pos(_run.node_id) if _run.node_id >= 0 else gate_pos()


func _hero_col() -> int:
	return int(_run.current_node().get("col", -1))


## &"done" (walked), &"open" (next to the hero), &"locked".
func _state(id: int, open: Array[int]) -> StringName:
	if id in _run.path:
		return &"done"
	return &"open" if id in open else &"locked"


func node_state(id: int) -> StringName:
	return _state(id, _run.next_choices())


## The node's type is known: within the scouts' sight, walked, or a guardian.
func is_revealed(id: int) -> bool:
	var n := _run.map.node(id)
	if id in _run.path or StringName(n["type"]) == &"boss":
		return true
	return int(n["col"]) - _hero_col() <= sight()


func sight() -> int:
	var town := GameState.town
	return BASE_SIGHT + (town.building_level(&"scout_tower") if town else 0)


## Signs show within sight; the cartographer reads them on the whole map.
func _hint_seen(id: int) -> bool:
	return is_revealed(id) or _has_cartographer()


## The cartographer in town (or the tavern's rumours this time) reads
## every sign on the map and names the rewards exactly.
func _has_cartographer() -> bool:
	return (GameState.town != null and GameState.town.has_resident(&"cartographer")) \
			or _run.flags.get("rumours", false)


func _icon_kind(n: Dictionary) -> StringName:
	if not is_revealed(int(n["id"])):
		return &"unknown"
	if StringName(n["sub"]) != &"":
		return StringName(n["sub"])
	return StringName(n["type"])


# ----------------------------------------------------------------- tooltip
func _tooltip(id: int) -> String:
	var n := _run.map.node(id)
	var reg := _run.map.region_of(id)
	if not is_revealed(id):
		var t := "[b]%s[/b]\n%s" % [tr("Неизвестно"), tr("Слишком далеко: разведчики не видят, что там.")]
		if StringName(n["hint"]) != &"" and _hint_seen(id):
			t += "\n" + tr(ExpeditionMap.HINT_TEXT[StringName(n["hint"])])
		return t
	var type := StringName(n["type"])
	var name := ExpeditionMap.type_name(type)
	if StringName(n["sub"]) != &"":
		name = tr(ExpeditionMap.SPECIAL_NAMES[StringName(n["sub"])])
	var lines: Array[String] = ["[b]%s[/b]" % name, ExpeditionMap.type_description(type)]
	var biome := ItemDatabase.biome_by_id(StringName(n["biome"]))
	lines.append(tr("%s · глубина %d") % [biome.display_name if biome else (reg.display_name if reg else ""), int(n["depth"])])
	if type in [&"boss", &"lair"]:
		var bd := ItemDatabase.boss_by_id(StringName(n["boss"]))
		if bd:
			lines.append(tr("Страж: %s") % bd.display_name)
	if not type in [&"camp", &"event"]:
		lines.append(tr("Опасность: %s") % _danger_text(n))
	lines.append(tr("Награда: %s") % _reward_text(n))
	if StringName(n["hint"]) != &"" and _hint_seen(id):
		lines.append("[color=#8a2a1e]%s[/color]" % tr(ExpeditionMap.HINT_TEXT[StringName(n["hint"])]))
	match node_state(id):
		&"done":
			lines.append("[i]%s[/i]" % tr("Пройдено"))
		&"locked":
			lines.append("[i]%s[/i]" % tr("Недоступно: не соседний узел"))
	return "\n".join(lines)


## Danger from the node's depth against the hero's level: ●●●··.
func _danger_text(n: Dictionary) -> String:
	var hero := GameState.hero
	var diff := int(n["depth"]) - (hero.level if hero else 1)
	var stars := 1 if diff <= -3 else (2 if diff <= 0 else (3 if diff <= 3 else 4))
	match StringName(n["type"]):
		&"elite":
			stars += 1
		&"lair", &"boss":
			stars += 2
	stars = clampi(stars, 1, 5)
	return "●".repeat(stars) + "·".repeat(5 - stars)  # (two ○ fuse into ∞ in the pixel font)


func _reward_text(n: Dictionary) -> String:
	var type := StringName(n["type"])
	var exact := _has_cartographer()
	match type:
		&"level":
			return tr("золото, снаряжение, немного ресурсов") if exact else tr("обычная")
		&"elite":
			return tr("редкие предметы, осколки") if exact else tr("выше обычной")
		&"special":
			match StringName(n["sub"]):
				&"cache":
					return tr("много сундуков и золота")
				&"mine":
					return tr("руда и камень для города")
				&"crypt":
					return tr("реликвии и проклятое добро")
		&"camp":
			return tr("отдых, торговля, дорога домой")
		&"rescue":
			return tr("новый житель города")
		&"event":
			return tr("зависит от выбора")
		&"lair":
			return tr("трофей стража, реликвия")
		&"boss":
			return tr("трофей региона, путь дальше")
	return "?"


# ------------------------------------------------------------------ moving
func _walk_to(id: int) -> void:
	if _moving or not id in _run.next_choices():
		return
	_moving = true
	Tooltip.hide_tip()
	AudioManager.play_ui(&"ui_click")
	var tw := create_tween()
	tw.tween_property(_hero_marker, "position", node_pos(id) - Vector2(6, 26), 0.55) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_interval(0.15)
	tw.tween_callback(func() -> void: GameFlow.enter_node(id))


func _center_on_hero() -> void:
	if _scroll:
		_scroll.scroll_horizontal = int(maxf(0.0, _hero_pos().x - 120.0))


# ------------------------------------------------------------------- input
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F5 and OS.is_debug_build():
		if _run.node_id < 0:
			GameFlow.reroll_map()
			get_tree().reload_current_scene()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause") and not _inventory.is_open:
		_toggle_menu()
		get_viewport().set_input_as_handled()


func _toggle_menu() -> void:
	if _menu:
		_menu.queue_free()
		_menu = null
		return
	_menu = PanelContainer.new()
	_menu.add_theme_stylebox_override("panel", UIStyle.texture_box(AssetPaths.TOOLTIP, 4))
	_menu.position = Vector2(470, 40)
	var box := VBoxContainer.new()
	_menu.add_child(box)
	box.add_child(BookPageScreen.button(tr("Настройки"), func() -> void: add_child(SettingsBook.new())))
	box.add_child(BookPageScreen.button(tr("Как играть"), func() -> void: add_child(InfoBook.how_to_play())))
	box.add_child(BookPageScreen.button(tr("В главное меню"), func() -> void: GameFlow.quit_to_menu()))
	box.add_child(UIStyle.label(tr("(выход посреди похода — поход провален)"), 6, UIStyle.INK_SOFT))
	add_child(_menu)


## Lines of the road, region bands and names, the town gate.
class MapCanvas extends Control:
	var screen: Control

	func _draw() -> void:
		var run: RunState = GameState.run
		if run == null:
			return
		var map := run.map
		# region bands
		for ri in map.regions.size():
			var cols := map.nodes_of(ri)
			if cols.is_empty():
				continue
			var c0 := 9999
			var c1 := 0
			for n in cols:
				c0 = mini(c0, int(n["col"]))
				c1 = maxi(c1, int(n["col"]))
			var x0: float = screen.LEFT + (c0 - 0.5) * screen.COL_W
			var x1: float = screen.LEFT + (c1 + 0.5) * screen.COL_W
			var reg := map.regions[ri]
			draw_rect(Rect2(x0, 4, x1 - x0, size.y - 8), Color(reg.color, 0.10))
			draw_line(Vector2(x1, 8), Vector2(x1, size.y - 8), Color(reg.color, 0.45), 1.0)
			var font := get_theme_default_font()
			draw_string(font, Vector2(x0 + 4, 16), reg.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(reg.color.darkened(0.3), 0.9))
		# the gate
		var gp: Vector2 = screen.gate_pos()
		draw_rect(Rect2(gp - Vector2(7, 9), Vector2(14, 14)), Color(0.45, 0.32, 0.2))
		draw_rect(Rect2(gp - Vector2(4, 5), Vector2(8, 10)), Color(0.12, 0.08, 0.05))
		# roads
		var walked := run.path
		var prev := -1
		for id in walked:
			if prev >= 0:
				_road(screen.node_pos(prev), screen.node_pos(id), Color(0.6, 0.12, 0.08), 2.0, false)
			else:
				_road(gp, screen.node_pos(id), Color(0.6, 0.12, 0.08), 2.0, false)
			prev = id
		var open := run.next_choices()
		for n in map.nodes:
			var id: int = n["id"]
			for to in n["links"]:
				var active: bool = id == run.node_id and to in open
				if id in walked and to in walked:
					continue
				_road(screen.node_pos(id), screen.node_pos(to),
						Color(0.4, 0.22, 0.1, 0.95) if active else Color(0.35, 0.24, 0.15, 0.4), 1.0, not active)
		if run.node_id < 0:
			for to in open:
				_road(gp, screen.node_pos(to), Color(0.4, 0.22, 0.1, 0.95), 1.0, false)

	func _road(a: Vector2, b: Vector2, col: Color, width: float, dashed: bool) -> void:
		var dir := (b - a)
		var len := dir.length()
		if len < 1.0:
			return
		dir /= len
		a += dir * 9.0
		b -= dir * 9.0
		if not dashed:
			draw_line(a, b, col, width)
			return
		var d := 0.0
		var total := a.distance_to(b)
		while d < total:
			draw_line(a + dir * d, a + dir * minf(d + 3.0, total), col, width)
			d += 6.0
