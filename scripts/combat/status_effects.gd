class_name StatusEffects
extends Node
## Status effects on a creature (child node named "StatusEffects").
## The host must implement:
##   take_status_damage(amount: int, status: StringName, color: Color)
## and may read speed_multiplier() / is_stunned().
## Damage-over-time statuses tick every TICK seconds for `power` damage.

signal changed

const TICK := 0.5
## id -> [name, color, is_damage_over_time]
const INFO := {
	&"poison": ["Яд", Color(0.45, 0.9, 0.3), true],
	&"burn": ["Горение", Color(1.0, 0.5, 0.15), true],
	&"bleed": ["Кровотечение", Color(0.85, 0.1, 0.15), true],
	&"stun": ["Оглушение", Color(1.0, 0.95, 0.4), false],
	&"slow": ["Замедление", Color(0.5, 0.8, 1.0), false],
	&"regen": ["Регенерация", Color(0.4, 1.0, 0.5), false],
	&"shield": ["Щит", Color(0.6, 0.8, 1.0), false],
}

## id -> {"time": float, "power": float, "tick": float}
var active: Dictionary = {}


static func display_name(id: StringName) -> String:
	return INFO[id][0] if INFO.has(id) else String(id)


static func color_of(id: StringName) -> Color:
	return INFO[id][1] if INFO.has(id) else Color.WHITE


func apply(id: StringName, duration: float, power: float = 1.0) -> void:
	var cur: Dictionary = active.get(id, {})
	if cur.is_empty():
		active[id] = {"time": duration, "power": power, "tick": TICK}
	else:
		cur["time"] = maxf(cur["time"], duration)
		cur["power"] = maxf(cur["power"], power)
	changed.emit()


func has(id: StringName) -> bool:
	return active.has(id)


func remove(id: StringName) -> void:
	if active.erase(id):
		changed.emit()


func clear() -> void:
	active.clear()
	changed.emit()


func is_stunned() -> bool:
	return active.has(&"stun")


func speed_multiplier() -> float:
	if is_stunned():
		return 0.0
	if active.has(&"slow"):
		return clampf(1.0 - float(active[&"slow"]["power"]), 0.2, 1.0)
	return 1.0


func _physics_process(delta: float) -> void:
	if active.is_empty():
		return
	var host := get_parent()
	var ended: Array[StringName] = []
	for id: StringName in active:
		var st: Dictionary = active[id]
		st["time"] -= delta
		if INFO.has(id) and INFO[id][2]:
			st["tick"] -= delta
			if st["tick"] <= 0.0:
				st["tick"] += TICK
				if host.has_method("take_status_damage"):
					host.take_status_damage(roundi(st["power"]), id, color_of(id))
		elif id == &"regen" and host.has_method("heal_status"):
			st["tick"] -= delta
			if st["tick"] <= 0.0:
				st["tick"] += TICK
				host.heal_status(roundi(st["power"]))
		if st["time"] <= 0.0:
			ended.append(id)
	for id in ended:
		active.erase(id)
	if not ended.is_empty():
		changed.emit()
