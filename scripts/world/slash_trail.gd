class_name SlashTrail
extends Node2D
## Short-lived swing trail: a crescent for arcs, a streak for thrusts.

var reach := 24.0
var thrust := false
var color := Color.WHITE
var _life := 0.16
var _t := 0.0


static func spawn(parent: Node, pos: Vector2, dir: float, p_reach: float, p_thrust: bool, p_color: Color) -> void:
	var s := SlashTrail.new()
	s.reach = p_reach
	s.thrust = p_thrust
	s.color = p_color
	s.scale.x = dir
	var m := CanvasItemMaterial.new()
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	s.material = m
	s.z_index = 15
	parent.add_child(s)
	s.global_position = pos


func _process(delta: float) -> void:
	_t += delta
	if _t >= _life:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var k := 1.0 - _t / _life
	var c := Color(color.r, color.g, color.b, 0.75 * k)
	if thrust:
		var w := 3.0 * k + 1.0
		draw_colored_polygon(PackedVector2Array([Vector2(4, -w), Vector2(reach + 4.0, 0), Vector2(4, w)]), c)
		draw_line(Vector2(4, 0), Vector2(reach + 2.0, 0), Color(1, 1, 1, 0.8 * k), 1.0)
		return
	# Crescent from above the head down in front of the hero.
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	var from := -110.0
	var to := 40.0
	for i in 13:
		var a := deg_to_rad(lerpf(from, to, i / 12.0))
		outer.append(Vector2.from_angle(a) * reach)
		inner.append(Vector2.from_angle(a) * reach * (0.55 + 0.25 * (1.0 - k)))
	inner.reverse()
	draw_colored_polygon(outer + inner, c)
	draw_polyline(outer, Color(1, 1, 1, 0.7 * k), 1.0)
