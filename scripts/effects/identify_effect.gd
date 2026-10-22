class_name IdentifyEffect
extends ItemEffect
## Identifies every unidentified item in the backpack and on the hero.


func apply(user: Node) -> bool:
	var hero: Hero = user.hero
	var names := Identify.all(hero)
	if names.is_empty():
		EventBus.message.emit("Опознавать нечего")
		return false
	EventBus.message.emit("Опознано: %s" % ", ".join(names))
	return true


func describe() -> String:
	return "Опознаёт все неопознанные предметы в рюкзаке."
