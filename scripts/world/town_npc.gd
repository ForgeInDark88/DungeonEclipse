class_name TownNpc
extends Area2D
## A person living in the town: strolls near their door (or the square),
## shows "!" when they have something new to say, talks (DialogBook) on E.

const WANDER := 26.0
const SPEED := 12.0

var data: NpcData
var _sprite: Sprite2D
var _mark: Label
var _home_x := 0.0
var _target := 0.0
var _wait := 0.0


func setup(p_data: NpcData) -> void:
	data = p_data


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("town_npcs")
	collision_layer = 16
	collision_mask = 0
	monitoring = false
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(18, 30)
	shape.shape = rect
	shape.position = Vector2(0, -15)
	add_child(shape)
	_sprite = Sprite2D.new()
	_sprite.texture = data.sprite
	_sprite.centered = false
	_sprite.offset = Vector2(-10, -30)
	add_child(_sprite)
	_mark = UIStyle.outlined_label("!", 10, UIStyle.GOLD)
	_mark.position = Vector2(-3, -46)
	add_child(_mark)
	_home_x = position.x
	_target = _home_x
	_wait = randf_range(0.5, 3.0)
	refresh_mark()


func refresh_mark() -> void:
	_mark.visible = Dialogs.has_news(data)


func _process(delta: float) -> void:
	if _mark.visible:
		_mark.position.y = -46 + sin(Time.get_ticks_msec() / 200.0) * 1.5
	if _wait > 0.0:
		_wait -= delta
		return
	var dx := _target - position.x
	if absf(dx) < 1.0:
		_wait = randf_range(1.5, 4.0)
		_target = _home_x + randf_range(-WANDER, WANDER)
		return
	position.x += signf(dx) * minf(absf(dx), SPEED * delta)
	_sprite.flip_h = dx < 0.0


func get_prompt() -> String:
	return tr("Поговорить: %s") % data.display_name


func interact(_player: Node) -> void:
	AudioManager.play_ui(&"ui_book_open")
	var book := DialogBook.new()
	get_tree().current_scene.add_child(book)
	book.open(data)
	book.closed.connect(func() -> void:
		for n in get_tree().get_nodes_in_group("town_npcs"):
			(n as TownNpc).refresh_mark())
