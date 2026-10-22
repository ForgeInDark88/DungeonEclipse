class_name DamageNumber
extends Label
## Floating number / text in the world. Not affected by the world light tint.


## `size_mult` > 1 for critical hits: bigger font and a pop.
func show_text(text_value: String, color: Color, pos: Vector2, size_mult := 1.0) -> void:
	text = text_value
	add_theme_color_override("font_color", color)
	add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.02))
	add_theme_constant_override("outline_size", 4)
	add_theme_font_size_override("font_size", roundi(9 * size_mult))
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var m := CanvasItemMaterial.new()
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = m
	z_index = 50
	size = Vector2(80, 14 * size_mult)
	global_position = pos - Vector2(40, 7 * size_mult) + Vector2(randf_range(-4, 4), 0)
	pivot_offset = size / 2.0
	if size_mult > 1.0:
		scale = Vector2(0.4, 0.4)
		create_tween().tween_property(self, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var tw := create_tween().set_parallel()
	tw.tween_property(self, "position:y", position.y - 18.0, 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(self, "modulate:a", 0.0, 0.35).set_delay(0.45)
	tw.chain().tween_callback(queue_free)
