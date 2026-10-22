class_name StatusEffects
extends Node
## Status effects on a creature (child node named "StatusEffects").
## The host may implement:
##   take_status_damage(amount: int, status: StringName, color: Color)
##   heal_status(amount: int)
##   status_resistance(status: StringName) -> float   (0..1, shortens duration)
## and reads speed_multiplier() / is_stunned() / absorb().
##
## Element interactions: burning melts "slow" (ice) and ice puts out burning;
## poison halves regeneration. `immunities` lists statuses that never apply.

signal changed
signal applied(id: StringName)

const TICK := 0.5
## Cursed creatures take this much more damage.
const CURSE_DAMAGE_MULT := 1.25
## id -> [name, color, is_damage_over_time, damage type (WeaponItemData.DamageType)]
const INFO := {
	&"poison": ["Яд", Color(0.45, 0.9, 0.3), true, 3],
	&"burn": ["Горение", Color(1.0, 0.5, 0.15), true, 1],
	&"bleed": ["Кровотечение", Color(0.85, 0.1, 0.15), true, 0],
	&"stun": ["Оглушение", Color(1.0, 0.95, 0.4), false, 0],
	&"slow": ["Замедление", Color(0.5, 0.8, 1.0), false, 2],
	&"regen": ["Регенерация", Color(0.4, 1.0, 0.5), false, 0],
	&"shield": ["Щит", Color(0.6, 0.8, 1.0), false, 0],
	&"curse": ["Проклятие", Color(0.7, 0.35, 0.9), false, 4],
	&"invisible": ["Невидимость", Color(0.75, 0.85, 1.0), false, 0],
}
## Statuses that are bad for their target (shown with a red frame in the HUD).
const NEGATIVE: Array[StringName] = [&"poison", &"burn", &"bleed", &"stun", &"slow", &"curse"]

## id -> {"time": float, "duration": float, "power": float, "tick": float}
var active: Dictionary = {}
var immunities: Array[StringName] = []


static func display_name(id: StringName) -> String:
	return INFO[id][0] if INFO.has(id) else String(id)


static func color_of(id: StringName) -> Color:
	return INFO[id][1] if INFO.has(id) else Color.WHITE


static func damage_type_of(id: StringName) -> int:
	return INFO[id][3] if INFO.has(id) else 0


static func icon_of(id: StringName) -> Texture2D:
	return AssetPaths.tex(AssetPaths.STATUS_ICON_DIR + String(id) + ".png")


func apply(id: StringName, duration: float, power: float = 1.0) -> void:
	if id in immunities:
		return
	var host := get_parent()
	if host and host.has_method("status_resistance"):
		duration *= 1.0 - clampf(host.status_resistance(id), 0.0, 0.9)
	if duration <= 0.05:
		return
	# Element interactions.
	if id == &"burn" and active.has(&"slow"):
		active.erase(&"slow")
	elif id == &"slow" and active.has(&"burn"):
		active.erase(&"burn")
	var cur: Dictionary = active.get(id, {})
	if cur.is_empty():
		active[id] = {"time": duration, "duration": duration, "power": power, "tick": TICK}
	else:
		cur["time"] = maxf(cur["time"], duration)
		cur["duration"] = maxf(cur["duration"], duration)
		cur["power"] = maxf(cur["power"], power)
	applied.emit(id)
	changed.emit()


func has(id: StringName) -> bool:
	return active.has(id)


func remove(id: StringName) -> void:
	if active.erase(id):
		changed.emit()


## Removes all negative statuses of the given ids (antidote, cleansing).
func cure(ids: Array) -> bool:
	var any := false
	for id in ids:
		if active.erase(id):
			any = true
	if any:
		changed.emit()
	return any


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


## Shield absorbs damage first. Returns what is left to deal.
func absorb(amount: int) -> int:
	if not active.has(&"shield"):
		return amount
	var st: Dictionary = active[&"shield"]
	var take := mini(amount, int(st["power"]))
	st["power"] -= take
	if st["power"] <= 0.0:
		active.erase(&"shield")
		changed.emit()
	return amount - take


## Remaining time fraction 0..1 (for HUD bars).
func ratio(id: StringName) -> float:
	var st: Dictionary = active.get(id, {})
	return clampf(st.get("time", 0.0) / maxf(0.01, st.get("duration", 1.0)), 0.0, 1.0) if not st.is_empty() else 0.0


func _physics_process(delta: float) -> void:
	if active.is_empty():
		return
	var host := get_parent()
	var ended: Array[StringName] = []
	for id: StringName in active.keys():
		if not active.has(id):
			continue
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
				var amount := roundi(st["power"] * (0.5 if active.has(&"poison") else 1.0))
				host.heal_status(maxi(1, amount))
		if st["time"] <= 0.0:
			ended.append(id)
	for id in ended:
		active.erase(id)
	if not ended.is_empty():
		changed.emit()
