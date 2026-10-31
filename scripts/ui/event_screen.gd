extends BookPageScreen
## A choice on the road (EventData) on the open book. Left page: the scene.
## Right page: the answers - those the hero cannot take are greyed out with
## what they need. The picked answer rolls its outcome (EventRunner), the
## page tells what happened, then «Дальше» (back to the map) or «В бой!».

var event: EventData
var _hero_line: Label


func _ready() -> void:
	get_tree().paused = false
	build_book(Vector2(520, 290))
	AudioManager.play_music(&"menu")
	event = null
	for e in ItemDatabase.road_events:
		if e.id == StringName(GameState.location.get("event", &"")):
			event = e
	left_page.add_theme_constant_override("separation", 4)
	right_page.add_theme_constant_override("separation", 4)
	if event == null:
		left_page.add_child(UIStyle.label(tr("Тихая дорога"), 12))
		_next_button()
		return
	left_page.add_child(UIStyle.label(tr(event.title), 12))
	left_page.add_child(_wrap(tr(event.text), 8))
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_page.add_child(fill)
	_hero_line = UIStyle.label("", 7, UIStyle.INK_SOFT)
	left_page.add_child(_hero_line)
	_refresh_hero()
	right_page.add_child(UIStyle.label(tr("Ваш выбор"), 10))
	var first: Button = null
	for opt: Dictionary in event.options:
		var ok := EventRunner.check(String(opt.get("requires", "")))
		var text := tr(String(opt.get("text", "")))
		if String(opt.get("hint", "")) != "":
			text += " [%s]" % tr(String(opt["hint"]))
		var b := BookPageScreen.button(text, func() -> void: _choose(opt))
		b.add_theme_font_size_override("font_size", 8)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = not ok
		right_page.add_child(b)
		if ok and first == null:
			first = b
	if first:
		first.grab_focus()


func _wrap(text: String, size: int, color := UIStyle.INK) -> Label:
	var l := UIStyle.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(book_size.x / 2.0 - 40, 0)
	return l


func _refresh_hero() -> void:
	var h := GameState.hero
	if _hero_line and h:
		_hero_line.text = tr("Здоровье %d/%d · Золото %d") % [h.stats.hp, h.stats.max_hp(), h.gold]


func _choose(opt: Dictionary) -> void:
	var outcome := EventRunner.roll(opt)
	var effects: Dictionary = outcome.get("effects", {})
	var lines := EventRunner.apply(effects)
	for c in right_page.get_children():
		c.queue_free()
	right_page.add_child(UIStyle.label(tr("Что вышло"), 10))
	right_page.add_child(_wrap(tr(String(outcome.get("text", ""))), 8))
	if not lines.is_empty():
		right_page.add_child(_wrap("\n".join(lines), 7, UIStyle.INK_SOFT))
	_refresh_hero()
	AudioManager.play_ui(&"pickup_epic" if not lines.is_empty() else &"ui_click")
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_page.add_child(fill)
	if effects.has("fight"):
		var fight := BookPageScreen.button(tr("В бой!"), func() -> void: GameFlow.event_fight(StringName(effects["fight"])))
		right_page.add_child(fight)
		fight.grab_focus()
	else:
		_next_button()


func _next_button() -> void:
	var b := BookPageScreen.button(tr("Дальше по дороге"), func() -> void: GameFlow.location_cleared())
	right_page.add_child(b)
	b.grab_focus()
