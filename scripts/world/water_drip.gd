class_name WaterDrip
extends Node2D
## Drop that forms on the ceiling, falls until it hits ground and splashes.

const GRAVITY := 500.0

var level: DungeonLevel
var _wait := 0.0
var _speed := 0.0
var _falling := false

@onready var drop: AnimatedSprite2D = $Drop


func _ready() -> void:
	AssetPaths.layout(AssetPaths.DROP_LAYOUT).apply_to(drop, AssetPaths.tex(AssetPaths.DROP_SHEET))
	drop.animation_finished.connect(_reset)
	_reset()
	_wait = randf_range(0.0, 3.0)


func _reset() -> void:
	drop.position = Vector2.ZERO
	drop.visible = false
	_falling = false
	_speed = 0.0
	_wait = randf_range(1.5, 4.5)


func _process(delta: float) -> void:
	if _wait > 0.0:
		_wait -= delta
		if _wait <= 0.0:
			drop.visible = true
			drop.play(&"fall")
			_falling = true
		return
	if not _falling:
		return
	_speed = minf(_speed + GRAVITY * delta, 300.0)
	drop.position.y += _speed * delta
	var p := global_position + drop.position
	if level == null or level.is_ground_at(p) or drop.position.y > 400.0:
		_falling = false
		drop.position.y = floorf(p.y / 16.0) * 16.0 - global_position.y
		drop.play(&"splash")
