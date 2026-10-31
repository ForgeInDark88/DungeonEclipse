class_name DialogBook
extends CanvasLayer
## A talk with a person of the town on parchment: portrait, name and trade,
## their words and the answers to pick. An answer shows the reply and may
## set a story flag (TownState.flags); a talk marked `once` is read then.

signal closed

const SIZE := Vector2(420, 210)

var npc: NpcData
var _dialog: Dictionary
var _text: RichTextLabel
var _options: VBoxContainer
var _paused_here := false


func _ready() -> void:
	layer = 22
	process_mode = Node.PROCESS_MODE_ALWAYS


func open(p_npc: NpcData) -> void:
	npc = p_npc
	if not get_tree().paused:
		get_tree().paused = true
		_paused_here = true
	_build()
	_dialog = Dialogs.current(npc)
	_show_dialog()


func close() -> void:
	if _paused_here:
		get_tree().paused = false
	AudioManager.play_ui(&"ui_book_close")
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
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
	var row := HBoxContainer.new()
	row.position = Vector2(20, 18)
	row.size = SIZE - Vector2(40, 36)
	row.add_theme_constant_override("separation", 10)
	root.add_child(row)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(96, 0)
	row.add_child(left)
	var portrait := TextureRect.new()
	portrait.texture = npc.portrait
	portrait.custom_minimum_size = Vector2(96, 96)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	left.add_child(portrait)
	var name_l := UIStyle.label(npc.display_name, 9)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(name_l)
	var prof := UIStyle.label(npc.profession, 7, UIStyle.INK_SOFT)
	prof.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(prof)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 4)
	row.add_child(right)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.custom_minimum_size = Vector2(0, 90)
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.add_theme_color_override("default_color", UIStyle.INK)
	_text.add_theme_font_size_override("normal_font_size", 8)
	right.add_child(_text)
	_options = VBoxContainer.new()
	_options.add_theme_constant_override("separation", 2)
	right.add_child(_options)


func _show_dialog() -> void:
	for c in _options.get_children():
		c.queue_free()
	if _dialog.is_empty():
		_text.text = tr("…")
		_add_option(tr("Уйти"), close)
		return
	_text.text = tr(String(_dialog.get("text", "")))
	for opt: Dictionary in _dialog.get("options", []):
		_add_option(tr(String(opt.get("text", ""))), func() -> void: _pick(opt))
	_add_option(tr("Уйти"), func() -> void:
		Dialogs.mark_read(npc, _dialog)
		close())
	_focus_first()


func _pick(opt: Dictionary) -> void:
	if String(opt.get("flag", "")) != "" and GameState.town:
		GameState.town.set_flag(String(opt["flag"]))
	Dialogs.mark_read(npc, _dialog)
	for c in _options.get_children():
		c.queue_free()
	_text.text = "[i]%s[/i]" % tr(String(opt.get("reply", "")))
	_add_option(tr("Дальше"), close)
	_focus_first()


func _add_option(text: String, cb: Callable) -> void:
	var b := BookPageScreen.button(text, cb)
	b.add_theme_font_size_override("font_size", 8)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_options.add_child(b)


func _focus_first() -> void:
	await get_tree().process_frame
	for c in _options.get_children():
		if c is Button and not c.is_queued_for_deletion():
			(c as Button).grab_focus()
			return
