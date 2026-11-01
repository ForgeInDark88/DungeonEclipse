class_name ChroniclerBook
extends CanvasLayer
## The chronicler's book: one chapter per place (three notes each) and the
## guardians' chapter. A complete chapter pays once - eclipse shards and
## gold to the Sanctum. The chronicler comments on the progress; when every
## guardian's story is known he hints at the other way to end it.

const SIZE := Vector2(420, 250)
const BIOME_REWARD := {"shards": 4, "gold": 80}
const GUARDIAN_REWARD := {"shards": 15, "gold": 200}

var _list: VBoxContainer
var _words: Label
var _paused_here := false


static func chapters() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var biomes := ItemDatabase.biomes.duplicate()
	biomes.sort_custom(func(a: BiomeData, b: BiomeData) -> bool: return a.order < b.order)
	for b: BiomeData in biomes:
		var notes := ItemDatabase.lore.filter(func(n: LoreData) -> bool: return n.biome == b.id)
		if not notes.is_empty():
			out.append({"id": b.id, "title": b.display_name, "notes": notes, "reward": BIOME_REWARD})
	var guards := ItemDatabase.lore.filter(func(n: LoreData) -> bool: return n.boss != &"")
	out.append({"id": &"guardians", "title": TranslationServer.translate("Стражи Затмения"), "notes": guards, "reward": GUARDIAN_REWARD})
	return out


static func read_in(ch: Dictionary) -> int:
	var n := 0
	for note: LoreData in ch["notes"]:
		if Codex.is_lore_read(note.id):
			n += 1
	return n


static func claimable_count() -> int:
	var n := 0
	for ch in chapters():
		if read_in(ch) == ch["notes"].size() and not Codex.is_chapter_claimed(ch["id"]):
			n += 1
	return n


func _ready() -> void:
	layer = 21
	process_mode = Node.PROCESS_MODE_ALWAYS


func open() -> void:
	if not Net.active:
		get_tree().paused = true
		_paused_here = true
	_build()
	_refresh()


func close() -> void:
	AudioManager.play_ui(&"ui_book_close")
	if _paused_here:
		get_tree().paused = false
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("inventory"):
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
	box.position = Vector2(24, 18)
	box.size = SIZE - Vector2(48, 36)
	box.add_theme_constant_override("separation", 3)
	root.add_child(box)
	var title := UIStyle.label(tr("Летопись Аурелии"), 12)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_words = UIStyle.label("", 8, UIStyle.INK_SOFT)
	_words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_words.custom_minimum_size = Vector2(SIZE.x - 48, 0)
	box.add_child(_words)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	scroll.add_child(_list)
	var close_b := BookPageScreen.button(tr("Закрыть"), close)
	close_b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(close_b)
	close_b.grab_focus()


func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	var total := 0
	var guards_done := false
	for ch in chapters():
		var have := read_in(ch)
		var need: int = ch["notes"].size()
		total += have
		if ch["id"] == &"guardians" and have == need:
			guards_done = true
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var name_l := UIStyle.label(ch["title"], 8, UIStyle.INK if have > 0 else UIStyle.INK_SOFT)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_l)
		row.add_child(UIStyle.label("%d / %d" % [have, need], 8, UIStyle.GOOD if have == need else UIStyle.INK_SOFT))
		var reward: Dictionary = ch["reward"]
		if Codex.is_chapter_claimed(ch["id"]):
			row.add_child(UIStyle.label(tr("получено"), 7, UIStyle.GOOD))
		else:
			var b := BookPageScreen.button(tr("+%d оск., +%d з.") % [reward["shards"], reward["gold"]], func() -> void: _claim(ch))
			b.add_theme_font_size_override("font_size", 7)
			b.disabled = have < need
			row.add_child(b)
		_list.add_child(row)
	_words.text = "«%s»" % _speech(total, guards_done)


func _speech(total: int, guards_done: bool) -> String:
	var all := ItemDatabase.lore.size()
	if total == 0:
		return tr("Внизу остались слова тех, кто видел, как падало солнце. Принеси мне их — я соберу историю, пока её не съела тьма.")
	if guards_done:
		return tr("Ты знаешь, кем были стражи. Могильщик, чародейка, шут, камень, колокол... Когда встанешь перед солнцем — вспомни их. Может быть, свет можно не разбить, а вернуть.")
	if total >= all / 2:
		return tr("Половина летописи уже здесь (%d из %d). Ищи записки стражей на их аренах — без них конец этой истории не дописать.") % [total, all]
	return tr("Записей: %d из %d. Каждая страница — чья-то последняя ночь. Неси ещё.") % [total, all]


func _claim(ch: Dictionary) -> void:
	if read_in(ch) < ch["notes"].size() or Codex.is_chapter_claimed(ch["id"]):
		return
	Codex.claim_chapter(ch["id"])
	var r: Dictionary = ch["reward"]
	MetaProgress.shards += int(r["shards"])
	MetaProgress.gold += int(r["gold"])
	MetaProgress.save_progress()
	MetaProgress.changed.emit()
	AudioManager.play_ui(&"coin")
	EventBus.message.emit(tr("Глава «%s» записана: +%d осколков, +%d золота в Святилище") % [ch["title"], r["shards"], r["gold"]])
	_refresh()
