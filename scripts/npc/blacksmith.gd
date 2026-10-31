class_name Blacksmith
extends Area2D
## Dwarf blacksmith at an anvil in a side room: upgrades, enchants, smelts and
## repairs gear (rules in Smithing, UI in SmithBook).

@onready var sprite: AnimatedSprite2D = $Sprite


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("smiths")
	AssetPaths.layout(AssetPaths.MERCHANT_LAYOUT).apply_to(sprite, AssetPaths.tex(AssetPaths.BLACKSMITH_SHEET))
	sprite.play(&"idle")


func get_prompt() -> String:
	return tr("Кузница")


func interact(player: Node) -> void:
	sprite.play(&"greet")
	sprite.animation_finished.connect(func() -> void: sprite.play(&"idle"), CONNECT_ONE_SHOT)
	AudioManager.play_sfx(&"dig", global_position)
	EventBus.smith_requested.emit(self, player)
