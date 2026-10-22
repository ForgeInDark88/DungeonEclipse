class_name BossPhase
extends Resource
## A boss phase starts when HP falls to `hp_threshold` (1.0 = first phase).

@export_range(0.0, 1.0) var hp_threshold: float = 1.0
@export var message: String = ""
@export var attacks: Array[BossAttack] = []
## Pause between attacks.
@export var attack_interval: float = 1.6
@export var speed_mult: float = 1.0
@export var tint: Color = Color.WHITE
