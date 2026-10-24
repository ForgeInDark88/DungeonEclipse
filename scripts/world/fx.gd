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


## --------------------------------------------------- skill blast variants
## Each damaging area skill picks its own look instead of the plain bomb.

static func _flash_light(parent: Node, pos: Vector2, color: Color, energy := 2.5, scale := 1.0, time := 0.35) -> void:
	var light := PointLight2D.new()
	light.texture = AssetPaths.tex(AssetPaths.LIGHT)
	light.color = color
	light.energy = energy
	light.texture_scale = scale
	parent.add_child(light)
	light.global_position = pos
	var tw := light.create_tween()
	tw.tween_property(light, "energy", 0.0, time)
	tw.tween_callback(light.queue_free)


## A wide sword sweep in front of the caster (cleave, backstab, execution).
static func arc_slash(parent: Node, pos: Vector2, radius: float, color: Color, facing := 1.0) -> void:
	AudioManager.play_sfx(&"hit_flesh", pos, -2.0, 0.2)
	var pts := PackedVector2Array()
	var base := 0.0 if facing > 0.0 else PI
	for i in 15:
		var a := base - 1.35 + 2.7 * i / 14.0
		pts.append(Vector2(cos(a), sin(a) * 0.75) * radius)
	var line := Line2D.new()
	line.width = 8.0
	line.default_color = color.lerp(Color.WHITE, 0.45)
	line.points = pts
	line.z_index = 20
	line.material = _unshaded()
	parent.add_child(line)
	line.global_position = pos
	var tw := line.create_tween()
	tw.set_parallel(true)
	tw.tween_property(line, "scale", Vector2(1.5, 1.5), 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(line, "width", 0.0, 0.24)
	tw.chain().tween_callback(line.queue_free)
	sparks(parent, pos + Vector2(facing * radius * 0.55, -4.0), color, 10, 130.0)
	_flash_light(parent, pos, color, 1.6, radius / 70.0, 0.25)


## Spinning knives thrown out in a circle (blade storms and dances).
static func blade_fan(parent: Node, pos: Vector2, radius: float, color: Color, count := 9) -> void:
	AudioManager.play_sfx(&"attack_dagger", pos, -2.0, 0.25)
	var tex := load("res://assets/sprites/fx/knife.png") as Texture2D
	for i in count:
		var a := TAU * i / count + randf() * 0.25
		var knife := Sprite2D.new()
		knife.texture = tex
		knife.rotation = a + PI / 2.0
		knife.modulate = color.lerp(Color.WHITE, 0.35)
		knife.z_index = 20
		knife.material = _unshaded()
		parent.add_child(knife)
		knife.global_position = pos
		var tw := knife.create_tween()
		tw.set_parallel(true)
		tw.tween_property(knife, "position", pos + Vector2.from_angle(a) * radius * 1.25, 0.3).set_ease(Tween.EASE_OUT)
		tw.tween_property(knife, "rotation", a + PI / 2.0 + TAU, 0.3)
		tw.tween_property(knife, "modulate:a", 0.0, 0.32)
		tw.chain().tween_callback(knife.queue_free)
	_flash_light(parent, pos, color, 1.8, radius / 60.0, 0.3)


## Expanding double ring (novas, shockwaves, war cries).
static func nova_ring(parent: Node, pos: Vector2, radius: float, color: Color) -> void:
	AudioManager.play_sfx(&"explosion", pos, -6.0, 0.3)
	for k in 2:
		var pts := PackedVector2Array()
		var n := 24
		for i in n:
			var a := TAU * i / n
			pts.append(Vector2(cos(a), sin(a) * 0.8) * (radius * 0.55))
		var line := Line2D.new()
		line.width = 6.0 - k * 2.0
		line.default_color = color.lerp(Color.WHITE, 0.25 + k * 0.3)
		line.points = pts
		line.z_index = 20
		line.material = _unshaded()
		parent.add_child(line)
		line.global_position = pos
		var delay := 0.09 * k
		var tw := line.create_tween()
		tw.tween_interval(delay)
		tw.set_parallel(true)
		tw.tween_property(line, "scale", Vector2(2.1, 2.1), 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(line, "width", 0.0, 0.36).set_delay(delay)
		tw.tween_property(line, "modulate:a", 0.0, 0.36).set_delay(delay)
		tw.chain().tween_callback(line.queue_free)
	sparks(parent, pos, color, 14, 110.0)
	_flash_light(parent, pos, color, 2.4, radius / 55.0)


## Frost: a cold ring plus flying ice shards (frost nova, blizzard, zero).
static func ice_burst(parent: Node, pos: Vector2, radius: float, color: Color) -> void:
	nova_ring(parent, pos, radius, color)
	var tex := load("res://assets/sprites/fx/shard.png") as Texture2D
	for i in 7:
		var a := TAU * i / 7 + randf() * 0.4
		var shard := Sprite2D.new()
		shard.texture = tex
		shard.rotation = a
		shard.modulate = Color(color.r * 0.7 + 0.3, color.g * 0.7 + 0.3, 1.0, 1.0)
		shard.z_index = 20
		shard.material = _unshaded()
		parent.add_child(shard)
		shard.global_position = pos
		var tw := shard.create_tween()
		tw.set_parallel(true)
		tw.tween_property(shard, "position", pos + Vector2.from_angle(a) * radius * 1.15, 0.34).set_ease(Tween.EASE_OUT)
		tw.tween_property(shard, "rotation", a + randf_range(-1.5, 1.5), 0.34)
		tw.tween_property(shard, "modulate:a", 0.0, 0.36)
		tw.chain().tween_callback(shard.queue_free)


## Pillars of light striking down inside the area (judgement, wrath).
static func light_pillars(parent: Node, pos: Vector2, radius: float, color: Color, count := 5) -> void:
	AudioManager.play_sfx(&"level_up", pos, -8.0, 0.3)
	for i in count:
		var px := pos + Vector2(randf_range(-0.8, 0.8) * radius, randf_range(-0.25, 0.25) * radius)
		var beam := Line2D.new()
		beam.width = 5.0
		beam.default_color = color.lerp(Color.WHITE, 0.5)
		beam.points = PackedVector2Array([Vector2(0, -110), Vector2(0, 0)])
		beam.z_index = 20
		beam.material = _unshaded()
		parent.add_child(beam)
		beam.global_position = px
		var tw := beam.create_tween()
		tw.tween_interval(0.07 * i)
		tw.set_parallel(true)
		tw.tween_property(beam, "modulate:a", 0.2, 0.05)
		tw.tween_property(beam, "width", 0.0, 0.3).set_delay(0.12)
		tw.tween_property(beam, "modulate:a", 0.0, 0.3).set_delay(0.12)
		tw.chain().tween_callback(beam.queue_free)
		sparks(parent, px, color, 6, 70.0)
	_flash_light(parent, pos, color, 3.0, radius / 45.0, 0.4)


## A blinding sun flash with rings and a shower of sparks (supernova).
static func sun_flash(parent: Node, pos: Vector2, radius: float, color: Color) -> void:
	AudioManager.play_sfx(&"explosion", pos)
	nova_ring(parent, pos, radius, color)
	_flash_light(parent, pos, Color(color.r * 0.6 + 0.4, color.g * 0.6 + 0.4, color.b * 0.6 + 0.4), 6.0, radius / 34.0, 0.5)
	sparks(parent, pos, color.lerp(Color.WHITE, 0.5), 26, 190.0)
	shards(parent, pos, color.lerp(Color.WHITE, 0.4), 8)


## Rock and dust bursting from the ground (earthquake, slams, meteors).
static func rock_burst(parent: Node, pos: Vector2, radius: float, color: Color) -> void:
	AudioManager.play_sfx(&"dig", pos, -2.0, 0.3)
	shards(parent, pos, Color(0.5, 0.4, 0.34), maxi(8, int(radius / 6.0)))
	for i in 3:
		dust(parent, pos + Vector2(randf_range(-0.6, 0.6) * radius, -2.0), true)
	nova_ring(parent, pos, radius * 0.8, Color(0.55, 0.45, 0.4))
	_flash_light(parent, pos, color, 1.6, radius / 60.0, 0.3)


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
