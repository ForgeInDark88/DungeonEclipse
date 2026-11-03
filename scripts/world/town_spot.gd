class_name TownSpot
extends Area2D
## Small things of the bigger town (TownBuilder specials):
## - carriage: a carriage stop; E lists the open districts with a stop and
##   takes the hero there (each hero rides alone, in co-op too);
## - memorial: the memorial to the fallen heroes (TownState.flags "fallen")
##   with the town's record of expeditions;
## - roof_cache: a cache on the roofs of the houses, once per town (gold
##   and maybe a blueprint);
## - district_notice: the notice on a closed district's palisade.

var kind: StringName = &"carriage"
var district: StringName = &""
var _menu: CanvasLayer


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("town_spots")
	collision_layer = 16
	collision_mask = 0
	monitoring = false
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(24, 30)
	shape.shape = rect
	shape.position = Vector2(0, -15)
	add_child(shape)
	if kind == &"carriage":
		var s := Sprite2D.new()
		s.texture = AssetPaths.tex("res://assets/sprites/town/carriage_stop.png")
		if s.texture:
			s.offset = Vector2(0, -s.texture.get_height() / 2.0)
		s.z_index = -1
		add_child(s)
	elif kind == &"roof_cache":
		var c := Sprite2D.new()
		c.texture = AssetPaths.tex("res://assets/sprites/surface/crate.png")
		if c.texture:
			c.offset = Vector2(0, -c.texture.get_height() / 2.0)
		add_child(c)


func can_interact() -> bool:
	return kind != &"roof_cache" or not _taken()


func _taken() -> bool:
	return GameState.town != null and bool(GameState.town.flags.get("roof_cache", false))


func get_prompt() -> String:
	match kind:
		&"carriage":
			return tr("Повозка: в другой квартал")
		&"memorial":
			return tr("Мемориал павшим")
		&"roof_cache":
			return tr("Тайник на крыше")
		&"district_notice":
			var d := _district()
			return "%s — %s" % [tr(d.display_name), TownDistricts.unlock_text(d)] if d else ""
	return ""


func _district() -> DistrictData:
	for d in TownDistricts.all():
		if d.id == district:
			return d
	return null


func interact(player: Node) -> void:
	match kind:
		&"carriage":
			_open_menu(player)
		&"memorial":
			_memorial()
		&"roof_cache":
			_cache()
		&"district_notice":
			EventBus.message.emit(get_prompt())


# --------------------------------------------------------------- carriage
func _open_menu(player: Node) -> void:
	if _menu and is_instance_valid(_menu):
		_menu.queue_free()
		return
	var stops: Array = []
	for n in get_tree().get_nodes_in_group("town_spots"):
		if n != self and n.kind == &"carriage":
			stops.append(n)
	if stops.is_empty():
		EventBus.message.emit(tr("Других остановок пока нет."))
		return
	var layer := CanvasLayer.new()
	layer.layer = 50
	get_tree().current_scene.add_child(layer)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIStyle.texture_box(AssetPaths.TOOLTIP, 4))
	panel.position = Vector2(220, 90)
	layer.add_child(panel)
	_menu = layer
	var box := VBoxContainer.new()
	panel.add_child(box)
	box.add_child(UIStyle.label(tr("Куда поедем?"), 9))
	for st in stops:
		var d: DistrictData = st._district()
		var dest: Node2D = st
		box.add_child(BookPageScreen.button(tr(d.display_name) if d else "?", func() -> void:
			layer.queue_free()
			_ride(player as Node2D, dest)))
	box.add_child(BookPageScreen.button(tr("Остаться"), func() -> void: layer.queue_free()))


func _ride(player: Node2D, dest: Node2D) -> void:
	if player == null:
		return
	AudioManager.play_sfx(&"step_wood", global_position)
	var fade := ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var layer := CanvasLayer.new()
	layer.layer = 90
	get_tree().current_scene.add_child(layer)
	layer.add_child(fade)
	var tw := layer.create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.3)
	tw.tween_callback(func() -> void:
		player.global_position = dest.global_position + Vector2(16, 0)
		if "velocity" in player:
			player.velocity = Vector2.ZERO
		if "camera" in player and player.camera:
			player.camera.reset_smoothing())
	tw.tween_property(fade, "color:a", 0.0, 0.3)
	tw.tween_callback(layer.queue_free)


# --------------------------------------------------------------- memorial
func _memorial() -> void:
	var t := GameState.town
	if t == null:
		return
	var fallen: Array = t.flags.get("fallen", [])
	var lines: Array[String] = [tr("Походов: %d · побед: %d · павших: %d") % [
		int(t.stats.get("expeditions", 0)), int(t.stats.get("victories", 0)), int(t.stats.get("deaths", 0))]]
	if fallen.is_empty():
		lines.append(tr("На камне ещё нет имён."))
	else:
		var last: Array = fallen.slice(maxi(0, fallen.size() - 3))
		last.reverse()
		for f in last:
			lines.append(tr("%s, %s %d ур. — пал(а) на глубине %d") % [f.get("name", "?"), tr(String(f.get("class", ""))), int(f.get("level", 1)), int(f.get("depth", 1))])
	EventBus.message.emit("\n".join(lines))
	AudioManager.play_ui(&"ui_book_open")


# ------------------------------------------------------------- roof cache
func _cache() -> void:
	if _taken() or GameState.town == null:
		return
	GameState.town.flags["roof_cache"] = true
	var gold := 60 + GameState.town.prosperity * 4
	if GameState.hero:
		GameState.hero.add_gold(gold)
	EventBus.floating_text.emit(global_position + Vector2(0, -20), "+%d" % gold, Color(1, 0.85, 0.3))
	EventBus.message.emit(tr("Тайник на крыше: %d золота. Кто-то копил на чёрный день.") % gold)
	AudioManager.play_sfx(&"chest_open", global_position)
	GameFlow.save_town()
	visible = false
