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
	p.lifetime = 0.55
	p.lifetime_randomness = 0.4
	p.explosiveness = 1.0
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.damping_min = speed * 0.25
	p.damping_max = speed * 0.6
	p.gravity = Vector2(0, 200)
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.0
	# born white-hot, cooling to the colour, fading out; sizes shrink
	p.color_ramp = _ramp(color)
	var sc := Curve.new()
	sc.add_point(Vector2(0, 1))
	sc.add_point(Vector2(1, 0.35))
	p.scale_amount_curve = sc
	p.material = _glow()
	parent.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	# a few slow embers drift up after the burst
	if amount >= 8:
		var e := CPUParticles2D.new()
		e.one_shot = true
		e.emitting = true
		e.amount = maxi(3, amount / 3)
		e.lifetime = 1.1
		e.lifetime_randomness = 0.5
		e.explosiveness = 0.8
		e.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		e.emission_sphere_radius = 6.0
		e.direction = Vector2.UP
		e.spread = 50.0
		e.initial_velocity_min = 8.0
		e.initial_velocity_max = 26.0
		e.gravity = Vector2(0, -18)
		e.color_ramp = _ramp(color)
		e.material = _glow()
		parent.add_child(e)
		e.global_position = pos
		e.finished.connect(e.queue_free)


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
	var core := Sprite2D.new()
	core.texture = AssetPaths.tex(AssetPaths.LIGHT)
	core.modulate = Color(color.r * 0.7 + 0.3, color.g * 0.7 + 0.3, color.b * 0.7 + 0.3, 0.75)
	core.scale = Vector2.ONE * clampf(scale * 0.3, 0.06, 0.6)
	core.material = _glow()
	core.z_index = 24
	parent.add_child(core)
	core.global_position = pos
	var twc := core.create_tween()
	twc.set_parallel(true)
	twc.tween_property(core, "scale", core.scale * 1.6, time).set_ease(Tween.EASE_OUT)
	twc.tween_property(core, "modulate:a", 0.0, time)
	twc.chain().tween_callback(core.queue_free)


## A wide sword sweep in front of the caster (cleave, backstab, execution).
static func arc_slash(parent: Node, pos: Vector2, radius: float, color: Color, facing := 1.0) -> void:
	AudioManager.play_sfx(&"hit_flesh", pos, -2.0, 0.2)
	var pts := PackedVector2Array()
	var base := 0.0 if facing > 0.0 else PI
	for i in 15:
		var a := base - 1.35 + 2.7 * i / 14.0
		pts.append(Vector2(cos(a), sin(a) * 0.75) * radius)
	var line := Line2D.new()
	line.width = 12.0
	line.default_color = color.lerp(Color.WHITE, 0.45)
	line.points = pts
	line.z_index = 20
	line.material = _unshaded()
	_beam(line)
	parent.add_child(line)
	line.global_position = pos
	var tw := line.create_tween()
	tw.set_parallel(true)
	tw.tween_property(line, "scale", Vector2(1.5, 1.5), 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(line, "width", 0.0, 0.24)
	tw.chain().tween_callback(line.queue_free)
	var echo := Line2D.new()
	echo.width = 6.0
	echo.default_color = color
	echo.points = pts
	echo.z_index = 19
	echo.material = _unshaded()
	_beam(echo)
	parent.add_child(echo)
	echo.global_position = pos
	var tw2 := echo.create_tween()
	tw2.tween_interval(0.06)
	tw2.set_parallel(true)
	tw2.tween_property(echo, "scale", Vector2(1.7, 1.7), 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw2.tween_property(echo, "width", 0.0, 0.26)
	tw2.tween_property(echo, "modulate:a", 0.0, 0.26)
	tw2.chain().tween_callback(echo.queue_free)
	sparks(parent, pos + Vector2(facing * radius * 0.55, -4.0), color, 14, 150.0)
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
		var streak := Line2D.new()
		streak.width = 3.0
		streak.default_color = color.lerp(Color.WHITE, 0.3)
		streak.z_index = 19
		streak.material = _unshaded()
		_beam(streak)
		streak.points = PackedVector2Array([pos, pos + Vector2.from_angle(a) * radius * 1.1])
		parent.add_child(streak)
		var tws := streak.create_tween()
		tws.tween_property(streak, "modulate:a", 0.0, 0.34)
		tws.tween_callback(streak.queue_free)
	_flash_light(parent, pos, color, 1.8, radius / 60.0, 0.3)
	# a spinning light core
	var core := Sprite2D.new()
	core.texture = AssetPaths.tex(AssetPaths.LIGHT)
	core.modulate = color.lerp(Color.WHITE, 0.4)
	core.scale = Vector2(radius / 50.0, radius / 50.0) * 0.5
	core.material = _unshaded()
	core.z_index = 25
	parent.add_child(core)
	core.global_position = pos
	var twc := core.create_tween()
	twc.tween_property(core, "rotation", TAU, 0.35)
	twc.parallel().tween_property(core, "modulate:a", 0.0, 0.4)
	twc.tween_callback(core.queue_free)


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
		_beam(line)
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
	sparks(parent, pos, color, 20, 140.0)
	sparks(parent, pos, color.lerp(Color.WHITE, 0.3), 8, 80.0)
	_flash_light(parent, pos, color, 3.0, radius / 50.0, 0.4)
	scorch(parent, pos, radius * 0.55, Color(0.1, 0.07, 0.06))
	# a bright ring of light expands faster than the shockwave
	var halo := Line2D.new()
	halo.width = 2.0
	halo.default_color = color.lerp(Color.WHITE, 0.6)
	var hpts := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		hpts.append(Vector2(cos(a), sin(a) * 0.8) * (radius * 0.4))
	halo.points = hpts
	halo.z_index = 21
	halo.material = _unshaded()
	_beam(halo)
	parent.add_child(halo)
	halo.global_position = pos
	var twh := halo.create_tween()
	twh.tween_property(halo, "scale", Vector2(2.6, 2.6), 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	twh.parallel().tween_property(halo, "modulate:a", 0.0, 0.28)
	twh.tween_callback(halo.queue_free)


## Frost: a cold ring plus flying ice shards (frost nova, blizzard, zero).
static func ice_burst(parent: Node, pos: Vector2, radius: float, color: Color) -> void:
	nova_ring(parent, pos, radius, color)
	for i in 5:
		var a := TAU * i / 5 + 0.3
		var spike := Line2D.new()
		spike.width = 3.0
		spike.default_color = Color(0.75, 0.95, 1.0)
		spike.z_index = 19
		spike.material = _unshaded()
		_beam(spike)
		var base := pos + Vector2.from_angle(a) * radius * 0.7
		spike.points = PackedVector2Array([base, base + Vector2(0, -12 - (i % 2) * 5)])
		parent.add_child(spike)
		var twi := spike.create_tween()
		twi.tween_interval(0.08)
		twi.set_parallel(true)
		twi.tween_property(spike, "modulate:a", 0.0, 0.45)
		twi.chain().tween_callback(spike.queue_free)
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
		var halo := Line2D.new()
		halo.width = 11.0
		halo.default_color = Color(color.r, color.g, color.b, 0.35)
		halo.points = beam.points
		halo.z_index = 19
		halo.material = _unshaded()
		_beam(halo)
		beam.add_child(halo)
		beam.z_index = 20
		beam.material = _unshaded()
		_beam(beam)
		parent.add_child(beam)
		beam.global_position = px
		var tw := beam.create_tween()
		tw.tween_interval(0.07 * i)
		tw.set_parallel(true)
		tw.tween_property(beam, "modulate:a", 0.2, 0.05)
		tw.tween_property(beam, "width", 0.0, 0.3).set_delay(0.12)
		tw.tween_property(beam, "modulate:a", 0.0, 0.3).set_delay(0.12)
		tw.chain().tween_callback(beam.queue_free)
		sparks(parent, px, color, 8, 90.0)
		sparks(parent, px, Color.WHITE, 3, 40.0)
	_flash_light(parent, pos, color, 3.0, radius / 45.0, 0.4)
	# a bright cross flash over the whole area
	var flash := Line2D.new()
	flash.width = 3.0
	flash.default_color = Color(color.r + 0.3, color.g + 0.3, color.b + 0.3, 0.8)
	flash.points = PackedVector2Array([Vector2(-radius, 0), Vector2(radius, 0)])
	flash.z_index = 22
	flash.material = _unshaded()
	_beam(flash)
	parent.add_child(flash)
	flash.global_position = pos
	var twf := flash.create_tween()
	twf.tween_property(flash, "modulate:a", 0.0, 0.3)
	twf.tween_callback(flash.queue_free)


## A blinding sun flash with rings and a shower of sparks (supernova).
static func sun_flash(parent: Node, pos: Vector2, radius: float, color: Color) -> void:
	AudioManager.play_sfx(&"explosion", pos)
	nova_ring(parent, pos, radius, color)
	var core := Polygon2D.new()
	var cpts := PackedVector2Array()
	for i in 16:
		var ca := TAU * i / 16.0
		cpts.append(Vector2(cos(ca), sin(ca)) * radius)
	core.polygon = cpts
	core.color = Color(1.0, 0.98, 0.9, 0.9)
	core.z_index = 30
	core.material = _unshaded()
	parent.add_child(core)
	core.global_position = pos
	var twc := core.create_tween()
	twc.tween_property(core, "scale", Vector2(1.6, 1.6), 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	twc.parallel().tween_property(core, "color:a", 0.0, 0.3)
	twc.tween_callback(core.queue_free)
	_flash_light(parent, pos, Color(color.r * 0.6 + 0.4, color.g * 0.6 + 0.4, color.b * 0.6 + 0.4), 6.0, radius / 34.0, 0.5)
	sparks(parent, pos, color.lerp(Color.WHITE, 0.5), 26, 190.0)
	shards(parent, pos, color.lerp(Color.WHITE, 0.4), 8)


## Rock and dust bursting from the ground (earthquake, slams, meteors).
static func rock_burst(parent: Node, pos: Vector2, radius: float, color: Color) -> void:
	AudioManager.play_sfx(&"dig", pos, -2.0, 0.3)
	shards(parent, pos, Color(0.5, 0.4, 0.34), maxi(12, int(radius / 4.0)))
	shards(parent, pos + Vector2(0, -6), Color(0.35, 0.28, 0.24), 6)
	for i in 3:
		dust(parent, pos + Vector2(randf_range(-0.6, 0.6) * radius, -2.0), true)
	nova_ring(parent, pos, radius * 0.8, Color(0.55, 0.45, 0.4))
	_flash_light(parent, pos, color, 1.6, radius / 60.0, 0.3)
	for i in 5:
		var a := TAU * i / 5 + randf() * 0.5
		var crack := Line2D.new()
		crack.width = 2.0
		crack.default_color = Color(0.16, 0.12, 0.1, 0.8)
		var kpts := PackedVector2Array([Vector2.ZERO])
		var cur := Vector2.ZERO
		for k in 4:
			cur += Vector2.from_angle(a + randf_range(-0.4, 0.4)) * radius * 0.3
			kpts.append(cur)
		crack.points = kpts
		crack.z_index = -1
		parent.add_child(crack)
		crack.global_position = pos
		var twk := crack.create_tween()
		twk.tween_interval(1.8)
		twk.tween_property(crack, "modulate:a", 0.0, 2.0)
		twk.tween_callback(crack.queue_free)
	scorch(parent, pos, radius * 0.6, Color(0.13, 0.1, 0.08))


## A burning rock falls from the sky onto the target (meteor cast phase).
static func meteor_fall(parent: Node, pos: Vector2, radius: float, color: Color) -> void:
	AudioManager.play_sfx(&"meteor_fall", pos)
	var warn := Telegraph.circle(parent, pos, radius * 0.8, 0.5)
	if warn:
		warn.color = Color(1.0, 0.45, 0.15)
	var rock := Sprite2D.new()
	rock.texture = AssetPaths.tex(AssetPaths.SHARD)
	rock.scale = Vector2(2.6, 2.6)
	rock.rotation = 0.6
	rock.modulate = Color(1.0, 0.55, 0.3)
	rock.z_index = 22
	rock.material = _unshaded()
	parent.add_child(rock)
	var from := pos + Vector2(60, -190)
	rock.global_position = from
	var trail := Line2D.new()
	trail.width = 10.0
	trail.default_color = Color(1.0, 0.6, 0.25, 0.85)
	trail.z_index = 21
	trail.material = _unshaded()
	_beam(trail)
	parent.add_child(trail)
	var tw := rock.create_tween()
	tw.tween_method(func(t: float) -> void:
		rock.global_position = from.lerp(pos, t)
		rock.rotation = 0.6 + t * 2.0
		trail.add_point(rock.global_position + Vector2(6, -8))
		if trail.get_point_count() > 14:
			trail.remove_point(0)
	, 0.0, 1.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		rock.queue_free()
		var fade := trail.create_tween()
		fade.tween_property(trail, "modulate:a", 0.0, 0.4)
		fade.tween_callback(trail.queue_free))


## The meteor lands: a double explosion, shockwave rings, debris, scorch.
static func meteor_impact(parent: Node, pos: Vector2, radius: float, color: Color) -> void:
	AudioManager.play_sfx(&"meteor_impact", pos)
	explosion(parent, pos, radius, color)
	nova_ring(parent, pos, radius * 1.1, color)
	shards(parent, pos, Color(0.55, 0.4, 0.32), 14)
	sparks(parent, pos, color.lerp(Color.WHITE, 0.4), 26, 220.0)
	_flash_light(parent, pos, color, 5.0, radius / 26.0, 0.5)
	scorch(parent, pos, radius * 0.7, Color(0.12, 0.07, 0.05))


## A fading dark mark on the ground (impacts, big slams).
static func scorch(parent: Node, pos: Vector2, radius: float, col: Color) -> void:
	var c := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 12:
		var a := TAU * i / 12.0
		var rr := radius * (0.8 + 0.25 * sin(i * 2.7))
		pts.append(Vector2(cos(a), sin(a) * 0.55) * rr)
	c.polygon = pts
	c.color = Color(col.r, col.g, col.b, 0.4)
	c.z_index = -2
	parent.add_child(c)
	c.global_position = pos + Vector2(0, 2)
	var tw := c.create_tween()
	tw.tween_interval(2.2)
	tw.tween_property(c, "color:a", 0.0, 2.6)
	tw.tween_callback(c.queue_free)


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
		var k := 16.0 / maxf(1.0, item.icon.get_width()) if item.icon else 1.0
		s.scale = Vector2(0.3, 0.3) * k
		var target := pos + Vector2((i - (n - 1) / 2.0) * 14.0, -22.0)
		var tw := s.create_tween()
		tw.set_parallel()
		tw.tween_property(s, "global_position", target, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(i * 0.06)
		tw.tween_property(s, "scale", Vector2.ONE * k, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(i * 0.06)
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


## Additive, unlit: light that adds up where effects overlap.
static func _glow() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m


## White-hot -> colour -> gone (particle colour over life).
static func _ramp(color: Color) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.18, 0.7, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), color.lerp(Color.WHITE, 0.25), color, Color(color.r, color.g, color.b, 0.0)])
	return g


static var _beam_cache := {}


## Turns a flat Line2D into a beam of light: a white-hot core inside the
## colour, soft edges across its width, additive, round ends; open strokes
## (slashes, trails, beams) taper toward their ends.
static func _beam(line: Line2D) -> void:
	var col := line.default_color
	var key := col.to_html(false)
	var tex: Texture2D = _beam_cache.get(key)
	if tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.22, 0.42, 0.5, 0.58, 0.78, 1.0])
		var c := Color(col.r, col.g, col.b, 1.0)
		var hot := c.lerp(Color.WHITE, 0.8)
		g.colors = PackedColorArray([Color(c.r, c.g, c.b, 0.0), Color(c.r, c.g, c.b, 0.45), c.lerp(Color.WHITE, 0.3), hot,
				c.lerp(Color.WHITE, 0.3), Color(c.r, c.g, c.b, 0.45), Color(c.r, c.g, c.b, 0.0)])
		# Built at once (a GradientTexture2D fills itself a frame later and
		# the first beams would be blank).
		var img := Image.create(2, 16, false, Image.FORMAT_RGBA8)
		for y in 16:
			var gc := g.sample((y + 0.5) / 16.0)
			img.set_pixel(0, y, gc)
			img.set_pixel(1, y, gc)
		tex = ImageTexture.create_from_image(img)
		_beam_cache[key] = tex
	line.texture = tex
	line.texture_mode = Line2D.LINE_TEXTURE_STRETCH
	line.default_color = Color(1, 1, 1, col.a)
	line.width *= 2.0
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.material = _glow()
	var n := line.points.size()
	if n >= 8 and line.points[0].distance_to(line.points[n - 1]) <= line.width * 2.0:
		line.closed = true  # rings: no gap
	elif n >= 3:
		var curve := Curve.new()
		curve.add_point(Vector2(0, 0.15))
		curve.add_point(Vector2(0.5, 1))
		curve.add_point(Vector2(1, 0.15))
		line.width_curve = curve


static func _unshaded() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return m
