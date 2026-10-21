class_name OverlayPanel
extends CanvasLayer
## Modal parchment panel over the game (pause menu, death screen).

var _box: VBoxContainer
var _panel: Control


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -110
	_panel.offset_right = 110
	_panel.offset_top = -80
	_panel.offset_bottom = 80
	add_child(_panel)
	_panel.add_child(UIStyle.frame(AssetPaths.BOOK_PANEL, 30, 0.5))
	_box = VBoxContainer.new()
	_box.position = Vector2(20, 18)
	_box.size = Vector2(180, 124)
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.add_theme_constant_override("separation", 6)
	_panel.add_child(_box)


func clear() -> void:
	Tooltip.hide_tip()
	for c in _box.get_children():
		c.queue_free()


func add_text(text: String, font_size: int = 8) -> Label:
	var l := UIStyle.label(text, font_size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(l)
	return l


func add_button(text: String, cb: Callable) -> Button:
	var b := BookPageScreen.button(text, cb)
	_box.add_child(b)
	return b
