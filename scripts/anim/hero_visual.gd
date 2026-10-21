class_name HeroVisual
extends Node2D
## Layered animated hero: body (race) + outfit (class) + armor (equipped
## chest item) + head (helmet or class headgear), all on the same sheet layout
## (data/animations/hero_layout.tres) and kept frame-synchronised.
## Also owns the item held in the hand (follows per-frame hand points/angles),
## facing flip, squash & stretch and the white hit flash.

signal animation_finished(anim: StringName)

const LAYER_ORDER: Array[StringName] = [&"body", &"outfit", &"armor", &"head"]
## Item icons are drawn with the blade pointing up-right; grip pixel in the icon.
const ICON_ANGLE := -45.0
const ICON_GRIP := Vector2(3, 12)
## Held items are drawn a bit smaller than inventory icons.
const HELD_SCALE := 0.8

var layout: SpriteSheetLayout
var facing: float = 1.0
var base_scale := Vector2.ONE
var squash := Vector2.ONE
## Tint (buffs) and transparency (invulnerability blink).
var tint := Color.WHITE
var alpha := 1.0
var current: StringName = &""
var hand_visible := true

var _layers: Dictionary = {}  # StringName -> AnimatedSprite2D
var _hand: Sprite2D
var _held_override: Texture2D
var _held_default: Texture2D
var _held_angle := ICON_ANGLE
var _held_grip := ICON_GRIP
var _squash_tween: Tween
var _flash_tween: Tween
var _speed := 1.0


func _ready() -> void:
	material = AssetPaths.flash_material()
	layout = AssetPaths.layout(AssetPaths.HERO_LAYOUT)
	for layer_name in LAYER_ORDER:
		var s := AnimatedSprite2D.new()
		s.name = String(layer_name).capitalize()
		s.use_parent_material = true
		s.centered = false
		s.offset = -layout.origin
		add_child(s)
		_layers[layer_name] = s
	_hand = Sprite2D.new()
	_hand.name = "HeldItem"
	_hand.centered = false
	_hand.offset = -ICON_GRIP
	_hand.use_parent_material = true
	_hand.scale = Vector2(HELD_SCALE, HELD_SCALE)
	add_child(_hand)
	var body: AnimatedSprite2D = _layers[&"body"]
	body.frame_changed.connect(_sync)
	body.animation_finished.connect(func() -> void: animation_finished.emit(body.animation))


## Sets (or hides with null) one layer's sheet.
func set_layer(layer_name: StringName, sheet: Texture2D) -> void:
	var s: AnimatedSprite2D = _layers[layer_name]
	s.visible = sheet != null
	if sheet == null:
		return
	s.sprite_frames = layout.build_frames(sheet)
	if current != &"" and s.sprite_frames.has_animation(current):
		s.play(current, _speed)
		_sync()


## Rebuilds all layers from the hero's race, class and equipment.
func refresh_from(hero: Hero) -> void:
	base_scale = hero.race.sprite_scale
	set_layer(&"body", hero.race.body_sheet)
	set_layer(&"outfit", hero.class_data.outfit_sheet)
	var armor: Texture2D = null
	var head: Texture2D = hero.class_data.head_sheet
	for item: EquipmentItemData in hero.equipment.items.values():
		if item and item.visual_sheet:
			if item.visual_layer == &"head":
				head = item.visual_sheet
			else:
				armor = item.visual_sheet
	set_layer(&"armor", armor)
	set_layer(&"head", head)
	var weapon := hero.weapon()
	_held_default = null
	_held_angle = ICON_ANGLE
	_held_grip = ICON_GRIP
	if weapon:
		_held_default = weapon.held_texture if weapon.held_texture else weapon.icon
		_held_angle = weapon.held_angle
		_held_grip = weapon.grip_pixel
	_update_held()


func play(anim: StringName, speed := 1.0, restart := false) -> void:
	if anim == current and not restart and is_equal_approx(speed, _speed):
		return
	current = anim
	_speed = speed
	for s: AnimatedSprite2D in _layers.values():
		if s.sprite_frames and s.sprite_frames.has_animation(anim):
			s.play(anim, speed)
			if restart:
				s.frame = 0
				s.frame_progress = 0.0
	_sync()


func set_paused(paused: bool) -> void:
	for s: AnimatedSprite2D in _layers.values():
		s.speed_scale = 0.0 if paused else 1.0


func frame() -> int:
	return (_layers[&"body"] as AnimatedSprite2D).frame


## Shows another item in the hand for a while (potion while drinking).
func hold_temporarily(texture: Texture2D, duration: float) -> void:
	_held_override = texture
	_update_held()
	get_tree().create_timer(duration).timeout.connect(func() -> void:
		_held_override = null
		_update_held())


func squash_to(target: Vector2, duration := 0.18) -> void:
	if _squash_tween:
		_squash_tween.kill()
	squash = target
	_squash_tween = create_tween()
	_squash_tween.tween_property(self, "squash", Vector2.ONE, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func flash(color := Color.WHITE, duration := 0.15) -> void:
	var m := material as ShaderMaterial
	m.set_shader_parameter("flash_color", color)
	if _flash_tween:
		_flash_tween.kill()
	m.set_shader_parameter("flash", 1.0)
	_flash_tween = create_tween()
	_flash_tween.tween_method(func(v: float) -> void: m.set_shader_parameter("flash", v), 1.0, 0.0, duration)


func _process(_delta: float) -> void:
	scale = Vector2(facing * squash.x * base_scale.x, squash.y * base_scale.y)
	modulate = Color(tint.r, tint.g, tint.b, alpha)
	# Smooth weapon motion between the key frames of one-shot animations.
	var body: AnimatedSprite2D = _layers[&"body"]
	if _hand and _hand.visible and current.begins_with("attack") and body.is_playing():
		var f := body.frame
		var n := body.sprite_frames.get_frame_count(current) if body.sprite_frames else 1
		if f < n - 1:
			var t := body.frame_progress
			_hand.position = layout.hand_point(current, f).lerp(layout.hand_point(current, f + 1), t)
			_hand.rotation_degrees = lerpf(layout.hand_angle(current, f), layout.hand_angle(current, f + 1), t) - _current_icon_angle()


func _sync() -> void:
	var body: AnimatedSprite2D = _layers[&"body"]
	for s: AnimatedSprite2D in _layers.values():
		if s != body and s.visible and s.animation == body.animation and s.frame != body.frame:
			s.frame = body.frame
	_update_held()


func _update_held() -> void:
	if _hand == null:
		return
	var tex := _held_override if _held_override else _held_default
	_hand.texture = tex
	_hand.offset = -(ICON_GRIP if _held_override else _held_grip)
	_hand.visible = tex != null and (hand_visible or _held_override != null)
	if layout and current != &"":
		var f := frame()
		_hand.position = layout.hand_point(current, f)
		_hand.rotation_degrees = layout.hand_angle(current, f) - _current_icon_angle()


func _current_icon_angle() -> float:
	return ICON_ANGLE if _held_override else _held_angle
