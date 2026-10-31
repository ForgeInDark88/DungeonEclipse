extends BookPageScreen
## A camp on the road (stage-1 version): rest, go home with the loot, or on.


func _ready() -> void:
	build_book(Vector2(440, 260))
	left_page.add_child(UIStyle.label(tr("Лагерь"), 12))
	right_page.add_child(BookPageScreen.button(tr("Отдохнуть у костра"), func() -> void:
		var h := GameState.hero
		h.stats.heal(h.stats.max_hp() / 2)))
	right_page.add_child(BookPageScreen.button(tr("Домой с добычей"), func() -> void: GameFlow.retreat()))
	right_page.add_child(BookPageScreen.button(tr("Идти дальше"), func() -> void: GameFlow.location_cleared()))
