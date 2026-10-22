class_name StatusHitEffect
extends HitEffect
## Applies a status (poison, burn, bleed, stun, slow...) to the target.

@export var status: StringName = &"poison"
@export var duration: float = 3.0
## Damage per tick for damage-over-time, slow fraction for "slow".
@export var power: float = 2.0


func on_hit(_attacker: Node, target: Node, _damage: int) -> void:
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
