class_name JournalBook
extends CanvasLayer
## The hero's journal: the town's people (who lives here, who is still
## lost below), the buildings (levels, what the next one needs), the road
## events met and the decisions taken, the bestiary. Pause menu / map menu.

enum Tab { PEOPLE, BUILDINGS, EVENTS, BESTIARY }

const SIZE := Vector2(540, 300)
const TAB_NAMES := ["Жители", "Постройки", "События", "Бестиарий"]
## Story flags that the journal names as decisions.
const DECISIONS := {
	"helped_survivors": "Вывели выживших из глубин",
	"oldric_rest": "Дали покой призраку могильщика",
	"oldric_heard": "Выслушали призрака могильщика",
	"king_honoured": "Почтили статую короля",
	"sun_refused": "Отказались от дара чёрного солнца",
}

var _tab: Tab = Tab.PEOPLE
var _list: VBoxContainer
var _tabs: Array[Button] = []
var _paused_here := false


func _ready() -> void:
	layer = 23
	process_mode = Node.PROCESS_MODE_ALWAYS


func open(tab: Tab = Tab.PEOPLE) -> void:
	if not get_tree().paused:
		get_tree().paused = true
		_paused_here = true
	_build()
	select(tab)


func close() -> void:
	if _paused_here:
		get_tree().paused = false
	AudioManager.play_ui(&"ui_book_close")
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_CENTER)
	root.offset_left = -SIZE.x / 2.0
	root.offset_right = SIZE.x / 2.0
	root.offset_top = -SIZE.y / 2.0
	root.offset_bottom = SIZE.y / 2.0
	add_child(root)
	root.add_child(UIStyle.frame(AssetPaths.BOOK_PANEL, 30, 0.5))
	var box := VBoxContainer.new()
	box.position = Vector2(22, 16)
	box.size = SIZE - Vector2(44, 32)
	box.add_theme_constant_override("separation", 4)
	root.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	box.add_child(head)
	head.add_child(UIStyle.label(tr("Журнал"), 12))
	for i in TAB_NAMES.size():
		var b := BookPageScreen.button(tr(TAB_NAMES[i]), func() -> void: select(i as Tab))
		b.toggle_mode = true
		b.add_theme_font_size_override("font_size", 8)
		head.add_child(b)
		_tabs.append(b)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	head.add_child(BookPageScreen.button(tr("Закрыть"), close))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 3)
	scroll.add_child(_list)


func select(tab: Tab) -> void:
	_tab = tab
	for i in _tabs.size():
		_tabs[i].button_pressed = i == int(tab)
	for c in _list.get_children():
		c.queue_free()
	match tab:
		Tab.PEOPLE:
			_people()
		Tab.BUILDINGS:
			_buildings()
		Tab.EVENTS:
			_events()
		Tab.BESTIARY:
			_bestiary()
	_tabs[int(tab)].grab_focus()


func _line(text: String, size := 7, color := UIStyle.INK) -> Label:
	var l := UIStyle.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(SIZE.x - 60, 0)
	_list.add_child(l)
	return l


func _people() -> void:
	var t := GameState.town
	var all: Array = ItemDatabase.npcs.values()
	all.sort_custom(func(a: NpcData, b: NpcData) -> bool: return a.order < b.order)
	for n: NpcData in all:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var home := t != null and t.has_resident(n.id)
		var pic := TextureRect.new()
		pic.texture = n.portrait
		pic.custom_minimum_size = Vector2(24, 24)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.modulate = Color.WHITE if home else Color(0, 0, 0, 0.6)
		row.add_child(pic)
		var text := ""
		if home:
			var b := ItemDatabase.building(n.home)
			text = "%s — %s" % [n.display_name, n.profession]
			if b:
				text += tr(" · %s") % b.display_name
			if n.discount > 0.0:
				text += tr(" · скидка в лавках %d%%") % roundi(n.discount * 100)
			if n.build_discount > 0.0:
				text += tr(" · стройка дешевле на %d%%") % roundi(n.build_discount * 100)
		else:
			text = tr("??? — %s. Томится в плену где-то на глубине %d+.") % [n.profession, n.depth_min]
		var l := UIStyle.label(text, 7, UIStyle.INK if home else UIStyle.INK_SOFT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		_list.add_child(row)
	if t and int(t.stats.get("refugees", 0)) > 0:
		_line(tr("Спасённых горожан: %d") % int(t.stats["refugees"]), 7, UIStyle.INK_SOFT)


func _buildings() -> void:
	var t := GameState.town
	_line(tr("Процветание: %d · %s") % [t.prosperity, TownResources.describe(t.resources) if not t.resources.is_empty() else tr("ресурсов нет")], 8)
	for b in ItemDatabase.buildings:
		var lvl := t.building_level(b.id)
		var text := "%s  %s" % [b.display_name, "◆".repeat(lvl) + "◇".repeat(b.max_level - lvl)]
		if lvl < b.max_level:
			var miss := Buildings.requirement_missing(b, lvl + 1)
			text += " — " + (miss if miss != "" else tr("следующий уровень: %s") % (b.level_texts[lvl] if lvl < b.level_texts.size() else ""))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var ic := TextureRect.new()
		ic.texture = AssetPaths.building_icon(b.id)
		ic.custom_minimum_size = Vector2(16, 16)
		ic.modulate = Color.WHITE if lvl > 0 else Color(1, 1, 1, 0.45)
		row.add_child(ic)
		var l := UIStyle.label(text, 7, UIStyle.INK if lvl > 0 else UIStyle.INK_SOFT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		_list.add_child(row)


func _events() -> void:
	var t := GameState.town
	var known: Array = t.flags.get("events_known", []) if t else []
	_line(tr("Встречено событий: %d из %d") % [known.size(), ItemDatabase.road_events.size()], 8)
	for e in ItemDatabase.road_events:
		if String(e.id) in known:
			_line("• %s — %s" % [tr(e.title), tr(e.text).left(90) + "…"], 7)
		else:
			_line("• ???", 7, UIStyle.INK_SOFT)
	var decisions: Array[String] = []
	for k in DECISIONS:
		if t and t.flag(k, false) == true:
			decisions.append(tr(DECISIONS[k]))
	_line(tr("Решения"), 8)
	_line(", ".join(decisions) if not decisions.is_empty() else tr("пока ни одного судьбоносного выбора"), 7, UIStyle.INK_SOFT)


func _bestiary() -> void:
	var known := 0
	var list: Array = ItemDatabase.enemies.duplicate()
	list.sort_custom(func(a: EnemyData, b: EnemyData) -> bool: return a.min_floor < b.min_floor)
	for e: EnemyData in list:
		if e.training_dummy:
			continue
		var kills := int(Codex.enemy_kills.get(e.id, 0))
		if kills > 0:
			known += 1
			_line(tr("%s — убито %d · с глубины %d") % [e.display_name, kills, e.min_floor], 7)
		else:
			_line("???", 7, UIStyle.INK_SOFT)
	for b in ItemDatabase.bosses:
		var beaten := GameState.town != null and b.id in GameState.town.bosses_defeated
		_line(tr("Страж: %s") % b.display_name if beaten else tr("Страж: ???"), 7, Color(0.45, 0.2, 0.5) if beaten else UIStyle.INK_SOFT)
	_line(tr("Полный бестиарий с описаниями — в библиотеке города."), 6, UIStyle.INK_SOFT)
