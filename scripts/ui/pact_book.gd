class_name PactBook
extends CanvasLayer
## Choice window of the altar of fate: one card per offer (blessing and its
## curse), plus «Отказаться». Pauses the game while open.

const CARD := Vector2(150, 120)

var _on_pick: Callable


func _ready() -> void:
	layer = 21
	process_mode = Node.PROCESS_MODE_ALWAYS


func open(offers: Array, on_pick: Callable) -> void:
	_on_pick = on_pick
	get_tree().paused = true
	_build(offers)
	AudioManager.play_ui(&"ui_book_open")


func close() -> void:
	AudioManager.play_ui(&"ui_book_close")
	get_tree().paused = false
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("inventory"):
		get_viewport().set_input_as_handled()
		close()


func _build(offers: Array) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var title := UIStyle.outlined_label(tr("Алтарь судьбы — до конца забега"), 11, UIStyle.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	var first: Button
	for offer: Dictionary in offers:
		var card := _card(offer)
		row.add_child(card)
		if first == null:
			first = card.get_meta("button")
	var refuse := BookPageScreen.button(tr("Отказаться"), close)
	refuse.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(refuse)
	var sz := box.get_combined_minimum_size()
	box.offset_left = -sz.x / 2.0
	box.offset_right = sz.x / 2.0
	box.offset_top = -sz.y / 2.0
	box.offset_bottom = sz.y / 2.0
	if first:
		first.grab_focus()


func _card(offer: Dictionary) -> Control:
	var card := Control.new()
	card.custom_minimum_size = CARD
	card.add_child(UIStyle.frame(AssetPaths.BOOK, 30, 0.35))
	var v := VBoxContainer.new()
	v.position = Vector2(10, 9)
	v.size = CARD - Vector2(20, 18)
	v.add_theme_constant_override("separation", 2)
	card.add_child(v)
	var b: RunPactData = offer["blessing"]
	var c: RunPactData = offer["curse"]
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.add_theme_color_override("default_color", UIStyle.INK)
	for k in ["normal_font_size", "bold_font_size"]:
		text.add_theme_font_size_override(k, 7)
	text.text = "[color=%s][b]%s[/b]\n%s[/color]" % [UIStyle.GOOD_HEX, b.display_name, b.description]
	if c:
		text.text += tr("\n\n[color=#8a2a1e][b]Проклятие: %s[/b]\n%s[/color]") % [c.display_name, c.description]
	else:
		text.text += tr("\n\n[color=%s]Без проклятия[/color]") % UIStyle.GOOD_HEX
	v.add_child(text)
	var pick := BookPageScreen.button(tr("Принять"), func() -> void:
		var cb := _on_pick
		close()
		cb.call(offer))
	pick.add_theme_font_size_override("font_size", 8)
	v.add_child(pick)
	card.set_meta("button", pick)
	return card
