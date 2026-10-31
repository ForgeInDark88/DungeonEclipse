extends Area2D
## Puzzle lever with a rune drawn above it.

var rune := 0
var puzzle: Node
var down := false

@onready var sprite: AnimatedSprite2D = $Sprite


func _ready() -> void:
	add_to_group("interactable")
	AssetPaths.layout(AssetPaths.LEVER_LAYOUT).apply_to(sprite, AssetPaths.tex(AssetPaths.LEVER_SHEET))
	sprite.play(&"up")
	var r := Sprite2D.new()
	r.texture = AssetPaths.tex(AssetPaths.RUNES)
	r.region_enabled = true
	r.region_rect = Rect2(rune * 8, 0, 8, 8)
	r.position = Vector2(0, -22)
	var m := CanvasItemMaterial.new()
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	r.material = m
	add_child(r)


func can_interact() -> bool:
	return not down


func get_prompt() -> String:
	return tr("Потянуть рычаг")


func interact(player: Node) -> void:
	puzzle.pull(self, player)


func set_down(value: bool) -> void:
	down = value
	sprite.play(&"down" if down else &"up")
