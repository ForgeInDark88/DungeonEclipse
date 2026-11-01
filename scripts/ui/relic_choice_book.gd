class_name RelicChoiceBook
extends CanvasLayer
## Choice window of the relic altar: three relic cards (icon, name, what it
## does), «Взять» on each, «Позже» closes (the altar keeps its three).
## Solo pauses the game; co-op holds only the hero (Player.busy).

const CARD := Vector2(150, 128)

var _on_pick: Callable
var _player: Player
var _paused_here := false


func _ready() -> void:
	layer = 21
	process_mode = Node.PROCESS_MODE_ALWAYS


func open(offers: Array[RelicItemData], player: Player, on_pick: Callable) -> void:
	_on_pick = on_pick
	_player = player
	if player:
		player.busy = true
	if not Net.active:
		get_tree().paused = true
		_paused_here = true
	_build(offers)
	AudioManager.play_ui(&"ui_book_open")


func close() -> void:
	AudioManager.play_ui(&"ui_book_close")
	queue_free()


func _exit_tree() -> void:
	if is_instance_valid(_player):
		_player.busy = false
	if _paused_here and get_tree():
		get_tree().paused = false


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("inventory"):
		get_viewport().set_input_as_handled()
		close()


func _build(offers: Array[RelicItemData]) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var title := UIStyle.outlined_label(tr("Алтарь реликвий — возьмите одну"), 11, UIStyle.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	var first: Button
	for r in offers:
		var card := _card(r)
		row.add_child(card)
		if first == null:
			first = card.get_meta("button")
	var later := BookPageScreen.button(tr("Позже"), close)
	later.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(later)
	var sz := box.get_combined_minimum_size()
	box.offset_left = -sz.x / 2.0
	box.offset_right = sz.x / 2.0
	box.offset_top = -sz.y / 2.0
	box.offset_bottom = sz.y / 2.0
	if first:
		first.grab_focus()


func _card(r: RelicItemData) -> Control:
	var card := Control.new()
	card.custom_minimum_size = CARD
	card.add_child(UIStyle.frame(AssetPaths.BOOK, 30, 0.35))
	var v := VBoxContainer.new()
	v.position = Vector2(10, 9)
	v.size = CARD - Vector2(20, 18)
	v.add_theme_constant_override("separation", 2)
	card.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	var icon := TextureRect.new()
	icon.texture = r.icon
	icon.custom_minimum_size = Vector2(24, 24)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(icon)
	var name_label := UIStyle.label(r.display_name, 8, r.rarity_color().darkened(0.35))
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	v.add_child(head)
	var text := UIStyle.label(r.description, 7, UIStyle.INK)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(text)
	var pick := BookPageScreen.button(tr("Взять"), func() -> void:
		var cb := _on_pick
		close()
		cb.call(r))
	pick.add_theme_font_size_override("font_size", 8)
	v.add_child(pick)
	card.set_meta("button", pick)
	return card
