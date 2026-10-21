class_name HitEffect
extends Resource
## Something that happens to a target when a weapon hits it (poison, burn,
## stun, life steal...). New effect = new script extending HitEffect.

@export_range(0.0, 1.0) var chance: float = 1.0


## `attacker` is the Player, `target` the enemy, `damage` what was dealt.
func on_hit(_attacker: Node, _target: Node, _damage: int) -> void:
	pass


func try_apply(attacker: Node, target: Node, damage: int) -> void:
	if randf() <= chance:
		on_hit(attacker, target, damage)


func describe() -> String:
	return ""


func _chance_text() -> String:
	return "" if chance >= 1.0 else " (%d%%)" % roundi(chance * 100.0)
