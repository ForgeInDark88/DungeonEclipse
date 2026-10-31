class_name LoreNote
extends Area2D
## A note lying in the dungeon: a journal on a stone lectern (a bottle in the
## Drowned Vaults). Interact to read it; the first reading adds it to the
## Codex. Unread notes glow and shed motes, read ones are dim.
## Co-op: every machine builds the same note from the floor seed; reading is
## personal (each player's own Codex), nothing goes over the net.

var lore: LoreData
var _sprite: Sprite2D
var _light: PointLight2D
var _motes: CPUParticles2D


func _ready() -> void:
	add_to_group("interactable")
	collision_layer = 16
	collision_mask = 0
	monitoring = false
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(20, 24)
	shape.shape = rect
	shape.position = Vector2(0, -12)
	add_child(shape)
	var bottle := lore != null and lore.biome == &"drowned_vaults"
	_sprite = Sprite2D.new()
	_sprite.texture = AssetPaths.tex(AssetPaths.SPRITES_DIR + ("props/lore_bottle.png" if bottle else "props/lore_note.png"))
	_sprite.centered = false
	_sprite.offset = Vector2(-_sprite.texture.get_width() / 2.0, -_sprite.texture.get_height())
	add_child(_sprite)
	_light = PointLight2D.new()
	_light.texture = AssetPaths.tex(AssetPaths.LIGHT)
	_light.color = Color(1.0, 0.88, 0.6)
	_light.texture_scale = 0.25
	_light.position = Vector2(0, -14)
	add_child(_light)
	_motes = CPUParticles2D.new()
	_motes.amount = 6
	_motes.lifetime = 1.6
	_motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_motes.emission_rect_extents = Vector2(5, 2)
	_motes.position = Vector2(0, -14)
	_motes.direction = Vector2.UP
	_motes.gravity = Vector2(0, -12)
	_motes.initial_velocity_min = 2.0
	_motes.initial_velocity_max = 6.0
	_motes.color = Color(1.0, 0.92, 0.65, 0.8)
	var m := CanvasItemMaterial.new()
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_motes.material = m
	add_child(_motes)
	_refresh()


func _refresh() -> void:
	var read := lore != null and Codex.is_lore_read(lore.id)
	_motes.emitting = not read
	_light.energy = 0.35 if read else 0.9
	_sprite.modulate = Color(0.8, 0.8, 0.8) if read else Color.WHITE


func can_interact() -> bool:
	return lore != null


func get_prompt() -> String:
	if lore == null:
		return ""
	return tr("Прочитать: «%s»") % lore.title if not Codex.is_lore_read(lore.id) else tr("Перечитать: «%s»") % lore.title


func interact(_player: Node) -> void:
	if lore == null:
		return
	var first := not Codex.is_lore_read(lore.id)
	if first:
		Codex.read_lore(lore.id)
		EventBus.message.emit(tr("Новая запись в Летописи: «%s»") % lore.title)
	AudioManager.play_ui(&"ui_book_open")
	var book := LoreBook.new()
	get_tree().current_scene.add_child(book)
	book.open(lore)
	_refresh()
