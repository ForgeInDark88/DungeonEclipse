class_name StatBar
extends Control
## Leather-framed bar (HP / mana / XP) with "value / max" text.

var fill_path: String
var _fill: NinePatchRect
var _label: Label
var _ratio := 1.0


static func create(p_fill_path: String, bar_size: Vector2) -> StatBar:
	var b := StatBar.new()
	b.fill_path = p_fill_path
	b.custom_minimum_size = bar_size
	b.size = bar_size
	return b


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(UIStyle.frame(AssetPaths.BAR_FRAME, 3))
	_fill = NinePatchRect.new()
	_fill.texture = AssetPaths.tex(fill_path)
	_fill.patch_margin_top = 1
	_fill.patch_margin_bottom = 1
	_fill.position = Vector2(2, 2)
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fill)
	_label = UIStyle.outlined_label("", 6, Color.WHITE)
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.offset_top = -1
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_label)
	_layout()


func set_values(value: float, max_value: float, text: String = "") -> void:
	_ratio = clampf(value / max_value, 0.0, 1.0) if max_value > 0.0 else 0.0
	if _label:
		_label.text = text if text != "" else "%d / %d" % [roundi(value), roundi(max_value)]
		_layout()


func _layout() -> void:
	if _fill:
		var inner := size - Vector2(4, 4)
		_fill.size = Vector2(maxf(0.0, inner.x * _ratio), inner.y)
		_fill.visible = _ratio > 0.0
