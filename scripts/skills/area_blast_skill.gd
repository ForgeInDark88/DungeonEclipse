class_name AreaBlastSkill
extends SkillEffect
## Damages every enemy around the caster in plain view (walls shield;
## optionally breaks bricks afterwards, stuns). Every skill family picks its
## own blast silhouette - and the meteor falls from the sky first.

@export var radius: float = 48.0
@export var radius_per_level: float = 6.0
@export var damage_multiplier: float = 1.6
@export var damage_per_level: float = 0.35
@export var knockback: float = 160.0
@export var breaks_tiles: bool = false
## Freezes enemies for this long (seconds), 0 = no freeze.
@export var stun_time: float = 0.0
## WeaponItemData.DamageType (resistances apply).
@export var damage_type: int = 0
@export var color: Color = Color(1.0, 0.5, 0.2)
## Look of the blast: explosion (default), slash, blades, ring, ice, light,
## sun, quake, meteor - each skill family gets its own silhouette.
@export var vfx: StringName = &"explosion"


func execute(caster: Node, level: int) -> bool:
	var center: Vector2 = caster.global_position + Vector2(0, -10)
	var r := radius + radius_per_level * (level - 1)
	var mult := damage_multiplier + damage_per_level * (level - 1)
	var parent := caster.get_parent()
	if vfx == &"meteor":
		# The rock falls first (whistle), then everything hits at once.
		Fx.meteor_fall(parent, center, r, color)
		_apply_blast(caster, center, r, mult, 0.5)
		return true
	_apply_blast(caster, center, r, mult, 0.0)
	match vfx:
		&"slash":
			Fx.arc_slash(parent, center, r, color, caster.facing)
		&"blades":
			Fx.blade_fan(parent, center, r, color)
		&"ring":
			Fx.nova_ring(parent, center, r, color)
		&"ice":
			Fx.ice_burst(parent, center, r, color)
		&"light":
			Fx.light_pillars(parent, center, r, color)
		&"sun":
			Fx.sun_flash(parent, center, r, color)
		&"quake":
			Fx.rock_burst(parent, center, r, color)
		_:
			Fx.explosion(parent, center, r, color)
	EventBus.screen_shake.emit(4.0)
	_net_blast_fx(caster, center, r)
	return true


## Co-op: echo the blast silhouette to the other machines (the damage was
## claimed per-enemy through the puppets' take_damage path).
func _net_blast_fx(caster: Node, center: Vector2, r: float) -> void:
	if not Net.active:
		return
	# Untyped on purpose: a hard NetSync reference here would create a
	# cyclic class dependency (net_sync knows AreaBlastSkill for cast replays).
	var ns = caster.get_tree().get_first_node_in_group("net_game")
	if ns == null:
		return
	ns.blast_fx.rpc(center, r, vfx, color)



## Damage + tile breaking; `delay` lets the meteor land first (the enemies
## inside the zone when it hits are the ones caught in it).
func _apply_blast(caster: Node, center: Vector2, r: float, mult: float, delay: float) -> void:
	if delay <= 0.0:
		_blast_now(caster, center, r, mult)
		return
	var tree := caster.get_tree()
	tree.create_timer(delay, false).timeout.connect(func() -> void:
		if not caster.is_inside_tree():
			return
		_blast_now(caster, center, r, mult)
		Fx.meteor_impact(caster.get_parent(), center, r, color)
		EventBus.screen_shake.emit(8.0))


func _blast_now(caster: Node, center: Vector2, r: float, mult: float) -> void:
	for enemy in caster.get_tree().get_nodes_in_group("enemies"):
		# Walls shield (checked before bricks break).
		if enemy.global_position.distance_to(center) <= r and LineOfSight.can_hit(caster, center, enemy):
			var d: Dictionary = caster.roll_damage(mult)
			enemy.take_damage(d["amount"], d["crit"], center, damage_type)
			if enemy.hp > 0:
				var dir: Vector2 = (enemy.global_position - center).normalized()
				enemy.velocity = dir * knockback + Vector2(0, -60)
				if stun_time > 0.0:
					enemy.stun(stun_time)
	if breaks_tiles and caster.level:
		caster.level.explode(center, r * 0.6)


func describe(level: int) -> String:
	var text := "Удар по области (радиус %d), урон %d%%" % [roundi(radius + radius_per_level * (level - 1)), roundi((damage_multiplier + damage_per_level * (level - 1)) * 100)]
	if stun_time > 0.0:
		text += ", оглушает на %.1f сек." % stun_time
	if breaks_tiles:
		text += ", ломает кирпич"
	return text
