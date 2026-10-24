class_name Decoration
extends Node2D
## Placed decoration sprite (+ optional glow, flicker and swaying).

var data: DecorData
## Wall props are tinted like the back wall (a bit lighter) so they sit on it.
var wall_tint := Color.WHITE


func _ready() -> void:
	var on_wall := data.placement == DecorData.Placement.WALL
	z_index = -4 if on_wall else -1
	var s := Sprite2D.new()
	s.texture = data.texture
	s.centered = false
	var size := data.texture.get_size()
	# Floor items stand on the origin, ceiling items hang from it.
	match data.placement:
		DecorData.Placement.FLOOR:
			s.offset = Vector2(-size.x / 2.0, -size.y)
		DecorData.Placement.WALL:
			s.offset = -size / 2.0
			if not data.unshaded:
				s.modulate = wall_tint
		_:
			s.offset = Vector2(-size.x / 2.0, 0)
	# Every copy sits a bit differently so repeats never look copy-pasted.
	s.flip_h = randf() < 0.5
	match data.placement:
		DecorData.Placement.FLOOR:
			# Tilt and resize pivot at the feet point, nudge along the floor.
			s.rotation_degrees = randf_range(-8.0, 8.0)
			var k := randf_range(0.88, 1.14)
			s.scale = Vector2(k, k)
			s.position.x = randf_range(-4.0, 4.0)
		DecorData.Placement.CEILING:
			var kc := randf_range(0.9, 1.12)
			s.scale = Vector2(kc, kc)
			s.position.x = randf_range(-3.0, 3.0)
		_:
			s.position.y = randf_range(-2.0, 2.0)
	if data.unshaded:
		var m := CanvasItemMaterial.new()
		m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		s.material = m
	add_child(s)
	if data.light_color.a > 0.0:
		var l := PointLight2D.new()
		l.texture = AssetPaths.tex(AssetPaths.LIGHT)
		l.color = data.light_color
		l.texture_scale = data.light_scale
		l.energy = 0.9
		match data.placement:
			DecorData.Placement.FLOOR:
					l.position = Vector2(0, -size.y / 2.0)
			DecorData.Placement.WALL:
					l.position = Vector2.ZERO
			_:
					l.position = Vector2(0, size.y / 2.0)
		add_child(l)
		_flicker(l)
	if data.sway:
		var tw := create_tween().set_loops()
		var amp := randf_range(3.0, 6.0)
		tw.tween_property(s, "rotation_degrees", amp, randf_range(1.2, 2.0)).set_trans(Tween.TRANS_SINE)
		tw.tween_property(s, "rotation_degrees", -amp, randf_range(1.2, 2.0)).set_trans(Tween.TRANS_SINE)


## A living flame breathes: two sines around the base energy.
func _flicker(l: PointLight2D) -> void:
	var base := l.energy
	var tw := create_tween().set_loops()
	tw.tween_method(func(phase: float) -> void:
		l.energy = base + sin(phase) * 0.07 + sin(phase * 2.7) * 0.05,
		0.0, TAU, randf_range(1.8, 2.6)).set_trans(Tween.TRANS_LINEAR)
