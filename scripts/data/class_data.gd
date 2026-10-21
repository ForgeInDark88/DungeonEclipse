class_name ClassData
extends Resource
## A playable class: base stats, growth per level, starting kit and skills.

@export var id: StringName
@export var display_name: String = ""
## Position in the character creation list (lower = first).
@export var order: int = 0
@export_multiline var description: String = ""
## Headgear / clothes layer drawn over the race portrait.
@export var portrait_overlay: Texture2D
## In-world sprite of the hero.
@export var sprite: Texture2D
## Animated layers drawn over the race body (same layout as the body sheet).
@export var outfit_sheet: Texture2D
## Headgear when no helmet with its own visual is equipped.
@export var head_sheet: Texture2D
## Base primary attributes, keyed by StatTypes names.
@export var base_stats: Dictionary = {"strength": 5, "agility": 5, "intellect": 5, "vitality": 5}
## Added to primary attributes on every level up.
@export var growth_per_level: Dictionary = {"strength": 1, "agility": 1, "intellect": 1, "vitality": 1}
## Attribute that scales melee damage.
@export var main_attribute: String = "strength"
@export var base_damage: int = 4
## Melee reach in pixels.
@export var attack_range: float = 18.0
@export var attack_cooldown: float = 0.4
## Starting items: ids from ItemDatabase -> count.
@export var starting_items: Dictionary = {}
## Item ids equipped at start (must also be in starting_items).
@export var starting_equipment: Array[StringName] = []
## Item ids placed into the quick bar at start, in order.
@export var starting_quick_bar: Array[StringName] = []
@export var skills: Array[SkillData] = []
