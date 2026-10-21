class_name QuickBar
extends RefCounted
## Quick access slots (keys 1-7). A slot references an item; the amount shown
## is what the inventory holds, and using it spends from the inventory.

signal changed

const SIZE := 7

var items: Array[ItemData] = []


func _init() -> void:
	items.resize(SIZE)


func get_item(index: int) -> ItemData:
	return items[index] if index >= 0 and index < SIZE else null


func assign(index: int, item: ItemData) -> void:
	if index < 0 or index >= SIZE:
		return
	# One item per bar: moving it clears the old position.
	for i in SIZE:
		if items[i] == item and i != index:
			items[i] = null
	items[index] = item
	changed.emit()


func clear(index: int) -> void:
	if index >= 0 and index < SIZE and items[index] != null:
		items[index] = null
		changed.emit()


func swap(a: int, b: int) -> void:
	var tmp := items[a]
	items[a] = items[b]
	items[b] = tmp
	changed.emit()


func first_free() -> int:
	return items.find(null)
