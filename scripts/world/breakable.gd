class_name Breakable
extends Area2D
## A barrel or a crate on the surface (bandits' stores, a trader's spilled
## cargo): E smashes it, a bomb blast too. Inside: a little gold or a small
## supply (data/loot_tables/supplies_small.tres). Personal in co-op.

const TABLE := "res://data/loot_tables/supplies_small.tres"

var look: StringName = &"crate"
var net_seq := 0
var depth := 1
var broken := false
var _sprite: Sprite2D


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("breakables")
	collision_layer = 16
	collision_mask = 0
	monitoring = false
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(16, 16)
	shape.shape = rect
	shape.position = Vector2(0, -8)
	add_child(shape)
	_sprite = Sprite2D.new()
	_sprite.texture = AssetPaths.tex("res://assets/sprites/surface/%s.png" % look)
	if _sprite.texture:
		_sprite.offset = Vector2(0, -_sprite.texture.get_height() / 2.0)
	add_child(_sprite)


func can_interact() -> bool:
	return not broken


func get_prompt() -> String:
	return tr("Разбить бочку") if look == &"barrel" else tr("Разбить ящик")


func interact(_player: Node) -> void:
	smash()


func smash() -> void:
	if broken:
		return
	broken = true
	remove_from_group("interactable")
	AudioManager.play_sfx(&"chest_open", global_position, -4.0)
	Fx.sparks(get_parent(), global_position + Vector2(0, -8), Color(0.7, 0.5, 0.3), 12, 80.0)
	if randf() < 0.5:
		var gold := 2 + depth + randi_range(0, 4 + depth)
		if GameState.hero:
			GameState.hero.add_gold(gold)
		EventBus.floating_text.emit(global_position + Vector2(0, -14), "+%d" % gold, Color(1, 0.85, 0.3))
	else:
		var table := load(TABLE) as LootTable
		if table:
			var stacks := table.roll(depth)
			if not stacks.is_empty():
				EventBus.spawn_items.emit(global_position + Vector2(0, -10), stacks)
	var tw := create_tween()
	tw.tween_property(_sprite, "modulate:a", 0.0, 0.3)  # stays (the saved state counts it)
