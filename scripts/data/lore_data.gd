class_name LoreData
extends Resource
## A scrap of the story: a diary page, a decree, a note in a bottle. Found on
## the floors of its biome (in `order` within the biome) or in the arena of
## its guardian (`boss`); read ones are kept in the Codex («Летопись»).

@export var id: StringName
@export var title: String = ""
@export var author: String = ""
@export_multiline var text: String = ""
## Normal floors of this biome show its notes one by one ("" = none).
@export var biome: StringName = &""
## The guardian whose arena holds this note ("" = none).
@export var boss: StringName = &""
@export var order: int = 0
