class_name LegendHitEffect
extends HitEffect
## The soul of a legendary weapon - each one carries a piece of the story:
##   TOLL   - Brother Ostwin's bell hammer: every `every`-th hit tolls - a ring
##            that hurts and stuns everything around the target;
##   MIRROR - Pip's mirror dagger: an echo of the blow strikes again a moment later;
##   EMBER  - Ilara's spark: the hit bursts into a ring of fire (burns around);
##   HEART  - a shard of the mountain's heart: every `every`-th hit crystals
##            erupt around the target and the bearer is healed;
##   GRAVE  - Oldric's spade: a struck enemy near death gets a grave dug under
##            it - a skeleton rises to fight for the bearer (`cap` at a time).
## Runs on the attacker's own machine (weapon procs are owner-local in co-op);
## damage to shells goes through the host as usual.

enum Kind { TOLL, MIRROR, EMBER, HEART, GRAVE }

@export var kind: Kind = Kind.TOLL
## Hits needed for TOLL / HEART.
@export var every: int = 3
## Share of the dealt damage for the extra strikes.
@export var power: float = 0.6
@export var radius: float = 44.0
## GRAVE: servants at a time; MIRROR / EMBER use `chance`.
@export var cap: int = 2


func on_hit(attacker: Node, target: Node, damage: int) -> void:
	var p := attacker as Player
	var e := target as Enemy
	if p == null or e == null or p.puppet:
		return
	match kind:
		Kind.TOLL:
			if _count(p) % every == 0:
				_ring(p, e, roundi(damage * power), Color(0.55, 1.0, 0.85), 0, &"boss_toll", true)
		Kind.MIRROR:
			var weak: WeakRef = weakref(e)
			p.get_tree().create_timer(0.15, false).timeout.connect(func() -> void:
				var t: Enemy = weak.get_ref()
				if t and not t.is_dead() and is_instance_valid(p):
					var side := signf(t.global_position.x - p.global_position.x)
					Fx.sparks(t.get_parent(), t.global_position + Vector2(side * 10.0, -12), Color(0.85, 0.6, 1.0), 10, 70.0)
					SlashTrail.spawn(t.get_parent(), t.global_position + Vector2(side * 18.0, -12), Vector2(-side, 0), 22.0, false, Color(0.85, 0.6, 1.0))
					t.take_damage(roundi(damage * power), false, t.global_position + Vector2(side * 20.0, 0), 4))
		Kind.EMBER:
			_ring(p, e, roundi(damage * power), Color(1.0, 0.5, 0.15), 1, &"cast_fire", false, &"burn")
		Kind.HEART:
			if _count(p) % every == 0:
				_ring(p, e, roundi(damage * power), Color(0.6, 0.95, 1.0), 2, &"cast_frost", false)
				var heal := maxi(1, roundi(p.hero.stats.max_hp() * 0.06))
				p.hero.stats.heal(heal)
				EventBus.floating_text.emit(p.global_position + Vector2(0, -26), "+%d" % heal, Color(0.6, 1.0, 0.9))
		Kind.GRAVE:
			if e.hp > 0 and float(e.hp) / maxf(1.0, e.max_hp) <= 0.3 and not e.has_meta("grave_dug"):
				e.set_meta("grave_dug", true)
				var mine := 0
				for m in p.get_tree().get_nodes_in_group("minions"):
					if m is Minion and m.owner_player == p and m.has_meta("spade"):
						mine += 1
				if mine < cap:
					var m := Minion.spawn(p, Minion.Kind.WARRIOR, 0.5, 12.0, mine, e.global_position + Vector2(0, -2))
					m.set_meta("spade", true)
					Fx.dust(e.get_parent(), e.global_position, true)


## Hits counted per bearer (TOLL / HEART fire on every N-th).
func _count(p: Player) -> int:
	var key := "legend_hits_%d" % kind
	var n: int = int(p.get_meta(key, 0)) + 1
	p.set_meta(key, n)
	return n


## A burst around the target: hurts everything else in `radius`, optionally
## stuns all of them (the target too) or sets a status for show.
func _ring(p: Player, center: Enemy, dmg: int, color: Color, dtype: int, sound: StringName,
		stun: bool, status_id: StringName = &"") -> void:
	var parent := center.get_parent()
	var pos := center.global_position + Vector2(0, -8)
	Fx.explosion(parent, pos, radius, color)
	AudioManager.play_sfx(sound, pos, -4.0)
	var ns: NetSync = p.get_tree().get_first_node_in_group("net_game") as NetSync if Net.active else null
	for n in p.get_tree().get_nodes_in_group("enemies"):
		var o := n as Enemy
		if o == null or o.is_dead() or o.global_position.distance_to(center.global_position) > radius:
			continue
		if o != center:
			o.take_damage(maxi(1, dmg), false, pos, dtype)
		if stun:
			if o.puppet and ns:
				ns.request_enemy_status.rpc_id(1, o.net_id, &"stun", 0.8)
			else:
				o.status.apply(&"stun", 0.8)
		elif status_id != &"" and not o.puppet:
			o.status.apply(status_id, 3.0, maxf(1.0, dmg * 0.15))


func describe() -> String:
	match kind:
		Kind.TOLL:
			return tr("Каждый %d-й удар звенит: урон %d%% и оглушение вокруг цели") % [every, roundi(power * 100)]
		Kind.MIRROR:
			return tr("Отражение повторяет удар (%d%% урона)%s") % [roundi(power * 100), _chance_text()]
		Kind.EMBER:
			return tr("Искра: огненное кольцо вокруг цели (%d%% урона, поджог)%s") % [roundi(power * 100), _chance_text()]
		Kind.HEART:
			return tr("Каждый %d-й удар: кристаллы вокруг цели (%d%%) и лечение 6%%") % [every, roundi(power * 100)]
		Kind.GRAVE:
			return tr("Враг при смерти (≤30%% HP) — из могилы под ним встаёт скелет (до %d)") % cap
	return ""
