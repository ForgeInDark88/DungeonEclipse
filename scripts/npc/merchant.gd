class_name Merchant
extends Area2D
## Travelling merchant in a side room. Stock is rolled once per floor from
## data/loot_tables/merchant.tres plus always-available basics.

const STOCK_TABLE := &"merchant"
const BASICS: Array[StringName] = [&"health_potion", &"antidote", &"whetstone", &"bomb", &"map_scroll", &"identify_scroll"]
const STOCK_ROLLS := 3
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


func get_prompt() -> String:
	return "Торговать"


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
