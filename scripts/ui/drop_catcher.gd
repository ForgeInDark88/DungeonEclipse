class_name DropCatcher
extends ColorRect
## Full-screen backdrop behind the inventory book. Items dropped here are
## thrown out of the backpack (spawned at the hero's feet); quick slots
## dropped here are cleared.

var hero: Hero


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("type") == "item_slot"


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var player := get_tree().get_first_node_in_group("player") as Player
	match data["kind"]:
		ItemSlot.Kind.QUICK:
			hero.quick_bar.clear(data["index"])
		ItemSlot.Kind.INVENTORY:
			var stack := hero.inventory.take_at(data["index"])
			if stack and player:
				_throw(player, stack)
		ItemSlot.Kind.EQUIPMENT:
			var item := hero.equipment.unequip(data["slot_id"])
			if item and player:
				_throw(player, ItemStack.new(item, 1))


func _throw(player: Player, stack: ItemStack) -> void:
	EventBus.spawn_items.emit(player.global_position + Vector2(player.facing * 10.0, -12.0),
			[{"item": stack.item, "count": stack.count}])
	EventBus.message.emit("Выброшено: %s" % stack.item.display_name)
