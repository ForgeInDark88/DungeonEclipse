class_name RelicAltar
extends Area2D
## The relic altar after a guardian falls: three relics the hero does not
## carry yet, one can be taken (RelicChoiceBook). Personal in co-op - every
## machine has its own altar and its own three: relics work for the hero
## who carries them.

const OFFERS := 3
## Chance that an offer slot rolls an epic relic.
const EPIC_CHANCE := 0.35

var used := false
var _offers: Array[RelicItemData] = []
var _sprite: Sprite2D
var _light: PointLight2D


func _ready() -> void:
	add_to_group("interactable")
	collision_layer = 16
	collision_mask = 0
	monitoring = false
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(26, 30)
	shape.shape = rect
	shape.position = Vector2(0, -15)
	add_child(shape)
	_sprite = Sprite2D.new()
	_sprite.texture = AssetPaths.tex(AssetPaths.SPRITES_DIR + "props/relic_altar.png")
	_sprite.centered = false
	_sprite.offset = Vector2(-16, -32)
	add_child(_sprite)
	_light = PointLight2D.new()
	_light.texture = AssetPaths.tex(AssetPaths.LIGHT)
	_light.color = Color(0.75, 0.5, 1.0)
	_light.energy = 1.0
	_light.texture_scale = 0.5
	_light.position = Vector2(0, -24)
	add_child(_light)
	_offers = roll_offers(GameState.hero)
	Fx.sparks(get_parent(), global_position + Vector2(0, -20), Color(0.75, 0.5, 1.0), 20, 90.0)


## Three different relics the hero does not carry, epic ones now and then.
static func roll_offers(hero: Hero) -> Array[RelicItemData]:
	var owned := {}
	if hero:
		for r in hero.relics():
			owned[r.id] = true
	var rare: Array[RelicItemData] = []
	var epic: Array[RelicItemData] = []
	for it: ItemData in ItemDatabase.items.values():
		var r := it as RelicItemData
		if r and r.power != &"" and not owned.has(r.id):
			(epic if r.rarity >= ItemData.Rarity.EPIC else rare).append(r)
	var out: Array[RelicItemData] = []
	for i in OFFERS:
		var pool := epic if (randf() < EPIC_CHANCE and not epic.is_empty()) or rare.is_empty() else rare
		if pool.is_empty():
			break
		out.append(pool.pop_at(randi() % pool.size()))
	return out


func can_interact() -> bool:
	return not used


func get_prompt() -> String:
	return tr("Алтарь реликвий: выбрать одну") if not used else tr("Алтарь угас")


func interact(player: Node) -> void:
	if used or _offers.is_empty():
		return
	var book := RelicChoiceBook.new()
	get_tree().current_scene.add_child(book)
	book.open(_offers, player as Player, func(r: RelicItemData) -> void: _take(r, player as Player))


func _take(r: RelicItemData, player: Player) -> void:
	if player == null or player.hero.inventory.add_item(r, 1) > 0:
		EventBus.message.emit(tr("Рюкзак полон — освободите место для реликвии"))
		return
	used = true
	remove_from_group("interactable")
	EventBus.item_collected.emit(r, global_position + Vector2(0, -20))
	EventBus.message.emit(tr("Реликвия: «%s»") % r.display_name)
	AudioManager.play_ui(&"pickup_epic")
	Fx.sparks(get_parent(), global_position + Vector2(0, -20), r.rarity_color(), 24, 110.0)
	var tw := create_tween()
	tw.tween_property(_sprite, "modulate", Color(0.6, 0.6, 0.7), 0.6)
	tw.parallel().tween_property(_light, "energy", 0.0, 0.6)
