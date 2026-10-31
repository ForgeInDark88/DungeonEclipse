class_name QuestBook
extends CanvasLayer
## The guild's quest book, opened by the town herald. Left page: the chain of
## orders (done / current / locked). Right page: the current quest, its story
## line, progress and the claim button. The game is paused while open.

const BOOK_SIZE := Vector2(520, 300)
const BOOK_MARGIN := 16

var hero: Hero
var is_open := false

var _root: Control
var _list: VBoxContainer
var _title: Label
var _story: Label
var _progress: Label
var _bar: ColorRect
var _bar_fill: ColorRect
var _reward: Label
var _claim: Button
var _hint: Label
var _page_w: float

const GOLD_COL := Color(1.0, 0.82, 0.35)
const DONE_COL := Color(0.45, 0.85, 0.5)
const LOCK_COL := Color(0.55, 0.5, 0.55, 0.75)


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func open() -> void:
	hero = GameState.hero
	if is_open or hero == null:
		return
	if _root == null:
		_build()
	is_open = true
	visible = true
	get_tree().paused = true
	_refresh()
	AudioManager.play_ui(&"ui_book_open")


func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	get_tree().paused = false
	Tooltip.hide_tip()
	AudioManager.play_ui(&"ui_book_close")


func _unhandled_input(event: InputEvent) -> void:
	if is_open and (event.is_action_pressed("pause") or event.is_action_pressed("inventory")):
		close()
		get_viewport().set_input_as_handled()


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
	_root.offset_top = 10
	_root.offset_bottom = 10 + BOOK_SIZE.y
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	# Deep-violet guild binding instead of the parchment book.
	var bg := ColorRect.new()
	bg.color = Color(0.11, 0.07, 0.16)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)
	var edge := ColorRect.new()
	edge.color = Color(0.32, 0.22, 0.42)
	edge.position = Vector2(2, 2)
	edge.size = BOOK_SIZE - Vector2(4, 4)
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(edge)
	var spine := ColorRect.new()
	spine.color = Color(0.05, 0.03, 0.08)
	spine.position = Vector2(BOOK_SIZE.x / 2.0 - 2, 0)
	spine.size = Vector2(4, BOOK_SIZE.y)
	spine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(spine)

	var head := UIStyle.outlined_label(tr("Приказы гильдии Затмения"), 11, UIStyle.PARCHMENT)
	head.position = Vector2(BOOK_MARGIN, 6)
	head.size = Vector2(BOOK_SIZE.x - BOOK_MARGIN * 2, 16)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(head)

	var page_w := BOOK_SIZE.x / 2.0 - BOOK_MARGIN - 10
	_page_w = page_w
	var page_h := BOOK_SIZE.y - 34
	_list = VBoxContainer.new()
	_list.position = Vector2(BOOK_MARGIN, 26)
	_list.size = Vector2(page_w, page_h)
	_list.add_theme_constant_override("separation", 2)
	_root.add_child(_list)

	var rx := BOOK_SIZE.x / 2.0 + 12
	_title = UIStyle.outlined_label("", 10, GOLD_COL)
	_title.position = Vector2(rx, 26)
	_title.size = Vector2(page_w, 30)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root.add_child(_title)
	_story = UIStyle.label("", 7, UIStyle.PARCHMENT)
	_story.position = Vector2(rx, 60)
	_story.size = Vector2(page_w, 66)
	_story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root.add_child(_story)
	_progress = UIStyle.label("", 7, UIStyle.PARCHMENT)
	_progress.position = Vector2(rx, 132)
	_progress.size = Vector2(page_w, 12)
	_root.add_child(_progress)
	_bar = ColorRect.new()
	_bar.color = Color(0.05, 0.03, 0.08)
	_bar.position = Vector2(rx, 148)
	_bar.size = Vector2(page_w, 8)
	_root.add_child(_bar)
	_bar_fill = ColorRect.new()
	_bar_fill.color = GOLD_COL
	_bar_fill.position = Vector2(1, 1)
	_bar_fill.size = Vector2(0, 6)
	_bar.add_child(_bar_fill)
	_reward = UIStyle.label("", 7, Color(0.75, 0.9, 0.7))
	_reward.position = Vector2(rx, 166)
	_reward.size = Vector2(page_w, 40)
	_reward.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root.add_child(_reward)
	_hint = UIStyle.label("", 6, LOCK_COL)
	_hint.position = Vector2(rx, 208)
	_hint.size = Vector2(page_w, 12)
	_root.add_child(_hint)
	var buttons := HBoxContainer.new()
	buttons.position = Vector2(rx, 236)
	buttons.size = Vector2(page_w, 26)
	buttons.add_theme_constant_override("separation", 8)
	_root.add_child(buttons)
	_claim = BookPageScreen.button(tr("Сдать задание"), _claim_current)
	_claim.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(_claim)
	buttons.add_child(BookPageScreen.button(tr("Закрыть"), close))


func _claim_current() -> void:
	var reward := GameState.quests.claim(hero)
	if reward.is_empty():
		AudioManager.play_ui(&"chest_locked")
		return
	EventBus.message.emit(tr("Награда получена: %d золота%s") % [reward["gold"],
			(tr(", %d осколка") % reward["shards"]) if int(reward["shards"]) > 0 else ""])
	Fx.sparks(_root, Vector2(BOOK_SIZE.x / 2.0 + 60, 150), GOLD_COL, 14, 60.0)
	_refresh()


func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	var log := GameState.quests
	var shown_hint := false
	for i in QuestLog.CHAIN.size():
		var q: Dictionary = QuestLog.CHAIN[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		var mark := UIStyle.outlined_label("—", 8, LOCK_COL)
		var name_l: Label
		if i < log.index:
			mark.text = "✓"
			mark.add_theme_color_override("font_color", DONE_COL)
			name_l = UIStyle.label(str(q["title"]), 7, LOCK_COL)
		elif i == log.index:
			mark.text = "✦"
			mark.add_theme_color_override("font_color", GOLD_COL)
			var suffix := tr(" — готово!") if log.is_done() else ""
			name_l = UIStyle.label("%s%s" % [q["title"], suffix], 8, UIStyle.PARCHMENT if not log.is_done() else DONE_COL)
		else:
			name_l = UIStyle.label("• • •", 7, Color(0.4, 0.34, 0.44))
			if not shown_hint:
				name_l.text = tr("Следующий приказ откроется позже")
				shown_hint = true
		row.add_child(mark)
		row.add_child(name_l)
		_list.add_child(row)

	var q2 := log.current()
	if q2.is_empty():
		_title.text = tr("Все приказы исполнены")
		_story.text = tr("Глашатай склоняет голову.\n\n«Ты сделал для гильдии больше, чем вся карта затмения. Возвращайся в следующий спуск — бумаги уже пишутся.»")
		_progress.text = ""
		_bar.visible = false
		_reward.text = ""
		_hint.text = ""
		_claim.visible = false
		return
	_bar.visible = true
	_claim.visible = true
	_title.text = "«%s»" % q2["title"]
	_story.text = str(q2["desc"])
	var target := int(q2["target"])
	_progress.text = tr("Прогресс: %d / %d") % [mini(log.progress, target), target]
	_bar_fill.size.x = (_page_w - 2) * clampf(float(log.progress) / target, 0.0, 1.0)
	var parts: Array[String] = []
	if int(q2["gold"]) > 0:
		parts.append(tr("%d золота") % int(q2["gold"]))
	if int(q2["shards"]) > 0:
		parts.append(tr("%d осколка затмения") % int(q2["shards"]))
	if q2["item"] != &"":
		parts.append("%d× %s" % [maxi(1, int(q2["item_count"])), _item_name(q2["item"])])
	_reward.text = tr("Награда: ") + ", ".join(parts)
	_hint.text = tr("Сдать можно только у глашатая в городе") if not log.is_done() else ""
	_claim.disabled = not log.is_done()
	_claim.text = tr("Сдать задание") if log.is_done() else tr("Ещё не готово")


func _item_name(id: StringName) -> String:
	var it := ItemDatabase.get_item(id)
	return it.display_name if it else String(id)
