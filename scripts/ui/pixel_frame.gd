@tool
class_name PixelFrame
extends Control
## Draws a nine-patch texture scaled by `pixel_scale` (keeps pixel-art
## borders thin on the 640x360 base resolution). Used for the book, the HUD
## panel and slot frames.

@export var texture: Texture2D:
	set(v):
		texture = v
		_rebuild()
@export var margin: int = 8:
	set(v):
		margin = v
		_rebuild()
@export var pixel_scale: float = 1.0:
	set(v):
		pixel_scale = v
		queue_redraw()
@export var draw_center: bool = true:
	set(v):
		draw_center = v
		_rebuild()

var _box: StyleBoxTexture


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _rebuild() -> void:
	if texture == null:
		_box = null
	else:
		_box = StyleBoxTexture.new()
		_box.texture = texture
		_box.texture_margin_left = margin
		_box.texture_margin_top = margin
		_box.texture_margin_right = margin
		_box.texture_margin_bottom = margin
		_box.draw_center = draw_center
	queue_redraw()


func _draw() -> void:
	if _box == null:
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(pixel_scale, pixel_scale))
	draw_style_box(_box, Rect2(Vector2.ZERO, size / pixel_scale))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
