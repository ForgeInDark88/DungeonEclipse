class_name ItemFactory
extends RefCounted
## Turns item templates (.tres) into what actually lands in the backpack:
## * items with durability become runtime instances (own durability);
## * rare / epic weapons also get random affixes (1 for rare, 2 for epic),
##   baked into the copy, and a name built from prefix + name + suffix.
## Stackable items stay shared templates.


static func create(item: ItemData, floor_number: int = 1, rng: RandomNumberGenerator = null) -> ItemData:
	if item == null or item.is_instance():
		return item
	var needs_instance := item.has_durability or (item is WeaponItemData and item.rarity > ItemData.Rarity.COMMON)
	if not needs_instance:
		return item
	var inst := item.make_instance()
	if inst is WeaponItemData:
		_roll_affixes(inst as WeaponItemData, floor_number, rng)
	return inst


## Applies `create` to every entry of a loot roll ([{item, count}]).
static func instantiate_loot(loot: Array, floor_number: int, rng: RandomNumberGenerator = null) -> Array:
	var out: Array = []
	for e: Dictionary in loot:
		var item: ItemData = e["item"]
		if item.is_stackable():
			out.append(e)
		else:
			for i in int(e["count"]):
				out.append({"item": create(item, floor_number, rng), "count": 1})
	return out


static func _roll_affixes(w: WeaponItemData, floor_number: int, rng: RandomNumberGenerator) -> void:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var count := 0
	match w.rarity:
		ItemData.Rarity.RARE:
			count = 1
		ItemData.Rarity.EPIC:
			count = 2
	var pool: Array[AffixData] = []
	for a in ItemDatabase.affixes:
		if a.fits(w):
			pool.append(a)
	var prefix: AffixData = null
	var suffix: AffixData = null
	for i in count:
		var candidates: Array[AffixData] = []
		var weights: Array[float] = []
		for a in pool:
			if a in w.affixes:
				continue
			# At most one prefix and one suffix.
			if (a.is_prefix() and prefix) or (not a.is_prefix() and suffix):
				continue
			candidates.append(a)
			weights.append(a.weight)
		if candidates.is_empty():
			break
		var picked: AffixData = candidates[LootTable._weighted_index(weights, rng)]
		picked.apply_to(w)
		w.affixes.append(picked)
		if picked.is_prefix():
			prefix = picked
		else:
			suffix = picked
	# Deeper floors give slightly stronger rolls.
	w.base_damage = snappedf(w.base_damage * (1.0 + 0.03 * maxi(0, floor_number - 1)), 0.1)
	w.display_name = compose_name(w.template.display_name if w.template else w.display_name, w.gender, prefix, suffix)


static func compose_name(base: String, gender: String, prefix: AffixData, suffix: AffixData) -> String:
	var name := base
	if prefix:
		var adj: String = prefix.prefix_forms.get(gender, prefix.prefix_forms.get("m", ""))
		# Lower-case the first letter of the base name after an adjective.
		name = "%s %s" % [adj, base.left(1).to_lower() + base.substr(1)]
	if suffix:
		name += " " + suffix.suffix
	return name
