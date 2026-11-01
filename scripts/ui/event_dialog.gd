class_name EventDialog
extends CanvasLayer
## The choice of a road event, opened by its scenery (EventSpot) right in
## the room: the scene's text on the left page, the answers on the right -
## those the hero cannot take are greyed out with what they need. The picked
## answer rolls its outcome (EventRunner) and the page tells what happened;
## a fight closes the book and starts in the room.

const SIZE := Vector2(520, 280)

var event: EventData
var spot: EventSpot
var _left: VBoxContainer
var _right: VBoxContainer
var _hero_line: Label
var _paused_here := false
var _fight: StringName = &""


func _ready() -> void:
	layer = 22
	process_mode = Node.PROCESS_MODE_ALWAYS


## A guest of a co-op party only watches: the host chooses for everyone.
var read_only := false


func open(p_event: EventData, p_spot: EventSpot) -> void:
	event = p_event
	spot = p_spot
	read_only = GameFlow.is_guest()
	if not get_tree().paused and not Net.active:
		get_tree().paused = true
		_paused_here = true
	_build()
	_show_choices()


func close() -> void:
	if _paused_here:
		get_tree().paused = false
	AudioManager.play_ui(&"ui_book_close")
	if _fight != &"" and spot:
		spot.start_fight(_fight)
	queue_free()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()  # walking away is allowed: the choice waits


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_CENTER)
	root.offset_left = -SIZE.x / 2.0
	root.offset_right = SIZE.x / 2.0
	root.offset_top = -SIZE.y / 2.0
	root.offset_bottom = SIZE.y / 2.0
	add_child(root)
	root.add_child(UIStyle.frame(AssetPaths.BOOK, 30, 0.5))
	var page := Vector2(SIZE.x / 2.0 - 30, SIZE.y - 36)
	_left = VBoxContainer.new()
	_left.position = Vector2(22, 18)
	_left.size = page
	_left.add_theme_constant_override("separation", 4)
	root.add_child(_left)
	_right = VBoxContainer.new()
	_right.position = Vector2(SIZE.x / 2.0 + 8, 18)
	_right.size = page
	_right.add_theme_constant_override("separation", 4)
	root.add_child(_right)
	_left.add_child(UIStyle.label(tr(event.title), 12))
	_left.add_child(_wrap(tr(event.text), 8))
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_left.add_child(fill)
	_hero_line = UIStyle.label("", 7, UIStyle.INK_SOFT)
	_left.add_child(_hero_line)
	_refresh_hero()


func _wrap(text: String, size: int, color := UIStyle.INK) -> Label:
	var l := UIStyle.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(SIZE.x / 2.0 - 40, 0)
	return l


func _refresh_hero() -> void:
	var h := GameState.hero
	if _hero_line and h:
		_hero_line.text = tr("Здоровье %d/%d · Золото %d") % [h.stats.hp, h.stats.max_hp(), h.gold]


func _show_choices() -> void:
	_right.add_child(UIStyle.label(tr("Ваш выбор"), 10))
	var first: Button = null
	for opt: Dictionary in event.options:
		var ok := EventRunner.check(String(opt.get("requires", "")))
		var text := tr(String(opt.get("text", "")))
		if String(opt.get("hint", "")) != "":
			text += " [%s]" % tr(String(opt["hint"]))
		var b := BookPageScreen.button(text, func() -> void: choose(opt))
		b.add_theme_font_size_override("font_size", 8)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = not ok or read_only
		_right.add_child(b)
		if ok and first == null:
			first = b
	if read_only:
		_right.add_child(_wrap(tr("Выбор делает хост: исход получат все."), 7, UIStyle.INK_SOFT))
		var back := BookPageScreen.button(tr("Закрыть"), close)
		_right.add_child(back)
		back.grab_focus.call_deferred()
	elif first:
		first.grab_focus.call_deferred()


## A party member's side of the host's choice: the outcome and what it did
## to this hero.
func show_result(text: String, lines: Array[String]) -> void:
	for c in _right.get_children():
		c.queue_free()
	_right.add_child(UIStyle.label(tr("Хост выбрал"), 10))
	_right.add_child(_wrap(tr(text), 8))
	if not lines.is_empty():
		_right.add_child(_wrap("\n".join(lines), 7, UIStyle.INK_SOFT))
	var b := BookPageScreen.button(tr("Дальше"), close)
	_right.add_child(b)
	b.grab_focus.call_deferred()


## Takes an answer: rolls and applies its outcome, tells what happened.
func choose(opt: Dictionary) -> void:
	var outcome := EventRunner.roll(opt)
	var effects: Dictionary = outcome.get("effects", {})
	var lines := EventRunner.apply(effects)
	WorldNet.share_event(event.id, String(outcome.get("text", "")), effects)
	if spot:
		spot.finish()
	for c in _right.get_children():
		c.queue_free()
	_right.add_child(UIStyle.label(tr("Что вышло"), 10))
	_right.add_child(_wrap(tr(String(outcome.get("text", ""))), 8))
	if not lines.is_empty():
		_right.add_child(_wrap("\n".join(lines), 7, UIStyle.INK_SOFT))
	_refresh_hero()
	AudioManager.play_ui(&"pickup_epic" if not lines.is_empty() else &"ui_click")
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_right.add_child(fill)
	var b: Button
	if effects.has("fight"):
		_fight = StringName(effects["fight"])
		b = BookPageScreen.button(tr("В бой!"), close)
	else:
		b = BookPageScreen.button(tr("Дальше"), close)
	_right.add_child(b)
	b.grab_focus.call_deferred()
