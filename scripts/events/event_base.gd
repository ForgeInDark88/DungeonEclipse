class_name EventObject
extends Area2D
## Base for one-shot interactable event objects (altar, fountain, cage...).
## Child scripts override _activate(player) and get_prompt().

@export var sheet_path: String
@export var layout_path: String
@export var idle_anim: StringName = &"idle"
@export var used_anim: StringName = &"used"

var used := false
var level: DungeonLevel
## LAN co-op: deterministic event identity (requests and snapshots).
var net_seq := 0
## Host: the guest this event was granted to, and how many world actions
## (loot rolls, ambushes) it already asked for - a cap against spam.
var net_grantee := 0
var net_world_calls := 0

@onready var sprite: AnimatedSprite2D = $Sprite


func setup_event(p_level: DungeonLevel, _info: Dictionary) -> void:
	level = p_level


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("events")
	if sheet_path != "":
		AssetPaths.layout(layout_path).apply_to(sprite, AssetPaths.tex(sheet_path))
		sprite.play(idle_anim)


func can_interact() -> bool:
	return not used


func get_prompt() -> String:
	return ""


func interact(player: Node) -> void:
	if used:
		return
	if Net.active and not Net.is_host:
		# Co-op guest: the host books the event (one use for everybody), then
		# grants it back - the effect lands on OUR hero, not on its mirror.
		if not can_activate(player):
			return
		var ns = get_tree().get_first_node_in_group("net_game")
		if ns:
			ns.request_event_use.rpc_id(1, net_seq)
		return
	if _activate(player):
		finish()


## Checked by a guest before asking the host (conditions on its own hero).
func can_activate(_player: Node) -> bool:
	return true


## Guest: the host booked the event for us - apply it to our hero.
func net_granted(player: Node) -> void:
	_activate(player)


## Marks the event as used (events with a choice window call it themselves).
func finish() -> void:
	used = true
	EventBus.event_completed.emit(self)
	if Net.active and Net.is_host:
		var ns = get_tree().get_first_node_in_group("net_game")
		if ns:
			ns.event_used.rpc(net_seq)
	if sprite.sprite_frames and sprite.sprite_frames.has_animation(used_anim):
		sprite.play(used_anim)
	var light := get_node_or_null("PointLight2D") as PointLight2D
	if light:
		create_tween().tween_property(light, "energy", 0.15, 1.0)


## Returns true when the event is consumed.
func _activate(_player: Node) -> bool:
	return false


func _reward_item(table_name: StringName, floor_number: int) -> void:
	if _ask_host(&"loot", table_name, floor_number, 0.0):
		return
	var table := ItemDatabase.get_loot_table(table_name)
	if table:
		var loot := table.roll(floor_number)
		EventBus.spawn_items.emit(global_position + Vector2(0, -16), loot)
		Fx.loot_popup(get_parent(), global_position + Vector2(0, -20), loot)


## Monsters jumping out (cursed chests, fake prisoners).
func _ambush(count: int, elite_chance: float) -> void:
	if _ask_host(&"ambush", &"", count, elite_chance):
		return
	if level == null:
		return
	var pool := ItemDatabase.enemies_for_floor(level.floor_number, level.biome.id if level.biome else &"")
	pool.assign(pool.filter(func(e: EnemyData) -> bool: return not e.ceiling_ambush))
	if pool.is_empty():
		return
	for i in count:
		var data: EnemyData = pool.pick_random()
		var elite: EliteAffixData = ItemDatabase.elites.pick_random() if randf() < elite_chance and not ItemDatabase.elites.is_empty() else null
		var e: Enemy = (load("res://scenes/enemies/enemy.tscn") as PackedScene).instantiate()
		e.setup(data, level.floor_number, elite)
		# Ambush enemies are dynamically spawned after the floor build: they
		# must use the same authoritative id/descriptor path as floor mobs.
		level._net_tag(e)
		var side := -1.0 if i % 2 == 0 else 1.0
		level.add_entity(e, global_position + Vector2(side * (24.0 + i * 10.0), -4.0))
		level._net_broadcast_enemy(e, elite, false)
		Fx.sparks(level.entities, e.global_position + Vector2(0, -8), Color(0.7, 0.3, 1.0), 14, 80.0)
	EventBus.screen_shake.emit(4.0)


## Co-op guest: loot and monsters belong to the shared world - the host
## makes them (for everyone). Returns true when the request was sent.
func _ask_host(kind: StringName, table_name: StringName, number: int, chance: float) -> bool:
	if not Net.active or Net.is_host:
		return false
	var ns = get_tree().get_first_node_in_group("net_game")
	if ns:
		ns.request_event_world.rpc_id(1, net_seq, kind, table_name, number, chance)
	return true
