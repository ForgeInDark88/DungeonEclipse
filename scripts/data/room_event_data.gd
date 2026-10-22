class_name RoomEventData
extends Resource
## A random event room (altar, fountain, cursed chest, puzzle, prisoner...).
## The generator reserves side rooms; DungeonLevel picks an event by weight
## and spawns its scene. Scenes may implement setup_event(level, info) where
## info = {"cell": Vector2i, "room": Rect2i}.

@export var id: StringName
@export var display_name: String = ""
@export_file("*.tscn") var scene: String = ""
@export var weight: float = 1.0
@export var min_floor: int = 1
