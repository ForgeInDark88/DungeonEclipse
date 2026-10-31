class_name Merchant
extends Area2D
## Travelling merchant in a side room. Stock is rolled once per floor from
## data/loot_tables/merchant.tres plus always-available basics.

const STOCK_TABLE := &"merchant"
const BASICS: Array[StringName] = [&"health_potion", &"antidote", &"whetstone", &"bomb", &"map_scroll", &"identify_scroll"]
const STOCK_ROLLS := 3
## Shared stock cap (bought goods + uniques sold by players).
const STOCK_CAP := 18
## Chance that the merchant also sells a pet egg.
const EGG_CHANCE := 0.35

var floor_number: int = 1
## Array of ItemData (instances for gear) — removed when bought.
var stock: Array[ItemData] = []
## LAN co-op: deterministic shop identity across machines.
var net_seq := 0

@onready var sprite: AnimatedSprite2D = $Sprite


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("merchants")
	AssetPaths.layout(AssetPaths.MERCHANT_LAYOUT).apply_to(sprite, AssetPaths.tex(AssetPaths.MERCHANT_SHEET))
	sprite.play(&"idle")
	_roll_stock()


func _roll_stock() -> void:
	stock.clear()
	for id in BASICS:
		var it := ItemDatabase.get_item(id)
		if it:
			stock.append(it)
	# In co-op the stock must match on every machine: seeded by run+floor+shop.
	var roll_rng := RandomNumberGenerator.new()
	if Net.active:
		roll_rng.seed = hash([GameState.run_seed, floor_number, net_seq])
	else:
		roll_rng.randomize()
	var table := ItemDatabase.get_loot_table(STOCK_TABLE)
	if table:
		for i in STOCK_ROLLS:
			for e: Dictionary in table.roll(floor_number, roll_rng):
				if e["item"].currency_value <= 0 and stock.size() < 12:
					stock.append(e["item"])
	# Sometimes a pet egg.
	if roll_rng.randf() < EGG_CHANCE:
		var eggs := ItemDatabase.items.values().filter(func(it: ItemData) -> bool: return it.id.begins_with("egg_"))
		if not eggs.is_empty():
			stock.append(eggs[roll_rng.randi() % eggs.size()])


## LAN co-op: rebuild this stock from the host's remaining item ids, in order.
func apply_stock_ids(ids: Array) -> void:
	var kept: Array[ItemData] = []
	var used := {}
	for id_str: String in ids:
		for i in stock.size():
			var it := stock[i]
			if it != null and String(it.id) == id_str and not used.has(i):
				kept.append(it)
				used[i] = true
				break
	stock = kept


func find_offer(offer_key: String) -> int:
	for i in stock.size():
		if offer_key_at(i) == offer_key:
			return i
	return -1


func offer_key_at(index: int) -> String:
	if index < 0 or index >= stock.size():
		return ""
	var item_id := String(stock[index].id)
	var occurrence := 0
	for i in index:
		if String(stock[i].id) == item_id:
			occurrence += 1
	return "%s#%d" % [item_id, occurrence]


func get_prompt() -> String:
	return tr("Торговать")


func interact(player: Node) -> void:
	sprite.play(&"greet")
	sprite.animation_finished.connect(func() -> void: sprite.play(&"idle"), CONNECT_ONE_SHOT)
	EventBus.shop_requested.emit(self, player)


## Repair price for everything worn (gold).
static func repair_cost(hero: Hero) -> int:
	var cost := 0.0
	for item: EquipmentItemData in hero.equipment.items.values():
		if item and item.has_durability and item.is_instance():
			cost += (item.max_durability - item.durability) * 0.3 * (1 + item.rarity)
	return ceili(cost)


static func heal_cost(hero: Hero) -> int:
	var missing := hero.stats.max_hp() - hero.stats.hp
	return 0 if missing <= 0 else 5 + ceili(missing * 0.4)
