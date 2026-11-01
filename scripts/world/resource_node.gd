class_name ResourceNode
extends Area2D
## Something to gather on the surface (SurfaceGenerator layout.resources):
## a tree (wood), a boulder (stone), an ore vein (iron and iron ore), herbs,
## a berry bush, a buried treasure under a cross (needs a shovel). E works
## it; a tool in the backpack (hatchet, pickaxe) doubles the yield. Town
## resources go into the expedition's haul (they reach the town with a
## living hero); items into the backpack. Personal in co-op: every machine
## gathers its own (like the loot of a world session).

const KINDS := {
	&"tree": {"res": &"wood", "tool": &"hatchet", "charges": 2, "verb": "Срубить", "sprite": ""},
	&"boulder": {"res": &"stone", "tool": &"pickaxe", "charges": 2, "verb": "Разбить камень", "sprite": ""},
	&"vein": {"res": &"iron", "tool": &"pickaxe", "item": &"iron_ore", "charges": 2, "verb": "Добыть руду", "sprite": "ore_vein"},
	&"herb": {"res": &"herbs", "tool": &"", "charges": 1, "verb": "Собрать травы", "sprite": "herb"},
	&"berries": {"item": &"wild_berries", "tool": &"", "charges": 1, "verb": "Собрать ягоды", "sprite": "berry_bush"},
	&"dig": {"tool": &"shovel", "need_tool": true, "charges": 1, "verb": "Копать клад", "sprite": "dig_mark"},
}

var kind: StringName = &"tree"
var net_seq := 0
var depth := 1
var charges := 1
var _cool := 0.0
var _sprite: Sprite2D


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("resource_nodes")
	collision_layer = 16
	collision_mask = 0
	monitoring = false
	var info: Dictionary = KINDS.get(kind, KINDS[&"herb"])
	charges = int(info["charges"])
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(22, 22)
	shape.shape = rect
	shape.position = Vector2(0, -11)
	add_child(shape)
	if String(info["sprite"]) != "":
		_sprite = Sprite2D.new()
		_sprite.texture = AssetPaths.tex("res://assets/sprites/surface/%s.png" % info["sprite"])
		if _sprite.texture:
			_sprite.offset = Vector2(0, -_sprite.texture.get_height() / 2.0)
		add_child(_sprite)


func _process(delta: float) -> void:
	_cool = maxf(0.0, _cool - delta)


func can_interact() -> bool:
	return charges > 0


func _tool() -> StringName:
	return StringName(KINDS[kind].get("tool", &""))


## In the backpack or in hand (the hatchet is also a weapon).
func _has_tool() -> bool:
	var t := _tool()
	var hero: Hero = GameState.hero
	if t == &"" or hero == null:
		return false
	if hero.inventory.count_of(t) > 0:
		return true
	for slot in hero.equipment.items:
		var it: ItemData = hero.equipment.items[slot]
		if it and (it.id == t or (it.template != null and it.template.id == t)):
			return true
	return false


func get_prompt() -> String:
	var info: Dictionary = KINDS[kind]
	var text := tr(String(info["verb"]))
	if bool(info.get("need_tool", false)) and not _has_tool():
		return tr("%s: нужна лопата") % text
	if _tool() != &"" and not _has_tool():
		var td := ItemDatabase.get_item(_tool())
		text += tr(" (с инструментом «%s» — вдвое больше)") % (td.display_name if td else String(_tool()))
	return text


func interact(_player: Node) -> void:
	if charges <= 0 or _cool > 0.0:
		return
	var info: Dictionary = KINDS[kind]
	if bool(info.get("need_tool", false)) and not _has_tool():
		EventBus.message.emit(get_prompt())
		AudioManager.play_sfx(&"chest_locked", global_position, -6.0)
		return
	_cool = 0.45
	charges -= 1
	var mult := 2 if _has_tool() else 1
	AudioManager.play_sfx(&"dig", global_position, -4.0)
	Fx.sparks(get_parent(), global_position + Vector2(0, -10), Color(0.8, 0.7, 0.5), 8, 60.0)
	if info.has("res"):
		GameFlow.gain_resource(StringName(info["res"]), mult, global_position)
	if info.has("item"):
		_give(StringName(info["item"]), mult)
	if kind == &"dig":
		_treasure()
	EventBus.resource_gathered.emit(kind)
	if charges <= 0:
		_spent()


func _give(id: StringName, count: int) -> void:
	var it := ItemDatabase.get_item(id)
	if it:
		EventBus.spawn_items.emit(global_position + Vector2(0, -12), [{"item": it, "count": count}])


## A buried chest: gold, sometimes a blueprint of the town, sometimes an item.
func _treasure() -> void:
	var gold := 15 + depth * 6 + randi_range(0, 10 + depth * 2)
	if GameState.hero:
		GameState.hero.add_gold(gold)
	EventBus.floating_text.emit(global_position + Vector2(0, -20), "+%d" % gold, Color(1, 0.85, 0.3))
	if randf() < 0.25 and GameState.run and GameState.town:
		var bp := GameFlow.roll_blueprint()
		if bp != &"":
			GameState.run.blueprints.append(bp)
			var bd := ItemDatabase.building(bp)
			EventBus.message.emit(tr("В кладе — чертёж: %s!") % (bd.display_name if bd else String(bp)))
			return
	EventBus.message.emit(tr("Клад: %d золота.") % gold)


func _spent() -> void:
	remove_from_group("interactable")
	if _sprite:
		var tw := create_tween()
		tw.tween_property(_sprite, "modulate:a", 0.0 if kind in [&"dig", &"herb", &"berries"] else 0.45, 0.4)
