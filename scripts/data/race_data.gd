class_name RaceData
extends Resource
## A playable race. Bonuses are added on top of the class base stats.

@export var id: StringName
@export var display_name: String = ""
## Position in the character creation list (lower = first).
@export var order: int = 0
@export_multiline var description: String = ""
## Face layer of the HUD portrait.
@export var portrait: Texture2D
## Flat bonuses, keyed by StatTypes names.
@export var stat_bonuses: Dictionary = {}
