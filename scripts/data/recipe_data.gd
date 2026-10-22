class_name RecipeData
extends Resource
## A crafting recipe (book tab «Ремесло» in the inventory). Add a .tres to
## data/recipes/: ingredients are item ids with counts, gold is optional.

@export var id: StringName
@export var result: StringName
@export var count: int = 1
## item id -> count
@export var ingredients: Dictionary = {}
@export var gold: int = 0
## Position in the list (lower = first).
@export var order: int = 0
