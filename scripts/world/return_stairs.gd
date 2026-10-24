class_name ReturnStairs
extends Area2D
## The wayfarer's archway near the floor entrance of every dungeon floor:
## interact to climb back to the town street (the run continues, the town
## gate leads back to this floor). A warm shaft of surface light, rising
## motes and a breathing glow mark it in the dark.

const UP_SFX := &"portal"


func _ready() -> void:
	add_to_group("interactable")
	collision_layer = 16
	collision_mask = 0
	monitoring = false
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(28, 30)
	shape.shape = rect
	shape.position = Vector2(0, -15)
	add_child(shape)
	_shaft()
	_motes()
	_breathing_light()


## A soft vertical shaft of daylight above the arch (additive, breathing).
func _shaft() -> void:
	var s := Sprite2D.new()
	s.texture = AssetPaths.tex(AssetPaths.LIGHT)
	s.position = Vector2(0, -34)
	s.scale = Vector2(0.45, 1.5)
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	s.material = m
	s.modulate = Color(1.0, 0.85, 0.55, 0.30)
	s.z_index = -1
	add_child(s)
	var tw := s.create_tween().set_loops()
	tw.tween_property(s, "modulate:a", 0.16, 1.3).set_trans(Tween.TRANS_SINE)
	tw.tween_property(s, "modulate:a", 0.30, 1.3).set_trans(Tween.TRANS_SINE)


## Warm motes drift up out of the archway.
func _motes() -> void:
	var p := CPUParticles2D.new()
	p.amount = 10
	p.lifetime = 2.2
	p.preprocess = 2.2
	p.position = Vector2(0, -14)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(5, 8)
	p.direction = Vector2.UP
	p.spread = 12.0
	p.gravity = Vector2(0, -14)
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 14.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	p.color = Color(1.0, 0.83, 0.5, 0.75)
	add_child(p)


## The point light breathes like a torch at a shrine.
func _breathing_light() -> void:
	var light := PointLight2D.new()
	light.texture = AssetPaths.tex(AssetPaths.LIGHT)
	light.color = Color(1.0, 0.75, 0.45)
	light.energy = 0.9
	light.texture_scale = 0.6
	light.position = Vector2(0, -16)
	add_child(light)
	var tw := create_tween().set_loops()
	tw.tween_property(light, "energy", 1.2, 1.1).set_trans(Tween.TRANS_SINE)
	tw.tween_property(light, "energy", 0.7, 1.1).set_trans(Tween.TRANS_SINE)


func get_prompt() -> String:
	return "Вернуться в город"


func interact(_player: Node) -> void:
	AudioManager.play_sfx(UP_SFX, global_position)
	EventBus.message.emit("Ты поднимаешься по лестнице на поверхность...")
	GameState.return_to_town()
