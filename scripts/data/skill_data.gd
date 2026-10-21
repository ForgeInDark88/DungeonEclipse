class_name SkillData
extends Resource
## A class skill. Behaviour is in `effect` (a SkillEffect resource).

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D
@export var mana_cost: int = 10
@export var cooldown: float = 3.0
@export_range(1, 5) var max_level: int = 4
@export var effect: SkillEffect
