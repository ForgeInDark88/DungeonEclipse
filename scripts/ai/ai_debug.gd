class_name AIDebug
extends RefCounted
## Monster AI diagnostics: the F3 overlay switch, counters of anti-stuck
## measures (read by tests/ai_sim) and an event log printed while the overlay
## is on (or when `verbose` is set by a test).

static var enabled := false
static var verbose := false
## Counters since the last reset(): repath, maneuver, teleport, nav.
static var counters: Dictionary = {}


static func reset() -> void:
	counters = {}


static func count(key: String) -> int:
	return int(counters.get(key, 0))


static func log_event(who: Node, key: String, text: String) -> void:
	counters[key] = count(key) + 1
	if enabled or verbose:
		print("[AI] %s %s: %s" % [who.name if who else "?", key, text])
