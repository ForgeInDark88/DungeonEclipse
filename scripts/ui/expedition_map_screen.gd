extends BookPageScreen
## The expedition map (stage-1 version: the road as a list of the next
## choices). GameFlow.enter_node() steps onto the picked node.


func _ready() -> void:
	build_book(Vector2(480, 280))
	var run := GameState.run
	if run == null:
		return
	var here := run.current_node()
	var reg := run.map.region_of(int(here["id"])) if not here.is_empty() else run.map.regions[0]
	left_page.add_child(UIStyle.label(tr("Карта похода"), 12))
	left_page.add_child(UIStyle.label(reg.display_name if reg else "", 9, UIStyle.INK_SOFT))
	var info := UIStyle.label(tr("Пройдено узлов: %d\nГлубина: %d") % [run.path.size(), run.depth() if not here.is_empty() else 0], 8)
	left_page.add_child(info)
	right_page.add_child(UIStyle.label(tr("Куда дальше?"), 10))
	for id in run.next_choices():
		var n := run.map.node(id)
		var b := BookPageScreen.button("%s · %s %d" % [ExpeditionMap.type_name(n["type"]), tr("глубина"), int(n["depth"])],
			func() -> void: GameFlow.enter_node(id))
		right_page.add_child(b)
	if run.node_id < 0:
		right_page.add_child(BookPageScreen.button(tr("Вернуться в город"), func() -> void: GameFlow.retreat()))
