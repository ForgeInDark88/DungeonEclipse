class_name RunState
extends RefCounted
## The current expedition: its map, where the hero stands on it, and what
## was gathered on the way (gold, items, town resources, rescued people).
## Lives only while the expedition lasts (a quit mid-expedition loses it -
## GameFlow treats that as a failed expedition).

enum Outcome { NONE, VICTORY, RETREAT, DEATH }

var seed_value: int = 0
var map: ExpeditionMap
## Node the hero stands on (-1 = at the town gate, before the first step).
var node_id: int = -1
## Ids of the nodes walked through, in order.
var path: Array[int] = []
## Region the expedition started in (ExpeditionMap regions are absolute).
var start_region: int = 0
## Hero gold when the expedition began (the death penalty takes the rest).
var gold_at_start: int = 0
var kills_at_start: int = 0
## Town resources found on the way (wood, stone, iron...): reach the town
## only when the hero comes back alive.
var resources: Dictionary = {}
## Item ids worth a line on the result screen (rare and better).
var finds: Array[StringName] = []
## NPC ids freed on the way (they move in on a safe return).
var rescued: Array[StringName] = []
## Blueprints found (building ids whose next level they open).
var blueprints: Array[StringName] = []
## Region bosses beaten this expedition (BossData ids).
var bosses: Array[StringName] = []
## Event flags set by choices this expedition (copied to the town on return).
var flags: Dictionary = {}
var outcome: Outcome = Outcome.NONE
## The location under way: gold / kills / shards at its start, finds and
## resources of this location, whether its clear reward was paid
## (GameFlow fills it, the location summary reads it).
var loc: Dictionary = {}
var start_ms: int = 0


func current_node() -> Dictionary:
	return map.node(node_id) if map and node_id >= 0 else {}


## Nodes the hero may step to next (the first step: every start node).
func next_choices() -> Array[int]:
	if map == null:
		return []
	if node_id < 0:
		return map.start_nodes()
	return map.links_of(node_id)


func add_resource(id: StringName, amount: int) -> void:
	resources[String(id)] = int(resources.get(String(id), 0)) + amount


func depth() -> int:
	return int(current_node().get("depth", 1))
