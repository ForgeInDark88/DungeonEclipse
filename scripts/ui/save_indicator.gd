class_name SaveIndicator
extends CanvasLayer
## The autosave mark in the corner: a little book and «Сохранено» fading in
## and out whenever the world is saved (EventBus.saved). Lives in GameFlow.

var _box: HBoxContainer
var _tween: Tween
var _last := -10000


func _ready() -> void:
	layer = 110
	process_mode = Node.PROCESS_MODE_ALWAYS
	_box = HBoxContainer.new()
	_box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_box.position = Vector2(-96, -22)
	_box.add_theme_constant_override("separation", 3)
	_box.modulate.a = 0.0
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)
	var icon := TextureRect.new()
	icon.texture = AssetPaths.building_icon(&"library")
	icon.custom_minimum_size = Vector2(16, 16)
	_box.add_child(icon)
	_box.add_child(UIStyle.outlined_label(tr("Сохранено"), 8, UIStyle.PARCHMENT))
	EventBus.saved.connect(_show)


func _show() -> void:
	var now := Time.get_ticks_msec()
	if now - _last < 1500:
		return
	_last = now
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_box, "modulate:a", 1.0, 0.2)
	_tween.tween_interval(1.2)
	_tween.tween_property(_box, "modulate:a", 0.0, 0.5)
