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
## Animated body layer of the hero (layout: data/animations/hero_layout.tres).
@export var body_sheet: Texture2D
## Size of the in-world hero (dwarves are short and wide, elves are tall).
@export var sprite_scale: Vector2 = Vector2.ONE
## Price in the Sanctum of the Eclipse; 0/0 = available from the start.
@export var unlock_shards: int = 0
@export var unlock_gold: int = 0
