class_name ThrowBombEffect
extends ItemEffect
## Throws a bomb that explodes after a fuse, damaging enemies and breaking
## brick tiles in the radius.

@export var damage: int = 40
@export var radius_tiles: float = 2.2
@export var fuse_time: float = 1.4
@export var throw_velocity: Vector2 = Vector2(160, -170)
## WeaponItemData.DamageType of the blast (resistances apply).
@export var damage_type: int = 0
## Status put on monsters in the blast (burn, slow, poison...), &"" = none.
@export var status: StringName = &""
@export var status_duration: float = 3.0
@export var status_power: float = 3.0
## Sticks where it first touches instead of bouncing.
@export var sticky: bool = false
@export var breaks_tiles: bool = true
@export var color: Color = Color(1.0, 0.6, 0.2)

const BOMB_SCENE := preload("res://scenes/world/bomb.tscn")


func apply(user: Node) -> bool:
	if user.level == null:
		return false
	var pos: Vector2 = user.global_position + Vector2(6 * user.facing, -10)
	var radius: float = radius_tiles * 16.0
	if Net.active:
		# Untyped: a hard NetSync reference here would be a cyclic class
		# dependency (net_sync references skill/effect classes for replays).
		var ns = user.get_tree().get_first_node_in_group("net_game")
		if ns == null:
			return false
		if Net.is_host:
			# The host throws the real bomb and everyone gets a visual copy.
			ns.spawn_net_bomb(pos, user.facing, damage, radius, fuse_time, damage_type,
					status, status_duration, status_power, breaks_tiles, color)
		else:
			# The guest asks; the host validates, spawns and mirrors back.
			ns.request_bomb.rpc_id(1, pos, user.facing, damage, radius, fuse_time,
					damage_type, status, status_duration, status_power, breaks_tiles, color)
		return true
	var bomb: Node2D = BOMB_SCENE.instantiate()
	bomb.damage = damage
	bomb.radius = radius
	bomb.fuse_time = fuse_time
	bomb.velocity = Vector2(throw_velocity.x * user.facing, throw_velocity.y)
	bomb.damage_type = damage_type
	bomb.status = status
	bomb.status_duration = status_duration
	bomb.status_power = status_power
	bomb.sticky = sticky
	bomb.breaks_tiles = breaks_tiles
	bomb.color = color
	user.level.add_entity(bomb, pos)
	return true


func describe() -> String:
	var text := tr("Бросок: %d урона по области") % damage
	if damage_type > 0:
		text += " (%s)" % TranslationServer.translate(WeaponItemData.DAMAGE_TYPE_NAMES[damage_type]).to_lower()
	if status != &"":
		text += tr(", %s на %.0f с") % [StatusEffects.display_name(status).to_lower(), status_duration]
	if sticky:
		text += tr(", липнет к поверхности")
	if breaks_tiles:
		text += tr(", ломает кирпич")
	return text
