class_name TownBuilding
extends Area2D
## A building of the town on its foundation: ruins until built, then its
## house; upgrades hang banners, light lanterns, make the chimney smoke.
## Interact (E) to open its book (BuildingBook): build / upgrade, and what
## the building does.

var data: BuildingData
var _sprite: Sprite2D
var _decor: Node2D


func setup(p_data: BuildingData) -> void:
	data = p_data


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("town_buildings")
	collision_layer = 16
	collision_mask = 0
	monitoring = false
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(maxf(24.0, data.width * 16.0 - 16.0), 34)
	shape.shape = rect
	shape.position = Vector2(0, -17)
	add_child(shape)
	_sprite = Sprite2D.new()
	_sprite.centered = false
	_sprite.z_index = -2
	add_child(_sprite)
	refresh()


func level() -> int:
	return Buildings.level(data.id)


## Redraws the building for its current level.
func refresh() -> void:
	var lvl := level()
	var tex: Texture2D = data.texture if lvl > 0 else AssetPaths.tex(AssetPaths.TOWN_DIR + "ruins.png")
	_sprite.texture = tex
	_sprite.offset = Vector2(-floorf(tex.get_width() / 2.0), -tex.get_height())
	_sprite.modulate = Color.WHITE if lvl > 0 else Color(0.85, 0.82, 0.8)
	if _decor:
		_decor.queue_free()
	_decor = Node2D.new()
	_decor.z_index = -1
	add_child(_decor)
	var top := -tex.get_height()
	var half := tex.get_width() / 2.0
	if lvl == 0:
		# A notice on the lot when it can be built right now.
		if Buildings.block_reason(data) == "":
			_add_sprite("signpost", Vector2(half - 6, 0))
		var icon := AssetPaths.building_icon(data.id)
		if icon:
			var post := Sprite2D.new()
			post.texture = icon
			post.position = Vector2(0, top - 10)
			_decor.add_child(post)
			var tw := post.create_tween().set_loops()
			tw.tween_property(post, "position:y", top - 12.0, 0.9).set_trans(Tween.TRANS_SINE)
			tw.tween_property(post, "position:y", top - 10.0, 0.9).set_trans(Tween.TRANS_SINE)
		return
	if lvl >= 2:
		_add_sprite("banner_red", Vector2(-half + 4, top + 2))
		_lantern(Vector2(0, -20), 0.75)
	if lvl >= 3:
		_add_sprite("banner_gold", Vector2(half - 10, top + 2))
		_lantern(Vector2(-half + 8, -26), 0.6)
		if data.chimney != Vector2.ZERO:
			_smoke(Vector2(-half + data.chimney.x, top + data.chimney.y))


func _add_sprite(name: String, pos: Vector2) -> void:
	var s := Sprite2D.new()
	s.texture = AssetPaths.tex(AssetPaths.TOWN_DIR + name + ".png")
	s.centered = false
	s.position = pos - Vector2(0, s.texture.get_height() if s.texture else 0)
	_decor.add_child(s)


func _lantern(pos: Vector2, energy: float) -> void:
	var light := PointLight2D.new()
	light.texture = AssetPaths.tex(AssetPaths.LIGHT)
	light.color = Color(1.0, 0.78, 0.45)
	light.energy = energy * (1.6 if Buildings.is_night() else 1.0)
	light.texture_scale = 0.45
	light.position = pos
	_decor.add_child(light)


func _smoke(pos: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.amount = 12
	p.lifetime = 3.0
	p.preprocess = 3.0
	p.position = pos
	p.direction = Vector2(0.3, -1)
	p.spread = 12.0
	p.gravity = Vector2(4, -6)
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 12.0
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.0
	p.color = Color(0.75, 0.72, 0.7, 0.45)
	_decor.add_child(p)


## The build / upgrade moment: dust and sparks, then the new look.
func play_built() -> void:
	refresh()
	Fx.sparks(get_parent(), global_position + Vector2(0, -20), Color(1.0, 0.85, 0.5), 30, 120.0)
	EventBus.screen_shake.emit(2.0)
	AudioManager.play_sfx(&"level_up", global_position)


func get_prompt() -> String:
	var lvl := level()
	if lvl == 0:
		return tr("%s (руины) — построить") % data.display_name
	return tr("%s, ур. %d") % [data.display_name, lvl]


func interact(_player: Node) -> void:
	AudioManager.play_ui(&"ui_book_open")
	var book := BuildingBook.new()
	get_tree().current_scene.add_child(book)
	book.open(self)
