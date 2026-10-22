class_name StatusVisual
extends Node2D
## Shows a creature's statuses: icon row over the head, color tint on
## `tint_target`, stun stars, shield bubble and burning embers.

var status: StatusEffects
var tint_target: CanvasItem
var head_height := 24.0

var _icons: HBoxContainer
var _bubble: Sprite2D
var _embers: CPUParticles2D
var _stars: Sprite2D
var _t := 0.0


func setup(p_status: StatusEffects, p_tint_target: CanvasItem, p_head_height: float) -> void:
	status = p_status
	tint_target = p_tint_target
	head_height = p_head_height
	status.changed.connect(_refresh)


func _ready() -> void:
	z_index = 25
	var unshaded := CanvasItemMaterial.new()
	unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_icons = HBoxContainer.new()
	_icons.add_theme_constant_override("separation", 1)
	_icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icons.material = unshaded
	add_child(_icons)
	_bubble = Sprite2D.new()
	_bubble.texture = AssetPaths.tex(AssetPaths.SHIELD_BUBBLE)
	_bubble.material = unshaded
	_bubble.visible = false
	add_child(_bubble)
	_stars = Sprite2D.new()
	_stars.texture = StatusEffects.icon_of(&"stun")
	_stars.material = unshaded
	_stars.visible = false
	add_child(_stars)
	_embers = CPUParticles2D.new()
	_embers.emitting = false
	_embers.amount = 10
	_embers.lifetime = 0.6
	_embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_embers.emission_rect_extents = Vector2(5, 8)
	_embers.direction = Vector2.UP
	_embers.spread = 20.0
	_embers.gravity = Vector2(0, -40)
	_embers.initial_velocity_min = 10.0
	_embers.initial_velocity_max = 25.0
	_embers.color = Color(1.0, 0.55, 0.15)
	_embers.material = unshaded
	add_child(_embers)
	_refresh()


func _refresh() -> void:
	if _icons == null or status == null:
		return
	for c in _icons.get_children():
		c.queue_free()
	for id: StringName in status.active:
		var t := TextureRect.new()
		t.texture = StatusEffects.icon_of(id)
		t.custom_minimum_size = Vector2(8, 8)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		t.use_parent_material = true
		_icons.add_child(t)
	var n := status.active.size()
	_icons.position = Vector2(-n * 4.5, -head_height - 18)
	_bubble.visible = status.has(&"shield")
	_bubble.position = Vector2(0, -head_height / 2.0)
	_stars.visible = status.is_stunned()
	_embers.emitting = status.has(&"burn")
	_embers.position = Vector2(0, -head_height / 2.0)


func _process(delta: float) -> void:
	if status == null:
		return
	_t += delta
	if _stars.visible:
		_stars.position = Vector2(sin(_t * 8.0) * 5.0, -head_height - 4 + cos(_t * 8.0) * 1.5)
	if _bubble.visible:
		_bubble.modulate.a = 0.7 + sin(_t * 5.0) * 0.2
	if tint_target:
		var tint := Color.WHITE
		if status.has(&"poison"):
			tint = tint * Color(0.7, 1.1, 0.7)
		if status.has(&"slow"):
			tint = tint * Color(0.7, 0.85, 1.25)
		if status.has(&"curse"):
			tint = tint * Color(0.9, 0.7, 1.1)
		if status.has(&"burn"):
			tint = tint * Color(1.2, 0.85 + sin(_t * 20.0) * 0.1, 0.7)
		tint_target.self_modulate = tint
