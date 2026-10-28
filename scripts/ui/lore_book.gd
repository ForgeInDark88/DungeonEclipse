class_name LoreBook
extends CanvasLayer
## Reading a note: a parchment page with the title, the author and the text,
## and how many notes of the chronicle are found. Pauses a solo game.

const SIZE := Vector2(360, 200)

var _paused_here := false


func _ready() -> void:
	layer = 21
	process_mode = Node.PROCESS_MODE_ALWAYS


func open(lore: LoreData) -> void:
	if not Net.active:
		get_tree().paused = true
		_paused_here = true
	_build(lore)


func close() -> void:
	AudioManager.play_ui(&"ui_book_close")
	if _paused_here:
		get_tree().paused = false
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("inventory") or event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		close()


func _build(lore: LoreData) -> void:
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
	box.position = Vector2(26, 22)
	box.size = SIZE - Vector2(52, 44)
	box.add_theme_constant_override("separation", 4)
	root.add_child(box)
	var title := UIStyle.label(lore.title, 11)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)
	var author := UIStyle.label("— %s" % lore.author, 7, UIStyle.INK_SOFT)
	author.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(author)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.add_theme_color_override("default_color", UIStyle.INK)
	text.add_theme_font_size_override("normal_font_size", 8)
	text.add_theme_font_size_override("italics_font_size", 8)
	text.text = "[i]%s[/i]" % lore.text
	text.visible_ratio = 0.0
	box.add_child(text)
	create_tween().tween_property(text, "visible_ratio", 1.0, clampf(lore.text.length() / 220.0, 0.6, 2.2))
	var foot := HBoxContainer.new()
	box.add_child(foot)
	var count := UIStyle.label("Летопись: %d из %d записей" % [Codex.lore_read_count(), ItemDatabase.lore.size()], 7, UIStyle.INK_SOFT)
	count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(count)
	var close_b := BookPageScreen.button("Закрыть", close)
	foot.add_child(close_b)
	close_b.grab_focus()
