class_name ProjectileSkill
extends SkillEffect
## Fires one or more projectiles forward.

const PROJECTILE_SCENE := preload("res://scenes/world/projectile.tscn")

@export var texture: Texture2D
@export var speed: float = 240.0
@export var damage_multiplier: float = 1.5
@export var damage_per_level: float = 0.3
@export var count: int = 1
## Extra projectiles every N levels (0 = never).
@export var extra_every_levels: int = 0
@export var spread_degrees: float = 10.0
@export var pierce: int = 0
@export var blast_radius: float = 0.0
## WeaponItemData.DamageType (resistances apply).
@export var damage_type: int = 0
@export var color: Color = Color(1.0, 0.6, 0.2)


func execute(caster: Node, level: int) -> bool:
	var level_node: DungeonLevel = caster.level
	if level_node == null:
		return false
	var n := count + (int((level - 1) / extra_every_levels) if extra_every_levels > 0 else 0)
	var mult := damage_multiplier + damage_per_level * (level - 1)
	var origin: Vector2 = caster.global_position + Vector2(0, -11.0)
	if caster.has_method("face_aim"):
		caster.face_aim()
	var aim: Vector2 = caster.aim_vector(origin) if caster.has_method("aim_vector") else Vector2(caster.facing, 0)
	for i in n:
		var angle := 0.0
		if n > 1:
			angle = deg_to_rad(lerpf(-spread_degrees, spread_degrees, float(i) / (n - 1)))
		var dir := aim.rotated(angle)
		var p: Projectile = PROJECTILE_SCENE.instantiate()
		var d: Dictionary = caster.roll_damage(mult)
		p.setup(texture, dir, speed, d["amount"], "enemies")
		p.crit = d["crit"]
		p.damage_type = damage_type
		p.pierce = pierce
		p.blast_radius = blast_radius
		p.blast_color = color
		level_node.add_entity(p, LineOfSight.safe_point(caster, origin, origin + dir * 8.0))
		# Co-op: the others see a visual copy; hits are claimed by the owner's
		# projectile through request_player_hit.
		if Net.active and texture:
			# Untyped: a hard NetSync reference would be a cyclic class
			# dependency (net_sync references skill classes for cast replays).
			var ns = caster.get_tree().get_first_node_in_group("net_game")
			if ns and texture.resource_path != "":
				ns.projectile_fx.rpc(texture.resource_path, origin, dir, speed, 1.2, color)
	return true


func describe(level: int) -> String:
	var n := count + (int((level - 1) / extra_every_levels) if extra_every_levels > 0 else 0)
	var text := "%d снаряд(а), урон %d%%" % [n, roundi((damage_multiplier + damage_per_level * (level - 1)) * 100)]
	if blast_radius > 0.0:
		text += ", взрыв"
	if pierce > 0:
		text += ", пробивает %d" % pierce
	return text
