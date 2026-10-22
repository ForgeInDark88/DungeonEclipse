class_name Telegraph
extends Node2D
## Pulsing red warning shape that disappears after `duration`:
## a circle (radius) or a horizontal line (length) on the ground.

var radius := 0.0
var line_length := 0.0
var duration := 0.8
var color := Color(1.0, 0.15, 0.1)
var _t := 0.0


static func circle(parent: Node, pos: Vector2, p_radius: float, p_duration: float) -> Telegraph:
	var t := Telegraph.new()
	t.radius = p_radius
	t.duration = p_duration
	parent.add_child(t)
	t.global_position = pos
	return t


static func line(parent: Node, pos: Vector2, length: float, p_duration: float) -> Telegraph:
	var t := Telegraph.new()
	t.line_length = length
	t.duration = p_duration
	parent.add_child(t)
	t.global_position = pos
	return t


func _ready() -> void:
	z_index = 40
	var m := CanvasItemMaterial.new()
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = m


func _process(delta: float) -> void:
	_t += delta
	if _t >= duration:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var k := _t / duration
	var a := 0.25 + 0.35 * absf(sin(_t * 14.0))
	var c := Color(color.r, color.g, color.b, a)
	if radius > 0.0:
		draw_circle(Vector2.ZERO, radius * (0.3 + 0.7 * k), Color(c.r, c.g, c.b, a * 0.6))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, Color(c.r, c.g, c.b, 0.9), 1.0)
	elif line_length != 0.0:
		draw_rect(Rect2(Vector2(minf(0.0, line_length), -3.0), Vector2(absf(line_length), 6.0)), c)
