class_name Chest
extends Area2D
## Loot chest. Tier 0 = wooden, 1 = iron, 2 = golden (locked, needs a key).
## Loot comes from data/loot_tables/chest_<tier>.tres.

const TIER_TABLES: Array[StringName] = [&"chest_common", &"chest_rare", &"chest_epic"]
const TIER_NAMES := ["Деревянный сундук", "Железный сундук", "Золотой сундук"]

var tier: int = 0
## Loot table id instead of the tier's table (boss reward chest: &"boss").
var table_override: StringName = &""
var floor_number: int = 1
var locked := false
var opened := false
## LAN co-op: deterministic chest identity across machines.
var net_seq := 0
## Golden chests are locked unless this is set (boss rewards).
var unlocked_by_default := false
## Behind a puzzle barrier: cannot be opened until the puzzle is solved.
var sealed := false

@onready var sprite: AnimatedSprite2D = $Sprite


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("chests")
	locked = tier == 2 and not unlocked_by_default
	AssetPaths.layout(AssetPaths.CHEST_LAYOUT).apply_to(sprite, AssetPaths.tex(AssetPaths.CHEST_SHEETS[tier]))
	sprite.play(&"closed")


func can_interact() -> bool:
	return not opened and not sealed


func get_prompt() -> String:
	if locked:
		return "Открыть ключом (%s)" % TIER_NAMES[tier]
	return "Открыть: %s" % TIER_NAMES[tier]


func interact(player: Node) -> void:
	if opened:
		return
	if Net.active and not Net.is_host:
		var has_key: bool = not locked or player.hero.inventory.count_of(&"key") > 0
		if locked and not has_key:
			EventBus.message.emit("Сундук заперт. Нужен ключ.")
			AudioManager.play_sfx(&"chest_locked", global_position)
			_shake()
			return
		var ns := get_tree().get_first_node_in_group("net_game") as NetSync
		if ns:
			ns.request_chest_open.rpc_id(1, net_seq, has_key)
		return
	if locked:
		var hero: Hero = player.hero
		if hero.inventory.remove_by_id(&"key", 1) == 0:
			EventBus.message.emit("Сундук заперт. Нужен ключ.")
			AudioManager.play_sfx(&"chest_locked", global_position)
			_shake()
			return
		unlock()
	open()


func unlock() -> void:
	locked = false
	EventBus.message.emit("Замок открыт")


func open(opener_peer: int = 1, consume_key := false) -> void:
	opened = true
	AudioManager.play_sfx(&"chest_open", global_position)
	sprite.play(&"opening")
	sprite.animation_finished.connect(func() -> void: sprite.play(&"open"), CONNECT_ONE_SHOT)
	var table := ItemDatabase.get_loot_table(table_override if table_override != &"" else TIER_TABLES[tier])
	var loot: Array = table.roll(floor_number) if table else []
	if not loot.is_empty():
		Fx.loot_popup(get_parent(), global_position + Vector2(0, -12), loot)
		# Items jump out when the lid is up.
		var pos := global_position + Vector2(0, -10)
		get_tree().create_timer(0.25).timeout.connect(func() -> void: EventBus.spawn_items.emit(pos, loot))
	Fx.sparks(get_parent(), global_position + Vector2(0, -10), Color(1.0, 0.85, 0.4), 10, 70.0)
	EventBus.chest_opened.emit(self)
	if Net.active and Net.is_host:
		var ns := get_tree().get_first_node_in_group("net_game") as NetSync
		if ns:
			ns.broadcast_chest(net_seq, opener_peer, consume_key)


func _shake() -> void:
	var tw := create_tween()
	for i in 3:
		tw.tween_property(sprite, "position:x", 2.0, 0.04)
		tw.tween_property(sprite, "position:x", -2.0, 0.04)
	tw.tween_property(sprite, "position:x", 0.0, 0.04)
