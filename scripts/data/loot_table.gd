class_name LootTable
extends Resource
## Rolls drops tied to the floor:
## 1. a rarity — `rarity_weights` on floor 1 plus `rarity_per_floor` for every
##    floor below; a rarity cannot appear before `rarity_min_floor`;
## 2. an entry of that rarity whose item is not above the item level allowed
##    here: item_level_base + item_level_per_floor × floor + item_level_bonus
##    (better chests/tables add a bonus, but the floor still caps it);
## 3. if nothing fits, the next lower rarity.
## `rolls_min..rolls_max` items, then each table in `extra_tables` once (e.g.
## supplies), then gold. Bigger chests = better rarity odds and a small level
## bonus, never "the best item of the game" on floor 1.
## Tune and regenerate with tools/gen_loot_tables.py; results: docs/BALANCE.md.

@export var rolls_min: int = 1
@export var rolls_max: int = 1
## Rarity weights (COMMON, RARE, EPIC, LEGENDARY) on floor 1 — "rarity_weight".
@export var rarity_weights: Array[float] = [80.0, 18.0, 1.0, 0.0]
## Added to each rarity weight for every floor below the first.
@export var rarity_per_floor: Array[float] = [0.0, 3.0, 1.2, 0.0]
## First floor where each rarity may drop at all.
@export var rarity_min_floor: Array[int] = [1, 1, 4, 8]
@export var item_level_base: float = 1.0
@export var item_level_per_floor: float = 0.75
@export var item_level_bonus: float = 0.0
@export var entries: Array[LootEntry] = []
## Rolled once each on top of this table (supplies, materials...).
@export var extra_tables: Array[LootTable] = []
## Gold added to every roll (scaled +25% per floor). 0 = none.
@export var gold_min: int = 0
@export var gold_max: int = 0


## Highest item_level this table gives on `floor_number`.
func item_level_cap(floor_number: int) -> int:
	return floori(item_level_base + item_level_per_floor * floor_number + item_level_bonus)


## Weights of every rarity on `floor_number` (0 for rarities not allowed yet).
func rarity_odds(floor_number: int) -> Array[float]:
	var depth := float(maxi(0, floor_number - 1))
	var out: Array[float] = []
	for r in ItemData.RARITY_NAMES.size():
		var base: float = rarity_weights[r] if r < rarity_weights.size() else 0.0
		var per: float = rarity_per_floor[r] if r < rarity_per_floor.size() else 0.0
		var min_f: int = rarity_min_floor[r] if r < rarity_min_floor.size() else 1
		out.append(0.0 if floor_number < min_f else maxf(0.0, base + per * depth))
	return out


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
	for t in extra_tables:
		if t:
			for e in t.roll_items(floor_number, rng):
				result.append(e)
	if gold_max > 0:
		var coin := ItemDatabase.get_item(&"gold_coin")
		if coin:
			result.append({"item": coin, "count": roundi(rng.randi_range(gold_min, gold_max) * (1.0 + 0.10 * (floor_number - 1)))})
	# Weapons/armor become unique copies (affixes, durability) when they drop.
	return ItemFactory.instantiate_loot(result, floor_number, rng)


## Like roll() but without turning items into instances (used for nesting).
func roll_items(floor_number: int, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	for i in rng.randi_range(rolls_min, maxi(rolls_min, rolls_max)):
		var entry := _pick_entry(floor_number, rng)
		if entry != null and entry.item != null:
			out.append({"item": entry.item, "count": rng.randi_range(entry.min_count, maxi(entry.min_count, entry.max_count))})
	return out


func _pick_entry(floor_number: int, rng: RandomNumberGenerator) -> LootEntry:
	var cap := item_level_cap(floor_number)
	var rarity := _weighted_index(rarity_odds(floor_number), rng)
	while rarity >= 0:
		var pool: Array[LootEntry] = []
		var pool_weights: Array[float] = []
		for e in entries:
			if e.item != null and e.item.rarity == rarity and e.allowed_on(floor_number) and e.item.item_level <= cap:
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
