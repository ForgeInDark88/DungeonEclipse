extends BookPageScreen
## The end of an expedition (stage-1 version): what happened and «В город».


func _ready() -> void:
	build_book(Vector2(440, 260))
	var r := GameFlow.last_result
	var titles := {RunState.Outcome.VICTORY: tr("Победа"), RunState.Outcome.RETREAT: tr("Возвращение домой"),
			RunState.Outcome.DEATH: tr("Герой пал")}
	left_page.add_child(UIStyle.label(titles.get(r.get("outcome", 0), tr("Поход окончен")), 12))
	left_page.add_child(UIStyle.label(tr("Узлов пройдено: %d\nУбито врагов: %d\nЗолото: %d") % [
		int(r.get("nodes", 0)), int(r.get("kills", 0)), int(r.get("gold", 0))], 8))
	var go := BookPageScreen.button(tr("В город"), func() -> void: GameFlow.back_to_town())
	right_page.add_child(go)
	go.grab_focus()
