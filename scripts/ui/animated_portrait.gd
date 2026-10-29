class_name AnimatedPortrait
extends Control
## The hero portrait of the in-game HUD, alive (frame-by-frame pixel art):
##   * a heroic close-up sheet (AssetPaths.HERO_PORTRAIT_FRAMES) over the class
##     background; class particles drift between them;
##   * breathing (shoulders rise, plumes / hair / hat tips sway), 3-frame
##     blinks (sometimes double), glances; a 2-frame snarl when hitting a
##     monster; pain throws the head back, then a grimace and a shake; heavy
##     breathing with a wounded face and a red pulse on low HP;
##   * glints: the warrior's lamp flickers, the mage's gem and amulet pulse,
##     a spark runs over the paladin's cross, the rogue's eye catches light;
##   * status tint, flashes on healing / level up, grey with closed eyes on death.
## Without a close-up for the race x class pair it falls back to the old
## layers (race face + class overlay, expressions <face>_blink/_glance/...).
## Menus keep the static UIStyle.portrait.

const LOW_HP := 0.3
const STATUS_TINTS := {
	&"poison": Color(0.55, 1.0, 0.45),
	&"burn": Color(1.0, 0.65, 0.35),
	&"slow": Color(0.6, 0.8, 1.0),
	&"curse": Color(0.8, 0.55, 1.0),
	&"stun": Color(1.0, 1.0, 0.6),
}
## Class id -> particles behind the hero.
const PARTICLES := {
	&"warrior": {"color": Color(1.0, 0.6, 0.2), "dir": Vector2(0.2, -1), "speed": Vector2(6, 14), "gravity": Vector2(0, -4), "size": 1.0, "amount": 14},
	&"paladin": {"color": Color(1.0, 0.92, 0.6), "dir": Vector2(-0.3, 1), "speed": Vector2(2, 6), "gravity": Vector2.ZERO, "size": 1.0, "amount": 12},
	&"rogue": {"color": Color(0.5, 0.8, 0.75, 0.5), "dir": Vector2(1, -0.2), "speed": Vector2(2, 5), "gravity": Vector2.ZERO, "size": 3.0, "amount": 8},
	&"mage": {"color": Color(0.8, 0.6, 1.0), "dir": Vector2(0, -1), "speed": Vector2(3, 9), "gravity": Vector2(0, -2), "size": 1.0, "amount": 14},
}
## Class id -> glints in sheet pixels: [position, colour, size, mode, in an eye]
## (mode: flicker = lamp, pulse = slow glow, twinkle = rare spark; eye glints
## go out while the eyes are shut).
const GLINTS := {
	&"warrior": [[Vector2(44, 8), Color(1.0, 0.85, 0.45), 14.0, &"flicker", false]],
	&"paladin": [[Vector2(33, 8), Color(1.0, 0.95, 0.7), 8.0, &"twinkle", false], [Vector2(38, 56), Color(1.0, 0.9, 0.5), 6.0, &"twinkle", false]],
	&"rogue": [[Vector2(32, 27), Color(0.6, 1.0, 0.85), 5.0, &"twinkle", true]],
	&"mage": [[Vector2(32, 10), Color(1.0, 0.4, 0.5), 8.0, &"pulse", false], [Vector2(37, 60), Color(0.4, 0.9, 1.0), 12.0, &"pulse", false]],
}

var hero: Hero
var player: Player
var _bg: TextureRect
var _particles: CPUParticles2D
var _body: Control
var _face: TextureRect
var _flash: ColorRect
var _frames := {}  # frame / expression name -> Texture2D
var _sheet := false
var _glints: Array = []  # [TextureRect, mode, phase, in an eye]
var _frame: StringName = &"neutral0"
var _last_hp := -1
var _dead := false
var _time := 0.0
var _blink_t := -1.0  # time since the blink started (< 0 = not blinking)
var _next_blink := 2.0
var _double_blink := false
var _glance_left := 0.0
var _next_glance := 7.0
var _hurt_t := -1.0
var _fierce_t := -1.0
## Reactions with a hold time: joy (level, a rare find), casting, a sip of a
## potion, resolve (a guardian appears). Seconds left; the strongest wins.
var _smile_left := 0.0
var _cast_left := 0.0
var _drink_left := 0.0
var _resolve_left := 0.0
var _shake_left := 0.0
var _flash_color := Color.TRANSPARENT
var _flash_left := 0.0
const FLASH_TIME := 0.45
const BLINK_TIME := 0.16
const HURT_TIME := 0.45
const FIERCE_TIME := 0.38


func setup(p_hero: Hero, p_player: Player) -> void:
	hero = p_hero
	player = p_player
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var race_id: StringName = hero.race.id if hero.race else &""
	var class_id: StringName = hero.class_data.id if hero.class_data else &""
	var hero_path := AssetPaths.hero_portrait_path(race_id, class_id, hero.female)
	_sheet = ResourceLoader.exists(hero_path)
	if _sheet:
		var bg_path := AssetPaths.portrait_bg_path(class_id)
		_bg = _rect(load(bg_path) if ResourceLoader.exists(bg_path) else null, self)
		_add_particles(class_id)
	_body = Control.new()
	_body.set_anchors_preset(Control.PRESET_FULL_RECT)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_body)
	if _sheet:
		var sheet: Texture2D = load(hero_path)
		for f in AssetPaths.HERO_PORTRAIT_FRAMES:
			_frames[f] = AssetPaths.hero_portrait_frame(sheet, f)
		_face = _rect(_frames[&"neutral0"], _body)
		_add_glints(class_id)
	else:
		_face = _rect(hero.race.portrait if hero.race else null, _body)
		_rect(hero.class_data.portrait_overlay if hero.class_data else null, _body)
		_frames[&"neutral0"] = _face.texture
		if _face.texture:
			var base := _face.texture.resource_path.get_basename()
			for e in ["blink", "glance", "hurt", "wounded"]:
				var path := "%s_%s.png" % [base, e]
				if ResourceLoader.exists(path):
					_frames[StringName(e)] = load(path)
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color.TRANSPARENT
	add_child(_flash)
	_last_hp = hero.stats.hp
	hero.stats.hp_changed.connect(_on_hp)
	hero.leveled_up.connect(func(_l: int) -> void:
		_start_flash(Color(1.0, 0.85, 0.3, 0.5))
		_smile_left = 1.8)
	EventBus.item_collected.connect(func(it: ItemData, _p: Vector2) -> void:
		if it and it.rarity >= ItemData.Rarity.RARE:
			_smile_left = maxf(_smile_left, 1.0))
	EventBus.hero_cast.connect(func() -> void: _cast_left = 0.5)
	EventBus.hero_used_item.connect(func(it: ItemData) -> void:
		if it is UsableItemData:
			_drink_left = 0.7)
	EventBus.boss_spawned.connect(func(_b: Node) -> void: _resolve_left = 2.0)
	EventBus.player_died.connect(func() -> void: _dead = true)
	# The hero hits a monster: a short snarl (not restarted while it plays).
	EventBus.damage_dealt.connect(func(_p: Vector2, _a: int, _c: bool, on_player: bool) -> void:
		if not on_player and not _dead and _fierce_t < 0.0:
			_fierce_t = 0.0)
	_next_blink = randf_range(1.5, 4.0)


func _rect(tex: Texture2D, parent: Control) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.set_anchors_preset(Control.PRESET_FULL_RECT)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(t)
	return t


## Pixel particles between the background and the hero.
func _add_particles(class_id: StringName) -> void:
	var cfg: Dictionary = PARTICLES.get(class_id, {})
	if cfg.is_empty():
		return
	_particles = CPUParticles2D.new()
	_particles.amount = cfg["amount"]
	_particles.lifetime = 3.5
	_particles.preprocess = 3.5
	_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_particles.emission_rect_extents = size / 2.0
	_particles.position = size / 2.0
	_particles.direction = cfg["dir"]
	_particles.spread = 25.0
	_particles.initial_velocity_min = cfg["speed"].x
	_particles.initial_velocity_max = cfg["speed"].y
	_particles.gravity = cfg["gravity"]
	_particles.scale_amount_min = cfg["size"]
	_particles.scale_amount_max = cfg["size"] + 1.0
	_particles.color = cfg["color"]
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 0.75, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
	_particles.color_ramp = g
	_particles.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_particles)


## Additive glow spots over lamps, gems and eyes (they move with the head frame).
func _add_glints(class_id: StringName) -> void:
	var k := size.x / AssetPaths.HERO_PORTRAIT_SIZE
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	for g: Array in GLINTS.get(class_id, []):
		var t := TextureRect.new()
		t.texture = AssetPaths.tex(AssetPaths.LIGHT)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.size = Vector2(g[2], g[2]) * k
		t.position = g[0] * k - t.size / 2.0
		t.modulate = g[1]
		t.material = add
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_body.add_child(t)
		_glints.append([t, g[3], randf() * TAU, g[4]])


func _on_hp(hp: int, max_hp: int) -> void:
	if _dead and hp > 0:
		_dead = false  # revived: the portrait lives again
	if _last_hp >= 0 and hp < _last_hp:
		_hurt_t = 0.0
		_shake_left = 0.3
		_start_flash(Color(1.0, 0.15, 0.1, 0.45))
	elif _last_hp >= 0 and hp > _last_hp + max_hp * 0.05:
		_start_flash(Color(0.4, 1.0, 0.5, 0.4))
	_last_hp = hp


func _start_flash(c: Color) -> void:
	_flash_color = c
	_flash_left = FLASH_TIME


func _low_hp() -> bool:
	return hero.stats.hp <= hero.stats.max_hp() * LOW_HP


func _process(delta: float) -> void:
	if hero == null:
		return
	_time += delta
	_update_timers(delta)
	_frame = _frame_name()
	_face.texture = _frames.get(_frame, _frames.get(_fallback(_frame), _frames[&"neutral0"]))
	var offset := Vector2.ZERO
	if not _sheet and not _dead:
		offset.y = roundf(sin(_time * 1.9) * 0.6)  # old layers: no breathing frames
	if _dead:
		offset.y = 1.0
	if _shake_left > 0.0:
		offset += Vector2(roundf(randf_range(-1.5, 1.5)), roundf(randf_range(-1.0, 1.0)))
	_body.position = offset
	var tint := _tint()
	_body.modulate = tint
	if _bg:
		# The class glow breathes slowly; brighter for a moment when snarling.
		var k := 0.92 + 0.08 * sin(_time * 1.3) + (0.15 if _fierce_t >= 0.0 else 0.0)
		_bg.modulate = Color(k, k, k) * (tint if _dead else Color.WHITE)
	if _particles:
		_particles.emitting = not _dead
	_update_glints()
	_flash.color = _flash_now(_low_hp())


func _update_timers(delta: float) -> void:
	_shake_left = maxf(0.0, _shake_left - delta)
	_smile_left = maxf(0.0, _smile_left - delta)
	_cast_left = maxf(0.0, _cast_left - delta)
	_drink_left = maxf(0.0, _drink_left - delta)
	_resolve_left = maxf(0.0, _resolve_left - delta)
	_flash_left = maxf(0.0, _flash_left - delta)
	if _hurt_t >= 0.0:
		_hurt_t += delta
		if _hurt_t > HURT_TIME:
			_hurt_t = -1.0
	if _fierce_t >= 0.0:
		_fierce_t += delta
		if _fierce_t > FIERCE_TIME:
			_fierce_t = -1.0
	if _blink_t >= 0.0:
		_blink_t += delta
		if _blink_t > BLINK_TIME:
			_blink_t = -1.0
			if _double_blink:
				_double_blink = false
				_next_blink = 0.1
	else:
		_next_blink -= delta
		if _next_blink <= 0.0:
			_blink_t = 0.0
			_double_blink = randf() < 0.2
			_next_blink = randf_range(2.5, 5.5)
	if _glance_left > 0.0:
		_glance_left -= delta
	else:
		_next_glance -= delta
		if _next_glance <= 0.0:
			_glance_left = randf_range(0.6, 1.2)
			_next_glance = randf_range(6.0, 11.0)


## Which frame to show now (priority: death, pain, snarl, blink, wounds, glance, breath).
func _frame_name() -> StringName:
	if _dead:
		return &"dead"
	if _hurt_t >= 0.0:
		return &"hurt0" if _hurt_t < 0.1 else &"hurt1"
	if _fierce_t >= 0.0:
		return &"fierce0" if _fierce_t < 0.08 else &"fierce1"
	if _cast_left > 0.0:
		return &"cast0" if _cast_left > 0.38 else &"cast1"
	if _drink_left > 0.0:
		return &"drink"
	if _blink_t >= 0.0:
		return &"blink_half" if _blink_t < 0.04 or _blink_t > BLINK_TIME - 0.04 else &"blink"
	if _smile_left > 0.0:
		return &"smile1" if fmod(_time, 0.6) < 0.3 else &"smile0"
	if _resolve_left > 0.0:
		return &"resolve"
	var low := _low_hp()
	if low:
		return &"wounded1" if fmod(_time, 0.9) < 0.45 else &"wounded0"
	if _glance_left > 0.0:
		return &"glance"
	# Calm breathing in four steps: rest, breathe in, full, breathe out, sway.
	var t := fmod(_time, 3.2)
	if t < 0.8:
		return &"neutral0"
	if t < 1.3:
		return &"neutral2"
	if t < 2.1:
		return &"neutral1"
	if t < 2.6:
		return &"neutral2"
	return &"neutral3"


## Old layered portraits have fewer expressions.
func _fallback(f: StringName) -> StringName:
	match f:
		&"neutral2":
			return &"neutral1"
		&"neutral3", &"smile0", &"smile1", &"resolve":
			return &"neutral0"
		&"cast0", &"cast1":
			return &"fierce0"
		&"drink":
			return &"blink_half"
		&"dead":
			return &"blink"
		&"blink_half":
			return &"blink"
		&"hurt0", &"hurt1":
			return &"hurt"
		&"wounded0", &"wounded1":
			return &"wounded"
		&"fierce0", &"fierce1":
			return &"hurt"
	return &"neutral0"


func _update_glints() -> void:
	for g: Array in _glints:
		var t: TextureRect = g[0]
		var ph: float = g[2]
		var a := 0.0
		match g[1]:
			&"flicker":
				a = 0.55 + 0.2 * sin(_time * 9.0 + ph) + 0.15 * sin(_time * 23.0 + ph * 2.0)
			&"pulse":
				a = 0.45 + 0.35 * sin(_time * 2.2 + ph)
			&"twinkle":
				var c := fmod(_time + ph, 3.5)
				a = clampf(1.0 - absf(c - 0.25) / 0.25, 0.0, 1.0)
		if _dead or (g[3] and _frame in [&"blink", &"blink_half", &"hurt0", &"hurt1", &"drink", &"dead"]):
			a = 0.0
		t.modulate.a = clampf(a, 0.0, 1.0)


## Status colour, pulsing; grey when dead.
func _tint() -> Color:
	if _dead:
		return Color(0.55, 0.52, 0.55)
	if player == null or not is_instance_valid(player):
		return Color.WHITE
	for id: StringName in STATUS_TINTS:
		if player.status.has(id):
			var k := 0.35 + 0.25 * sin(_time * 6.0)
			return Color.WHITE.lerp(STATUS_TINTS[id], k)
	return Color.WHITE


func _flash_now(low: bool) -> Color:
	if _flash_left > 0.0:
		var c := _flash_color
		c.a *= _flash_left / FLASH_TIME
		return c
	if low and not _dead:
		return Color(0.9, 0.05, 0.05, 0.1 + 0.1 * sin(_time * 4.0))
	return Color.TRANSPARENT
