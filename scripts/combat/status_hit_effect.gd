class_name StatusHitEffect
extends HitEffect
## Applies a status (poison, burn, bleed, stun, slow...) to the target.

@export var status: StringName = &"poison"
@export var duration: float = 3.0
## Damage per tick for damage-over-time, slow fraction for "slow".
@export var power: float = 2.0


func on_hit(_attacker: Node, target: Node, _damage: int) -> void:
	# A guest's hero is a puppet on this machine: forward the status to the
	# owner so the real hero gets stunned/poisoned where it is simulated.
	if target is Player and target.puppet:
		var ns: NetSync = target.get_tree().get_first_node_in_group("net_game")
		if ns:
			ns.player_status.rpc_id(target.peer_id, status, duration, power)
		return
	var st: StatusEffects = target.get_node_or_null("StatusEffects")
	if st:
		st.apply(status, duration, power)


func describe() -> String:
	var name := StatusEffects.display_name(status)
	match status:
		&"stun":
			return "%s на %.1f с%s" % [name, duration, _chance_text()]
		&"slow":
			return "%s на %d%% на %.1f с%s" % [name, roundi(power * 100.0), duration, _chance_text()]
	return "%s: %d урона/0.5 с, %.1f с%s" % [name, roundi(power), duration, _chance_text()]
