class_name FishingSpot
extends Area2D
## A dark pool in the Drowned Vaults: interact to fish (FishingGame). Three
## catches, then the fish leave. Personal in co-op: each machine has its
## own copy of the spot and the catch goes straight into the hero's bag.

const USES := 3

var uses_left := USES
var _sprite: Sprite2D
var _bubbles: CPUParticles2D


func _ready() -> void:
	add_to_group("interactable")
	collision_layer = 16
	collision_mask = 0
	monitoring = false
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(32, 18)
	shape.shape = rect
	shape.position = Vector2(0, -9)
	add_child(shape)
	_sprite = Sprite2D.new()
	_sprite.texture = AssetPaths.tex(AssetPaths.SPRITES_DIR + "props/fishing_spot.png")
	_sprite.centered = false
	_sprite.offset = Vector2(-16, -16)
	_sprite.z_index = -1
	add_child(_sprite)
	_bubbles = CPUParticles2D.new()
	_bubbles.amount = 5
	_bubbles.lifetime = 1.4
	_bubbles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_bubbles.emission_rect_extents = Vector2(10, 1)
	_bubbles.position = Vector2(-2, -4)
	_bubbles.direction = Vector2.UP
	_bubbles.gravity = Vector2(0, -10)
	_bubbles.initial_velocity_min = 3.0
	_bubbles.initial_velocity_max = 8.0
	_bubbles.color = Color(0.7, 0.95, 1.0, 0.7)
	add_child(_bubbles)


func can_interact() -> bool:
	return true


func get_prompt() -> String:
	return tr("Рыбачить (ещё %d)") % uses_left if uses_left > 0 else tr("Рыба ушла из этого омута")


func interact(player: Node) -> void:
	if uses_left <= 0:
		EventBus.message.emit(tr("Вода неподвижна: рыба ушла."))
		return
	var game := FishingGame.new()
	get_tree().current_scene.add_child(game)
	game.open(self, player as Player)


## FishingGame calls it after a catch.
func caught() -> void:
	uses_left -= 1
	if uses_left <= 0:
		_bubbles.emitting = false
		_sprite.modulate = Color(0.75, 0.75, 0.8)
