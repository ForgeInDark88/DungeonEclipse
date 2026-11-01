class_name CureEffect
extends ItemEffect
## Removes statuses from the user (antidote, bandage...).

@export var statuses: Array[StringName] = [&"poison", &"bleed"]


func apply(user: Node) -> bool:
	if not user.status.cure(statuses):
		EventBus.message.emit(tr("Нечего лечить"))
		return false
	return true


func describe() -> String:
	var names: Array[String] = []
	for s in statuses:
		names.append(StatusEffects.display_name(s).to_lower())
	return tr("Снимает: ") + ", ".join(names)
