class_name LevelUpBanner
extends Control
## "Level up" splash: rotating golden rays, a popping title, then fade out.

var level_number := 2
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var title := UIStyle.outlined_label("НОВЫЙ УРОВЕНЬ!", 16, UIStyle.GOLD)
	var sub := UIStyle.outlined_label("Уровень %d" % level_number, 10, UIStyle.PARCHMENT)
	for l: Label in [title, sub]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.anchor_left = 0.0
		l.anchor_right = 1.0
		add_child(l)
	title.position.y = 92
	sub.position.y = 114
	title.size.y = 20
	pivot_offset = Vector2(320, 105)
	scale = Vector2(0.3, 0.3)
	modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel()
	tw.tween_property(self, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 1.0, 0.15)
	tw.chain().tween_interval(1.3)
	tw.chain().tween_property(self, "modulate:a", 0.0, 0.5)
	tw.chain().tween_callback(queue_free)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var c := Vector2(320, 108)
	for i in 12:
		var a := _t * 0.8 + i * TAU / 12.0
		var dir := Vector2.from_angle(a)
		var side := Vector2.from_angle(a + PI / 2.0) * 7.0
		var col := Color(1.0, 0.85, 0.3, 0.25)
		draw_colored_polygon(PackedVector2Array([c + dir * 14.0, c + dir * 90.0 + side, c + dir * 90.0 - side]), col)
