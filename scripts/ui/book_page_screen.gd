class_name BookPageScreen
extends Control
## Base for full-screen menus drawn on the open book: builds the dark
## background, the book and two page containers (left_page / right_page).

var book_size := Vector2(520, 300)
var left_page: Control
var right_page: Control
var book: Control


func build_book(p_size: Vector2) -> void:
	book_size = p_size
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.035, 0.06)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_add_embers(bg)

	book = Control.new()
	book.set_anchors_preset(Control.PRESET_CENTER)
	book.offset_left = -book_size.x / 2.0
	book.offset_right = book_size.x / 2.0
	book.offset_top = -book_size.y / 2.0
	book.offset_bottom = book_size.y / 2.0
	add_child(book)
	book.add_child(UIStyle.frame(AssetPaths.BOOK, 30, 0.5))

	var margin := 18.0
	var page_size := Vector2(book_size.x / 2.0 - margin - 10, book_size.y - margin * 2)
	left_page = VBoxContainer.new()
	left_page.position = Vector2(margin + 4, margin)
	left_page.size = page_size
	book.add_child(left_page)
	right_page = VBoxContainer.new()
	right_page.position = Vector2(book_size.x / 2.0 + 8, margin)
	right_page.size = page_size
	book.add_child(right_page)


func _add_embers(parent: Control) -> void:
	var p := CPUParticles2D.new()
	p.amount = 40
	p.lifetime = 6.0
	p.preprocess = 6.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(340, 10)
	p.position = Vector2(320, 370)
	p.direction = Vector2.UP
	p.spread = 15.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 10.0
	p.initial_velocity_max = 30.0
	p.color = Color(0.9, 0.45, 0.15, 0.7)
	parent.add_child(p)


static func button(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(callback)
	return b
