class_name Fx
extends RefCounted
## Small reusable visual effects (animated sheets + particles).


## Plays one animation of a sheet once at `pos` and frees it afterwards.
static func play_once(parent: Node, pos: Vector2, sheet_path: String, layout_path: String,
		anim: StringName, unshaded := true, scale := Vector2.ONE) -> AnimatedSprite2D:
	var lay := AssetPaths.layout(layout_path)
	var tex := AssetPaths.tex(sheet_path)
	if lay == null or tex == null or parent == null:
		return null
	var s := AnimatedSprite2D.new()
	lay.apply_to(s, tex)
	if unshaded:
		s.material = _unshaded()
	s.z_index = 20
	s.scale = scale
	parent.add_child(s)
	s.global_position = pos
	s.play(anim)
	s.animation_finished.connect(s.queue_free)
	return s


## Bomb / fireball explosion: animated blast + flash light + sparks.
static func explosion(parent: Node, pos: Vector2, radius: float, color: Color) -> void:
	AudioManager.play_sfx(&"explosion", pos)
	var sc := maxf(0.6, radius / 24.0)
	var boom := play_once(parent, pos, AssetPaths.EXPLOSION_SHEET, AssetPaths.EXPLOSION_LAYOUT, &"boom", true, Vector2(sc, sc))
	if boom:
		boom.modulate = color.lerp(Color.WHITE, 0.5)
	var light := PointLight2D.new()
	light.texture = AssetPaths.tex(AssetPaths.LIGHT)
	light.color = color
	light.energy = 2.5
	light.texture_scale = radius / 60.0
	parent.add_child(light)
	light.global_position = pos
	var tw := light.create_tween()
	tw.tween_property(light, "energy", 0.0, 0.35)
	tw.tween_callback(light.queue_free)
	sparks(parent, pos, color, 18, 140.0)


static func hit_spark(parent: Node, pos: Vector2, crit := false) -> void:
	var sc := Vector2(1.5, 1.5) if crit else Vector2.ONE
	var s := play_once(parent, pos, AssetPaths.HIT_SHEET, AssetPaths.HIT_LAYOUT, &"hit", true, sc)
	if s and crit:
		s.modulate = Color(1.0, 0.85, 0.3)


static func dust(parent: Node, feet_pos: Vector2, big := false) -> void:
	var sc := Vector2(1.6, 1.3) if big else Vector2.ONE
	play_once(parent, feet_pos, AssetPaths.DUST_SHEET, AssetPaths.DUST_LAYOUT, &"puff", false, sc)


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


## Rotating shards (broken bricks, shattered things).
static func shards(parent: Node, pos: Vector2, color: Color, amount := 10) -> void:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = amount
	p.lifetime = 0.8
	p.explosiveness = 1.0
	p.spread = 180.0
	p.direction = Vector2.UP
	p.initial_velocity_min = 50.0
	p.initial_velocity_max = 130.0
	p.gravity = Vector2(0, 450)
	p.angular_velocity_min = -540.0
	p.angular_velocity_max = 540.0
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.4
	p.texture = AssetPaths.tex(AssetPaths.SHARD)
	p.color = color
	parent.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)


## Item icons that pop out above a chest and fade (loot preview).
static func loot_popup(parent: Node, pos: Vector2, items: Array) -> void:
	var n := items.size()
	for i in n:
		var item: ItemData = items[i]["item"]
		var s := Sprite2D.new()
		s.texture = item.icon
		s.material = _unshaded()
		s.z_index = 30
		parent.add_child(s)
		s.global_position = pos
		s.scale = Vector2(0.3, 0.3)
		var target := pos + Vector2((i - (n - 1) / 2.0) * 14.0, -22.0)
		var tw := s.create_tween()
		tw.set_parallel()
		tw.tween_property(s, "global_position", target, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(i * 0.06)
		tw.tween_property(s, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(i * 0.06)
		if item.rarity > ItemData.Rarity.COMMON:
			tw.tween_property(s, "modulate", item.rarity_color() * 1.6, 0.2).set_delay(0.3)
		tw.chain().tween_interval(0.5)
		tw.chain().tween_property(s, "modulate:a", 0.0, 0.3)
		tw.chain().tween_callback(s.queue_free)


## Translucent copy of the hero for dash trails.
static func afterimage(visual: Node2D, parent: Node) -> void:
	var ghost := Node2D.new()
	ghost.global_transform = visual.global_transform
	ghost.modulate = Color(0.6, 0.8, 1.0, 0.5)
	ghost.material = _unshaded()
	for child in visual.get_children():
		if child is AnimatedSprite2D and child.visible and child.sprite_frames:
			var s := Sprite2D.new()
			s.texture = child.sprite_frames.get_frame_texture(child.animation, child.frame)
			s.centered = false
			s.offset = child.offset
			s.use_parent_material = true
			ghost.add_child(s)
	parent.add_child(ghost)
	ghost.global_transform = visual.global_transform
	var tw := ghost.create_tween()
	tw.tween_property(ghost, "modulate:a", 0.0, 0.25)
	tw.tween_callback(ghost.queue_free)


static func _unshaded() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return m
