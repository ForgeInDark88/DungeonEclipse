extends CanvasLayer
## Autoload "Tooltip": one parchment tooltip that follows the mouse.
## Works while the game is paused (inventory open).

var _panel: PanelContainer
var _text: RichTextLabel
var _visible_for: Object
## The tooltip belongs to an object (a freed one is not "== null").
var _has_owner := false


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UIStyle.texture_box(AssetPaths.TOOLTIP, 4))
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	add_child(_panel)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(150, 0)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.add_theme_color_override("default_color", UIStyle.INK)
	for font_name in ["normal_font_size", "bold_font_size", "italics_font_size"]:
		_text.add_theme_font_size_override(font_name, 8)
	_panel.add_child(_text)


func show_text(bbcode: String, owner_obj: Object = null) -> void:
	_visible_for = owner_obj
	_has_owner = owner_obj != null
	_text.text = bbcode
	_panel.visible = true
	_panel.reset_size()
	_follow()


## Hides only if the tooltip still belongs to `owner_obj` (or always if null).
func hide_tip(owner_obj: Object = null) -> void:
	if owner_obj == null or owner_obj == _visible_for:
		_panel.visible = false
		_visible_for = null
		_has_owner = false


func is_shown_for(owner_obj: Object) -> bool:
	return _panel.visible and _visible_for == owner_obj


func _process(_delta: float) -> void:
	if _panel.visible:
		if _has_owner and not is_instance_valid(_visible_for):
			hide_tip()
			return
		if _visible_for is Control and not (_visible_for as Control).is_visible_in_tree():
			hide_tip()
			return
		_follow()


func _follow() -> void:
	var vp := get_viewport().get_visible_rect().size
	var mouse := get_viewport().get_mouse_position()
	_panel.reset_size()
	var pos := mouse + Vector2(12, 12)
	if pos.x + _panel.size.x > vp.x:
		pos.x = mouse.x - _panel.size.x - 6
	if pos.y + _panel.size.y > vp.y:
		pos.y = vp.y - _panel.size.y - 2
	_panel.position = pos.max(Vector2.ZERO)
