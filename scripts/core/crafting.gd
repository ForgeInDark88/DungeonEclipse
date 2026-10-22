class_name Crafting
extends RefCounted
## Crafting rules: a recipe can be made when the backpack holds every
## ingredient (and the gold) and there is room for the result.


static func missing(hero: Hero, r: RecipeData) -> Dictionary:
	var out := {}
	for id in r.ingredients:
		var lack := int(r.ingredients[id]) - hero.inventory.count_of(id)
		if lack > 0:
			out[id] = lack
	return out


static func can_craft(hero: Hero, r: RecipeData) -> bool:
	var item := ItemDatabase.get_item(r.result)
	return item != null and missing(hero, r).is_empty() and hero.gold >= r.gold \
			and hero.inventory.free_space_for(item) >= r.count


static func craft(hero: Hero, r: RecipeData) -> bool:
	if not can_craft(hero, r):
		return false
	for id in r.ingredients:
		hero.inventory.remove_by_id(id, int(r.ingredients[id]))
	if r.gold > 0:
		hero.spend_gold(r.gold)
	var item := ItemDatabase.get_item(r.result)
	if item.is_stackable():
		hero.inventory.add_item(item, r.count)
	else:
		for i in r.count:
			hero.inventory.add_item(ItemFactory.create(item, GameState.floor_number))
	EventBus.item_crafted.emit(item)
	return true
