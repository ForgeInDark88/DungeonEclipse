class_name Chronicler
extends Area2D
## The town chronicler by the chapel: collects the notes heroes bring back
## from below. Interact to open the chronicle (ChroniclerBook): chapters by
## place, rewards for complete chapters, and his words on how far the story
## has come - including the hint to the secret ending.

var _sprite: Sprite2D


func _ready() -> void:
	add_to_group("interactable")
	collision_layer = 16
	collision_mask = 0
	monitoring = false
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(22, 30)
	shape.shape = rect
	shape.position = Vector2(0, -15)
	add_child(shape)
	_sprite = Sprite2D.new()
	_sprite.texture = AssetPaths.tex(AssetPaths.SPRITES_DIR + "npc/chronicler.png")
	_sprite.centered = false
	_sprite.offset = Vector2(-8, -30)
	add_child(_sprite)
	var light := PointLight2D.new()
	light.texture = AssetPaths.tex(AssetPaths.LIGHT)
	light.color = Color(1.0, 0.85, 0.55)
	light.texture_scale = 0.35
	light.energy = 0.8
	light.position = Vector2(0, -12)
	add_child(light)
	# Turning a page now and then: a small bob.
	var tw := create_tween().set_loops()
	tw.tween_interval(2.5)
	tw.tween_property(_sprite, "position:y", -1.0, 0.25)
	tw.tween_property(_sprite, "position:y", 0.0, 0.25)


func get_prompt() -> String:
	var ready := ChroniclerBook.claimable_count()
	return tr("Летописец: награды за главы (%d)") % ready if ready > 0 else tr("Летописец")


func interact(_player: Node) -> void:
	AudioManager.play_ui(&"ui_book_open")
	var book := ChroniclerBook.new()
	get_tree().current_scene.add_child(book)
	book.open()
