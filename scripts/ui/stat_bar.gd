class_name StatBar
extends Control
## Leather-framed bar (HP / mana / XP) with "value / max" text.
## The fill moves smoothly; when the value drops, a pale "damage" trail
## stays behind for a moment and then catches up.

const TRAIL_DELAY := 0.35

var fill_path: String
var shown_ratio := 1.0
var trail_ratio := 1.0
var _fill: NinePatchRect
var _trail: NinePatchRect
var _label: Label
var _target := 1.0
var _fill_tween: Tween
var _trail_tween: Tween
var _initialized := false


static func create(p_fill_path: String, bar_size: Vector2) -> StatBar:
	var b := StatBar.new()
	b.fill_path = p_fill_path
	b.custom_minimum_size = bar_size
	b.size = bar_size
	return b


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(UIStyle.frame(AssetPaths.BAR_FRAME, 3))
	_trail = _make_fill()
	_trail.modulate = Color(1.0, 0.95, 0.85, 0.75)
	_fill = _make_fill()
	_label = UIStyle.outlined_label("", 6, Color.WHITE)
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.offset_top = -1
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_label)
	_layout()


func _make_fill() -> NinePatchRect:
	var f := NinePatchRect.new()
	f.texture = AssetPaths.tex(fill_path)
	f.patch_margin_top = 1
	f.patch_margin_bottom = 1
	f.position = Vector2(2, 2)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(f)
	return f


func set_values(value: float, max_value: float, text: String = "") -> void:
	var ratio := clampf(value / max_value, 0.0, 1.0) if max_value > 0.0 else 0.0
	if _label:
		_label.text = text if text != "" else "%d / %d" % [roundi(value), roundi(max_value)]
	if not _initialized or not is_inside_tree():
		_initialized = true
		_target = ratio
		shown_ratio = ratio
		trail_ratio = ratio
		_layout()
		return
	if is_equal_approx(ratio, _target):
		return
	var dropping := ratio < _target
	_target = ratio
	if _fill_tween:
		_fill_tween.kill()
	_fill_tween = create_tween()
	_fill_tween.tween_method(_set_shown, shown_ratio, ratio, 0.2).set_ease(Tween.EASE_OUT)
	if _trail_tween:
		_trail_tween.kill()
	if dropping:
		_trail_tween = create_tween()
		_trail_tween.tween_interval(TRAIL_DELAY)
		_trail_tween.tween_method(_set_trail, trail_ratio, ratio, 0.4).set_ease(Tween.EASE_IN)
	else:
		_set_trail(ratio)


func _set_shown(v: float) -> void:
	shown_ratio = v
	_layout()


func _set_trail(v: float) -> void:
	trail_ratio = v
	_layout()


func _layout() -> void:
	if _fill == null:
		return
	var inner := size - Vector2(4, 4)
	_fill.size = Vector2(maxf(0.0, inner.x * shown_ratio), inner.y)
	_fill.visible = shown_ratio > 0.001
	_trail.size = Vector2(maxf(0.0, inner.x * maxf(trail_ratio, shown_ratio)), inner.y)
	_trail.visible = trail_ratio > shown_ratio + 0.001
