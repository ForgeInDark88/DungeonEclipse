class_name Fx
extends RefCounted
## Small reusable visual effects built from code (no assets needed).


## Expanding flash ring + sparks.
static func explosion(parent: Node, pos: Vector2, radius: float, color: Color) -> void:
	var flash := Sprite2D.new()
	flash.texture = AssetPaths.tex(AssetPaths.LIGHT)
	flash.modulate = color
	flash.material = _unshaded()
	parent.add_child(flash)
	flash.global_position = pos
	var base := radius * 2.0 / 256.0
	flash.scale = Vector2.ONE * base * 0.3
	var tw := flash.create_tween().set_parallel()
	tw.tween_property(flash, "scale", Vector2.ONE * base * 1.4, 0.25)
	tw.tween_property(flash, "modulate:a", 0.0, 0.3)
	tw.chain().tween_callback(flash.queue_free)
	sparks(parent, pos, color, 18, 140.0)


static func sparks(parent: Node, pos: Vector2, color: Color, amount := 8, speed := 90.0) -> void:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = amount
	p.lifetime = 0.5
	p.explosiveness = 1.0
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector2(0, 200)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	p.color = color
	p.material = _unshaded()
	parent.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)


static func _unshaded() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return m
