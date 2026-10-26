extends EventObject
## Healing fountain: one full heal and cleansing per floor.


func get_prompt() -> String:
	return "Испить из фонтана (полное исцеление)"


func _activate(player: Node) -> bool:
	var hero: Hero = player.hero
	hero.stats.heal(roundi(hero.stats.max_hp() * (1.0 if not Net.active else 0.7)))
	hero.stats.restore_mana(hero.stats.max_mana())
	player.status.cure([&"poison", &"burn", &"bleed", &"slow", &"curse"])
	player.status.apply(&"regen", 8.0, 2.0)
	Fx.sparks(get_parent(), global_position + Vector2(0, -16), Color(0.5, 0.8, 1.0), 24, 70.0)
	AudioManager.play_sfx(&"potion_drink", global_position)
	EventBus.message.emit("Вода смывает раны и проклятия")
	return true
