class_name Inventory
extends RefCounted
## Backpack logic: fixed number of slots, stacking, moving. No UI here;
## the UI listens to `changed`.

signal changed
signal item_added(item: ItemData, count: int)

var slots: Array[ItemStack] = []


func _init(capacity: int = 30) -> void:
	slots.resize(capacity)


func capacity() -> int:
	return slots.size()


func stack_at(index: int) -> ItemStack:
	if index < 0 or index >= slots.size():
		return null
	return slots[index]


## Adds items, filling existing stacks first. Returns how many did NOT fit.
func add_item(item: ItemData, count: int = 1) -> int:
	if item == null or count <= 0:
		return count
	var left := count
	if item.is_stackable():
		for stack in slots:
			if left == 0:
				break
			if stack != null and stack.item == item and stack.space_left() > 0:
				var moved := mini(left, stack.space_left())
				stack.count += moved
				left -= moved
	for i in slots.size():
		if left == 0:
			break
		if slots[i] == null:
			var moved := mini(left, item.max_stack)
			slots[i] = ItemStack.new(item, moved)
			left -= moved
	if left != count:
		item_added.emit(item, count - left)
		changed.emit()
	return left


## How many of `item` can still be added.
func free_space_for(item: ItemData) -> int:
	var space := 0
	for stack in slots:
		if stack == null:
			space += item.max_stack
		elif stack.item == item:
			space += stack.space_left()
	return space


func count_of(item_id: StringName) -> int:
	var total := 0
	for stack in slots:
		if stack != null and stack.item.id == item_id:
			total += stack.count
	return total


func find_index(item_id: StringName) -> int:
	for i in slots.size():
		if slots[i] != null and slots[i].item.id == item_id:
			return i
	return -1


## Removes `count` of an item anywhere in the backpack. Returns removed amount.
func remove_by_id(item_id: StringName, count: int = 1) -> int:
	var removed := 0
	for i in range(slots.size() - 1, -1, -1):
		if removed == count:
			break
		var stack := slots[i]
		if stack != null and stack.item.id == item_id:
			var take := mini(count - removed, stack.count)
			stack.count -= take
			removed += take
			if stack.count <= 0:
				slots[i] = null
	if removed > 0:
		changed.emit()
	return removed


## Removes from a given slot. Returns the removed stack (or null).
func take_at(index: int, count: int = -1) -> ItemStack:
	var stack := stack_at(index)
	if stack == null:
		return null
	if count < 0 or count >= stack.count:
		slots[index] = null
		changed.emit()
		return stack
	stack.count -= count
	changed.emit()
	return ItemStack.new(stack.item, count)


## Puts a stack into an exact slot. Returns what could not be placed
## (the previous content when swapping is not possible is handled by callers).
func put_at(index: int, stack: ItemStack) -> ItemStack:
	if stack == null:
		return null
	var current := stack_at(index)
	if current == null:
		slots[index] = stack
		changed.emit()
		return null
	if current.item == stack.item and current.space_left() > 0:
		var moved := mini(stack.count, current.space_left())
		current.count += moved
		stack.count -= moved
		changed.emit()
		return stack if stack.count > 0 else null
	return stack


## Drag & drop inside the backpack: merge stacks of the same item or swap.
func move(from: int, to: int) -> void:
	if from == to:
		return
	var a := stack_at(from)
	var b := stack_at(to)
	if a == null:
		return
	if b != null and b.item == a.item and b.space_left() > 0:
		var moved := mini(a.count, b.space_left())
		b.count += moved
		a.count -= moved
		if a.count <= 0:
			slots[from] = null
	else:
		slots[from] = b
		slots[to] = a
	changed.emit()


func is_full() -> bool:
	return not slots.has(null)
