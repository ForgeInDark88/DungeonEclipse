class_name Chest
extends Area2D
## Loot chest. Tier 0 = wooden, 1 = iron, 2 = golden (locked, needs a key).
## Loot comes from data/loot_tables/chest_<tier>.tres.

const TIER_TABLES: Array[StringName] = [&"chest_common", &"chest_rare", &"chest_epic"]
const TIER_TEXTURES := [
	["res://assets/sprites/props/chest_wood.png", "res://assets/sprites/props/chest_wood_open.png"],
	["res://assets/sprites/props/chest_iron.png", "res://assets/sprites/props/chest_iron_open.png"],
	["res://assets/sprites/props/chest_gold.png", "res://assets/sprites/props/chest_gold_open.png"],
]
const TIER_NAMES := ["Деревянный сундук", "Железный сундук", "Золотой сундук"]

var tier: int = 0
var floor_number: int = 1
var locked := false
var opened := false

@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("chests")
	locked = tier == 2
	sprite.texture = load(TIER_TEXTURES[tier][0])


func can_interact() -> bool:
	return not opened


func get_prompt() -> String:
	if locked:
		return "Открыть ключом (%s)" % TIER_NAMES[tier]
	return "Открыть: %s" % TIER_NAMES[tier]


func interact(player: Node) -> void:
	if opened:
		return
	if locked:
		var hero: Hero = player.hero
		if hero.inventory.remove_by_id(&"key", 1) == 0:
			EventBus.message.emit("Сундук заперт. Нужен ключ.")
			_shake()
			return
		unlock()
	open()


func unlock() -> void:
	locked = false
	EventBus.message.emit("Замок открыт")


func open() -> void:
	opened = true
	sprite.texture = load(TIER_TEXTURES[tier][1])
	var table := ItemDatabase.get_loot_table(TIER_TABLES[tier])
	if table:
		var loot := table.roll(floor_number)
		if not loot.is_empty():
			EventBus.spawn_items.emit(global_position + Vector2(0, -10), loot)
	EventBus.chest_opened.emit(self)


func _shake() -> void:
	var tw := create_tween()
	for i in 3:
		tw.tween_property(sprite, "position:x", 2.0, 0.04)
		tw.tween_property(sprite, "position:x", -2.0, 0.04)
	tw.tween_property(sprite, "position:x", 0.0, 0.04)
