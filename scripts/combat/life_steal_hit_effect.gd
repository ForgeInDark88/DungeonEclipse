class_name LifeStealHitEffect
extends HitEffect
## Heals the attacker for a share of the damage dealt.

@export_range(0.0, 1.0) var percent: float = 0.1


func on_hit(attacker: Node, _target: Node, damage: int) -> void:
	if not ("hero" in attacker):
		return
	var amount := maxi(1, roundi(damage * percent))
	if attacker is Player and attacker.puppet:
		# The damage was judged on the host: forward the heal to the owner.
		var ns: NetSync = attacker.get_tree().get_first_node_in_group("net_game")
		if ns:
			ns.player_heal.rpc_id(attacker.peer_id, amount)
		return
	attacker.hero.stats.heal(amount)
	EventBus.floating_text.emit(attacker.global_position + Vector2(0, -26), "+%d" % amount, Color(0.9, 0.2, 0.3))


func describe() -> String:
	return tr("Кража жизни %d%%%s") % [roundi(percent * 100.0), _chance_text()]
