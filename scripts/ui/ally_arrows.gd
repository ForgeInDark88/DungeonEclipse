class_name AllyArrows
extends Control
## Co-op: an arrow at the screen edge for every ally out of sight - in the
## ally's colour, with the first letter of the name and the distance in
## tiles; a fallen ally gets a grey arrow and a cross.

const MARGIN := 22.0
const SIZE := 7.0

var _font: Font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


func _process(_delta: float) -> void:
	visible = Net.active
	if visible:
		queue_redraw()


func _draw() -> void:
	var game := get_tree().current_scene
	if game == null or not game.has_method("party") or game.player == null:
		return
	var screen := get_viewport_rect().size
	var to_screen := get_viewport().get_canvas_transform()
	var me: Player = game.player
	# The playfield: above the bottom panel of the HUD (arrows never sit on it).
	var bottom := screen.y
	var panel = get_parent().get("_panel") if get_parent() else null
	if panel is Control and (panel as Control).visible:
		bottom = (panel as Control).get_global_rect().position.y
	var inner := Rect2(Vector2(MARGIN, MARGIN), Vector2(screen.x - MARGIN * 2.0, bottom - MARGIN * 2.0))
	for p: Player in game.party():
		if p == me or not is_instance_valid(p):
			continue
		var pos: Vector2 = to_screen * (p.global_position + Vector2(0, -14))
		if Rect2(Vector2.ZERO, screen).grow(-4.0).has_point(pos):
			continue  # on screen: the name tag over the head is enough
		var center := inner.get_center()
		var dir := (pos - center).normalized()
		# The point where the line to the ally leaves the inner rectangle.
		var k := INF
		if absf(dir.x) > 0.001:
			k = minf(k, ((inner.end.x if dir.x > 0.0 else inner.position.x) - center.x) / dir.x)
		if absf(dir.y) > 0.001:
			k = minf(k, ((inner.end.y if dir.y > 0.0 else inner.position.y) - center.y) / dir.y)
		var at := center + dir * k
		var col := UIStyle.ally_color(p.peer_id) if not p.dead else Color(0.6, 0.6, 0.6)
		var tip := at + dir * SIZE
		var side := dir.orthogonal() * SIZE * 0.7
		draw_colored_polygon(PackedVector2Array([tip, at - dir * SIZE * 0.4 + side, at - dir * SIZE * 0.4 - side]), col)
		draw_polyline(PackedVector2Array([tip, at - dir * SIZE * 0.4 + side, at - dir * SIZE * 0.4 - side, tip]), Color(0, 0, 0, 0.8), 1.0)
		var badge := at - dir * (SIZE + 6.0)
		draw_circle(badge, 6.0, Color(0, 0, 0, 0.75))
		draw_arc(badge, 6.0, 0.0, TAU, 16, col, 1.0)
		var name_text := String(Net.players.get(p.peer_id, {}).get("name", "?"))
		var letter := "†" if p.dead else name_text.substr(0, 1).to_upper()
		draw_string(_font, badge + Vector2(-3.5, 3.5), letter, HORIZONTAL_ALIGNMENT_CENTER, 7.0, 8, col)
		var tiles := int(me.global_position.distance_to(p.global_position) / 16.0)
		var label := "%d" % tiles
		var lpos := badge - dir * 12.0 + Vector2(-6, 3)
		draw_string(_font, lpos + Vector2(1, 1), label, HORIZONTAL_ALIGNMENT_CENTER, 12.0, 7, Color(0, 0, 0, 0.8))
		draw_string(_font, lpos, label, HORIZONTAL_ALIGNMENT_CENTER, 12.0, 7, col)
