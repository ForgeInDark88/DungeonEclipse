class_name AIDebugDraw
extends Node2D
## F3 overlay in the world: each monster's current path, its sight radius,
## the line of sight to the hero (green = visible, red = blocked) and the
## state name above the head. Drawn only while AIDebug.enabled.

const STATE_COLORS := {
	"patrol": Color(0.6, 0.8, 1.0), "alert": Color(1.0, 0.9, 0.3), "chase": Color(1.0, 0.5, 0.2),
	"attack": Color(1.0, 0.2, 0.2), "search": Color(0.9, 0.6, 1.0), "return": Color(0.6, 1.0, 0.6),
	"hurt": Color(1, 1, 1),
}


func _ready() -> void:
	z_index = 100
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_ai"):
		AIDebug.enabled = not AIDebug.enabled
		queue_redraw()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if AIDebug.enabled:
		queue_redraw()


func _draw() -> void:
	if not AIDebug.enabled:
		return
	var font := ThemeDB.fallback_font
	for e in get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Enemy
		if enemy == null or enemy.is_dead():
			continue
		var name := enemy.state_name()
		var col: Color = STATE_COLORS.get(name, Color.WHITE)
		var pos := to_local(enemy.global_position)
		var pts := enemy.debug_path_points()
		for i in range(1, pts.size()):
			draw_line(to_local(pts[i - 1]), to_local(pts[i]), col, 1.0)
		for p in pts:
			draw_rect(Rect2(to_local(p) - Vector2(1.5, 1.5), Vector2(3, 3)), col)
		draw_arc(pos + Vector2(0, -8), enemy.data.aggro_range, 0.0, TAU, 32, Color(col, 0.25), 1.0)
		var player := enemy.debug_player()
		if player:
			var seen := enemy.debug_sees_player()
			draw_line(pos + Vector2(0, -8), to_local(player.global_position + Vector2(0, -10)),
					Color(0.2, 1.0, 0.3, 0.5) if seen else Color(1.0, 0.2, 0.2, 0.25), 1.0)
		if enemy.debug_memory_pos() != Vector2.INF:
			var m := to_local(enemy.debug_memory_pos())
			draw_circle(m, 3.0, Color(0.9, 0.6, 1.0, 0.8))
		var text := name + ("" if enemy.debug_extra() == "" else " " + enemy.debug_extra())
		draw_string(font, pos + Vector2(-30, -enemy.data.collision_size.y - 14), text, HORIZONTAL_ALIGNMENT_CENTER, 60, 7, col)
