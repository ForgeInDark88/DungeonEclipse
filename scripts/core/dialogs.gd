class_name Dialogs
extends RefCounted
## Talks of the town's people (NpcData.dialogs): the current talk is the
## first whose condition holds and that is not read yet when it is `once`.
## Read talks and option flags are kept in TownState.flags.


static func current(npc: NpcData) -> Dictionary:
	for d: Dictionary in npc.dialogs:
		if not condition(String(d.get("when", ""))):
			continue
		if d.get("once", false) and is_read(npc, d):
			continue
		return d
	return {}


## A new talk waits ("!" over the head).
static func has_news(npc: NpcData) -> bool:
	var d := current(npc)
	return not d.is_empty() and d.get("once", false) and not is_read(npc, d)


static func is_read(npc: NpcData, d: Dictionary) -> bool:
	var t := GameState.town
	return t != null and t.flag("talk_%s_%s" % [npc.id, d.get("id", "")], false)


static func mark_read(npc: NpcData, d: Dictionary) -> void:
	var t := GameState.town
	if t:
		t.set_flag("talk_%s_%s" % [npc.id, d.get("id", "")])


## "" | "boss:<id>" | "flag:<id>" | "!flag:<id>" | "building:<id>:<lvl>" |
## "resident:<id>" | "expeditions:<n>", several joined by " & ".
static func condition(expr: String) -> bool:
	var t := GameState.town
	if expr.strip_edges() == "":
		return true
	if t == null:
		return false
	for part in expr.split("&"):
		var c := part.strip_edges()
		var neg := c.begins_with("!")
		if neg:
			c = c.substr(1)
		var bits := c.split(":")
		var ok := false
		match bits[0]:
			"boss":
				ok = StringName(bits[1]) in t.bosses_defeated
			"flag":
				var v: Variant = t.flag(bits[1], false)
				ok = (v is bool and v) or ((v is int or v is float) and v != 0) or (v is String and v != "")
			"building":
				ok = t.building_level(StringName(bits[1])) >= (int(bits[2]) if bits.size() > 2 else 1)
			"resident":
				ok = t.has_resident(StringName(bits[1]))
			"expeditions":
				ok = int(t.stats.get("expeditions", 0)) >= int(bits[1])
			_:
				ok = false
		if ok == neg:
			return false
	return true
