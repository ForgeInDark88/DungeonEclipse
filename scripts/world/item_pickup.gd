class_name ItemPickup
extends CharacterBody2D
## An item lying in the world. Picked up with the interact key
## (every pickup in reach is collected at once).

const GRAVITY := 700.0

var item: ItemData
var count: int = 1
var _bob := 0.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var count_label: Label = $Count


func setup(p_item: ItemData, p_count: int, impulse: Vector2) -> void:
	item = p_item
	count = p_count
	velocity = impulse


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("pickups")
	sprite.texture = item.icon if item else null
	count_label.text = str(count) if count > 1 else ""
	_bob = randf() * TAU


func _physics_process(delta: float) -> void:
	velocity.y = minf(velocity.y + GRAVITY * delta, 400.0)
	if is_on_floor():
		velocity.x = move_toward(velocity.x, 0.0, 400.0 * delta)
	move_and_slide()
	_bob += delta * 3.0
	sprite.position.y = -8.0 + sin(_bob) * 1.5


func get_prompt() -> String:
	var text := item.display_name
	if count > 1:
		text += " x%d" % count
	return "Подобрать: " + text


func interact(player: Node) -> void:
	# Collect everything in reach, not just the nearest item.
	for area in player.interact_area.get_overlapping_areas():
		var p := area.get_parent() as ItemPickup
		if p != null and p != self:
			p.collect(player.hero)
	collect(player.hero)


func collect(hero: Hero) -> void:
	if item == null or is_queued_for_deletion():
		return
	var left := hero.inventory.add_item(item, count)
	var taken := count - left
	if taken > 0:
		EventBus.item_collected.emit(item, global_position + Vector2(0, -8))
		EventBus.floating_text.emit(global_position + Vector2(0, -16), "+%d %s" % [taken, item.display_name], item.rarity_color())
	if left > 0:
		count = left
		count_label.text = str(count) if count > 1 else ""
		EventBus.message.emit("Рюкзак полон")
	else:
		queue_free()
