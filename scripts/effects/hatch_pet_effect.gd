class_name HatchPetEffect
extends ItemEffect
## Hatches a pet from an egg; it replaces the current pet.

@export var pet: StringName


func apply(_user: Node) -> bool:
	var data := ItemDatabase.pets.get(pet) as PetData
	if data == null:
		return false
	if GameState.pet == data:
		EventBus.message.emit("%s уже с вами" % data.display_name)
		return false
	GameState.set_pet(data)
	EventBus.message.emit("Из яйца вылупился питомец: %s" % data.display_name)
	return true


func describe() -> String:
	var data := ItemDatabase.pets.get(pet) as PetData
	return "Вылупляется питомец: %s. %s" % [data.display_name, data.description] if data else ""
