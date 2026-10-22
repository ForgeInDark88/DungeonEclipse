class_name ItemSetData
extends Resource
## An equipment set: wearing 2 / 3 / 4 parts gives extra bonuses. Parts point
## to the set with EquipmentItemData.set_id; add a .tres to data/sets/.

@export var id: StringName
@export var display_name: String = ""
## Item ids of the parts (for the tooltip list).
@export var items: Array[StringName] = []
## Parts worn -> bonuses (StatTypes keys), e.g. {2: {"armor": 4}, 4: {...}}.
## Bonuses of every reached threshold add up.
@export var bonuses: Dictionary = {}


## Sum of the bonuses for `worn` parts.
func bonuses_for(worn: int) -> Dictionary:
	var total := {}
	for need in bonuses:
		if worn >= int(need):
			var b: Dictionary = bonuses[need]
			for k in b:
				total[k] = float(total.get(k, 0.0)) + float(b[k])
	return total


func thresholds() -> Array:
	var t := bonuses.keys()
	t.sort()
	return t
