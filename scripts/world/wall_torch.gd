class_name WallTorch
extends Node2D
## Flickering wall torch: animated flame + warm light with noisy energy.

var light_color := Color(1.0, 0.62, 0.3)
var _t := 0.0
var _base_energy := 1.0
var _core: PointLight2D

@onready var flame: AnimatedSprite2D = $Flame
@onready var light: PointLight2D = $PointLight2D


func _ready() -> void:
	AssetPaths.layout(AssetPaths.TORCH_LAYOUT).apply_to(flame, AssetPaths.tex(AssetPaths.TORCH_SHEET))
	flame.play(&"burn")
	flame.frame = randi() % 6
	light.texture = AssetPaths.tex(AssetPaths.LIGHT)
	light.color = light_color
	_base_energy = light.energy
	# A tight bright core on the wall around the flame: the wide light
	# alone melts into the ambient, this gives the torch its warm pool.
	_core = PointLight2D.new()
	_core.texture = light.texture
	_core.color = light_color.lerp(Color(1, 0.95, 0.8), 0.25)
	_core.energy = 0.9
	_core.texture_scale = 0.32
	_core.position = light.position
	add_child(_core)
	_t = randf() * 10.0


func _process(delta: float) -> void:
	_t += delta
	var flick := sin(_t * 9.0) * 0.08 + sin(_t * 23.0) * 0.06 + randf_range(-0.04, 0.04)
	light.energy = _base_energy + flick
	_core.energy = 0.9 + flick * 1.5
