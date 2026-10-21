class_name ItemStack
extends RefCounted
## An item plus amount, stored in an Inventory slot.

var item: ItemData
var count: int = 1


func _init(p_item: ItemData = null, p_count: int = 1) -> void:
	item = p_item
	count = p_count


func space_left() -> int:
	return item.max_stack - count
