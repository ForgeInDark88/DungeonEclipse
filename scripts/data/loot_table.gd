class_name LootTable
extends Resource
## Rolls items: first a rarity (weights grow towards rare/epic with depth),
## then a weighted entry of that rarity. Falls back to lower rarities if the
## table has nothing of the rolled one.

@export var rolls_min: int = 1
@export var rolls_max: int = 2
## Weights for COMMON, RARE, EPIC.
@export var rarity_weights: Array[float] = [70.0, 25.0, 5.0]
## Added to RARE / EPIC weights per floor below the first.
@export var rare_bonus_per_floor: float = 3.0
@export var epic_bonus_per_floor: float = 1.5
@export var entries: Array[LootEntry] = []


## Returns an Array of {item: ItemData, count: int}.
func roll(floor_number: int, rng: RandomNumberGenerator = null) -> Array:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var result: Array = []
	var rolls := rng.randi_range(rolls_min, maxi(rolls_min, rolls_max))
	for i in rolls:
		var entry := _pick_entry(floor_number, rng)
		if entry != null and entry.item != null:
			result.append({"item": entry.item, "count": rng.randi_range(entry.min_count, maxi(entry.min_count, entry.max_count))})
	return result


func _pick_entry(floor_number: int, rng: RandomNumberGenerator) -> LootEntry:
	var depth := float(maxi(0, floor_number - 1))
	var weights: Array[float] = [
		rarity_weights[0] if rarity_weights.size() > 0 else 70.0,
		(rarity_weights[1] if rarity_weights.size() > 1 else 25.0) + rare_bonus_per_floor * depth,
		(rarity_weights[2] if rarity_weights.size() > 2 else 5.0) + epic_bonus_per_floor * depth,
	]
	var rarity := _weighted_index(weights, rng)
	while rarity >= 0:
		var pool: Array[LootEntry] = []
		var pool_weights: Array[float] = []
		for e in entries:
			if e.item != null and e.item.rarity == rarity and e.min_floor <= floor_number:
				pool.append(e)
				pool_weights.append(e.weight)
		if not pool.is_empty():
			return pool[_weighted_index(pool_weights, rng)]
		rarity -= 1
	return null


static func _weighted_index(weights: Array[float], rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for w in weights:
		total += maxf(w, 0.0)
	if total <= 0.0:
		return 0
	var r := rng.randf() * total
	for i in weights.size():
		r -= maxf(weights[i], 0.0)
		if r <= 0.0:
			return i
	return weights.size() - 1
