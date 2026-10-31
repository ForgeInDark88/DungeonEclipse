extends BookPageScreen
## A choice on the road (stage-1 version).


func _ready() -> void:
	build_book(Vector2(440, 260))
	left_page.add_child(UIStyle.label(tr("Происшествие"), 12))
	right_page.add_child(BookPageScreen.button(tr("Идти дальше"), func() -> void: GameFlow.location_cleared()))
