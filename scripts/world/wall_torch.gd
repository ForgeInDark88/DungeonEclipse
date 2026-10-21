class_name WallTorch
extends Node2D
## Flickering wall torch: animated flame + warm light with noisy energy.

var _t := 0.0
var _base_energy := 1.0

@onready var flame: AnimatedSprite2D = $Flame
@onready var light: PointLight2D = $PointLight2D


func _ready() -> void:
	AssetPaths.layout(AssetPaths.TORCH_LAYOUT).apply_to(flame, AssetPaths.tex(AssetPaths.TORCH_SHEET))
	flame.play(&"burn")
	flame.frame = randi() % 6
	light.texture = AssetPaths.tex(AssetPaths.LIGHT)
	_base_energy = light.energy
	_t = randf() * 10.0


func _process(delta: float) -> void:
	_t += delta
	light.energy = _base_energy + sin(_t * 9.0) * 0.08 + sin(_t * 23.0) * 0.06 + randf_range(-0.04, 0.04)
