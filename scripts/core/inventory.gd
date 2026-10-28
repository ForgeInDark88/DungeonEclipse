class_name Inventory
extends RefCounted
## Backpack logic: fixed number of slots, stacking, moving. No UI here;
## the UI listens to `changed`.

signal changed
signal item_added(item: ItemData, count: int)

var slots: Array[ItemStack] = []
## The material pouch: ores, essences, shards, scraps... never take a slot,
## any amount (see is_material). count_of / remove_by_id see both.
var pouch: Array[ItemStack] = []


func _init(capacity: int = 30) -> void:
	slots.resize(capacity)


func capacity() -> int:
	return slots.size()


func stack_at(index: int) -> ItemStack:
	if index < 0 or index >= slots.size():
		return null
	return slots[index]


## Crafting materials and other stackable stuff go to the pouch.
static func is_material(item: ItemData) -> bool:
	return item != null and item.item_type == ItemData.ItemType.MATERIAL and item.is_stackable() \
			and item.currency_value <= 0


## Adds items, filling existing stacks first. Returns how many did NOT fit.
func add_item(item: ItemData, count: int = 1) -> int:
	if item == null or count <= 0:
		return count
	if is_material(item):
		var st := _pouch_stack(item.id)
		if st:
			st.count += count
		else:
			pouch.append(ItemStack.new(item, count))
			pouch.sort_custom(func(a: ItemStack, b: ItemStack) -> bool: return a.item.display_name < b.item.display_name)
		item_added.emit(item, count)
		changed.emit()
		return 0
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
	if is_material(item):
		return 9999
	var space := 0
	for stack in slots:
		if stack == null:
			space += item.max_stack
		elif stack.item == item:
			space += stack.space_left()
	return space


func count_of(item_id: StringName) -> int:
	var st := _pouch_stack(item_id)
	var total := st.count if st else 0
	for stack in slots:
		if stack != null and stack.item.id == item_id:
			total += stack.count
	return total


## Index of this exact item (instances first by reference, then by id).
func find_item(item: ItemData) -> int:
	for i in slots.size():
		if slots[i] != null and slots[i].item == item:
			return i
	return find_index(item.id)


func find_index(item_id: StringName) -> int:
	for i in slots.size():
		if slots[i] != null and slots[i].item.id == item_id:
			return i
	return -1


## Removes `count` of an item anywhere in the backpack. Returns removed amount.
func remove_by_id(item_id: StringName, count: int = 1) -> int:
	var removed := 0
	var ps := _pouch_stack(item_id)
	if ps:
		removed = mini(count, ps.count)
		ps.count -= removed
		if ps.count <= 0:
			pouch.erase(ps)
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


func _pouch_stack(item_id: StringName) -> ItemStack:
	for st in pouch:
		if st.item.id == item_id:
			return st
	return null


## Every stack the hero carries: backpack slots and the pouch.
func all_stacks() -> Array[ItemStack]:
	var out: Array[ItemStack] = []
	for st in slots:
		if st != null:
			out.append(st)
	out.append_array(pouch)
	return out


## Old saves: materials lying in backpack slots move to the pouch.
func tidy_materials() -> void:
	var moved := false
	for i in slots.size():
		var st := slots[i]
		if st != null and is_material(st.item):
			slots[i] = null
			var ps := _pouch_stack(st.item.id)
			if ps:
				ps.count += st.count
			else:
				pouch.append(st)
			moved = true
	if moved:
		changed.emit()


func toggle_junk(index: int) -> void:
	var st := stack_at(index)
	if st:
		st.junk = not st.junk
		changed.emit()


func junk_indices() -> Array[int]:
	var out: Array[int] = []
	for i in slots.size():
		if slots[i] != null and slots[i].junk:
			out.append(i)
	return out


## Sort: equipment by rarity (best first), then usables, relics; junk last.
func sort_slots() -> void:
	var items: Array[ItemStack] = []
	for st in slots:
		if st != null:
			items.append(st)
	var rank := func(st: ItemStack) -> int:
		var t := {ItemData.ItemType.EQUIPMENT: 0, ItemData.ItemType.RELIC: 1, ItemData.ItemType.USABLE: 2, ItemData.ItemType.MATERIAL: 3}
		return (1000 if st.junk else 0) + int(t.get(st.item.item_type, 4)) * 100 + (10 - st.item.rarity) * 5
	items.sort_custom(func(a: ItemStack, b: ItemStack) -> bool:
		var ra: int = rank.call(a)
		var rb: int = rank.call(b)
		return ra < rb if ra != rb else a.item.display_name < b.item.display_name)
	for i in slots.size():
		slots[i] = items[i] if i < items.size() else null
	changed.emit()
