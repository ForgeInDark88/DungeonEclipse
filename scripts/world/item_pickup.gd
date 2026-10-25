class_name ItemPickup
extends CharacterBody2D
## An item lying in the world. Picked up with the interact key
## (every pickup in reach is collected at once).

const GRAVITY := 700.0

var item: ItemData
var count: int = 1
var _bob := 0.0
var _settle_check := 0.0
var _glow: PointLight2D
## LAN co-op: replicas of host-dropped loot; touching one asks the host.
var puppet := false
var net_id := 0

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
	# Rare and epic items glow on the floor.
	if item and item.rarity > ItemData.Rarity.COMMON:
		_glow = PointLight2D.new()
		_glow.texture = AssetPaths.tex(AssetPaths.LIGHT)
		_glow.color = item.rarity_color()
		_glow.texture_scale = [0.2, 0.25, 0.35, 0.45][item.rarity]
		_glow.position = Vector2(0, -8)
		add_child(_glow)


func _physics_process(delta: float) -> void:
	# Lying still: physics only twice a second (the floor may be dug away).
	_settle_check -= delta
	var settled := is_on_floor() and absf(velocity.x) < 1.0 and absf(velocity.y) < 1.0
	if not settled or _settle_check <= 0.0:
		_settle_check = 0.5
		velocity.y = minf(velocity.y + GRAVITY * delta, 400.0)
		if is_on_floor():
			velocity.x = move_toward(velocity.x, 0.0, 400.0 * delta)
		move_and_slide()
	_bob += delta * 3.0
	sprite.position.y = -8.0 + sin(_bob) * 1.5
	if _glow:
		_glow.energy = 0.9 + sin(_bob * 1.7) * 0.35
		sprite.modulate = Color.WHITE.lerp(item.rarity_color() * 1.5, (sin(_bob * 1.7) + 1.0) * 0.2)


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
	if puppet:
		var ns := get_tree().get_first_node_in_group("net_game") as NetSync
		if ns:
			ns.take_item.rpc_id(1, net_id)
			queue_free()
		return
	# The host collecting its own loot must remove the replicas on clients,
	# or they keep a phantom copy that vanishes when touched.
	if Net.active and Net.is_host and net_id > 0:
		tree_exiting.connect(func() -> void:
			var ns := get_tree().get_first_node_in_group("net_game") as NetSync
			if ns:
				ns.forget_item(net_id))
	if item.currency_value > 0:
		var amount := item.currency_value * count
		hero.add_gold(amount)
		EventBus.floating_text.emit(global_position + Vector2(0, -16), "+%d з." % amount, Color(1.0, 0.85, 0.3))
		AudioManager.play_sfx(&"coin", global_position)
		queue_free()
		return
	var left := hero.inventory.add_item(item, count)
	var taken := count - left
	if taken > 0:
		EventBus.item_collected.emit(item, global_position + Vector2(0, -8))
		var found: Array = GameState.run_stats.get("found", [0, 0, 0])
		if found.size() > item.rarity:
			found[item.rarity] += 1
		var snd: StringName = [&"pickup_common", &"pickup_rare", &"pickup_epic", &"pickup_epic"][item.rarity]
		AudioManager.play_sfx(&"coin" if item.id == &"gold_coin" else snd, global_position)
		EventBus.floating_text.emit(global_position + Vector2(0, -16), "+%d %s" % [taken, item.display_name], item.rarity_color())
	if left > 0:
		count = left
		count_label.text = str(count) if count > 1 else ""
		EventBus.message.emit("Рюкзак полон")
	else:
		queue_free()
