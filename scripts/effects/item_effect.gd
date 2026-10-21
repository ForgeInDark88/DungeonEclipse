class_name ItemEffect
extends Resource
## Base class for what a usable item does. Create a new script extending
## ItemEffect, override apply() and attach it to an UsableItemData in the
## inspector: no core code has to change.


## `user` is the Player node. Return true if the effect happened
## (only then a consumable is spent).
func apply(_user: Node) -> bool:
	return false


## Line for the item tooltip.
func describe() -> String:
	return ""
