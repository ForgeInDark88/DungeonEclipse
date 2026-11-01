class_name LayerPortal
extends Area2D
## A way between the layers of a location (LocationInstance portals): a
## cave mouth or a side passage down from the surface, stairs between the
## floors, the road sign back to the map, the guardian's way out. E uses it
## (LocationManager moves the hero to the other end); a locked one says why.
## In co-op Shift+E calls the whole party through it (the host agrees).

const SPRITES := {
	&"map": "res://assets/sprites/portals/map_exit.png",
	&"entrance": "res://assets/sprites/portals/cave.png",
	&"side": "res://assets/sprites/portals/cave_mossy.png",
	&"up": "res://assets/sprites/portals/stairs_up.png",
	&"down": "res://assets/sprites/portals/stairs_down.png",
	&"arena_exit": "res://assets/sprites/portals/arena_exit.png",
}

var portal_id: StringName
var kind: StringName
## The look of a way down from the surface (LevelLayout.portal_kinds):
## cave, well, crypt, ruin_stairs, sinkhole ("" — by kind).
var look: StringName = &""
var manager: LocationManager
var _sprite: Sprite2D
var _light: PointLight2D


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("layer_portals")
	collision_layer = 16
	collision_mask = 0
	monitoring = false
	z_index = -1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(24, 30)
	shape.shape = rect
	shape.position = Vector2(0, -15)
	add_child(shape)
	_sprite = Sprite2D.new()
	var path: String = SPRITES.get(kind, SPRITES[&"down"])
	if look != &"" and look != &"cave":
		path = "res://assets/sprites/portals/%s.png" % String(look)
	_sprite.texture = AssetPaths.tex(path)
	_sprite.centered = true
	_sprite.offset = Vector2(0, -_sprite.texture.get_height() / 2.0) if _sprite.texture else Vector2.ZERO
	add_child(_sprite)
	if kind in [&"arena_exit", &"up", &"down"]:
		_light = PointLight2D.new()
		_light.texture = AssetPaths.tex(AssetPaths.LIGHT)
		_light.color = Color(0.8, 0.7, 1.0) if kind == &"arena_exit" else Color(1.0, 0.85, 0.6)
		_light.energy = 0.6
		_light.position = Vector2(0, -14)
		if _light.texture:
			add_child(_light)
	refresh()


## Shown open or closed (a beaten guardian opens the arena's way out).
func refresh() -> void:
	var open := manager == null or manager.portal_open(portal_id)
	if _sprite:
		_sprite.modulate = Color.WHITE if open else Color(0.45, 0.42, 0.5)
		visible = open or kind != &"arena_exit"


func can_interact() -> bool:
	return visible


func get_prompt() -> String:
	if manager == null:
		return ""
	return manager.portal_prompt(portal_id)


func interact(player: Node) -> void:
	if manager:
		manager.use_portal(portal_id, player, Input.is_key_pressed(KEY_SHIFT))
