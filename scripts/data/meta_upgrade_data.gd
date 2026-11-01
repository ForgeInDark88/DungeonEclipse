class_name MetaUpgradeData
extends Resource
## A permanent upgrade bought in the Sanctum of the Eclipse (main menu) for
## eclipse shards and banked gold. Every level adds the same bonuses again.
## Drop a .tres into data/meta to add one; MetaProgress picks it up.

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D
## Position in the Sanctum list (lower = first).
@export var order: int = 0
@export var max_level: int = 1
## Price of level 1, 2, ... (the last value repeats if the array is short).
@export var shard_costs: Array[int] = [5]
@export var gold_costs: Array[int] = [0]
## Stat bonuses per level, keyed by StatTypes names.
@export var stat_bonuses: Dictionary = {}
## Gold at the start of a run, per level.
@export var start_gold: int = 0
## Extra starting items per level: item id -> count.
@export var starting_items: Dictionary = {}


func shard_cost(level: int) -> int:
	return _cost(shard_costs, level)


func gold_cost(level: int) -> int:
	return _cost(gold_costs, level)


## Cost of buying `level` (1-based).
func _cost(costs: Array[int], level: int) -> int:
	if costs.is_empty():
		return 0
	return costs[clampi(level - 1, 0, costs.size() - 1)]


## Effect text for `level` levels (UI).
func describe(level: int) -> String:
	var parts: Array[String] = []
	for k in stat_bonuses:
		parts.append("%s %s" % [StatTypes.label(k), StatTypes.format_value(k, float(stat_bonuses[k]) * level, true)])
	if start_gold > 0:
		parts.append(tr("+%d золота на старте") % (start_gold * level))
	for item_id: StringName in starting_items:
		var item := ItemDatabase.get_item(item_id)
		parts.append("+%d %s" % [int(starting_items[item_id]) * level, item.display_name if item else String(item_id)])
	return ", ".join(parts)
